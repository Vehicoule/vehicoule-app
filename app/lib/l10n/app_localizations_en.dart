// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get errorNetwork =>
      'The connection isn\'t responding. Try again in a moment.';

  @override
  String get errorProviderWall =>
      'The service is blocking this request for now. Try again later.';

  @override
  String get errorRateLimited =>
      'Too many requests at once. Try again in a minute.';

  @override
  String get errorBudgetExceeded =>
      'The source took too long to answer. Try again.';

  @override
  String get errorNotFound => 'This isn\'t available anymore.';

  @override
  String get errorExpired =>
      'This track isn\'t available right now. Try again in a moment.';

  @override
  String get errorInternal =>
      'Something went wrong on our side. Try again, or send a bug report from Settings.';

  @override
  String get errorOffline => 'Offline · your downloads are still here.';

  @override
  String get errorInvalidFeed => 'This source link couldn\'t be used.';

  @override
  String get errorNoSourceSearch => 'You need a source to search.';

  @override
  String get errorNoSourceEntity => 'You need a source to open this page.';

  @override
  String get errorNoSourcePlay => 'You need a source to play music.';

  @override
  String get errorNoSourceLyrics => 'You need a source to see lyrics.';

  @override
  String get errorNoSourceRadio => 'You need a source to start a radio.';

  @override
  String get errorNoSourceBrowse => 'You need a source to explore.';

  @override
  String get actionAddSource => 'Add a source';
}
