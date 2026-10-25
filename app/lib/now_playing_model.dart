/// What plays, once for the whole app: the core's `nowPlaying` and `queueStates`, the
/// player's state, and the player's actions. Every player on screen (mini player, sheet,
/// pane, strip, immersive view) reads it; the shell turns it into [NowPlayingScope].
library;

import 'package:material_ui/material_ui.dart';

import 'bridge/api/library.dart' as store;
import 'bridge/api/playback.dart' as core;
import 'bridge/catalog.dart';
import 'bridge/downloads.dart';
import 'bridge/events.dart';
import 'bridge/player.dart'
    show QueueOp, SleepState_EndOfTrack, SleepState_EndsAt;
import 'bridge/queue.dart';
import 'design/design.dart';
import 'l10n/app_localizations.dart';
import 'platform/player.dart';

class NowPlayingModel extends ChangeNotifier {
  NowPlayingModel(this.player);

  final PlayerAdapter player;

  NowPlaying _now = const NowPlaying();
  QueueView? _queue;
  bool _playing = false, _loading = false;
  final _downloads = <String, DownloadProgress>{};

  /// Likes not yet echoed by the core, by track.
  final _liked = <String, bool>{};
  PlayerView _view = PlayerView.player;

  /// Subscribes before the core starts, so the restored queue lands here.
  void start() {
    core.nowPlaying().listen((n) {
      _now = n;
      _liked.clear();
      notifyListeners();
    });
    core.queueStates().listen((q) {
      _queue = q;
      notifyListeners();
    });
    player.playing.listen((p) {
      _playing = p;
      notifyListeners();
    });
    player.loading.listen((l) {
      _loading = l;
      notifyListeners();
    });
    store.downloadProgress().listen((p) {
      _downloads[p.id] = p;
      if (p.id == track?.id) notifyListeners();
    });
  }

  TrackView? get track => _now.track;
  QueueView? get queue => _queue;
  bool get playing => _playing;

  /// The album, playlist or artist the queue plays from.
  String? get contextId => _queue?.context?.id;

  /// Lecteur, Paroles or File: one choice for every player on screen.
  PlayerView get view => _view;
  set view(PlayerView v) {
    if (v == _view) return;
    _view = v;
    notifyListeners();
  }

  bool get _likedNow {
    final t = track;
    return t != null && (_liked[t.id] ?? t.liked);
  }

  /// The player's slow state; null when nothing is loaded.
  NowPlayingData? data({VCoverTop? coverTop}) {
    final t = track;
    if (t == null) return null;
    final d = _downloads[t.id];
    final sleep = _now.sleep;
    return NowPlayingData(
      track: t,
      sourceTitle: _queue?.context?.title ?? t.album?.title ?? '',
      playing: _playing,
      loading: _loading,
      durationMs: _now.durationMs?.toInt() ?? t.durationMs ?? 0,
      liked: _likedNow,
      download: t.downloaded ? DownloadStateView.done : d?.state,
      downloadProgress: switch (d) {
        DownloadProgress(:final bytesDone, bytesTotal: final total?)
            when total > BigInt.zero =>
          bytesDone / total,
        _ => null,
      },
      shuffle: _queue?.shuffle ?? false,
      repeat: _queue?.repeat ?? Repeat.off,
      sleepLeft: switch (sleep) {
        SleepState_EndsAt(:final endsAtMs) => Duration(
          milliseconds: endsAtMs - DateTime.now().millisecondsSinceEpoch,
        ),
        _ => null,
      },
      sleepEndOfTrack: sleep is SleepState_EndOfTrack,
      coverTop: coverTop,
    );
  }

  /// A resume is a tap that waits for sound (Task 3: markTap right before it).
  void playPause() {
    if (_playing) {
      player.pause();
    } else {
      player.markTap();
      player.play();
    }
  }

  void next() {
    player.markTap();
    core.skipNext();
  }

  void previous() {
    player.markTap();
    core.previous(positionMs: BigInt.from(player.position.value));
  }

  void seek(int ms) => player.seek(Duration(milliseconds: ms));

  void like() {
    final t = track;
    if (t == null) return;
    final liked = !_likedNow;
    _liked[t.id] = liked;
    notifyListeners();
    store.setLiked(id: t.id, liked: liked);
  }

  void download() {
    final t = track;
    if (t != null) store.download(ids: [t.id]);
  }

  void shuffle() =>
      core.queueOp(op: QueueOp.shuffle(!(_queue?.shuffle ?? false)));

  void repeat() => core.queueOp(
    op: QueueOp.repeat(switch (_queue?.repeat ?? Repeat.off) {
      Repeat.off => Repeat.all,
      Repeat.all => Repeat.one,
      Repeat.one => Repeat.off,
    }),
  );

  /// Stops and hides; « Annuler » brings it back for [VDurations.undo] (spec UI §5.3).
  void stop(BuildContext context) {
    final l = AppLocalizations.of(context);
    core.stop();
    showVSnack(
      context,
      l.playbackStopped,
      actionLabel: l.actionUndo,
      onAction: core.undoStop,
      duration: VDurations.undo,
    );
  }

  /// A queue entry plays now.
  void jumpTo(String entry) {
    player.markTap();
    core.queueOp(op: QueueOp.jumpTo(entry));
  }

  /// The actions every player shares; [onOpen], [onCollapse] and [onStop] are the
  /// shell's (sheet, pane).
  NowPlayingActions actions({
    VoidCallback? onOpen,
    VoidCallback? onCollapse,
    VoidCallback? onStop,
  }) => NowPlayingActions(
    onPlayPause: playPause,
    onNext: next,
    onPrevious: previous,
    onSeek: seek,
    onLike: like,
    // Task 6: the playlist menu.
    onAddToPlaylist: () {},
    onDownload: download,
    onShuffle: shuffle,
    onRepeat: repeat,
    onOpen: onOpen,
    onCollapse: onCollapse,
    onStop: onStop,
  );
}
