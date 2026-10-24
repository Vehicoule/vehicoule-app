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
    cs = cs.copyWith(
      surface: _black,
      surfaceDim: _black,
      surfaceContainerLowest: _black,
    );
  }
  final base = ThemeData(colorScheme: cs, useMaterial3: true);
  return base.copyWith(
    textTheme: vTextTheme(base.textTheme),
    primaryTextTheme: vTextTheme(base.primaryTextTheme),
    scaffoldBackgroundColor: cs.surface,
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

final _m3e = Expando<M3EThemeData>();

class _M3EScope extends StatelessWidget {
  const _M3EScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _m3e[theme] ??= M3EThemeData.fromMaterial(theme).copyWith(
      fontFamily: VFonts.family,
      fontFamilyFallback: VFonts.fallback,
      focusRingTheme: M3EFocusRingTheme(
        color: theme.colorScheme.secondary,
        width: 3,
        gap: 2,
      ),
    );
    return M3ETheme(data: data, child: child);
  }
}
