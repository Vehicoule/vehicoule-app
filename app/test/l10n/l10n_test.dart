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

  test('no source to play: the ruled wording and its action', () {
    expect(
      errorMessage(fr, const CoreError.noPlugin(Capability.resolve)),
      'Il te faut une source pour lire.',
    );
    expect(
      errorMessage(en, const CoreError.noPlugin(Capability.resolve)),
      'You need a source to play music.',
    );
    expect(fr.actionAddSource, 'Ajouter une source');
    expect(en.actionAddSource, 'Add a source');
  });

  test(
    'notFound is neutral: the core raises it for pages, tracks, downloads',
    () {
      expect(
        errorMessage(fr, const CoreError.notFound()),
        "Ce contenu n'est plus disponible.",
      );
      expect(
        errorMessage(en, const CoreError.notFound()),
        "This isn't available anymore.",
      );
    },
  );

  test('arb strings follow voice.md', () {
    // ♡ too: the like heart is an icon with a spoken label, never the raw glyph.
    // The analyzer checks this pattern without the unicode flag, so \p{} looks invalid.
    final emoji = RegExp(
      // ignore: valid_regexps
      r'[\p{Extended_Pictographic}\u{FE0F}♡]',
      unicode: true,
    );
    final banned = RegExp(
      r'\b(plug-?ins?|feeds?|oups|oops|veuillez|please|vous)\b'
      r'|d[ée]p[ôo]ts?|r[ée]solutions?|\b[1-5]\d\d\b',
      caseSensitive: false,
      unicode: true,
    );
    // English only: « repos » is a French word (au repos).
    final bannedEn = RegExp(r'\brepo(sitor(y|ies))?s?\b', caseSensitive: false);
    expect(bannedEn.hasMatch('the repository'), isTrue);
    expect(banned.hasMatch('au repos'), isFalse);
    for (final lang in ['fr', 'en']) {
      for (final MapEntry(:key, :value) in _strings(lang).entries) {
        final where = '$lang.$key: $value';
        expect(value, isNot(contains('!')), reason: where);
        expect(emoji.hasMatch(value), isFalse, reason: where);
        expect(banned.hasMatch(value), isFalse, reason: where);
        if (lang == 'en') {
          expect(bannedEn.hasMatch(value), isFalse, reason: where);
        }
        expect(
          value,
          isNot(contains('"')),
          reason: '$where (typographic quotes)',
        );
        if (lang == 'fr') {
          expect(value, isNot(matches(r'[“”]')), reason: where);
          // French spacing: no-break space inside « » and before ? ; : (wraps cleanly).
          expect(value, isNot(matches(r'« | »| [?;:]')), reason: where);
          // ...and the no-break space is there (\s covers U+00A0 and U+202F).
          expect(value, isNot(matches(r'[^\s][?;:!»]|«[^\s]')), reason: where);
        } else {
          expect(value, isNot(matches(r'[«»]')), reason: where);
        }
      }
    }
  });
}
