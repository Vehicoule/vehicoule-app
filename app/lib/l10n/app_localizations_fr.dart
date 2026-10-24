// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get errorNetwork =>
      'La connexion ne répond pas. Réessaie dans un moment.';

  @override
  String get errorProviderWall =>
      'Le service bloque cette demande pour l\'instant. Réessaie plus tard.';

  @override
  String get errorRateLimited =>
      'Trop de demandes d\'un coup. Réessaie dans une minute.';

  @override
  String get errorBudgetExceeded =>
      'La source a mis trop de temps à répondre. Réessaie.';

  @override
  String get errorNotFound => 'Ce contenu n\'est plus disponible.';

  @override
  String get errorExpired =>
      'Ce titre n\'est plus disponible pour l\'instant. Réessaie dans un moment.';

  @override
  String get errorInternal =>
      'Quelque chose s\'est mal passé de notre côté. Réessaie, ou envoie un rapport de bug depuis les Réglages.';

  @override
  String get errorOffline => 'Hors ligne · tes téléchargements restent là.';

  @override
  String get errorInvalidFeed => 'Ce lien de source n\'a pas pu être utilisé.';

  @override
  String get errorNoSourceSearch => 'Il te faut une source pour chercher.';

  @override
  String get errorNoSourceEntity =>
      'Il te faut une source pour ouvrir cette page.';

  @override
  String get errorNoSourcePlay => 'Il te faut une source pour lire.';

  @override
  String get errorNoSourceLyrics =>
      'Il te faut une source pour voir les paroles.';

  @override
  String get errorNoSourceRadio =>
      'Il te faut une source pour lancer une radio.';

  @override
  String get errorNoSourceBrowse => 'Il te faut une source pour explorer.';

  @override
  String get actionAddSource => 'Ajouter une source';
}
