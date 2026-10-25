/// Where the theme's seed comes from (spec UI §2.2). One source at a time: the app's
/// `ColorScheme`. [seedFromArtwork] is the only color extraction in the app.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

enum ColorSource { nowPlaying, system, preset }

/// The chosen seeds of [ColorSource.preset] (spec UI §2.2), already pastel.
abstract final class VPresets {
  static const seeds = <ui.Color>[
    ui.Color(0xFF6F8F72), // sage
    ui.Color(0xFFB5838D), // rose
    ui.Color(0xFF6D8EAD), // lake
    ui.Color(0xFFC9A66B), // sand
  ];
}

const _maxChroma = 48.0;

/// Always pastel: the hue is kept, the chroma capped. Contrast comes from the scheme's
/// tones, never from the hue.
ui.Color pastelSeed(ui.Color raw) {
  final hct = Hct.fromInt(raw.toARGB32());
  if (hct.chroma <= _maxChroma) return raw;
  return ui.Color(Hct.from(hct.hue, _maxChroma, hct.tone).toInt());
}

const _cacheSize = 64;
final _arts = <String, Future<_Art?>>{};

/// How many artworks were quantized: the cache test checks a second call costs nothing.
@visibleForTesting
int debugQuantizations = 0;

/// The top band of a cover, under the Vague's header: the relative luminance of its
/// darker and lighter pixels (1st and 99th percentiles: specks of JPEG noise don't
/// count, a logo or a line of lettering under the header does).
class VCoverTop {
  const VCoverTop(this.low, this.high);

  final double low, high;
}

/// What the Vague's header sits on (spec UI §6.6): dark content on a light top band,
/// light content on a dark one, a scrim (light content) when neither reads, a busy or
/// mid-tone top, or an unknown cover.
enum VOnCover { light, dark, scrim }

/// The header's two content colours over a cover.
const vOnCoverLight = ui.Color(0xFFFFFFFF), vOnCoverDark = ui.Color(0xFF141414);

double _contrast(double a, double b) =>
    (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

/// Text at 4.5:1 (icons, at 3:1, follow) over every pixel of the band but the extremes.
VOnCover vOnCoverFor(VCoverTop? top) {
  if (top == null) return VOnCover.scrim;
  if (_contrast(vOnCoverLight.computeLuminance(), top.high) >= 4.5) {
    return VOnCover.light;
  }
  if (_contrast(vOnCoverDark.computeLuminance(), top.low) >= 4.5) {
    return VOnCover.dark;
  }
  return VOnCover.scrim;
}

/// The part of a cover's height its top band covers (the header over the Vague).
const _topBand = 0.2;

typedef _Art = ({ui.Color? seed, VCoverTop top});

/// One decode per artwork, cached by path (LRU, 64 entries): its seed and its top band.
Future<_Art?> _art(String path) {
  final hit = _arts.remove(path);
  final art = hit ?? _extract(path);
  _arts[path] = art;
  if (_arts.length > _cacheSize) _arts.remove(_arts.keys.first);
  // A failure isn't kept: the file may arrive later (a cover still downloading).
  if (hit == null) {
    art.then((a) {
      if (a == null && _arts[path] == art) _arts.remove(path);
    });
  }
  return art;
}

/// The seed of a track's artwork: [path] is the 112 px file from `artworkFile`. Decoded
/// on the UI isolate (image codecs need it), quantized off it (`QuantizerCelebi`), and
/// cached by path. Null when the image has no usable color.
Future<ui.Color?> seedFromArtwork(String path) async =>
    (await _art(path))?.seed;

/// The top band of a track's artwork, measured with its seed (same decode, same cache).
Future<VCoverTop?> coverTopFromArtwork(String path) async =>
    (await _art(path))?.top;

/// The theme's seed while a track plays (spec UI §2.2): its artwork's, or [fallback]
/// (the System seed, or the chosen preset) when the cover has no colour: the same
/// answer for the same cover, never the previous track's colour.
Future<ui.Color> seedForArtwork(
  String? path, {
  required ui.Color fallback,
}) async => (path == null ? null : await seedFromArtwork(path)) ?? fallback;

Future<_Art?> _extract(String path) async {
  try {
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
      targetWidth: 112,
    );
    final image = (await codec.getNextFrame()).image;
    final rgba = await image.toByteData();
    final width = image.width, height = image.height;
    image.dispose();
    if (rgba == null) return null;
    final bytes = rgba.buffer.asUint8List();
    debugQuantizations++;
    final (argb, low, high) = await Isolate.run(() async {
      final pixels = <int>[
        for (var i = 0; i + 3 < bytes.length; i += 4)
          if (bytes[i + 3] == 0xFF)
            0xFF000000 | bytes[i] << 16 | bytes[i + 1] << 8 | bytes[i + 2],
      ];
      final result = await QuantizerCelebi().quantize(pixels, 128);
      final seed = Score.score(
        result.colorToCount,
        desired: 1,
        fallbackColorARGB: 0,
      ).first;
      double linear(int c) {
        final v = c / 255;
        return v <= 0.04045
            ? v / 12.92
            : math.pow((v + 0.055) / 1.055, 2.4) as double;
      }

      final rows = math.max(1, (height * _topBand).round());
      final lum = <double>[
        for (var i = 0; i < width * rows * 4; i += 4)
          0.2126 * linear(bytes[i]) +
              0.7152 * linear(bytes[i + 1]) +
              0.0722 * linear(bytes[i + 2]),
      ]..sort();
      double at(double p) => lum[((lum.length - 1) * p).round()];
      return (seed, at(0.01), at(0.99));
    });
    return (
      seed: argb == 0 ? null : pastelSeed(ui.Color(argb)),
      top: VCoverTop(low, high),
    );
  } on Exception {
    return null;
  }
}

/// The system seed: Material You on Android, the accent color on desktop. Null when the
/// platform has none.
Future<ui.Color?> systemSeed() async {
  try {
    final palette = await DynamicColorPlugin.getCorePalette();
    if (palette != null) return pastelSeed(ui.Color(palette.primary.get(40)));
    final accent = await DynamicColorPlugin.getAccentColor();
    return accent == null ? null : pastelSeed(accent);
  } on Exception {
    // PlatformException, or no plugin at all (tests, an unsupported platform).
    return null;
  }
}
