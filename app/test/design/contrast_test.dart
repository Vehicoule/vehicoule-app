import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  pureBlackTests();
  test('token color pairs meet WCAG AA for every source', () {
    // Self-check of the formula: black on white is 21:1.
    expect(
      contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.01),
    );
    final seeds = [
      for (var h = 0; h < 360; h += 30)
        Color(Hct.from(h.toDouble(), 80, 50).toInt()),
      ...VPresets.seeds,
    ];
    expect(seeds.length, greaterThanOrEqualTo(12));
    for (final seed in seeds) {
      for (final (b, black) in [
        (Brightness.light, false),
        (Brightness.dark, false),
        (Brightness.dark, true),
      ]) {
        final s = vTheme(
          brightness: b,
          seed: seed,
          pureBlack: black,
        ).colorScheme;
        for (final (name, fg, bg) in [
          ('onPrimary/primary', s.onPrimary, s.primary),
          ('onSurface/surface', s.onSurface, s.surface),
          ('onSurfaceVariant/surface', s.onSurfaceVariant, s.surface),
          (
            'onSecondaryContainer/secondaryContainer',
            s.onSecondaryContainer,
            s.secondaryContainer,
          ),
          (
            'onSurface/surfaceContainerHighest',
            s.onSurface,
            s.surfaceContainerHighest,
          ),
          ('primary/surface', s.primary, s.surface),
        ]) {
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name, $seed, $b, black $black',
          );
        }
        if (black) expect(s.surface, const Color(0xFF000000));
      }
    }
  });
}

void pureBlackTests() {
  test('pure black keeps tonal blocks and containers readable, not dull', () {
    for (var h = 0; h < 360; h += 30) {
      final seed = Color(Hct.from(h.toDouble(), 80, 50).toInt());
      final s = vTheme(
        brightness: Brightness.dark,
        seed: seed,
        pureBlack: true,
      ).colorScheme;
      expect(
        contrast(s.secondaryContainer, s.surface),
        greaterThanOrEqualTo(2),
        reason: 'tonal blocks, hue $h',
      );
      expect(
        contrast(s.surfaceContainer, s.surface),
        greaterThanOrEqualTo(1.4),
        reason: 'toolbar, hue $h',
      );
      expect(
        contrast(s.surfaceContainerHigh, s.surface),
        greaterThanOrEqualTo(1.6),
        reason: 'chips, hue $h',
      );
      expect(
        contrast(s.onSurface, s.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(s.onSecondaryContainer, s.secondaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
