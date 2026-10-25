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

  @override
  String get nowPlaying => 'En lecture';

  @override
  String get offlineChip => 'Hors ligne · tes téléchargements restent là';

  @override
  String get offlineTrack =>
      'Ce titre n\'est pas téléchargé. Il revient dès que tu es en ligne.';

  @override
  String get playbackStopped => 'Lecture arrêtée';

  @override
  String playingFrom(String source) {
    return 'Lecture depuis $source';
  }

  @override
  String get viewPlayer => 'Lecteur';

  @override
  String get viewLyrics => 'Paroles';

  @override
  String get viewQueue => 'File';

  @override
  String get actionPlay => 'Lire';

  @override
  String get actionPause => 'Mettre en pause';

  @override
  String get actionNext => 'Titre suivant';

  @override
  String get actionPrevious => 'Titre précédent';

  @override
  String get actionShuffle => 'Lecture aléatoire';

  @override
  String get actionRepeat => 'Répéter';

  @override
  String get actionLike => 'J\'aime';

  @override
  String get actionAddToPlaylist => 'Ajouter à une playlist';

  @override
  String get actionDownload => 'Télécharger';

  @override
  String get actionPlayNext => 'Lire ensuite';

  @override
  String get actionAddToQueue => 'Ajouter à la file';

  @override
  String get actionRemove => 'Retirer';

  @override
  String get actionRetry => 'Réessayer';

  @override
  String get actionUndo => 'Annuler';

  @override
  String get actionSeeAll => 'Tout voir';

  @override
  String get actionReorder => 'Déplacer';

  @override
  String get actionCollapse => 'Réduire';

  @override
  String get actionOutput => 'Sortie audio';

  @override
  String get actionImmersive => 'Plein écran';

  @override
  String get actionMore => 'Plus d\'options';

  @override
  String get downloaded => 'Téléchargé';

  @override
  String get downloading => 'Téléchargement en cours';

  @override
  String get explicitLabel => 'Explicite';

  @override
  String get selectedLabel => 'Sélectionné';

  @override
  String get loading => 'Chargement';

  @override
  String get seekLabel => 'Position de lecture';

  @override
  String get volumeLabel => 'Volume';

  @override
  String get sleepEndOfTrack => 'Fin du titre';

  @override
  String sleepMinutesLeft(int minutes) {
    return '$minutes min';
  }

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get themePureBlack => 'Noir pur';

  @override
  String get colorSourceSystem => 'Système';

  @override
  String colorSourcePreset(int number) {
    return 'Préréglage $number';
  }

  @override
  String colorSourceArtwork(int number) {
    return 'Pochette $number';
  }

  @override
  String get reduceMotion => 'Réduire les animations';

  @override
  String get playerStyleDisc => 'Disque';

  @override
  String get playerStyleWave => 'Vague';

  @override
  String get galleryTitle => 'Galerie du design';

  @override
  String get galleryArtwork => 'Pochettes et formes';

  @override
  String get galleryTrackRows => 'Lignes de titre';

  @override
  String get galleryPlayer => 'Lecteur';

  @override
  String get galleryButtons => 'Boutons';

  @override
  String get galleryShelf => 'Étagère et carte héros';

  @override
  String get galleryTransitions => 'Transitions de page';

  @override
  String get galleryFeedback => 'Chargement, messages et feuille latérale';

  @override
  String get galleryListStates => 'États des listes';

  @override
  String get galleryTypography => 'Typographie';

  @override
  String get gallerySpacing => 'Espacements';

  @override
  String get galleryReplay => 'Rejouer';

  @override
  String get galleryShowSnack => 'Afficher un message';

  @override
  String get galleryToggleSheet => 'Ouvrir ou fermer la feuille';

  @override
  String get galleryOpenMenu => 'Ouvrir le menu';

  @override
  String get transitionContainer => 'Carte vers page';

  @override
  String get transitionFadeThrough => 'Changement de destination';

  @override
  String get transitionSharedAxis => 'Vues du lecteur';

  @override
  String get emptyLikes =>
      'Rien de liké pour l\'instant. Touche le cœur d\'un titre pour le retrouver ici.';

  @override
  String get shelfTracks => 'Titres';

  @override
  String get shelfAlbums => 'Albums';

  @override
  String get shelfArtists => 'Artistes';

  @override
  String get shelfPlaylists => 'Playlists';

  @override
  String get actionOpenPlayer => 'Ouvrir le lecteur';

  @override
  String get actionStop => 'Arrêter la lecture';

  @override
  String get actionExitImmersive => 'Quitter le plein écran';

  @override
  String get miniPlayerLabel => 'Mini-lecteur';

  @override
  String get playingFromLabel => 'Lecture depuis';

  @override
  String get actionNewPlaylist => 'Nouvelle playlist';

  @override
  String get actionImportLink => 'Importer un lien';

  @override
  String get actionCreate => 'Créer';

  @override
  String get actionCancel => 'Annuler';

  @override
  String get actionOk => 'OK';

  @override
  String get actionAdd => 'Ajouter';

  @override
  String get actionLater => 'Plus tard';

  @override
  String get actionInstall => 'Installer';

  @override
  String get actionSelectAll => 'Tout sélectionner';

  @override
  String get actionExpandMenu => 'Déplier le menu';

  @override
  String get actionCollapseMenu => 'Replier le menu';

  @override
  String get navHome => 'Accueil';

  @override
  String get navExplore => 'Explorer';

  @override
  String get navLibrary => 'Bibliothèque';

  @override
  String get navSettings => 'Réglages';

  @override
  String get railPinned => 'Épinglés';

  @override
  String get likedTracks => 'Titres likés';

  @override
  String get downloadsTitle => 'Téléchargements';

  @override
  String get sourcesTitle => 'Sources';

  @override
  String get searchHint => 'Titres, albums, artistes…';

  @override
  String selectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnés',
      one: '1 sélectionné',
    );
    return '$_temp0';
  }

  @override
  String get settingsAppearance => 'Apparence';

  @override
  String get settingsColor => 'Couleur';

  @override
  String get settingsPlayerStyle => 'Style du lecteur';

  @override
  String get settingsTheme => 'Thème';

  @override
  String get settingsPlayback => 'Lecture';

  @override
  String get settingsNormalize => 'Volume égal d\'un titre à l\'autre';

  @override
  String get settingsEndRadio => 'Radio quand la file se termine';

  @override
  String get themeSystem => 'Système';

  @override
  String get colorSourceNowPlaying => 'Ce qui joue';

  @override
  String get colorSourcePresets => 'Préréglage';

  @override
  String get gestureHintTitle => 'Le mini-lecteur';

  @override
  String get gestureHint => 'Glisse ← → pour changer de titre, ↓ pour arrêter.';

  @override
  String get updateTitle => 'Mise à jour disponible';

  @override
  String updateBody(String version, String size) {
    return 'Version $version, $size. La lecture reprend plus vite après un appel.';
  }

  @override
  String get addSourceWarning =>
      'Cette source ne vient pas de Vehicoule. Ajoute-la seulement si tu lui fais confiance.';

  @override
  String get greeting => 'Bonsoir';

  @override
  String get discoveryTitle => 'Ta découverte du jour';

  @override
  String get galleryJump => 'Aller à';

  @override
  String get galleryMiniPlayer => 'Mini-lecteur et bande';

  @override
  String get galleryFabs => 'Boutons flottants';

  @override
  String get galleryButtonGroups => 'Groupes de boutons';

  @override
  String get galleryToolbars => 'Barres d\'outils';

  @override
  String get galleryMenus => 'Menus';

  @override
  String get gallerySheets => 'Feuilles et dialogues';

  @override
  String get galleryNavigation => 'Navigation';

  @override
  String get gallerySearch => 'Recherche et filtres';

  @override
  String get galleryCarousels => 'Carrousels et étagères';

  @override
  String get gallerySettings => 'Réglages';

  @override
  String get galleryStates => 'Chargement et états';

  @override
  String get galleryShowDialog => 'Afficher un dialogue';

  @override
  String get galleryShowSheet => 'Ouvrir une feuille';

  @override
  String get galleryShowSourceSheet => 'Ajouter une source';

  @override
  String get galleryShowSideSheet => 'Ouvrir une feuille latérale';

  @override
  String get galleryOpenMenuEdge => 'Menu au bord';

  @override
  String get fabLaunch => 'Lancer';

  @override
  String get fabNew => 'Nouvelle';

  @override
  String get launchShuffleLikes => 'Mélanger mes likés';

  @override
  String get launchRadio => 'Radio de ce que j\'écoute';

  @override
  String get launchResume => 'Reprendre la dernière écoute';

  @override
  String get actionPlayInOrder => 'Lire dans l\'ordre';

  @override
  String get actionRadio => 'Radio';

  @override
  String get galleryFabHome => 'Accueil';

  @override
  String get galleryFabSources => 'Sources';

  @override
  String get galleryFabCollection => 'Album';

  @override
  String get galleryFabArtist => 'Artiste';

  @override
  String get galleryFabPhone => 'Téléphone, avec le mini-lecteur';

  @override
  String get splitShuffle => 'Aléatoire';
}
