/// The core simulated for the debug build and the tests: `RustLib.initMock(api: FakeApi())`.
/// It answers the player's streams from the sample library (skip, previous, stop and undo
/// move through it); every other call is recorded, then refused by name. Each later task
/// adds the calls it uses.
library;

import 'dart:async';

import '../bridge/api/app.dart' show Onboarding;
import '../bridge/app.dart';
import '../bridge/catalog.dart';
import '../bridge/downloads.dart';
import '../bridge/error.dart';
import '../bridge/events.dart';
import '../bridge/frb_generated.dart';
import '../bridge/library.dart';
import '../bridge/player.dart';
import '../bridge/queue.dart';
import '../bridge/telemetry.dart';
import '../bridge/updates.dart';
import 'library.dart';

class FakeApi implements RustLibApi {
  FakeApi();

  /// Every call received, for the tests.
  final List<Invocation> calls = [];

  /// What `playerCommands()` streams.
  final StreamController<PlayerCommand> commands =
      StreamController<PlayerCommand>.broadcast();

  /// What `downloadProgress()` streams.
  final StreamController<DownloadProgress> downloadEvents =
      StreamController<DownloadProgress>.broadcast(sync: true);

  /// What `libraryChanges()` streams.
  final StreamController<LibraryChanged> libraryEvents =
      StreamController<LibraryChanged>.broadcast(sync: true);

  /// What `downloads()` answers.
  List<DownloadProgress> downloadRows = [];

  /// The UI preferences (`uiPref` / `setUiPref`).
  final Map<String, String?> prefs = {};

  T _record<T>(Symbol name, Map<Symbol, Object?> args, T result) {
    calls.add(Invocation.method(name, const [], args));
    return result;
  }

