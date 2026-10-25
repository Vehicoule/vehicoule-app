/// The app theme: an M3 tonal-spot scheme from a pastel seed, our surfaces and our type
/// (spec UI §2.2, §2.4), projected for the M3E components by [vAppBuilder].
library;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'color.dart';
import 'typography.dart';

const _black = Color(0xFF000000);

/// [seed] is made pastel first. Light surfaces sit at tones 98 to 92, tinted, never
/// white; [pureBlack] puts the dark surfaces at 0.
ThemeData vTheme({
  required Brightness brightness,
  required Color seed,
  bool pureBlack = false,
}) {
  final pastel = pastelSeed(seed);
  final dark = brightness == Brightness.dark;
  var cs = ColorScheme.fromSeed(seedColor: pastel, brightness: brightness);
  if (!dark) {
    final n = SchemeTonalSpot(
      sourceColorHct: Hct.fromInt(pastel.toARGB32()),
      isDark: false,
      contrastLevel: 0,
    ).neutralPalette;
    Color tone(int t) => Color(n.get(t));
    cs = cs.copyWith(
      surface: tone(98),
      surfaceBright: tone(98),
      surfaceContainerLowest: tone(98),
      surfaceContainerLow: tone(96),
      surfaceContainer: tone(94),
      surfaceContainerHigh: tone(93),
      surfaceContainerHighest: tone(92),
      surfaceDim: tone(92),
    );
  } else if (pureBlack) {
    // On black, the containers step up a few tones so toolbars, chips and tonal
    // blocks keep their edge instead of going dull.
    final n = SchemeTonalSpot(
      sourceColorHct: Hct.fromInt(pastel.toARGB32()),
      isDark: true,
      contrastLevel: 0,
    ).neutralPalette;
    Color tone(int t) => Color(n.get(t));
    cs = cs.copyWith(
      surface: _black,
      surfaceDim: _black,
      surfaceContainerLowest: _black,
      surfaceContainerLow: tone(10),
      surfaceContainer: tone(16),
      surfaceContainerHigh: tone(22),
      surfaceContainerHighest: tone(26),
    );
  }
  final base = ThemeData(colorScheme: cs, useMaterial3: true);
  return base.copyWith(
    textTheme: vTextTheme(base.textTheme),
    primaryTextTheme: vTextTheme(base.primaryTextTheme),
    scaffoldBackgroundColor: cs.surface,
  );
}

/// What a full-screen surface paints (the player, spec UI §6.6): `surfaceContainer`,
/// but black in pure black (§2.2: surfaces at 0; only floating containers step up).
Color vScreenSurface(ColorScheme cs) =>
    cs.surface == _black ? _black : cs.surfaceContainer;

final _onScrim = Expando<ThemeData>();

/// Light content on a dark scrim over artwork (the Vague's header): white foregrounds
/// and a light veil for tonal fills, for Material and M3E components alike.
Widget vOnScrim(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  const white = Color(0xFFFFFFFF);
  final t = _onScrim[theme] ??= theme.copyWith(
    colorScheme: theme.colorScheme.copyWith(
      onSurface: white,
      onSurfaceVariant: white,
      secondaryContainer: white.withValues(alpha: 0.16),
      onSecondaryContainer: white,
    ),
  );
  return Theme(
    data: t,
    child: _M3EScope(child: child),
  );
}

/// Every delegate the app needs: our strings, and material_ui's own Material, Cupertino
/// and widgets localizations (flutter_localizations' Material ones are another type).
const vLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

/// `MaterialApp.builder`: gives the M3E components our theme, with the focus ring of spec
/// UI §4.4 (secondary, 3 px, 2 px away).
Widget vAppBuilder(BuildContext context, Widget? child) =>
    _M3EScope(child: child ?? const SizedBox.shrink());

final _m3e = Expando<M3EThemeData>(), _m3eReduced = Expando<M3EThemeData>();

/// A spring that lands at once: what M3E's springs become with "reduce motion".
const _instant = M3ESpring(stiffness: 100000, damping: 1);

class _M3EScope extends StatelessWidget {
  const _M3EScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final cache = reduced ? _m3eReduced : _m3e;
    final data = cache[theme] ??= _data(theme, reduced);
    return M3ETheme(data: data, child: child);
  }

  static M3EThemeData _data(ThemeData theme, bool reduced) {
    final base = M3EThemeData.fromMaterial(theme).copyWith(
      fontFamily: VFonts.family,
      fontFamilyFallback: VFonts.fallback,
      focusRingTheme: M3EFocusRingTheme(
        color: theme.colorScheme.secondary,
        width: 3,
        gap: 2,
      ),
    );
    if (!reduced) return base;
    // "Reduce motion" (spec UI §5.6): the components' own springs land at once.
    return base.copyWith(
      buttonTheme: base.buttonTheme.copyWith(shapeSpring: _instant),
      buttonGroupTheme: base.buttonGroupTheme.copyWith(
        neighborSquishSpring: _instant,
      ),
      toolbarTheme: base.toolbarTheme.copyWith(
        labelSpring: _instant,
        expandSpring: _instant,
      ),
      fabMenuTheme: base.fabMenuTheme.copyWith(
        expandSpring: _instant,
        fabShapeSpring: _instant,
        expandStagger: Duration.zero,
      ),
    );
  }
}
