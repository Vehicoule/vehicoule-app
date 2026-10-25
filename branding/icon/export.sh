#!/bin/sh
# The app icons and splash layers, from the user's Mochi (spec UI §2.5, §6.10):
#   mochi_master.svg (512 viewBox: background, ground shadow, Mochi, note) and
#   source/mochi_3b_macos.svg (the Big Sur squircle and grid).
# The drawing and its colours are the user's: this only places, scales and masks them.
# Run again whenever a source changes; it rewrites every output.
#
# Needs rsvg-convert (librsvg) and python3 (standard library only).
#
# Writes:
#   app/android/.../mipmap-*/ic_launcher_{foreground,monochrome}.png  adaptive icon, 108 dp
#   app/android/.../mipmap-*/ic_launcher.png                           before Android 8, 48 dp
#   app/android/.../mipmap-anydpi-v26/ic_launcher.xml, values/ic_launcher_background.xml
#   app/android/.../drawable-*/ic_stat_mochi.png                       notifications, 24 dp
#   app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png
#   app/windows/runner/resources/app_icon.ico
#   app/linux/runner/resources/app_icon{,_small}.png
#   app/assets/brand/splash_{shadow,mochi,note}.png                    SplashOverlay layers
#   branding/icon/export/                 derived SVGs, the ≤ 48 px variant, previews
# and fails if the adaptive foreground leaves the 66 dp safe zone.
set -eu
cd "$(dirname "$0")"
command -v rsvg-convert >/dev/null || { echo "export.sh: rsvg-convert is missing (brew install librsvg)" >&2; exit 1; }
exec python3 - <<'PY'
import math, os, re, struct, subprocess, sys, zlib
import xml.etree.ElementTree as ET

NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
APP = '../../app'
RES = f'{APP}/android/app/src/main/res'
OUT = 'export'
for d in (f'{OUT}/svg', f'{OUT}/preview', f'{OUT}/small'):
    os.makedirs(d, exist_ok=True)

# --- The master, in its four parts -------------------------------------------------------

master = ET.parse('mochi_master.svg').getroot()
parts = {}
for el in master:
    tag, t = el.tag.split('}')[1], el.get('transform', '')
    if tag == 'rect':
        parts['bg'] = el
    elif tag == 'ellipse':
        parts['shadow'] = el
    elif tag == 'g' and t.startswith('translate(406'):
        parts['note'] = el
    elif tag == 'g' and t.startswith('translate(248'):
        parts['mochi'] = el
    else:
        sys.exit(f'mochi_master.svg: unexpected element <{tag} transform="{t}">')
if set(parts) != {'bg', 'shadow', 'note', 'mochi'}:
    sys.exit(f'mochi_master.svg: found {sorted(parts)}, expected bg, shadow, mochi, note')
BG = parts['bg'].get('fill')

def src(*names):
    """The named parts, in the master's order."""
    return ''.join(ET.tostring(el, encoding='unicode') for el in master
                   if any(parts[n] is el for n in names))

ART = ('shadow', 'mochi', 'note')

def doc(body, defs=''):
    return (f'<svg xmlns="{NS}" viewBox="0 0 512 512" width="512" height="512">'
            f'<defs>{defs}</defs>{body}</svg>')

def save(name, text):
    path = f'{OUT}/svg/{name}.svg'
    open(path, 'w').write(text)
    return path

def render(svg_path, png, size):
    os.makedirs(os.path.dirname(png) or '.', exist_ok=True)
    subprocess.run(['rsvg-convert', '-w', str(size), '-h', str(size), '-o', png, svg_path],
                   check=True)

# --- PNG reading (alpha only), for measuring --------------------------------------------