  @override
  Stream<PlayerCommand> crateApiPlaybackPlayerCommands() =>
      _record(#crateApiPlaybackPlayerCommands, const {}, commands.stream);

  @override
  void crateApiPlaybackPlayerEvent({required PlayerEvent e}) =>
      _record(#crateApiPlaybackPlayerEvent, {#e: e}, null);

  /// The sample track playing, or none after a stop.
  int? _index = 0;
  int? _stopped;

  /// What `nowPlaying()` gives first, then each [setNow].
  late NowPlaying current = _nowAt(0);
  late QueueView currentQueue = _queueAt(0);
  final _nowEvents = StreamController<NowPlaying>.broadcast(sync: true);
  final _queueEvents = StreamController<QueueView>.broadcast(sync: true);

  /// What `notices()` streams.
  final StreamController<Notice> noticeEvents =
      StreamController<Notice>.broadcast(sync: true);

  /// What `onboarding()` answers.
  bool onboardingDone = true;

  /// What `playlists()` answers.
  List<CollectionView> playlistRows = [];

  /// What `artworkFile()` answers, by id.
  final Map<String, String> artworkPaths = {};

  static NowPlaying _nowAt(int i) => NowPlaying(
    track: sampleTracks[i],
    durationMs: BigInt.from(sampleTracks[i].durationMs ?? 0),
  );

  static QueueView _queueAt(int i) {
    final t = sampleTracks[i];
    return QueueView(
      currentEntry: 'e$i',
      current: t,
      upcoming: [
        for (final (j, u) in sampleTracks.indexed.skip(i + 1))
          QueueItemView(entry: 'e$j', track: u, fromRadio: false),
      ],
      index: i,
      shuffle: false,
      repeat: Repeat.off,
      context: t.album == null
          ? null
          : PlayContext(kind: 'album', id: t.album!.id, title: t.album!.title),
    );
  }

  /// Sends what plays now (and the queue, if given) to the listeners.
  void setNow(NowPlaying n, [QueueView? q]) {
    current = n;
    _nowEvents.add(n);
    if (q != null) {
      currentQueue = q;
      _queueEvents.add(q);
    }
  }

  void _play(int? i) {
    _index = i;
    setNow(
      i == null ? const NowPlaying() : _nowAt(i),
      i == null
          ? const QueueView(
              upcoming: [],
              index: 0,
              shuffle: false,
              repeat: Repeat.off,
            )
          : _queueAt(i),
    );
  }

  /// The current value first, then the changes.
  static Stream<T> _live<T>(T Function() current, Stream<T> changes) =>
      Stream.multi((c) {
        c.add(current());
        final s = changes.listen(c.add);
        c.onCancel = s.cancel;
      });

  @override
  Stream<NowPlaying> crateApiPlaybackNowPlaying() => _record(
    #crateApiPlaybackNowPlaying,
    const {},
    _live(() => current, _nowEvents.stream),
  );

  @override
  Stream<QueueView> crateApiPlaybackQueueStates() => _record(
    #crateApiPlaybackQueueStates,
    const {},
    _live(() => currentQueue, _queueEvents.stream),
  );

  @override
  Stream<Notice> crateApiPlaybackNotices() =>
      _record(#crateApiPlaybackNotices, const {}, noticeEvents.stream);

  @override
  Future<Onboarding> crateApiAppOnboarding() => _record(
    #crateApiAppOnboarding,
    const {},
    Future.value(Onboarding(done: onboardingDone)),
  );

  @override
  Future<void> crateApiAppStart() =>
      _record(#crateApiAppStart, const {}, Future.value());

  @override
  Future<UpdateInfo?> crateApiSystemCheckUpdates({required bool force}) =>
      _record(#crateApiSystemCheckUpdates, {#force: force}, Future.value());

  @override
  Future<String?> crateApiCatalogArtworkFile({
    required String id,
    required int size,
  }) => _record(#crateApiCatalogArtworkFile, {
    #id: id,
    #size: size,
  }, Future.value(artworkPaths[id]));

  @override
  Future<void> crateApiPlaybackUndoStop() {
    final i = _stopped;
    _stopped = null;
    if (i != null) _play(i);
    return _record(#crateApiPlaybackUndoStop, const {}, Future.value());
  }

  @override
  Future<void> crateApiPlaybackQueueOp({required QueueOp op}) =>
      _record(#crateApiPlaybackQueueOp, {#op: op}, Future.value());

  @override
  Future<List<CollectionView>> crateApiLibraryPlaylists({
    required CollectionSort sort,
  }) => _record(#crateApiLibraryPlaylists, {
    #sort: sort,
  }, Future.value(playlistRows));

  @override
  Future<void> crateApiLibraryAddToPlaylist({
    required String id,
    required List<String> items,
  }) => _record(#crateApiLibraryAddToPlaylist, {
    #id: id,
    #items: items,
  }, Future.value());

  @override
  Future<void> crateApiLibraryDownload({required List<String> ids}) =>
      _record(#crateApiLibraryDownload, {#ids: ids}, Future.value());

  @override
  Future<void> crateApiLibraryRefreshHome() =>
      _record(#crateApiLibraryRefreshHome, const {}, Future.value());

  @override
  Future<EntityView> crateApiCatalogEntity({
    required String id,
    String? cursor,
  }) {
    final c = sampleCollections.where((c) => c.$1 == id).firstOrNull;
    return _record(
      #crateApiCatalogEntity,
      {#id: id, #cursor: cursor},
      c == null
          ? Future.error(const CoreError.notFound())
          : Future.value(
              EntityView(
                header: CollectionView(
                  id: c.$1,
                  kind: ItemKind.album,
                  title: c.$2,
                  subtitle: c.$3,
                  liked: false,
                  isUserPlaylist: false,
                ),
                tracks: const [],
                albums: const [],
                fromCache: true,
              ),
            ),
    );
  }

  @override
  Future<void> crateApiSystemReportPerf({
    required PerfMetric metric,
    required BigInt valueMs,
  }) => _record(#crateApiSystemReportPerf, {
    #metric: metric,
    #valueMs: valueMs,
  }, Future.value());

  @override
  Future<void> crateApiAppInitApp({required AppConfig cfg}) =>
      _record(#crateApiAppInitApp, {#cfg: cfg}, Future.value());

  @override
  Future<void> crateApiAppSetOnline({required bool online}) =>
      _record(#crateApiAppSetOnline, {#online: online}, Future.value());

  @override
  Future<void> crateApiPlaybackSkipNext() {
    if (_index case final i?) _play((i + 1) % sampleTracks.length);
    return _record(#crateApiPlaybackSkipNext, const {}, Future.value());
  }

  @override
  Future<void> crateApiPlaybackPrevious({required BigInt positionMs}) {
    if (_index case final i?) {
      _play((i - 1 + sampleTracks.length) % sampleTracks.length);
    }
    return _record(#crateApiPlaybackPrevious, {
      #positionMs: positionMs,
    }, Future.value());
  }

  /// Stops; `undoStop` brings the track back.
  @override
  Future<void> crateApiPlaybackStop() {
    _stopped = _index ?? _stopped;
    _play(null);
    return _record(#crateApiPlaybackStop, const {}, Future.value());
  }

  @override
  Future<void> crateApiLibrarySetLiked({
    required String id,
    required bool liked,
  }) => _record(#crateApiLibrarySetLiked, {
    #id: id,
    #liked: liked,
  }, Future.value());

  @override
  Future<List<TrackView>> crateApiLibraryTracks({required List<String> ids}) =>
      _record(#crateApiLibraryTracks, {
        #ids: ids,
      }, Future.value([...sampleTracks.where((t) => ids.contains(t.id))]));

  @override
  Stream<DownloadProgress> crateApiLibraryDownloadProgress() => _record(
    #crateApiLibraryDownloadProgress,
    const {},
    downloadEvents.stream,
  );

  @override
  Future<List<DownloadProgress>> crateApiLibraryDownloads() =>
      _record(#crateApiLibraryDownloads, const {}, Future.value(downloadRows));

  @override
  Stream<LibraryChanged> crateApiLibraryLibraryChanges() =>
      _record(#crateApiLibraryLibraryChanges, const {}, libraryEvents.stream);

  @override
  Future<String?> crateApiSettingsUiPref({required String key}) =>
      _record(#crateApiSettingsUiPref, {#key: key}, Future.value(prefs[key]));

  @override
  Future<void> crateApiSettingsSetUiPref({required String key, String? value}) {
    prefs[key] = value;
    return _record(#crateApiSettingsSetUiPref, {
      #key: key,
      #value: value,
    }, Future.value());
  }

  @override
  Future<void> crateApiSystemReportDartError({
    required String kind,
    required String stack,
  }) => _record(#crateApiSystemReportDartError, {
    #kind: kind,
    #stack: stack,
  }, Future.value());

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    // Symbol("name") → name.
    throw UnimplementedError(invocation.memberName.toString().split('"')[1]);
  }
}
