import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @errorNetwork.
  ///
  /// In fr, this message translates to:
  /// **'La connexion ne répond pas. Réessaie dans un moment.'**
  String get errorNetwork;

  /// No description provided for @errorProviderWall.
  ///
  /// In fr, this message translates to:
  /// **'Le service bloque cette demande pour l\'instant. Réessaie plus tard.'**
  String get errorProviderWall;

  /// No description provided for @errorRateLimited.
  ///
  /// In fr, this message translates to:
  /// **'Trop de demandes d\'un coup. Réessaie dans une minute.'**
  String get errorRateLimited;

  /// No description provided for @errorBudgetExceeded.
  ///
  /// In fr, this message translates to:
  /// **'La source a mis trop de temps à répondre. Réessaie.'**
  String get errorBudgetExceeded;

  /// No description provided for @errorNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Ce contenu n\'est plus disponible.'**
  String get errorNotFound;

  /// No description provided for @errorExpired.
  ///
  /// In fr, this message translates to:
  /// **'Ce titre n\'est plus disponible pour l\'instant. Réessaie dans un moment.'**
  String get errorExpired;

  /// No description provided for @errorInternal.
  ///
  /// In fr, this message translates to:
  /// **'Quelque chose s\'est mal passé de notre côté. Réessaie, ou envoie un rapport de bug depuis les Réglages.'**
  String get errorInternal;

  /// No description provided for @errorOffline.
  ///
  /// In fr, this message translates to:
  /// **'Hors ligne · tes téléchargements restent là.'**
  String get errorOffline;

  /// No description provided for @errorInvalidFeed.
  ///
  /// In fr, this message translates to:
  /// **'Ce lien de source n\'a pas pu être utilisé.'**
  String get errorInvalidFeed;

  /// No description provided for @errorNoSourceSearch.
  ///
  /// In fr, this message translates to:
  /// **'Il te faut une source pour chercher.'**
  String get errorNoSourceSearch;

  /// No description provided for @errorNoSourceEntity.
  ///
  /// In fr, this message translates to:
  /// **'Il te faut une source pour ouvrir cette page.'**
  String get errorNoSourceEntity;

  /// No description provided for @errorNoSourcePlay.
  ///
  /// In fr, this message translates to:
  /// **'Il te faut une source pour lire.'**
  String get errorNoSourcePlay;

  /// No description provided for @errorNoSourceLyrics.
  ///
  /// In fr, this message translates to:
  /// **'Il te faut une source pour voir les paroles.'**
  String get errorNoSourceLyrics;

  /// No description provided for @errorNoSourceRadio.
  ///
  /// In fr, this message translates to:
  /// **'Il te faut une source pour lancer une radio.'**
  String get errorNoSourceRadio;

  /// No description provided for @errorNoSourceBrowse.
  ///
  /// In fr, this message translates to:
  /// **'Il te faut une source pour explorer.'**
  String get errorNoSourceBrowse;

  /// No description provided for @actionAddSource.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une source'**
  String get actionAddSource;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
