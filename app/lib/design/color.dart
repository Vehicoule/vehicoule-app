/// Where the theme's seed comes from (spec UI §2.2). One source at a time: the app's
/// `ColorScheme`. [seedFromArtwork] is the only color extraction in the app.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
final _seeds = <String, Future<ui.Color?>>{};

/// How many artworks were quantized: the cache test checks a second call costs nothing.
@visibleForTesting
int debugQuantizations = 0;

/// The seed of a track's artwork: [path] is the 112 px file from `artworkFile`. Decoded
/// on the UI isolate (image codecs need it), quantized off it (`QuantizerCelebi`), and
/// cached by path (LRU, 64 entries). Null when the image has no usable color.
Future<ui.Color?> seedFromArtwork(String path) {
  final hit = _seeds.remove(path);
  final seed = hit ?? _extract(path);
  _seeds[path] = seed;
  if (_seeds.length > _cacheSize) _seeds.remove(_seeds.keys.first);
  // A failure isn't kept: the file may arrive later (a cover still downloading).
  if (hit == null) {
    seed.then((c) {
      if (c == null && _seeds[path] == seed) _seeds.remove(path);
    });
  }
  return seed;
}

Future<ui.Color?> _extract(String path) async {
  try {
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
      targetWidth: 112,
    );
    final image = (await codec.getNextFrame()).image;
    final rgba = await image.toByteData();
    image.dispose();
    if (rgba == null) return null;
    final pixels = <int>[
      for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4)
        if (rgba.getUint8(i + 3) == 0xFF)
          0xFF000000 |
              rgba.getUint8(i) << 16 |
              rgba.getUint8(i + 1) << 8 |
              rgba.getUint8(i + 2),
    ];
    debugQuantizations++;
    final argb = await Isolate.run(() async {
      final result = await QuantizerCelebi().quantize(pixels, 128);
      return Score.score(
        result.colorToCount,
        desired: 1,
        fallbackColorARGB: 0,
      ).first;
    });
    return argb == 0 ? null : pastelSeed(ui.Color(argb));
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
  } on PlatformException {
    return null;
  }
}
