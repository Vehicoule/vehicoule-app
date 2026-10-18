// Step-1 probe: plays files/playlist.json for an hour, screen off, and logs
// every start / end / error / slow load to files/playback-log.jsonl.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

const slowLoad = Duration(seconds: 2);

late final IOSink _log;
final _clock = Stopwatch()..start();

void log(String event, int index, [String detail = '']) {
  _log.writeln(jsonEncode({'t': _clock.elapsedMilliseconds, 'event': event, 'index': index, 'detail': detail}));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final dir = (await getExternalStorageDirectory())!;
  _log = File('${dir.path}/playback-log.jsonl').openWrite(mode: FileMode.append);

  final tracks = (jsonDecode(await File('${dir.path}/playlist.json').readAsString()) as List)
      .cast<Map<String, dynamic>>();
  final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
  final handler = await AudioService.init(
    builder: () => ProbeHandler(player, tracks),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'app.vehicoule.probe.playback.audio',
      androidNotificationChannelName: 'Playback probe',
      androidStopForegroundOnPause: false,
    ),
  );
  await handler.start();
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text('${tracks.length} titres — écran éteint, attendre 1 h')))));
}

class ProbeHandler extends BaseAudioHandler with QueueHandler {
  ProbeHandler(this.player, this.tracks);

  final Player player;
  final List<Map<String, dynamic>> tracks;
  int _index = -1;
  bool _loading = false;
  Timer? _slow;
  final _loadClock = Stopwatch();

  Future<void> start() async {
    queue.add([for (final (i, t) in tracks.indexed) MediaItem(id: '$i', title: t['title'] as String)]);
    player.stream.playlist.listen((p) => _onIndex(p.index));
    // Audible start: first position past zero after a track change.
    player.stream.position.listen((p) {
      if (!_loading || p <= Duration.zero) return;
      _loading = false;
      _slow?.cancel();
      log('start', _index, '${_loadClock.elapsedMilliseconds}');
    });
    player.stream.error.listen((e) => log('error', _index, e));
    player.stream.log.listen((l) => log('mpv', _index, '${l.level} ${l.prefix}: ${l.text}'));
    player.stream.completed.listen((done) {
      if (done && _index == tracks.length - 1) log('end', _index);
    });
    player.stream.playing.listen((playing) => playbackState.add(playbackState.value.copyWith(
          playing: playing,
          controls: [MediaControl.pause, MediaControl.play, MediaControl.skipToNext],
          processingState: AudioProcessingState.ready,
        )));
    await player.open(Playlist([
      for (final t in tracks)
        Media(t['url'] as String, httpHeaders: (t['headers'] as Map).cast<String, String>()),
    ]));
  }

  void _onIndex(int index) {
    if (index == _index) return;
    if (_index >= 0) log('end', _index);
    _index = index;
    _loading = true;
    _loadClock.reset();
    _loadClock.start();
    log('load', index);
    _slow?.cancel();
    _slow = Timer(slowLoad, () {
      if (_loading) log('slow_load', index, '>${slowLoad.inMilliseconds}');
    });
    mediaItem.add(queue.value[index]);
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> skipToNext() => player.next();
}
