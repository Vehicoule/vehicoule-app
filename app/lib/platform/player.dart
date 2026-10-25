/// The player: Rust decides what plays (`playerCommands`), media_kit plays it, and what
/// happens goes back to Rust as `PlayerEvent`s (contract: core/core/src/player.rs).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../bridge/api/playback.dart' show playerCommands, playerEvent;
import '../bridge/api/system.dart' show reportPerf;
import '../bridge/player.dart';
import '../bridge/telemetry.dart' show PerfMetric;
import 'player_errors.dart';

/// mpv's volume (100 = unchanged) for a loudness gain in dB.
double gainToVolume(double gainDb) =>
    100 * math.pow(10, gainDb / 20).toDouble();

/// What plays the sound: media_kit for real, a fake in the tests. Its playlist holds the
/// current track and at most one next; `index` is the one playing.
abstract interface class MediaBackend {
  /// [start]: where the first item starts, applied as it loads.
  Future<void> open(
    List<Source> items, {
    required bool play,
    Duration start = Duration.zero,
  });
  Future<void> add(Source s);
  Future<void> removeAt(int index);
  Future<void> seek(Duration d);
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> setVolume(double percent);
  Stream<int> get index;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<bool> get completed;
  Stream<String> get errors;
}

class MediaKitBackend implements MediaBackend {
  MediaKitBackend() {
    MediaKit.ensureInitialized();
  }

  // Late: created after ensureInitialized. Warnings logged: ffmpeg's HTTP errors are.
  late final _player = Player(
    configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn),
  );

  static Media _media(Source s, {Duration? start}) => Media(
    s.uri,
    httpHeaders: Map.fromEntries([
      for (final (k, v) in s.headers) MapEntry(k, v),
    ]),
    start: start,
  );

  @override
  Future<void> open(
    List<Source> items, {
    required bool play,
    Duration start = Duration.zero,
  }) => _player.open(
    Playlist([
      for (final (i, s) in items.indexed)
        _media(s, start: i == 0 && start > Duration.zero ? start : null),
    ]),
    play: play,
  );
  @override
  Future<void> add(Source s) => _player.add(_media(s));
  @override
  Future<void> removeAt(int index) => _player.remove(index);
  @override
  Future<void> seek(Duration d) => _player.seek(d);
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> playOrPause() => _player.playOrPause();
  @override
  Future<void> setVolume(double percent) => _player.setVolume(percent);

  @override
  Stream<int> get index => _player.stream.playlist.map((p) => p.index);
  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Stream<String> get errors => errorsFrom(_player.stream.log);

  /// media_kit's own `error` filter (real.dart, MPV_EVENT_LOG_MESSAGE), plus the 403
  /// ffmpeg logs as a warning (`https: HTTP error 403 Forbidden`), in log order. Other
  /// HTTP warnings are left out: mpv may get past them.
  static Stream<String> errorsFrom(Stream<PlayerLog> log) => log
      .where(
        (l) =>
            (l.level == 'error' &&
                (_errorPrefixes.contains(l.prefix) ||
                    l.prefix == 'ffmpeg' && l.text.startsWith('tcp:'))) ||
            (l.level == 'error' || l.level == 'warn') &&
                _http403.hasMatch(l.text),
      )
      .map((l) => l.text);

  static const _errorPrefixes = {'file', 'vd', 'ad', 'cplayer', 'stream'};
  static final _http403 = RegExp(r'HTTP error 403\b');
}

/// Runs Rust's player commands on a [MediaBackend] and reports what happens, in order.
class PlayerAdapter {
  PlayerAdapter(
    this._backend, {
    this._commands,
    void Function(PlayerEvent e)? report,
  }) : _report = report ?? ((e) => playerEvent(e: e));

  final MediaBackend _backend;
  final Stream<PlayerCommand>? _commands;
  final void Function(PlayerEvent e) _report;

  final _position = ValueNotifier(0);
  final _volume = ValueNotifier(1.0);
  final _loading = StreamController<bool>.broadcast();

  /// The backend's playlist: the entry and its gain at each index.
  final _entries = <String>[];
  final _gains = <double>[];
  var _index = 0;