def alpha_rows(path):
    d = open(path, 'rb').read()
    pos, idat = 8, b''
    while pos < len(d):
        n, = struct.unpack('>I', d[pos:pos + 4])
        typ, chunk = d[pos + 4:pos + 8], d[pos + 8:pos + 8 + n]
        pos += 12 + n
        if typ == b'IHDR':
            w, h, depth, ctype, _, _, inter = struct.unpack('>IIBBBBB', chunk)
        elif typ == b'IDAT':
            idat += chunk
    assert (depth, ctype, inter) == (8, 6, 0), path
    raw, s, rows, prev, i = zlib.decompress(idat), w * 4, [], bytearray(w * 4), 0
    for _ in range(h):
        f, line = raw[i], bytearray(raw[i + 1:i + 1 + s])
        i += 1 + s
        for x in range(s):
            a = line[x - 4] if x >= 4 else 0
            b = prev[x]
            c = prev[x - 4] if x >= 4 else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line[3::4])
        prev = line
    return w, rows

def outline(path):
    """Corners of each row's leftmost and rightmost visible pixel, in pixels."""
    w, rows = alpha_rows(path)
    pts = []
    for y, r in enumerate(rows):
        xs = [x for x in range(w) if r[x]]
        if xs:
            pts += [(xs[0], y), (xs[0], y + 1), (xs[-1] + 1, y), (xs[-1] + 1, y + 1)]
    return w, pts

def enclosing_circle(pts):
    """The smallest circle around pts (to a quarter unit): centre and radius."""
    best = None
    for step, span, c in ((4, 64, (256, 256)), (1, 6, None), (0.25, 2, None)):
        c = c or best[1:]
        for i in range(-int(span / step), int(span / step) + 1):
            for j in range(-int(span / step), int(span / step) + 1):
                cx, cy = c[0] + i * step, c[1] + j * step
                r = max(math.hypot(x - cx, y - cy) for x, y in pts)
                if best is None or r < best[0]:
                    best = (r, cx, cy)
    return best

# --- Android adaptive icon: 108 dp canvas, everything inside the 66 dp circle ------------

render(save('art', doc(src(*ART))), f'{OUT}/svg/art.png', 512)
_, art_pts = outline(f'{OUT}/svg/art.png')
r_art, cx, cy = enclosing_circle(art_pts)
SAFE = 33 / 108 * 512                      # the 66 dp circle's radius, in 512 units
USER = 0.6111111111111112                  # source/android_foreground.svg's scale
# 1 % for the anti-aliased edge.
scale = math.floor(SAFE * 0.99 / r_art * 1000) / 1000
place = f'translate(256 256) scale({scale}) translate({-cx} {-cy})'
print(f'adaptive foreground: art circle r={r_art:.1f} at ({cx}, {cy}); '
      f'scale {scale} = x{scale / USER:.3f} the source foreground')

fg = save('android_foreground', doc(f'<g transform="{place}">{src(*ART)}</g>'))

# Monochrome: the silhouette, solid, with the face cut out; no ground shadow (a bar once
# tinted). The Mochi group's last two children are the face strokes and blush lines.
mochi = parts['mochi']
face = [el for el in mochi if el.tag.endswith('path') and el.get('stroke') == '#4A1828']
blush = [el for el in mochi if el.tag.endswith('g') and el.get('stroke') == '#EE5A82']
if len(face) != 3 or len(blush) != 1:
    sys.exit('mochi_master.svg: expected 3 face strokes and 1 blush group in the Mochi')
cut = ''.join(ET.tostring(el, encoding='unicode') for el in face + blush)
cut = re.sub(r'stroke="#[0-9A-Fa-f]{6}"', 'stroke="#000"', cut)
mono_defs = (
    '<filter id="white"><feColorMatrix type="matrix" '
    'values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 1 0"/></filter>'
    '<mask id="face" maskUnits="userSpaceOnUse" x="0" y="0" width="512" height="512">'
    '<rect width="512" height="512" fill="#fff"/>'
    f'<g transform="{mochi.get("transform")}">{cut}</g></mask>')
mono = save('android_monochrome', doc(
    f'<g transform="{place}"><g mask="url(#face)"><g filter="url(#white)">'
    f'{src("mochi", "note")}</g></g></g>', mono_defs))

DPI = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, k in DPI.items():
    render(fg, f'{RES}/mipmap-{name}/ic_launcher_foreground.png', round(108 * k))
    render(mono, f'{RES}/mipmap-{name}/ic_launcher_monochrome.png', round(108 * k))

