import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show PlayerLog;
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/bridge/player.dart';
import 'package:vehicoule/bridge/telemetry.dart';
import 'package:vehicoule/debug/fake_api.dart';
import 'package:vehicoule/platform/player.dart';
import 'package:vehicoule/platform/player_errors.dart';

class FakeBackend implements MediaBackend {
  final calls = <String>[];
  final indexes = StreamController<int>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final durations = StreamController<Duration>.broadcast(sync: true);
  final playings = StreamController<bool>.broadcast(sync: true);
  final completes = StreamController<bool>.broadcast(sync: true);
  final errorLines = StreamController<String>.broadcast(sync: true);

  /// While set, `seek` waits for it.
  Completer<void>? seekGate;

  /// The volumes set, in order.
  List<double> get volumes => [
    for (final c in calls)
      if (c.startsWith('volume ')) double.parse(c.substring(7)),
  ];

  @override
  Future<void> open(
    List<Source> items, {
    required bool play,
    Duration start = Duration.zero,
  }) async => calls.add(
    'open ${items.map((s) => s.uri).join(',')} play=$play'
    '${start > Duration.zero ? ' start=${start.inMilliseconds}' : ''}',
  );
  @override
  Future<void> add(Source s) async => calls.add('add ${s.uri}');
  @override
  Future<void> removeAt(int index) async => calls.add('removeAt $index');
  @override
  Future<void> seek(Duration d) async {
    calls.add('seek ${d.inMilliseconds}');
    await seekGate?.future;
  }

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> playOrPause() async => calls.add('playOrPause');
  @override
  Future<void> setVolume(double percent) async => calls.add('volume $percent');

  @override
  Stream<int> get index => indexes.stream;
  @override
  Stream<Duration> get position => positions.stream;
  @override
  Stream<Duration> get duration => durations.stream;
  @override
  Stream<bool> get playing => playings.stream;
  @override
  Stream<bool> get completed => completes.stream;
  @override
  Stream<String> get errors => errorLines.stream;
}

Source src(String uri) => Source(uri: uri, headers: const []);

PlayerCommand playCmd(
  String entry,
  String uri, {
  int positionMs = 0,
  bool autoplay = true,
  double gainDb = 0,
}) => PlayerCommand.play(
  entry: entry,
  source: src(uri),
  positionMs: BigInt.from(positionMs),
  autoplay: autoplay,
  gainDb: gainDb,
);

BigInt ms(int v) => BigInt.from(v);

/// A backend, a command stream and the reported events around a started adapter.
class Rig {
  Rig() {
    adapter = PlayerAdapter(
      backend,
      commands: commands.stream,
      report: events.add,
    )..start();
  }

  final backend = FakeBackend();
  final commands = StreamController<PlayerCommand>();
  final events = <PlayerEvent>[];
  late final PlayerAdapter adapter;
}

