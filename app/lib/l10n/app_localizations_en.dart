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
}