# The check: at 4 px/dp, nothing visible past the 66 dp circle.
size = 432
w, fg_pts = outline(f'{RES}/mipmap-xxxhdpi/ic_launcher_foreground.png')
worst = max(math.hypot(x - size / 2, y - size / 2) for x, y in fg_pts) / 4
print(f'adaptive foreground: farthest visible pixel {worst:.1f} dp from the centre (limit 33)')
if worst > 33:
    sys.exit('export.sh: the foreground leaves the 66 dp safe zone')

os.makedirs(f'{RES}/mipmap-anydpi-v26', exist_ok=True)
open(f'{RES}/mipmap-anydpi-v26/ic_launcher.xml', 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<!-- Written by branding/icon/export.sh. -->\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background" />\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
    '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
    '</adaptive-icon>\n')
open(f'{RES}/values/ic_launcher_background.xml', 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<!-- Written by branding/icon/export.sh: the background of mochi_master.svg. -->\n'
    f'<resources>\n    <color name="ic_launcher_background">{BG}</color>\n</resources>\n')

# --- The ≤ 48 px variant: the Mochi alone, larger (no note, no ground shadow) ------------

render(save('mochi_only', doc(src('mochi'))), f'{OUT}/svg/mochi_only.png', 512)
_, m_pts = outline(f'{OUT}/svg/mochi_only.png')
x0, y0 = min(p[0] for p in m_pts), min(p[1] for p in m_pts)
x1, y1 = max(p[0] for p in m_pts), max(p[1] for p in m_pts)

def fit(margin):
    """The Mochi alone, centred, its box filling the canvas but [margin] units."""
    k = (512 - 2 * margin) / max(x1 - x0, y1 - y0)
    return (f'<g transform="translate(256 256) scale({k:.4f}) '
            f'translate({-(x0 + x1) / 2} {-(y0 + y1) / 2})">{src("mochi")}</g>')

small = save('mochi_small', doc(fit(16)))
for s in (16, 24, 32, 48):
    render(small, f'{OUT}/small/mochi_small_{s}.png', s)

# --- Tiles: rounded (Windows, Linux, Android before 8) and Big Sur (macOS) ----------------

def rounded(inner):
    return doc(f'<rect x="16" y="16" width="480" height="480" rx="96" fill="{BG}"/>'
               f'<g transform="translate(256 256) scale(0.9375) translate(-256 -256)">'
               f'<clipPath id="r"><rect x="0" y="0" width="512" height="512" rx="102"/></clipPath>'
               f'<g clip-path="url(#r)">{inner}</g></g>')

tile = save('tile', rounded(src(*ART)))
tile_small = save('tile_small', rounded(fit(40)))

macos = ET.parse('source/mochi_3b_macos.svg').getroot()
squircle = ET.tostring(macos.find(f'.//{{{NS}}}clipPath'), encoding='unicode')
grid = macos.find(f'{{{NS}}}g').get('transform')   # 824 px tile in 1024, the Big Sur grid
# Big Sur's shadow: black 30 %, 10 px down, 10 px blur, at 1024 px (2 px a unit).
shadow = ('<filter id="drop" x="-10%" y="-10%" width="120%" height="125%">'
          '<feDropShadow dx="0" dy="5" stdDeviation="2.5" flood-color="#000" '
          'flood-opacity="0.3"/></filter>')

def bigsur(inner):
    cid = re.search(r'id="([^"]+)"', squircle).group(1)
    return doc(f'<g filter="url(#drop)"><g transform="{grid}">{squircle}'
               f'<g clip-path="url(#{cid})"><rect width="512" height="512" fill="{BG}"/>'
               f'{inner}</g></g></g>', shadow)

mac = save('macos', bigsur(src(*ART)))
mac_small = save('macos_small', bigsur(fit(40)))

# --- Platform files ----------------------------------------------------------------------

# Status bar: the white silhouette, filling 22 of its 24 dp.
stat = save('android_stat', doc(
    f'<g transform="translate(256 256) scale({22 / 24 * 256 / r_art:.4f}) '
    f'translate({-cx} {-cy})"><g mask="url(#face)"><g filter="url(#white)">'
    f'{src("mochi", "note")}</g></g></g>', mono_defs))
