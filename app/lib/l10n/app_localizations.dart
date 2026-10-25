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

  /// No description provided for @nowPlaying.
  ///
  /// In fr, this message translates to:
  /// **'En lecture'**
  String get nowPlaying;

  /// No description provided for @offlineChip.
  ///
  /// In fr, this message translates to:
  /// **'Hors ligne · tes téléchargements restent là'**
  String get offlineChip;

  /// No description provided for @offlineTrack.
  ///
  /// In fr, this message translates to:
  /// **'Ce titre n\'est pas téléchargé. Il revient dès que tu es en ligne.'**
  String get offlineTrack;

  /// No description provided for @playbackStopped.
  ///
  /// In fr, this message translates to:
  /// **'Lecture arrêtée'**
  String get playbackStopped;

  /// No description provided for @playingFrom.
  ///
  /// In fr, this message translates to:
  /// **'Lecture depuis {source}'**
  String playingFrom(String source);

  /// No description provided for @viewPlayer.
  ///
  /// In fr, this message translates to:
  /// **'Lecteur'**
  String get viewPlayer;

  /// No description provided for @viewLyrics.
  ///
  /// In fr, this message translates to:
  /// **'Paroles'**
  String get viewLyrics;

  /// No description provided for @viewQueue.
  ///
  /// In fr, this message translates to:
  /// **'File'**
  String get viewQueue;

  /// No description provided for @viewMenu.
  ///
  /// In fr, this message translates to:
  /// **'Vue {view}'**
  String viewMenu(String view);

  /// No description provided for @actionPlay.
  ///
  /// In fr, this message translates to:
  /// **'Lire'**
  String get actionPlay;

  /// No description provided for @actionPause.
  ///
  /// In fr, this message translates to:
  /// **'Mettre en pause'**
  String get actionPause;

  /// No description provided for @actionNext.
  ///
  /// In fr, this message translates to:
  /// **'Titre suivant'**
  String get actionNext;

  /// No description provided for @actionPrevious.
  ///
  /// In fr, this message translates to:
  /// **'Titre précédent'**
  String get actionPrevious;

  /// No description provided for @actionShuffle.
  ///
  /// In fr, this message translates to:
  /// **'Lecture aléatoire'**
  String get actionShuffle;

  /// No description provided for @actionRepeat.
  ///
  /// In fr, this message translates to:
  /// **'Répéter'**
  String get actionRepeat;

  /// No description provided for @actionLike.
  ///
  /// In fr, this message translates to:
  /// **'J\'aime'**
  String get actionLike;

  /// No description provided for @actionAddToPlaylist.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter à une playlist'**
  String get actionAddToPlaylist;

  /// No description provided for @actionDownload.
  ///
  /// In fr, this message translates to:
  /// **'Télécharger'**
  String get actionDownload;

  /// No description provided for @actionPlayNext.
  ///
  /// In fr, this message translates to:
  /// **'Lire ensuite'**
  String get actionPlayNext;

  /// No description provided for @actionAddToQueue.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter à la file'**
  String get actionAddToQueue;

  /// No description provided for @actionRemove.
  ///
  /// In fr, this message translates to:
  /// **'Retirer'**
  String get actionRemove;

  /// No description provided for @actionRetry.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get actionRetry;

  /// No description provided for @actionUndo.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get actionUndo;

  /// No description provided for @actionSeeAll.
  ///
  /// In fr, this message translates to:
  /// **'Tout voir'**
  String get actionSeeAll;

  /// No description provided for @actionReorder.
  ///
  /// In fr, this message translates to:
  /// **'Déplacer'**
  String get actionReorder;

  /// No description provided for @actionCollapse.
  ///
  /// In fr, this message translates to:
  /// **'Réduire'**
  String get actionCollapse;

  /// No description provided for @actionOutput.
  ///
  /// In fr, this message translates to:
  /// **'Sortie audio'**
  String get actionOutput;

  /// No description provided for @actionImmersive.
  ///
  /// In fr, this message translates to:
  /// **'Plein écran'**
  String get actionImmersive;

  /// No description provided for @actionMore.
  ///
  /// In fr, this message translates to:
  /// **'Plus d\'options'**
  String get actionMore;

  /// No description provided for @downloaded.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargé'**
  String get downloaded;

  /// No description provided for @downloading.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement en cours'**
  String get downloading;

  /// No description provided for @explicitLabel.
  ///
  /// In fr, this message translates to:
  /// **'Explicite'**
  String get explicitLabel;

  /// No description provided for @selectedLabel.
  ///
  /// In fr, this message translates to:
  /// **'Sélectionné'**
  String get selectedLabel;

  /// No description provided for @loading.
  ///
  /// In fr, this message translates to:
  /// **'Chargement'**
  String get loading;

  /// No description provided for @seekLabel.
  ///
  /// In fr, this message translates to:
  /// **'Position de lecture'**
  String get seekLabel;

  /// No description provided for @volumeLabel.
  ///
  /// In fr, this message translates to:
  /// **'Volume'**
  String get volumeLabel;

  /// No description provided for @sleepEndOfTrack.
  ///
  /// In fr, this message translates to:
  /// **'Fin du titre'**
  String get sleepEndOfTrack;

  /// No description provided for @sleepMinutesLeft.
  ///
  /// In fr, this message translates to:
  /// **'{minutes} min'**
  String sleepMinutesLeft(int minutes);

  /// No description provided for @themeLight.
  ///
  /// In fr, this message translates to:
  /// **'Clair'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In fr, this message translates to:
  /// **'Sombre'**
  String get themeDark;

  /// No description provided for @themePureBlack.
  ///
  /// In fr, this message translates to:
  /// **'Noir pur'**
  String get themePureBlack;

  /// No description provided for @colorSourceSystem.
  ///
  /// In fr, this message translates to:
  /// **'Système'**
  String get colorSourceSystem;

  /// No description provided for @colorSourcePreset.
  ///
  /// In fr, this message translates to:
  /// **'Préréglage {number}'**
  String colorSourcePreset(int number);

  /// No description provided for @colorSourceArtwork.
  ///
  /// In fr, this message translates to:
  /// **'Pochette {number}'**
  String colorSourceArtwork(int number);

  /// No description provided for @reduceMotion.
  ///
  /// In fr, this message translates to:
  /// **'Réduire les animations'**
  String get reduceMotion;

  /// No description provided for @playerStyleDisc.
  ///
  /// In fr, this message translates to:
  /// **'Disque'**
  String get playerStyleDisc;

  /// No description provided for @playerStyleWave.
  ///
  /// In fr, this message translates to:
  /// **'Vague'**
  String get playerStyleWave;

  /// No description provided for @galleryTitle.
  ///
  /// In fr, this message translates to:
  /// **'Galerie du design'**
  String get galleryTitle;

  /// No description provided for @galleryArtwork.
  ///
  /// In fr, this message translates to:
  /// **'Pochettes et formes'**
  String get galleryArtwork;

  /// No description provided for @galleryTrackRows.
  ///
  /// In fr, this message translates to:
  /// **'Lignes de titre'**
  String get galleryTrackRows;

  /// No description provided for @galleryPlayer.
  ///
  /// In fr, this message translates to:
  /// **'Lecteur'**
  String get galleryPlayer;

  /// No description provided for @galleryButtons.
  ///
  /// In fr, this message translates to:
  /// **'Boutons'**
  String get galleryButtons;

  /// No description provided for @galleryShelf.
  ///
  /// In fr, this message translates to:
  /// **'Étagère et carte héros'**
  String get galleryShelf;

  /// No description provided for @galleryTransitions.
  ///
  /// In fr, this message translates to:
  /// **'Transitions de page'**
  String get galleryTransitions;

  /// No description provided for @galleryFeedback.
  ///
  /// In fr, this message translates to:
  /// **'Chargement, messages et feuille latérale'**
  String get galleryFeedback;

  /// No description provided for @galleryListStates.
  ///
  /// In fr, this message translates to:
  /// **'États des listes'**
  String get galleryListStates;

  /// No description provided for @galleryTypography.
  ///
  /// In fr, this message translates to:
  /// **'Typographie'**
  String get galleryTypography;

  /// No description provided for @gallerySpacing.
  ///
  /// In fr, this message translates to:
  /// **'Espacements'**
  String get gallerySpacing;

  /// No description provided for @galleryReplay.
  ///
  /// In fr, this message translates to:
  /// **'Rejouer'**
  String get galleryReplay;

  /// No description provided for @galleryShowSnack.
  ///
  /// In fr, this message translates to:
  /// **'Afficher un message'**
  String get galleryShowSnack;

  /// No description provided for @galleryToggleSheet.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir ou fermer la feuille'**
  String get galleryToggleSheet;

  /// No description provided for @galleryOpenMenu.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir le menu'**
  String get galleryOpenMenu;

  /// No description provided for @transitionContainer.
  ///
  /// In fr, this message translates to:
  /// **'Carte vers page'**
  String get transitionContainer;

  /// No description provided for @transitionFadeThrough.
  ///
  /// In fr, this message translates to:
  /// **'Changement de destination'**
  String get transitionFadeThrough;

  /// No description provided for @transitionSharedAxis.
  ///
  /// In fr, this message translates to:
  /// **'Vues du lecteur'**
  String get transitionSharedAxis;

  /// No description provided for @emptyLikes.
  ///
  /// In fr, this message translates to:
  /// **'Rien de liké pour l\'instant. Touche le cœur d\'un titre pour le retrouver ici.'**
  String get emptyLikes;

  /// No description provided for @shelfTracks.
  ///
  /// In fr, this message translates to:
  /// **'Titres'**
  String get shelfTracks;

  /// No description provided for @shelfAlbums.
  ///
  /// In fr, this message translates to:
  /// **'Albums'**
  String get shelfAlbums;

  /// No description provided for @shelfArtists.
  ///
  /// In fr, this message translates to:
  /// **'Artistes'**
  String get shelfArtists;

  /// No description provided for @shelfPlaylists.
  ///
  /// In fr, this message translates to:
  /// **'Playlists'**
  String get shelfPlaylists;

  /// No description provided for @actionOpenPlayer.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir le lecteur'**
  String get actionOpenPlayer;

  /// No description provided for @actionStop.
  ///
  /// In fr, this message translates to:
  /// **'Arrêter la lecture'**
  String get actionStop;

  /// No description provided for @actionExitImmersive.
  ///
  /// In fr, this message translates to:
  /// **'Quitter le plein écran'**
  String get actionExitImmersive;

  /// No description provided for @miniPlayerLabel.
  ///
  /// In fr, this message translates to:
  /// **'Mini-lecteur'**
  String get miniPlayerLabel;

  /// No description provided for @playingFromLabel.
  ///
  /// In fr, this message translates to:
  /// **'Lecture depuis'**
  String get playingFromLabel;

  /// No description provided for @actionNewPlaylist.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle playlist'**
  String get actionNewPlaylist;

  /// No description provided for @actionImportLink.
  ///
  /// In fr, this message translates to:
  /// **'Importer un lien'**
  String get actionImportLink;

  /// No description provided for @actionCreate.
  ///
  /// In fr, this message translates to:
  /// **'Créer'**
  String get actionCreate;

  /// No description provided for @actionCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get actionCancel;

  /// No description provided for @actionOk.
  ///
  /// In fr, this message translates to:
  /// **'OK'**
  String get actionOk;

  /// No description provided for @actionAdd.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter'**
  String get actionAdd;

  /// No description provided for @actionLater.
  ///
  /// In fr, this message translates to:
  /// **'Plus tard'**
  String get actionLater;

  /// No description provided for @actionInstall.
  ///
  /// In fr, this message translates to:
  /// **'Installer'**
  String get actionInstall;

  /// No description provided for @actionSelectAll.
  ///
  /// In fr, this message translates to:
  /// **'Tout sélectionner'**
  String get actionSelectAll;

  /// No description provided for @actionExpandMenu.
  ///
  /// In fr, this message translates to:
  /// **'Déplier le menu'**
  String get actionExpandMenu;

  /// No description provided for @actionCollapseMenu.
  ///
  /// In fr, this message translates to:
  /// **'Replier le menu'**
  String get actionCollapseMenu;

  /// No description provided for @navHome.
  ///
  /// In fr, this message translates to:
  /// **'Accueil'**
  String get navHome;

  /// No description provided for @navExplore.
  ///
  /// In fr, this message translates to:
  /// **'Explorer'**
  String get navExplore;

  /// No description provided for @navLibrary.
  ///
  /// In fr, this message translates to:
  /// **'Bibliothèque'**
  String get navLibrary;

  /// No description provided for @navSettings.
  ///
  /// In fr, this message translates to:
  /// **'Réglages'**
  String get navSettings;

  /// No description provided for @railPinned.
  ///
  /// In fr, this message translates to:
  /// **'Épinglés'**
  String get railPinned;

  /// No description provided for @likedTracks.
  ///
  /// In fr, this message translates to:
  /// **'Titres likés'**
  String get likedTracks;

  /// No description provided for @downloadsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargements'**
  String get downloadsTitle;

  /// No description provided for @sourcesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Sources'**
  String get sourcesTitle;

  /// No description provided for @searchHint.
  ///
  /// In fr, this message translates to:
  /// **'Titres, albums, artistes…'**
  String get searchHint;

  /// No description provided for @selectionCount.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 sélectionné} other{{count} sélectionnés}}'**
  String selectionCount(int count);

  /// No description provided for @settingsAppearance.
  ///
  /// In fr, this message translates to:
  /// **'Apparence'**
  String get settingsAppearance;

  /// No description provided for @settingsColor.
  ///
  /// In fr, this message translates to:
  /// **'Couleur'**
  String get settingsColor;

  /// No description provided for @settingsPlayerStyle.
  ///
  /// In fr, this message translates to:
  /// **'Style du lecteur'**
  String get settingsPlayerStyle;

  /// No description provided for @settingsTheme.
  ///
  /// In fr, this message translates to:
  /// **'Thème'**
  String get settingsTheme;

  /// No description provided for @settingsPlayback.
  ///
  /// In fr, this message translates to:
  /// **'Lecture'**
  String get settingsPlayback;

  /// No description provided for @settingsNormalize.
  ///
  /// In fr, this message translates to:
  /// **'Volume égal d\'un titre à l\'autre'**
  String get settingsNormalize;

  /// No description provided for @settingsEndRadio.
  ///
  /// In fr, this message translates to:
  /// **'Radio quand la file se termine'**
  String get settingsEndRadio;

  /// No description provided for @themeSystem.
  ///
  /// In fr, this message translates to:
  /// **'Système'**
  String get themeSystem;

  /// No description provided for @colorSourceNowPlaying.
  ///
  /// In fr, this message translates to:
  /// **'Ce qui joue'**
  String get colorSourceNowPlaying;

  /// No description provided for @colorSourcePresets.
  ///
  /// In fr, this message translates to:
  /// **'Préréglage'**
  String get colorSourcePresets;

  /// No description provided for @gestureHintTitle.
  ///
  /// In fr, this message translates to:
  /// **'Le mini-lecteur'**
  String get gestureHintTitle;

  /// No description provided for @gestureHint.
  ///
  /// In fr, this message translates to:
  /// **'Glisse ← → pour changer de titre, ↓ pour arrêter.'**
  String get gestureHint;

  /// No description provided for @updateTitle.
  ///
  /// In fr, this message translates to:
  /// **'Mise à jour disponible'**
  String get updateTitle;

  /// No description provided for @updateBody.
  ///
  /// In fr, this message translates to:
  /// **'Version {version}, {size}. La lecture reprend plus vite après un appel.'**
  String updateBody(String version, String size);

  /// No description provided for @addSourceWarning.
  ///
  /// In fr, this message translates to:
  /// **'Cette source ne vient pas de Vehicoule. Ajoute-la seulement si tu lui fais confiance.'**
  String get addSourceWarning;

  /// No description provided for @greeting.
  ///
  /// In fr, this message translates to:
  /// **'Bonsoir'**
  String get greeting;

  /// No description provided for @discoveryTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ta découverte du jour'**
  String get discoveryTitle;

  /// No description provided for @galleryJump.
  ///
  /// In fr, this message translates to:
  /// **'Aller à'**
  String get galleryJump;

  /// No description provided for @galleryMiniPlayer.
  ///
  /// In fr, this message translates to:
  /// **'Mini-lecteur et bande'**
  String get galleryMiniPlayer;

  /// No description provided for @galleryFabs.
  ///
  /// In fr, this message translates to:
  /// **'Boutons flottants'**
  String get galleryFabs;

  /// No description provided for @galleryButtonGroups.
  ///
  /// In fr, this message translates to:
  /// **'Groupes de boutons'**
  String get galleryButtonGroups;

  /// No description provided for @galleryToolbars.
  ///
  /// In fr, this message translates to:
  /// **'Barres d\'outils'**
  String get galleryToolbars;

  /// No description provided for @galleryMenus.
  ///
  /// In fr, this message translates to:
  /// **'Menus'**
  String get galleryMenus;

  /// No description provided for @gallerySheets.
  ///
  /// In fr, this message translates to:
  /// **'Feuilles et dialogues'**
  String get gallerySheets;

  /// No description provided for @galleryNavigation.
  ///
  /// In fr, this message translates to:
  /// **'Navigation'**
  String get galleryNavigation;

  /// No description provided for @gallerySearch.
  ///
  /// In fr, this message translates to:
  /// **'Recherche et filtres'**
  String get gallerySearch;

  /// No description provided for @galleryCarousels.
  ///
  /// In fr, this message translates to:
  /// **'Carrousels et étagères'**
  String get galleryCarousels;

  /// No description provided for @gallerySettings.
  ///
  /// In fr, this message translates to:
  /// **'Réglages'**
  String get gallerySettings;

  /// No description provided for @galleryStates.
  ///
  /// In fr, this message translates to:
  /// **'Chargement et états'**
  String get galleryStates;

  /// No description provided for @galleryShowDialog.
  ///
  /// In fr, this message translates to:
  /// **'Afficher un dialogue'**
  String get galleryShowDialog;

  /// No description provided for @galleryShowSheet.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir une feuille'**
  String get galleryShowSheet;

  /// No description provided for @galleryShowSourceSheet.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une source'**
  String get galleryShowSourceSheet;

  /// No description provided for @galleryShowSideSheet.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir une feuille latérale'**
  String get galleryShowSideSheet;

  /// No description provided for @galleryOpenMenuEdge.
  ///
  /// In fr, this message translates to:
  /// **'Menu au bord'**
  String get galleryOpenMenuEdge;

  /// No description provided for @fabLaunch.
  ///
  /// In fr, this message translates to:
  /// **'Lancer'**
  String get fabLaunch;

  /// No description provided for @fabNew.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle'**
  String get fabNew;

  /// No description provided for @launchShuffleLikes.
  ///
  /// In fr, this message translates to:
  /// **'Mélanger mes likés'**
  String get launchShuffleLikes;

  /// No description provided for @launchRadio.
  ///
  /// In fr, this message translates to:
  /// **'Radio de ce que j\'écoute'**
  String get launchRadio;

  /// No description provided for @launchResume.
  ///
  /// In fr, this message translates to:
  /// **'Reprendre la dernière écoute'**
  String get launchResume;

  /// No description provided for @actionPlayInOrder.
  ///
  /// In fr, this message translates to:
  /// **'Lire dans l\'ordre'**
  String get actionPlayInOrder;

  /// No description provided for @actionRadio.
  ///
  /// In fr, this message translates to:
  /// **'Radio'**
  String get actionRadio;

  /// No description provided for @galleryFabHome.
  ///
  /// In fr, this message translates to:
  /// **'Accueil'**
  String get galleryFabHome;

  /// No description provided for @galleryFabSources.
  ///
  /// In fr, this message translates to:
  /// **'Sources'**
  String get galleryFabSources;

  /// No description provided for @galleryFabCollection.
  ///
  /// In fr, this message translates to:
  /// **'Album'**
  String get galleryFabCollection;

  /// No description provided for @galleryFabArtist.
  ///
  /// In fr, this message translates to:
  /// **'Artiste'**
  String get galleryFabArtist;

  /// No description provided for @galleryFabPhone.
  ///
  /// In fr, this message translates to:
  /// **'Téléphone, avec le mini-lecteur'**
  String get galleryFabPhone;

  /// The artist's split button and its FAB (spec UI §5.4).
  ///
  /// In fr, this message translates to:
  /// **'Aléatoire'**
  String get splitShuffle;

  /// The app's name: the macOS application menu.
  ///
  /// In fr, this message translates to:
  /// **'Vehicoule'**
  String get appName;

  /// No description provided for @actionOpenMenu.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir le menu'**
  String get actionOpenMenu;

  /// No description provided for @domainMusic.
  ///
  /// In fr, this message translates to:
  /// **'Musique'**
  String get domainMusic;

  /// No description provided for @domainVideo.
  ///
  /// In fr, this message translates to:
  /// **'Vidéos'**
  String get domainVideo;

  /// No description provided for @domainBooks.
  ///
  /// In fr, this message translates to:
  /// **'Livres'**
  String get domainBooks;

  /// No description provided for @actionHistoryBack.
  ///
  /// In fr, this message translates to:
  /// **'Page précédente'**
  String get actionHistoryBack;

  /// No description provided for @actionHistoryForward.
  ///
  /// In fr, this message translates to:
  /// **'Page suivante'**
  String get actionHistoryForward;

  /// No description provided for @actionSearch.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher'**
  String get actionSearch;

  /// No description provided for @actionPlayPause.
  ///
  /// In fr, this message translates to:
  /// **'Lecture ou pause'**
  String get actionPlayPause;

  /// No description provided for @actionSeekBack.
  ///
  /// In fr, this message translates to:
  /// **'Reculer de 10 s'**
  String get actionSeekBack;

  /// No description provided for @actionSeekForward.
  ///
  /// In fr, this message translates to:
  /// **'Avancer de 10 s'**
  String get actionSeekForward;

  /// No description provided for @actionVolumeUp.
  ///
  /// In fr, this message translates to:
  /// **'Monter le volume'**
  String get actionVolumeUp;

  /// No description provided for @actionVolumeDown.
  ///
  /// In fr, this message translates to:
  /// **'Baisser le volume'**
  String get actionVolumeDown;

  /// No description provided for @actionRefreshHome.
  ///
  /// In fr, this message translates to:
  /// **'Rafraîchir l\'accueil'**
  String get actionRefreshHome;

  /// ⌘⌥B and the Fenêtre menu: fold or unfold the desktop pane.
  ///
  /// In fr, this message translates to:
  /// **'Panneau en lecture'**
  String get actionTogglePane;

  /// No description provided for @menuPlayback.
  ///
  /// In fr, this message translates to:
  /// **'Lecture'**
  String get menuPlayback;

  /// No description provided for @menuGo.
  ///
  /// In fr, this message translates to:
  /// **'Aller'**
  String get menuGo;

  /// No description provided for @menuWindow.
  ///
  /// In fr, this message translates to:
  /// **'Fenêtre'**
  String get menuWindow;

  /// No description provided for @downloadedTracks.
  ///
  /// In fr, this message translates to:
  /// **'Titres téléchargés'**
  String get downloadedTracks;

  /// No description provided for @topTracks.
  ///
  /// In fr, this message translates to:
  /// **'Top 50'**
  String get topTracks;

  /// No description provided for @historyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Historique'**
  String get historyTitle;

  /// No description provided for @settingsDiagnostics.
  ///
  /// In fr, this message translates to:
  /// **'Diagnostics'**
  String get settingsDiagnostics;

  /// No description provided for @onboardingTitle.
  ///
  /// In fr, this message translates to:
  /// **'Bienvenue'**
  String get onboardingTitle;

  /// Notice.skipped (spec UI §2.9).
  ///
  /// In fr, this message translates to:
  /// **'« {title} » n\'a pas pu être lu, on continue.'**
  String trackSkipped(String title);

  /// Windows/Linux tray menu: bring the window back.
  ///
  /// In fr, this message translates to:
  /// **'Afficher Vehicoule'**
  String get trayShow;

  /// No description provided for @trayQuit.
  ///
  /// In fr, this message translates to:
  /// **'Quitter'**
  String get trayQuit;

  /// No description provided for @pinnedDropHere.
  ///
  /// In fr, this message translates to:
  /// **'déposer ici'**
  String get pinnedDropHere;

  /// No description provided for @pinnedKindTracks.
  ///
  /// In fr, this message translates to:
  /// **'Titres'**
  String get pinnedKindTracks;

  /// No description provided for @pinnedKindPlaylist.
  ///
  /// In fr, this message translates to:
  /// **'Playlist'**
  String get pinnedKindPlaylist;

  /// No description provided for @pinnedKindAlbum.
  ///
  /// In fr, this message translates to:
  /// **'Album'**
  String get pinnedKindAlbum;

  /// No description provided for @pinnedKindArtist.
  ///
  /// In fr, this message translates to:
  /// **'Artiste'**
  String get pinnedKindArtist;

  /// The title bar search's key hint (macOS).
  ///
  /// In fr, this message translates to:
  /// **'⌘F'**
  String get shortcutSearchApple;

  /// No description provided for @shortcutSearchOther.
  ///
  /// In fr, this message translates to:
  /// **'Ctrl+F'**
  String get shortcutSearchOther;

  /// A screen with nothing to show yet (its VEmptyState).
  ///
  /// In fr, this message translates to:
  /// **'Rien ici pour l\'instant.'**
  String get emptyScreen;
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
