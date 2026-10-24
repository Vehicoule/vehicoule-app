/// Google Sans Flex, one family (spec UI §2.4): ROND 100 for display, headlines and large
/// titles (and the player's track title), ROND 0 for running text; Noto Sans JP behind it
/// for CJK. Variable axes are set explicitly: a weight alone doesn't move `wght`.
library;

import 'package:material_ui/material_ui.dart';

abstract final class VFonts {
  static const family = 'GoogleSansFlex';
  static const fallback = <String>['NotoSansJP'];
}

TextStyle? _axes(TextStyle? s, {required double rond}) => s?.copyWith(
  fontFamily: VFonts.family,
  fontFamilyFallback: VFonts.fallback,
  fontVariations: [
    FontVariation('ROND', rond),
    FontVariation('wght', (s.fontWeight ?? FontWeight.w400).value.toDouble()),
    if (s.fontSize != null) FontVariation('opsz', s.fontSize!),
  ],
);

/// [base] (the M3 scale with the scheme's colors) in our family and axes.
TextTheme vTextTheme(TextTheme base) => base.copyWith(
  displayLarge: _axes(base.displayLarge, rond: 100),
  displayMedium: _axes(base.displayMedium, rond: 100),
  displaySmall: _axes(base.displaySmall, rond: 100),
  headlineLarge: _axes(base.headlineLarge, rond: 100),
  headlineMedium: _axes(base.headlineMedium, rond: 100),
  headlineSmall: _axes(base.headlineSmall, rond: 100),
  titleLarge: _axes(base.titleLarge, rond: 100),
  titleMedium: _axes(base.titleMedium, rond: 0),
  titleSmall: _axes(base.titleSmall, rond: 0),
  bodyLarge: _axes(base.bodyLarge, rond: 0),
  bodyMedium: _axes(base.bodyMedium, rond: 0),
  bodySmall: _axes(base.bodySmall, rond: 0),
  labelLarge: _axes(base.labelLarge, rond: 0),
  labelMedium: _axes(base.labelMedium, rond: 0),
  labelSmall: _axes(base.labelSmall, rond: 0),
);
