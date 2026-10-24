import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/l10n/app_localizations.dart';

/// The app's theme, strings and M3E scope around [child], with no core: artwork resolves
/// to nothing (the placeholder) unless [resolve] says otherwise.
Widget harness(
  Widget child, {
  bool reduce = false,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('fr'),
  ArtworkSource? resolve,
}) => MaterialApp(
  theme: vTheme(brightness: brightness, seed: VPresets.seeds.first),
  locale: locale,
  localizationsDelegates: vLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
    child: ArtworkResolver(
      resolve: resolve ?? (id, px) async => null,
      child: vAppBuilder(context, child),
    ),
  ),
  home: Scaffold(body: child),
);

AppLocalizations fr() => lookupAppLocalizations(const Locale('fr'));

/// Every Dart file under [dir] (relative to app/), as (path, text).
Iterable<(String, String)> sources(String dir) sync* {
  final d = Directory(dir);
  if (!d.existsSync()) return;
  for (final f in d.listSync(recursive: true).whereType<File>()) {
    if (f.path.endsWith('.dart')) yield (f.path, f.readAsStringSync());
  }
}

/// The lines of [files] that match [bad], as "path:line: text".
List<String> offending(Iterable<(String, String)> files, RegExp bad) => [
  for (final (path, text) in files)
    for (final (i, line) in text.split('\n').indexed)
      if (!line.trimLeft().startsWith('//') && bad.hasMatch(line))
        '$path:${i + 1}: $line',
];

/// Screens and shells: what the guards watch.
Iterable<(String, String)> screens() => [
  ...sources('lib/features'),
  for (final d in Directory('lib').listSync().whereType<Directory>())
    if (d.path.split('/').last.startsWith('shell_')) ...sources(d.path),
];

/// Everything in lib/ except generated code and the design system itself.
Iterable<(String, String)> outsideDesign() => [
  for (final s in sources('lib'))
    if (!s.$1.startsWith('lib/design/') && !s.$1.startsWith('lib/bridge/')) s,
];
