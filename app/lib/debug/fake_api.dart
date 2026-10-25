/// The core simulated for the debug build and the tests: `RustLib.initMock(api: FakeApi())`.
/// It answers the player's streams from the sample library; every other call is recorded,
/// then refused by name. Each later task adds the calls it uses.
library;

import 'dart:async';

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
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    // Symbol("name") → name.
    throw UnimplementedError(invocation.memberName.toString().split('"')[1]);
  }
}