for name, k in DPI.items():
    render(tile, f'{RES}/mipmap-{name}/ic_launcher.png', round(48 * k))
    render(stat, f'{RES}/drawable-{name}/ic_stat_mochi.png', round(24 * k))

iconset = f'{APP}/macos/Runner/Assets.xcassets/AppIcon.appiconset'
for s in (16, 32, 64, 128, 256, 512, 1024):
    render(mac_small if s <= 48 else mac, f'{iconset}/app_icon_{s}.png', s)

def png(svg_path, s):
    tmp = f'{OUT}/svg/.ico_{s}.png'
    render(svg_path, tmp, s)
    data = open(tmp, 'rb').read()
    os.remove(tmp)
    return s, data

entries = [png(tile_small if s <= 48 else tile, s) for s in (16, 24, 32, 48, 64, 128, 256)]
head = struct.pack('<HHH', 0, 1, len(entries))
offset, table, blobs = 6 + 16 * len(entries), b'', b''
for s, data in entries:
    table += struct.pack('<BBBBHHII', s % 256, s % 256, 0, 0, 1, 32, len(data),
                         offset + len(blobs))
    blobs += data
open(f'{APP}/windows/runner/resources/app_icon.ico', 'wb').write(head + table + blobs)

render(tile, f'{APP}/linux/runner/resources/app_icon.png', 256)
render(tile_small, f'{APP}/linux/runner/resources/app_icon_small.png', 48)

# SplashOverlay's three layers, on the full 512 canvas so they stack (3x of 256 dp).
for name in ART:
    render(save(f'splash_{name}', doc(src(name))), f'{APP}/assets/brand/splash_{name}.png', 768)

for tmp in ('art', 'mochi_only'):
    os.remove(f'{OUT}/svg/{tmp}.png')

# --- Previews (for review; not shipped) --------------------------------------------------

def preview(name, body, defs=''):
    path = f'{OUT}/preview/{name}.svg'
    open(path, 'w').write(doc(body, defs))
    render(path, f'{OUT}/preview/{name}.png', 512)
    os.remove(path)

def zone(name, transform):
    # 108 dp → 512 units: the 72 dp viewport and the 66 dp safe zone.
    k = 512 / 108
    preview(name,
            f'<rect width="512" height="512" fill="{BG}"/>'
            f'<g transform="{transform}">{src(*ART)}</g>'
            f'<rect x="{18 * k}" y="{18 * k}" width="{72 * k}" height="{72 * k}" fill="none" '
            f'stroke="#1E88E5" stroke-width="2" stroke-dasharray="6 6"/>'
            f'<circle cx="256" cy="256" r="{36 * k}" fill="none" stroke="#1E88E5" stroke-width="2"/>'
            f'<circle cx="256" cy="256" r="{33 * k}" fill="none" stroke="#E53935" stroke-width="3"/>')

zone('android_safe_zone_source',
     'translate(99.55555555555554 99.55555555555554) scale(0.6111111111111112)')
zone('android_safe_zone_x1.3',
     f'translate(256 256) scale({USER * 1.3}) translate(-256 -256)')
zone('android_safe_zone_export', place)
k = 512 / 108
preview('android_circle_mask',
        f'<clipPath id="c"><circle cx="256" cy="256" r="{36 * k}"/></clipPath>'
        f'<g clip-path="url(#c)"><rect width="512" height="512" fill="{BG}"/>'
        f'<g transform="{place}">{src(*ART)}</g></g>')
preview('android_monochrome_themed',
        f'<rect width="512" height="512" fill="#2B2930"/>'
        f'<clipPath id="c"><circle cx="256" cy="256" r="{36 * k}"/></clipPath>'
        f'<g clip-path="url(#c)"><rect width="512" height="512" fill="#D0BCFF"/>'
        f'<g transform="{place}"><g mask="url(#face)"><g filter="url(#ink)">'
        f'{src("mochi", "note")}</g></g></g></g>',
        mono_defs + '<filter id="ink"><feColorMatrix type="matrix" values="0 0 0 0 0.22  '
        '0 0 0 0 0.12  0 0 0 0 0.37  0 0 0 1 0"/></filter>')
print('done')
PY
