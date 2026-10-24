# Polices embarquées

Trois polices, sans téléchargement au lancement (spec UI §2.4, §2.5). Chaque dossier garde la
licence de la police.

| Dossier | Police | Licence | Source officielle |
|---|---|---|---|
| `google_sans_flex/` | Google Sans Flex, variable (`opsz`, `wght`, `ROND`) | SIL OFL 1.1 (`OFL.txt`) ; marques : `TRADEMARKS.md` | github.com/google/fonts, `ofl/googlesansflex/` |
| `noto_sans_jp/` | Noto Sans JP, variable (`wght`), sous-ensemble | SIL OFL 1.1 (`OFL.txt`) | github.com/google/fonts, `ofl/notosansjp/` |
| `material_symbols_rounded/` | Material Symbols Rounded, variable (`FILL`, `wght`) | Apache 2.0 (`LICENSE`) | github.com/google/material-design-icons, `variablefont/` |

Les fichiers sont dérivés des originaux (versions du 2026-10-24, SHA-256 ci-dessous) :

- Google Sans Flex : largeur et inclinaison figées (`wdth=100`, `slnt=0`) ; restent `opsz`,
  `wght`, `ROND`. Aucun nom de police réservé dans sa licence.
- Material Symbols Rounded : grade et taille optique figés (`GRAD=0`, `opsz=24`) ; restent
  `FILL` et `wght`, avec tous les glyphes (un écran qui ajoute une icône n'a rien à refaire).
- Noto Sans JP : rangs 1 à 8 de JIS X 0208 (symboles, kana, grec, cyrillique), kanji du
  niveau 1 (rangs 16 à 47), ponctuation CJK, formes demi et pleine chasse, flèches, latin.
  Le nom réservé de sa licence (« Source ») n'est pas utilisé.

Originaux :

```
a9ac770798857d5e8ac593ced42b22e40a7c08cec98319f92b0eccc2783a77ba  GoogleSansFlex[ROND,opsz,slnt,wdth,wght].ttf
7e74e36533ccee12c2b81e75bfcf3ccf123d3bb7e7e46d65d94445f23db0c97c  MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf
c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f  NotoSansJP[wght].ttf
```

Pour refaire les fichiers, télécharger les trois originaux dans un dossier, puis lancer ce
script (fonttools 4.60.1) :

```sh
#!/bin/sh
# Rebuilds app/assets/fonts from the official sources. Needs fonttools 4.60.1:
#   python3 -m venv venv && ./venv/bin/pip install fonttools==4.60.1
# Usage: subset_fonts.sh <venv bin dir> <download dir> <app/assets/fonts>
set -eu
BIN=$1; DL=$2; OUT=$3
# Google Sans Flex: keep opsz, wght and ROND; pin width and slant.
"$BIN/fonttools" varLib.instancer "$DL/GoogleSansFlex[ROND,opsz,slnt,wdth,wght].ttf" wdth=100 slnt=0 \
  -o "$OUT/google_sans_flex/GoogleSansFlex.ttf"
# Material Symbols Rounded: keep FILL and wght (every glyph); pin grade and optical size.
"$BIN/fonttools" varLib.instancer "$DL/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf" GRAD=0 opsz=24 \
  -o "$OUT/material_symbols_rounded/MaterialSymbolsRounded.ttf"
# Noto Sans JP: JIS X 0208 rows 1-8 (symbols, kana, Greek, Cyrillic) and level 1 kanji
# (rows 16-47), CJK punctuation, half/full-width forms, arrows and Latin.
"$BIN/python" - "$DL/jis.txt" <<'PY'
import sys
chars = set()
for row in list(range(1, 9)) + list(range(16, 48)):
    for cell in range(1, 95):
        try:
            chars.add(bytes([0xA0 + row, 0xA0 + cell]).decode('euc_jp'))
        except UnicodeDecodeError:
            pass
open(sys.argv[1], 'w', encoding='utf-8').write(''.join(sorted(chars)))
PY
"$BIN/pyftsubset" "$DL/NotoSansJP[wght].ttf" --text-file="$DL/jis.txt" \
  --unicodes='U+0020-007E,U+00A0-00FF,U+2190-21FF,U+2300-23FF,U+3000-30FF,U+FF00-FFEF' \
  --layout-features='*' --output-file="$OUT/noto_sans_jp/NotoSansJP.ttf"
```