/// Lets queued commands and their backend calls run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('play opens the source at the given position', () async {
    final r = Rig();
    r.commands.add(playCmd('e1', 'a', positionMs: 30000));
    await settle();
    // The start goes with the media: a seek right after open is lost before it loads.
    expect(r.backend.calls, ['open a play=true start=30000']);
    expect(r.adapter.position.value, 30000);
    r.backend.indexes.add(0);
    r.backend.playings.add(true);
    r.backend.durations.add(const Duration(seconds: 200));
    expect(r.events, [
      const PlayerEvent.trackStarted(entry: 'e1'),
      const PlayerEvent.resumed(entry: 'e1'),
      PlayerEvent.duration(entry: 'e1', ms: ms(200000)),
    ]);
  });

  test('pause command fades out, pauses, restores volume, reports Paused', () {
    fakeAsync((async) {
      final r = Rig();
      r.commands.add(playCmd('e1', 'a'));
      async.flushMicrotasks();
      r.backend.indexes.add(0);
      r.backend.playings.add(true);
      r.backend.positions.add(const Duration(seconds: 42));
      async.flushMicrotasks();
      r.events.clear();
      r.commands.add(const PlayerCommand.pause(fadeMs: 1000));
      async.elapse(const Duration(milliseconds: 500));
      expect(r.backend.calls, isNot(contains('pause')), reason: 'still fading');
      async.elapse(const Duration(milliseconds: 600));
      final at = r.backend.calls.indexOf('pause');
      expect(r.backend.calls.sublist(at - 1), [
        'volume 0.0',
        'pause',
        'volume 100.0',
      ]);
      final fade = r.backend.volumes;
      expect(fade.length, greaterThan(3), reason: 'a fade, not a cut');
      for (var i = 1; i < fade.length - 1; i++) {
        expect(fade[i], lessThanOrEqualTo(fade[i - 1]));
      }
      expect(r.events.last, PlayerEvent.paused(entry: 'e1', ms: ms(42000)));
    });
  });

  test('auto_advance_reports_preloaded_entry', () async {
    final r = Rig();
    r.commands.add(playCmd('e1', 'a'));
    await settle();
    r.backend.indexes.add(0);
    r.commands.add(
      PlayerCommand.enqueueNext(entry: 'e2', source: src('b'), gainDb: 0),
    );
    await settle();
    expect(r.backend.calls.last, 'add b');
    // Adding to the playlist reports its index again: not a new track.
    r.backend.indexes.add(0);
    r.backend.indexes.add(1);
    expect(r.events, [
      const PlayerEvent.trackStarted(entry: 'e1'),
      const PlayerEvent.trackStarted(entry: 'e2'),
    ]);
  });

  test('replace_next swaps the queued source', () async {
    final r = Rig();
    r.commands.add(playCmd('e1', 'a'));
    await settle();
    r.backend.indexes.add(0);
    r.commands
      ..add(PlayerCommand.enqueueNext(entry: 'e2', source: src('b'), gainDb: 0))
      ..add(
        PlayerCommand.replaceNext(entry: 'e3', source: src('c'), gainDb: 0),
      );
    await settle();
    List<String> playlist() => [
      for (final c in r.backend.calls)
        if (!c.startsWith('volume')) c,
    ];
    expect(playlist().skip(1), ['add b', 'removeAt 1', 'add c']);
    r.commands
      ..add(const PlayerCommand.clearNext())
      ..add(const PlayerCommand.clearNext());
    await settle();
    expect(playlist().skip(4), [
      'removeAt 1',
    ], reason: 'nothing to clear twice');
    // The current one ends with nothing after it.
    r.backend.completes.add(true);
    expect(r.events.last, const PlayerEvent.ended(entry: 'e1'));
  });

  test('a completed track with a next one held is no end', () async {
    final r = Rig();
    r.commands
      ..add(playCmd('e1', 'a'))
      ..add(
        PlayerCommand.replaceNext(entry: 'e2', source: src('b'), gainDb: 0),
      );
    await settle();
    r.backend.indexes.add(0);
    r.backend.completes.add(true);
    expect(r.events, [const PlayerEvent.trackStarted(entry: 'e1')]);
  });

  test('position is reported every 10s and on pause', () {
    fakeAsync((async) {
      final r = Rig();
      r.commands.add(playCmd('e1', 'a'));
      async.flushMicrotasks();
      r.backend.indexes.add(0);
      r.backend.playings.add(true);
      r.events.clear();
      r.backend.positions.add(const Duration(milliseconds: 9900));
      async.elapse(const Duration(seconds: 10));
      r.backend.positions.add(const Duration(milliseconds: 19900));
      async.elapse(const Duration(seconds: 10));
      expect(r.events, [
        PlayerEvent.position(entry: 'e1', ms: ms(9900)),
        PlayerEvent.position(entry: 'e1', ms: ms(19900)),
      ]);
      r.events.clear();
      r.backend.positions.add(const Duration(milliseconds: 21000));
      r.adapter.pause();
      async.flushMicrotasks();
      r.backend.playings.add(false);
      async.elapse(const Duration(seconds: 30));
      expect(r.events, [
        PlayerEvent.position(entry: 'e1', ms: ms(21000)),
        PlayerEvent.paused(entry: 'e1', ms: ms(21000)),
      ], reason: 'once on pause, then nothing while paused');
    });
  });

  test('gain is applied when the track changes', () async {
    expect(gainToVolume(-6), closeTo(50.1, 0.05));
    expect(gainToVolume(0), 100);
    final r = Rig();
    r.commands
      ..add(playCmd('e1', 'a', gainDb: -6))
      ..add(
        PlayerCommand.enqueueNext(entry: 'e2', source: src('b'), gainDb: 0),
      );
    await settle();
    r.backend.indexes.add(0);
    expect(r.backend.volumes.last, closeTo(50.1, 0.05));
    r.backend.indexes.add(1);
    expect(r.backend.volumes.last, 100);
  });

  test('user volume scales the gain and the sleep fade starts from it', () {
    fakeAsync((async) {
      final r = Rig();
      r.commands.add(playCmd('e1', 'a', gainDb: -6));
      async.flushMicrotasks();
      r.backend.indexes.add(0);
      r.adapter.setVolume(0.5);
      async.flushMicrotasks();
      expect(r.adapter.volume.value, 0.5);
      expect(r.backend.volumes.last, closeTo(25.05, 0.05));
      final before = r.backend.volumes.length;
      r.commands.add(const PlayerCommand.pause(fadeMs: 1000));
      async.elapse(const Duration(seconds: 2));
      final fade = r.backend.volumes.sublist(before);
      expect(fade.first, lessThan(25.06));
      expect(
        fade.first,
        greaterThan(20),
        reason: 'from the user volume, not from 100',
      );
      expect(fade.last, closeTo(25.05, 0.05), reason: 'restored');
      expect(r.adapter.volume.value, 0.5);
    });
  });

  test('pause when already paused stays paused', () async {
    final r = Rig();
    r.commands.add(playCmd('e1', 'a', autoplay: false));
    await settle();
    r.backend.indexes.add(0);
    await r.adapter.pause();
    await r.adapter.pause();
    expect(r.backend.calls, isNot(contains('play')));
    expect(r.backend.calls, isNot(contains('playOrPause')));
    expect(r.backend.calls.where((c) => c == 'pause'), hasLength(2));
  });

  group('with the fake api', () {
    late FakeApi api;
    setUp(() {
      api = FakeApi();
      RustLib.initMock(api: api);
    });
    tearDown(RustLib.dispose);

    test('loading turns on at tap and off at the first position', () async {
      final r = Rig();
      final loading = <bool>[];
      r.adapter.loading.listen(loading.add);
      r.adapter.markTap();
      r.commands.add(playCmd('e1', 'a'));
      await settle();
      r.backend.indexes.add(0);
      r.backend.positions.add(Duration.zero);
      await settle();
      expect(loading, [true]);
      r.backend.positions.add(const Duration(milliseconds: 200));
      await settle();
      expect(loading, [true, false]);
      // A play loads again, an error ends it; a stop too.
      r.commands.add(playCmd('e2', 'b'));
      await settle();
      r.backend.errorLines.add('Failed to open https://x: Connection refused');
      await settle();
      r.commands.add(playCmd('e3', 'c'));
      await settle();
      r.commands.add(const PlayerCommand.stop());
      await settle();
      expect(loading, [true, false, true, false, true, false]);
      expect(r.backend.calls.skip(r.backend.calls.length - 2), [
        'pause',
        'open  play=false',
      ]);
    });

    test('first position after a tap reports tap-to-first-sound', () async {
      final r = Rig();
      r.adapter.markTap();
      r.commands.add(playCmd('e1', 'a'));
      await settle();
      r.backend.indexes.add(0);
      r.backend.positions.add(Duration.zero);
      r.backend.positions.add(const Duration(milliseconds: 300));
      r.backend.positions.add(const Duration(milliseconds: 600));
      await settle();
      final perf = api.calls.where(
        (c) => c.memberName == #crateApiSystemReportPerf,
      );
      expect(perf, hasLength(1));
      expect(perf.single.namedArguments[#metric], PerfMetric.tapToFirstSoundMs);
      expect(perf.single.namedArguments[#valueMs], isA<BigInt>());
    });
  });

  test(
    'an error is reported once, with its kind and where it stopped',
    () async {
      final r = Rig();
      r.commands.add(playCmd('e1', 'a'));
      await settle();
      r.backend.indexes.add(0);
      r.backend.playings.add(true);
      r.backend.positions.add(const Duration(seconds: 75));
      r.events.clear();
      r.backend.errorLines.add('https: HTTP error 403 Forbidden');
      r.backend.errorLines.add('Failed to open https://x.');
      r.backend.playings.add(false);
      await settle();
      expect(r.events, [
        PlayerEvent.error(
          entry: 'e1',
          kind: PlayerErrorKind.forbidden,
          message: 'https: HTTP error 403 Forbidden',
          positionMs: ms(75000),
        ),
      ], reason: 'one error, and the stop it causes is no pause');
      expect(r.backend.calls.last, 'pause', reason: 'the player stays stopped');
    },
  );

  test('seek_publishes_its_target_at_once', () async {
    final r = Rig();
    r.commands.add(playCmd('e1', 'a'));
    await settle();
    r.backend.indexes.add(0);
    r.backend.positions.add(const Duration(seconds: 10));
    r.events.clear();
    final gate = r.backend.seekGate = Completer<void>();
    final done = r.adapter.seek(const Duration(seconds: 90));
    expect(r.adapter.position.value, 90000);
    // A position from before the seek, arriving while it runs: ignored.
    r.backend.positions.add(const Duration(seconds: 12));
    expect(r.adapter.position.value, 90000);
    gate.complete();
    await done;
    expect(r.events, [PlayerEvent.seeked(entry: 'e1', ms: ms(90000))]);
    r.backend.positions.add(const Duration(seconds: 91));
    expect(
      r.adapter.position.value,
      91000,
      reason: 'then it follows the player',
    );
    r.backend.seekGate = null;
    await r.adapter.seekBy(const Duration(seconds: -10));
    expect(r.backend.calls.last, 'seek 81000');
    await r.adapter.seekBy(const Duration(minutes: -5));
    expect(r.backend.calls.last, 'seek 0');
  });

  test(
    'the same entry played twice in a row reports two TrackStarted',
    () async {
      // Repeat one: Rust holds the same entry as the next one.
      final r = Rig();
      r.commands
        ..add(playCmd('e1', 'a'))
        ..add(
          PlayerCommand.enqueueNext(entry: 'e1', source: src('a'), gainDb: 0),
        );
      await settle();
      r.backend.indexes
        ..add(0)
        ..add(0) // the add reports its index again: no new track
        ..add(1);
      // Played again from the start (a 403 resume, a jump back to it).
      r.commands.add(playCmd('e1', 'a'));
      await settle();
      r.backend.indexes.add(0);
      expect(r.events, [
        for (var i = 0; i < 3; i++) const PlayerEvent.trackStarted(entry: 'e1'),
      ]);
    },
  );

  test('a mid-play error followed by completed reports only Error', () async {
    final r = Rig();
    r.commands.add(playCmd('e1', 'a'));
    await settle();
    r.backend.indexes.add(0);
    r.backend.playings.add(true);
    r.backend.positions.add(const Duration(seconds: 75));
    r.events.clear();
    // The stream dies: mpv logs it, then reaches the end of what it had.
    r.backend.errorLines.add('https: HTTP error 403 Forbidden');
    r.backend.playings.add(false);
    r.backend.completes.add(true);
    expect(r.events, [
      PlayerEvent.error(
        entry: 'e1',
        kind: PlayerErrorKind.forbidden,
        message: 'https: HTTP error 403 Forbidden',
        positionMs: ms(75000),
      ),
    ]);
  });

  test(
    'media_kit errors come from the log, the HTTP warnings included',
    () async {
      final lines = await MediaKitBackend.errorsFrom(
        Stream.fromIterable(const [
          PlayerLog(
            prefix: 'cplayer',
            level: 'info',
            text: 'Playing: https://x',
          ),
          PlayerLog(
            prefix: 'ffmpeg',
            level: 'warn',
            text: 'https: HTTP error 403 Forbidden',
          ),
          PlayerLog(
            prefix: 'ffmpeg',
            level: 'warn',
            text: 'mov: stream 0, timescale not set',
          ),
          PlayerLog(
            prefix: 'stream',
            level: 'error',
            text: 'Failed to open https://x.',
          ),
          PlayerLog(
            prefix: 'ffmpeg',
            level: 'error',
            text: 'tcp: Connection refused',
          ),
          PlayerLog(
            prefix: 'ffmpeg',
            level: 'error',
            text: 'mov: moov atom not found',
          ),
          PlayerLog(
            prefix: 'ad',
            level: 'error',
            text: 'Error decoding audio.',
          ),
          PlayerLog(prefix: 'ao', level: 'warn', text: 'buffer underrun'),
        ]),
      ).toList();
      expect(lines, [
        'https: HTTP error 403 Forbidden',
        'Failed to open https://x.',
        'tcp: Connection refused',
        'Error decoding audio.',
      ]);
      expect(classifyPlayerError(lines.first), PlayerErrorKind.forbidden);
    },
  );

  test('a resume after an error reports the end again', () async {
    final r = Rig();
    r.commands.add(playCmd('e1', 'a'));
    await settle();
    r.backend.indexes.add(0);
    r.backend.playings.add(true);
    r.backend.positions.add(const Duration(seconds: 75));
    r.backend.errorLines.add('tcp: Connection refused');
    r.backend.playings.add(false);
    // A network error leaves it stopped; the user resumes in place.
    r.backend.playings.add(true);
    r.backend.completes.add(true);
    expect(r.events.last, const PlayerEvent.ended(entry: 'e1'));
  });

  test(
    'after a play with a start, position holds the start until sound',
    () async {
      final r = Rig();
      r.commands.add(playCmd('e1', 'a', positionMs: 30000, autoplay: false));
      await settle();
      r.backend.indexes.add(0);
      r.backend.positions.add(Duration.zero);
      expect(r.adapter.position.value, 30000);
      await r.adapter.pause();
      expect(r.events.last, PlayerEvent.paused(entry: 'e1', ms: ms(30000)));
      r.backend.positions.add(const Duration(milliseconds: 30200));
      expect(r.adapter.position.value, 30200);
      // Once it played, 0 is a real position (a seek back to the start).
      r.backend.positions.add(Duration.zero);
      expect(r.adapter.position.value, 0);
    },
  );

  test('other HTTP warnings are no errors', () async {
    final lines = await MediaKitBackend.errorsFrom(
      Stream.fromIterable(const [
        PlayerLog(
          prefix: 'ffmpeg',
          level: 'warn',
          text: 'https: HTTP error 404 Not Found',
        ),
        PlayerLog(
          prefix: 'ffmpeg',
          level: 'warn',
          text: 'https: HTTP error 503 Service Unavailable',
        ),
        PlayerLog(
          prefix: 'ffmpeg',
          level: 'warn',
          text: 'https: HTTP error 4030',
        ),
      ]),
    ).toList();
    expect(lines, isEmpty);
  });
}
