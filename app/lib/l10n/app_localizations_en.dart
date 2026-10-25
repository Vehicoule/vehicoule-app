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

  @override
  String get nowPlaying => 'Now playing';

  @override
  String get offlineChip => 'Offline · your downloads are still here';

  @override
  String get offlineTrack =>
      'This track isn\'t downloaded. It\'s back as soon as you\'re online.';

  @override
  String get playbackStopped => 'Playback stopped';

  @override
  String playingFrom(String source) {
    return 'Playing from $source';
  }

  @override
  String get viewPlayer => 'Player';

  @override
  String get viewLyrics => 'Lyrics';

  @override
  String get viewQueue => 'Queue';

  @override
  String get actionPlay => 'Play';

  @override
  String get actionPause => 'Pause';

  @override
  String get actionNext => 'Next track';

  @override
  String get actionPrevious => 'Previous track';

  @override
  String get actionShuffle => 'Shuffle';

  @override
  String get actionRepeat => 'Repeat';

  @override
  String get actionLike => 'Like';

  @override
  String get actionAddToPlaylist => 'Add to a playlist';

  @override
  String get actionDownload => 'Download';

  @override
  String get actionPlayNext => 'Play next';

  @override
  String get actionAddToQueue => 'Add to queue';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionUndo => 'Undo';

  @override
  String get actionSeeAll => 'See all';

  @override
  String get actionReorder => 'Move';

  @override
  String get actionCollapse => 'Collapse';

  @override
  String get actionOutput => 'Audio output';

  @override
  String get actionImmersive => 'Full screen';

  @override
  String get actionMore => 'More options';

  @override
  String get downloaded => 'Downloaded';

  @override
  String get downloading => 'Downloading';

  @override
  String get explicitLabel => 'Explicit';

  @override
  String get selectedLabel => 'Selected';

  @override
  String get loading => 'Loading';

  @override
  String get seekLabel => 'Playback position';

  @override
  String get volumeLabel => 'Volume';

  @override
  String get sleepEndOfTrack => 'End of track';

  @override
  String sleepMinutesLeft(int minutes) {
    return '$minutes min';
  }

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themePureBlack => 'Pure black';

  @override
  String get colorSourceSystem => 'System';

  @override
  String colorSourcePreset(int number) {
    return 'Preset $number';
  }

  @override
  String colorSourceArtwork(int number) {
    return 'Artwork $number';
  }

  @override
  String get reduceMotion => 'Reduce motion';

  @override
  String get playerStyleDisc => 'Disc';

  @override
  String get playerStyleWave => 'Wave';

  @override
  String get galleryTitle => 'Design gallery';

  @override
  String get galleryArtwork => 'Artwork and shapes';

  @override
  String get galleryTrackRows => 'Track rows';

  @override
  String get galleryPlayer => 'Player';

  @override
  String get galleryButtons => 'Buttons';

  @override
  String get galleryShelf => 'Shelf and hero card';

  @override
  String get galleryTransitions => 'Page transitions';

  @override
  String get galleryFeedback => 'Loading, messages and side sheet';

  @override
  String get galleryListStates => 'List states';

  @override
  String get galleryTypography => 'Typography';

  @override
  String get gallerySpacing => 'Spacing';

  @override
  String get galleryReplay => 'Replay';

  @override
  String get galleryShowSnack => 'Show a message';

  @override
  String get galleryToggleSheet => 'Open or close the sheet';

  @override
  String get galleryOpenMenu => 'Open the menu';

  @override
  String get transitionContainer => 'Card to page';

  @override
  String get transitionFadeThrough => 'Change of destination';

  @override
  String get transitionSharedAxis => 'Player views';

  @override
  String get emptyLikes =>
      'Nothing liked yet. Tap the heart on a track to find it here.';

  @override
  String get shelfTracks => 'Tracks';

  @override
  String get shelfAlbums => 'Albums';

  @override
  String get shelfArtists => 'Artists';

  @override
  String get shelfPlaylists => 'Playlists';

  @override
  String get actionOpenPlayer => 'Open the player';

  @override
  String get actionStop => 'Stop playback';

  @override
  String get actionExitImmersive => 'Exit full screen';

  @override
  String get miniPlayerLabel => 'Mini player';

  @override
  String get playingFromLabel => 'Playing from';

  @override
  String get actionNewPlaylist => 'New playlist';

  @override
  String get actionImportLink => 'Import a link';

  @override
  String get actionCreate => 'Create';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionOk => 'OK';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionLater => 'Later';

  @override
  String get actionInstall => 'Install';

  @override
  String get actionSelectAll => 'Select all';

  @override
  String get actionExpandMenu => 'Expand the menu';

  @override
  String get actionCollapseMenu => 'Collapse the menu';

  @override
  String get navHome => 'Home';

  @override
  String get navExplore => 'Explore';

  @override
  String get navLibrary => 'Library';

  @override
  String get navSettings => 'Settings';

  @override
  String get railPinned => 'Pinned';

  @override
  String get likedTracks => 'Liked songs';

  @override
  String get downloadsTitle => 'Downloads';

  @override
  String get sourcesTitle => 'Sources';

  @override
  String get searchHint => 'Songs, albums, artists…';

  @override
  String selectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsColor => 'Colour';

  @override
  String get settingsPlayerStyle => 'Player style';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsPlayback => 'Playback';

  @override
  String get settingsNormalize => 'Same volume from one song to the next';

  @override
  String get settingsEndRadio => 'Radio when the queue ends';

  @override
  String get themeSystem => 'System';

  @override
  String get colorSourceNowPlaying => 'What\'s playing';

  @override
  String get colorSourcePresets => 'Preset';

  @override
  String get gestureHintTitle => 'The mini player';

  @override
  String get gestureHint => 'Swipe ← → to change songs, ↓ to stop.';

  @override
  String get updateTitle => 'Update available';

  @override
  String updateBody(String version, String size) {
    return 'Version $version, $size. Playback resumes faster after a call.';
  }

  @override
  String get addSourceWarning =>
      'This source doesn\'t come from Vehicoule. Add it only if you trust it.';

  @override
  String get greeting => 'Good evening';

  @override
  String get discoveryTitle => 'Your discovery of the day';

  @override
  String get galleryJump => 'Go to';

  @override
  String get galleryMiniPlayer => 'Mini player and strip';

  @override
  String get galleryFabs => 'Floating buttons';

  @override
  String get galleryButtonGroups => 'Button groups';

  @override
  String get galleryToolbars => 'Toolbars';

  @override
  String get galleryMenus => 'Menus';

  @override
  String get gallerySheets => 'Sheets and dialogs';

  @override
  String get galleryNavigation => 'Navigation';

  @override
  String get gallerySearch => 'Search and filters';

  @override
  String get galleryCarousels => 'Carousels and shelves';

  @override
  String get gallerySettings => 'Settings';

  @override
  String get galleryStates => 'Loading and states';

  @override
  String get galleryShowDialog => 'Show a dialog';

  @override
  String get galleryShowSheet => 'Open a sheet';

  @override
  String get galleryShowSourceSheet => 'Add a source';

  @override
  String get galleryShowSideSheet => 'Open a side sheet';

  @override
  String get galleryOpenMenuEdge => 'Menu at the edge';

  @override
  String get fabLaunch => 'Start';

  @override
  String get fabNew => 'New';

  @override
  String get launchShuffleLikes => 'Shuffle my likes';

  @override
  String get launchRadio => 'Radio from what I play';

  @override
  String get launchResume => 'Resume where I left off';

  @override
  String get actionPlayInOrder => 'Play in order';

  @override
  String get actionRadio => 'Radio';

  @override
  String get galleryFabHome => 'Home';

  @override
  String get galleryFabSources => 'Sources';

  @override
  String get galleryFabCollection => 'Album';

  @override
  String get galleryFabArtist => 'Artist';

  @override
  String get galleryFabPhone => 'Phone, with the mini player';

  @override
  String get splitShuffle => 'Shuffle';

  @override
  String get appName => 'Vehicoule';

  @override
  String get actionOpenMenu => 'Open the menu';

  @override
  String get domainMusic => 'Music';

  @override
  String get actionHistoryBack => 'Previous page';

  @override
  String get actionHistoryForward => 'Next page';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionPlayPause => 'Play or pause';

  @override
  String get actionSeekBack => 'Back 10 s';

  @override
  String get actionSeekForward => 'Forward 10 s';

  @override
  String get actionVolumeUp => 'Volume up';

  @override
  String get actionVolumeDown => 'Volume down';

  @override
  String get actionRefreshHome => 'Refresh home';

  @override
  String get actionTogglePane => 'Now playing pane';

  @override
  String get menuPlayback => 'Playback';

  @override
  String get menuGo => 'Go';

  @override
  String get menuWindow => 'Window';

  @override
  String get downloadedTracks => 'Downloaded tracks';

  @override
  String get topTracks => 'Top 50';

  @override
  String get historyTitle => 'History';

  @override
  String get settingsDiagnostics => 'Diagnostics';

  @override
  String get onboardingTitle => 'Welcome';

  @override
  String trackSkipped(String title) {
    return 'Couldn\'t play “$title”, moving on.';
  }
}
