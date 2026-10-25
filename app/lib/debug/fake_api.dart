/// The core simulated for the debug build and the tests: `RustLib.initMock(api: FakeApi())`.
/// It answers the player's streams from the sample library; every other call is recorded,
/// then refused by name. Each later task adds the calls it uses.
library;

import 'dart:async';

import '../bridge/app.dart';
import '../bridge/catalog.dart';
import '../bridge/downloads.dart';
import '../bridge/events.dart';
import '../bridge/frb_generated.dart';
import '../bridge/player.dart';
import '../bridge/queue.dart';
import '../bridge/telemetry.dart';
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

  @override
  Stream<NowPlaying> crateApiPlaybackNowPlaying() => _record(
    #crateApiPlaybackNowPlaying,
    const {},
    Stream.value(
      NowPlaying(
        track: sampleTracks.first,
        durationMs: BigInt.from(sampleTracks.first.durationMs ?? 0),
      ),
    ),
  );

  @override
  Stream<QueueView> crateApiPlaybackQueueStates() => _record(
    #crateApiPlaybackQueueStates,
    const {},
    Stream.value(
      QueueView(
        currentEntry: 'e0',
        current: sampleTracks.first,
        upcoming: [
          for (final (i, t) in sampleTracks.indexed.skip(1))
            QueueItemView(entry: 'e$i', track: t, fromRadio: false),
        ],
        index: 0,
        shuffle: false,
        repeat: Repeat.off,
      ),
    ),
  );

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
  Future<void> crateApiPlaybackSkipNext() =>
      _record(#crateApiPlaybackSkipNext, const {}, Future.value());

  @override
  Future<void> crateApiPlaybackPrevious({required BigInt positionMs}) =>
      _record(#crateApiPlaybackPrevious, {
        #positionMs: positionMs,
      }, Future.value());

  @override
  Future<void> crateApiPlaybackStop() =>
      _record(#crateApiPlaybackStop, const {}, Future.value());

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
