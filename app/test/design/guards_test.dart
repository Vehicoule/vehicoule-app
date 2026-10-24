// The anti-slop guards of spec UI §2.8 that read the sources. Each scanner first flags an
// inline bad sample, so an empty folder or a regex typo can't make it pass for nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

final rawColor = RegExp(r'\bColor\(\s*0x|\bColors\.');
final decoration = RegExp(
  r'\bBackdropFilter\b|ImageFilter\.blur|\bBoxShadow\b|\w*Gradient\b',
);
final timing = RegExp(r'\bDuration\(|\bCurves\.');

void main() {
  test('no raw colors outside design/', () {
    expect(
      offending([('sample', 'final c = Color(0xFF00FF00);')], rawColor),
      hasLength(1),
    );
    expect(
      offending([('sample', 'color: Colors.red,')], rawColor),
      hasLength(1),
    );
    expect(
      offending([('sample', 'color: scheme.primary,')], rawColor),
      isEmpty,
    );
    expect(offending(outsideDesign(), rawColor), isEmpty);
  });

  test('no blur, glass, glow or extra gradients', () {
    for (final bad in [
      'BackdropFilter(filter: f)',
      'ImageFilter.blur(sigmaX: 4)',
      'boxShadow: [BoxShadow()]',
      'gradient: LinearGradient(colors: c)',
    ]) {
      expect(
        offending([('sample', bad)], decoration),
        hasLength(1),
        reason: bad,
      );
    }
    expect(offending(outsideDesign(), decoration), isEmpty);
  });

  test('no ad-hoc durations or curves in screens', () {
    expect(
      offending([('sample', 'duration: Duration(milliseconds: 300),')], timing),
      hasLength(1),
    );
    expect(
      offending([('sample', 'curve: Curves.easeIn,')], timing),
      hasLength(1),
    );
    expect(
      offending([('sample', 'duration: VDurations.medium,')], timing),
      isEmpty,
    );
    expect(offending(screens(), timing), isEmpty);
  });

  test('light scheme never uses pure white surfaces', () {
    for (final seed in [
      ...VPresets.seeds,
      const Color(0xFFFFFFFF),
      const Color(0xFFFF0000),
    ]) {
      final s = vTheme(brightness: Brightness.light, seed: seed).colorScheme;
      final surfaces = {
        'surface': s.surface,
        'surfaceBright': s.surfaceBright,
        'surfaceDim': s.surfaceDim,
        'surfaceContainerLowest': s.surfaceContainerLowest,
        'surfaceContainerLow': s.surfaceContainerLow,
        'surfaceContainer': s.surfaceContainer,
        'surfaceContainerHigh': s.surfaceContainerHigh,
        'surfaceContainerHighest': s.surfaceContainerHighest,
      };
      for (final MapEntry(:key, :value) in surfaces.entries) {
        expect(value.toARGB32(), isNot(0xFFFFFFFF), reason: '$key for $seed');
        final l = value.computeLuminance();
        // Tones 92 to 98 (L* 92..98 → relative luminance ≈ 0.81..0.95).
        expect(l, inInclusiveRange(0.80, 0.96), reason: '$key for $seed');
      }
    }
  });
}
