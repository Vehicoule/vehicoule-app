import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicoule/bridge/error.dart';
import 'package:vehicoule/l10n/app_localizations.dart';
import 'package:vehicoule/l10n/errors.dart';

Map<String, String> _strings(String lang) {
  final json = jsonDecode(
    File('lib/l10n/app_$lang.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      if (!e.key.startsWith('@')) e.key: e.value as String,
  };
}

/// Every CoreError the bridge can throw: errorMessage's switch is exhaustive, so a new
/// variant fails to compile there; this list covers the payloads.
final _allErrors = <CoreError>[
  const CoreError.network(),
  const CoreError.providerWall(),
  const CoreError.rateLimited(),
  const CoreError.budgetExceeded(),
  const CoreError.notFound(),
  const CoreError.expired(),
  const CoreError.internal('store corrupt'),
  const CoreError.offline(),
  const CoreError.invalidFeed(),
  for (final c in Capability.values) CoreError.noPlugin(c),
];

void main() {
  final fr = lookupAppLocalizations(const Locale('fr'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('fr and en arb files have the same keys', () {
    expect(_strings('en').keys.toSet(), _strings('fr').keys.toSet());
  });

  test('every CoreError variant has a message in both languages', () {
    for (final e in _allErrors) {
      final f = errorMessage(fr, e), g = errorMessage(en, e);
      expect(f.trim(), isNotEmpty, reason: '$e fr');
      expect(g.trim(), isNotEmpty, reason: '$e en');
      expect(f, isNot(g), reason: '$e: fr and en are the same text');
      expect(
        '$f$g',
        isNot(contains('store corrupt')),
        reason: 'internal detail leaked',
      );
    }
  });

  test('no source to play points to adding one', () {
    expect(
      errorMessage(fr, const CoreError.noPlugin(Capability.resolve)),
      contains('Ajoute une source pour lire'),
    );
    expect(
      errorMessage(en, const CoreError.noPlugin(Capability.resolve)),
      contains('Add a source'),
    );
  });

  test('arb strings follow voice.md', () {
    // ♡ is the like glyph the UI names (voice.md), not an emoji.
    // The analyzer checks this pattern without the unicode flag, so \p{} looks invalid.
    // ignore: valid_regexps
    final emoji = RegExp(r'[\p{Extended_Pictographic}\u{FE0F}]', unicode: true);
    final banned = RegExp(
      r'\b(plugins?|feeds?|oups|oops|veuillez|please|vous)\b'
      r'|d[ée]p[ôo]ts?|r[ée]solutions?|\b[1-5]\d\d\b',
      caseSensitive: false,
      unicode: true,
    );
    for (final lang in ['fr', 'en']) {
      for (final MapEntry(:key, :value) in _strings(lang).entries) {
        final where = '$lang.$key: $value';
        expect(value, isNot(contains('!')), reason: where);
        expect(
          emoji.hasMatch(value.replaceAll('♡', '')),
          isFalse,
          reason: where,
        );
        expect(banned.hasMatch(value), isFalse, reason: where);
        expect(
          value,
          isNot(contains('"')),
          reason: '$where (typographic quotes)',
        );
        if (lang == 'fr') {
          expect(value, isNot(matches(r'[“”]')), reason: where);
          // French spacing: no-break space inside « » and before ? ; : (wraps cleanly).
          expect(value, isNot(matches(r'« | »| [?;:]')), reason: where);
        } else {
          expect(value, isNot(matches(r'[«»]')), reason: where);
        }
      }
    }
  });
}
