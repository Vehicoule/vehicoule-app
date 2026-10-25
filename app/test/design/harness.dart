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
      resolve: resolve ?? _noCover,
      child: vAppBuilder(context, child),
    ),
  ),
  home: Scaffold(body: child),
);

/// One function for every build, so the resolver doesn't look new each time.
Future<ImageProvider?> _noCover(String id, int px) async => null;

AppLocalizations fr() => lookupAppLocalizations(const Locale('fr'));

/// Every Dart file under [dir] (relative to app/), as (path, text).
Iterable<(String, String)> sources(String dir) sync* {
  final d = Directory(dir);
  if (!d.existsSync()) return;
  for (final f in d.listSync(recursive: true).whereType<File>()) {
    if (f.path.endsWith('.dart')) yield (f.path, f.readAsStringSync());
  }
}

/// Where [bad] matches in [files], as "path:line: text" (the line where the match
/// starts). It reads whole files, so a construct dart format split over several lines is
/// caught; matches on a commented line are skipped.
List<String> offending(Iterable<(String, String)> files, RegExp bad) => [
  for (final (path, text) in files)
    for (final m in bad.allMatches(text))
      if (_line(text, m.start) case final line
          when !line.$2.trimLeft().startsWith('//'))
        '$path:${line.$1}: ${line.$2}',
];

(int, String) _line(String text, int offset) {
  final start = text.lastIndexOf('\n', offset == 0 ? 0 : offset - 1) + 1;
  final end = text.indexOf('\n', offset);
  final number = '\n'.allMatches(text.substring(0, start)).length + 1;
  return (number, text.substring(start, end < 0 ? text.length : end));
}

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