  /// The index `TrackStarted` went out for: the playlist reports its index again when
  /// it changes (add, remove), which is no new track. By index, not entry: repeat one
  /// holds the same entry next.
  int? _startedIndex;

  /// The entry an `Error` went out for: mpv logs one failure on several lines.
  String? _failed;
  var _playing = false;
  var _isLoading = false;

  /// Since the last `Play` opened, no position past 0 yet: the first one is the sound.
  var _awaitingSound = false;
  Stopwatch? _tap;

  /// Backend seeks (and opens) not done yet: positions from before them are stale.
  var _seeks = 0;
  Timer? _ticker;
  Future<void> _chain = Future.value();

  /// Milliseconds; a seek shows its target at once.
  ValueListenable<int> get position => _position;
  Stream<Duration?> get duration =>
      _backend.duration.map((d) => d > Duration.zero ? d : null);
  Stream<bool> get playing => _backend.playing;

  /// On at [markTap] or a `Play`; off at the first sound, an error or a stop.
  Stream<bool> get loading => _loading.stream;

  /// The user's volume, 0..1, before the track's gain.
  ValueListenable<double> get volume => _volume;

  String? get _entry => _index < _entries.length ? _entries[_index] : null;
  double get _gain => _index < _gains.length ? _gains[_index] : 0;
  bool get _hasNext => _index + 1 < _entries.length;

  void start() {
    (_commands ?? playerCommands()).listen(
      (c) => _chain = _chain.then((_) => _run(c)).catchError(_failedCommand),
    );
    _backend.index.listen(_onIndex);
    _backend.position.listen(_onPosition);
    _backend.duration.listen((d) {
      final e = _entry;
      if (e != null && d > Duration.zero) {
        _report(PlayerEvent.duration(entry: e, ms: _ms(d.inMilliseconds)));
      }
    });
    _backend.playing.listen(_onPlaying);
    _backend.completed.listen((done) {
      final e = _entry;
      // With a next one held, it starts by itself.
      // After an Error, its end is no end: Rust already decides what follows.
      if (!done || e == null || e == _failed || _hasNext) return;
      _report(PlayerEvent.ended(entry: e));
    });
    _backend.errors.listen(_onError);
  }

  Future<void> setVolume(double v) {
    _volume.value = v.clamp(0.0, 1.0);
    return _applyVolume();
  }

  Future<void> play() => _backend.play();

  /// A pause of the user or the system (lock screen, headphones, a call).
  Future<void> pause() async {
    await _backend.pause();
    _paused();
  }

  Future<void> togglePlay() => _playing ? pause() : play();

  Future<void> seek(Duration d) async {
    await _seekTo(d);
    final e = _entry;
    if (e != null) {
      _report(PlayerEvent.seeked(entry: e, ms: _ms(d.inMilliseconds)));
    }
  }

  Future<void> seekBy(Duration delta) => seek(
    Duration(milliseconds: math.max(0, _position.value + delta.inMilliseconds)),
  );

  /// A tap that starts a track (Rust answers with a `Play`), or ⏯ on a track loaded
  /// paused: times the first sound.
  void markTap() {
    _tap = Stopwatch()..start();
    _setLoading(true);
  }

  Future<void> _run(PlayerCommand c) async {
    switch (c) {
      case PlayerCommand_Play(
        :final entry,
        :final source,
        :final positionMs,
        :final autoplay,
        :final gainDb,
      ):
        _entries
          ..clear()
          ..add(entry);
        _gains
          ..clear()
          ..add(gainDb);
        _index = 0;
        _startedIndex = null;
        _failed = null;
        // A paused load (the restore at launch) is no loading, and no sound to time.
        _setLoading(autoplay);
        if (!autoplay) _tap = null;
        final at = positionMs.toInt();
        _position.value = at;
        _seeks++;
        try {
          // The start goes with the media: a seek right after open is lost (not loaded).
          await _backend.open(
            [source],
            play: autoplay,
            start: Duration(milliseconds: at),
          );
        } finally {
          _seeks--;
        }
        _awaitingSound = true;
      case PlayerCommand_EnqueueNext(
            :final entry,
            :final source,
            :final gainDb,
          ) ||
          PlayerCommand_ReplaceNext(:final entry, :final source, :final gainDb):
        await _clearNext();
        await _backend.add(source);
        _entries.add(entry);
        _gains.add(gainDb);
      case PlayerCommand_ClearNext():
        await _clearNext();
      case PlayerCommand_Pause(:final fadeMs):
        // The sleep timer: a system pause, faded from what plays now.
        final from = _volume.value * gainToVolume(_gain);
        const steps = 20;
        for (var i = 1; i <= steps; i++) {
          await Future<void>.delayed(Duration(milliseconds: fadeMs ~/ steps));
          await _backend.setVolume(from * (1 - i / steps));
        }
        await _backend.pause();
        await _backend.setVolume(from);
        _paused();
      case PlayerCommand_Stop():
        _entries.clear();
        _gains.clear();
        _index = 0;
        _startedIndex = null;
        _tap = null;
        _setLoading(false);
        _position.value = 0;
        await _backend.pause();
        await _backend.open(const [], play: false);
    }
  }

  Future<void> _clearNext() async {
    if (!_hasNext) return;
    await _backend.removeAt(_index + 1);
    _entries.removeAt(_index + 1);
    _gains.removeAt(_index + 1);
  }

  Future<void> _seekTo(Duration d) async {
    _position.value = d.inMilliseconds;
    _seeks++;
    try {
      await _backend.seek(d);
    } finally {
      _seeks--;
    }
  }

  Future<void> _applyVolume() =>
      _backend.setVolume(_volume.value * gainToVolume(_gain));

  /// Not on an error or the end: those stop it without a pause (a 403 would resume paused).
  void _paused() {
    final e = _entry;
    if (e == null) return;
    final ms = _ms(_position.value);
    _report(PlayerEvent.position(entry: e, ms: ms));
    _report(PlayerEvent.paused(entry: e, ms: ms));
  }

  void _onIndex(int i) {
    _index = i;
    final e = _entry;
    if (e == null || i == _startedIndex) return;
    _startedIndex = i;
    _failed = null;
    _report(PlayerEvent.trackStarted(entry: e));
    unawaited(_applyVolume());
  }

  void _onPosition(Duration d) {
    // Until the first sound of a Play, a 0 is no position: the start is held.
    if (_seeks > 0 || (_awaitingSound && d <= Duration.zero)) return;
    _position.value = d.inMilliseconds;
    if (d <= Duration.zero || !_awaitingSound) return;
    _awaitingSound = false;
    _setLoading(false);
    final tap = _tap;
    _tap = null;
    if (tap != null) {
      reportPerf(
        metric: PerfMetric.tapToFirstSoundMs,
        valueMs: _ms(tap.elapsedMilliseconds),
      ).ignore();
    }
  }

  void _onPlaying(bool p) {
    if (p == _playing) return;
    _playing = p;
    // A resume (after a network error, say) is a new run: its end is reported again.
    if (p) _failed = null;
    _ticker?.cancel();
    _ticker = null;
    final e = _entry;
    if (!p || e == null) return;
    _report(PlayerEvent.resumed(entry: e));
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      final e = _entry;
      if (e != null) {
        _report(PlayerEvent.position(entry: e, ms: _ms(_position.value)));
      }
    });
  }

  void _onError(String message) {
    final e = _entry;
    if (e == null || e == _failed) return;
    _failed = e;
    _tap = null;
    _setLoading(false);
    _report(
      PlayerEvent.error(
        entry: e,
        kind: classifyPlayerError(message),
        message: message,
        positionMs: _ms(_position.value),
      ),
    );
    // Stopped until Rust says what next (a new Play, or nothing for a network error).
    unawaited(_backend.pause());
  }

  void _setLoading(bool v) {
    if (v == _isLoading) return;
    _isLoading = v;
    _loading.add(v);
  }

  static BigInt _ms(int v) => BigInt.from(v);

  static void _failedCommand(Object e, StackTrace s) =>
      FlutterError.reportError(
        FlutterErrorDetails(exception: e, stack: s, library: 'player'),
      );
}
