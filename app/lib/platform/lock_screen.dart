/// The lock screen, the Android media notification and macOS « En cours de lecture »,
/// through audio_service (spec UI §6.11). What plays stays in the [PlayerAdapter]; track
/// changes, likes and stop go to Rust.
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bridge/api/library.dart' show setLiked;
import '../bridge/api/playback.dart' as core;
import '../bridge/events.dart';
import 'player.dart';

/// The notification's own texts, from Android's strings.xml (FR, EN): the system shows
/// them, not Flutter. Unused elsewhere (macOS shows no custom action).
class MediaLabels {
  const MediaLabels({
    this.like = '',
    this.unlike = '',
    this.stop = '',
    this.channel = '',
  });

  final String like;
  final String unlike;
  final String stop;

  /// The notification channel's name in the system settings.
  final String channel;
}

/// Starts the system media session, where there is one (Android, macOS, iOS).
Future<LockScreen?> initLockScreen(PlayerAdapter player) async {
  if (defaultTargetPlatform
      case TargetPlatform.windows ||
          TargetPlatform.linux ||
          TargetPlatform.fuchsia) {
    return null;
  }
  var labels = const MediaLabels();
  if (defaultTargetPlatform == TargetPlatform.android) {
    final m = await const MethodChannel('app.vehicoule/notifications')
        .invokeMapMethod<String, String>('labels');
    labels = MediaLabels(
      like: m?['like'] ?? '',
      unlike: m?['unlike'] ?? '',
      stop: m?['stop'] ?? '',
      channel: m?['channel'] ?? '',
    );
  }
  return AudioService.init(
    builder: () => LockScreen(player, labels: labels)..start(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'app.vehicoule.playback',
      androidNotificationChannelName: labels.channel,
      androidNotificationIcon: 'drawable/ic_stat_mochi',
    ),
  );
}

class LockScreen extends BaseAudioHandler {
  LockScreen(this._player, {this.labels = const MediaLabels()});

  final PlayerAdapter _player;
  final MediaLabels labels;

  String? _trackId;
  var _liked = false;
  var _playing = false;
  var _loading = false;

  void start() {
    core.nowPlaying().listen(_onNowPlaying);
    _player.playing.listen((p) {
      _playing = p;
      _publish();
    });
    _player.loading.listen((l) {
      _loading = l;
      _publish();
    });
    // A seek (here, in the app, from Rust) moves the system's bar; playback itself
    // advances it from updateTime.
    _player.position.addListener(() {
      final s = playbackState.value;
      final expected = s.playing
          ? s.updatePosition + DateTime.now().difference(s.updateTime)
          : s.updatePosition;
      final at = Duration(milliseconds: _player.position.value);
      if ((at - expected).abs() > const Duration(milliseconds: 1500)) {
        _publish();
      }
    });
  }

  @override
  Future<void> play() {
    _player.markTap();
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() {
    _player.markTap();
    return core.skipNext();
  }

  @override
  Future<void> skipToPrevious() {
    _player.markTap();
    return core.previous(positionMs: BigInt.from(_player.position.value));
  }

  /// The system's stop (a swipe, a headset), and the notification's ×.
  @override
  Future<void> stop() => core.stop();

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    switch (name) {
      case 'like':
        final id = _trackId;
        if (id == null) return;
        _liked = !_liked;
        _publish();
        await setLiked(id: id, liked: _liked);
      case 'stop':
        await stop();
    }
  }

  void _onNowPlaying(NowPlaying n) {
    final t = n.track;
    _trackId = t?.id;
    _liked = t?.liked ?? false;
    final ms = n.durationMs?.toInt() ?? t?.durationMs;
    final art = n.artworkPath;
    mediaItem.add(
      t == null
          ? null
          : MediaItem(
              id: t.id,
              title: t.title,
              artist: t.artists.map((a) => a.name).join(', '),
              album: t.album?.title,
              duration: ms == null ? null : Duration(milliseconds: ms),
              artUri: art == null ? null : Uri.file(art),
            ),
    );
    _publish();
  }

  void _publish() {
    final loaded = _trackId != null;
    playbackState.add(
      PlaybackState(
        processingState: !loaded
            ? AudioProcessingState.idle
            : _loading
            ? AudioProcessingState.loading
            : AudioProcessingState.ready,
        playing: _playing,
        updatePosition: Duration(milliseconds: _player.position.value),
        controls: loaded
            ? [
                MediaControl.skipToPrevious,
                _playing ? MediaControl.pause : MediaControl.play,
                MediaControl.skipToNext,
                MediaControl.custom(
                  androidIcon: _liked
                      ? 'drawable/ic_notif_liked'
                      : 'drawable/ic_notif_like',
                  label: _liked ? labels.unlike : labels.like,
                  name: 'like',
                ),
                MediaControl.custom(
                  androidIcon: 'drawable/ic_notif_close',
                  label: labels.stop,
                  name: 'stop',
                ),
              ]
            : const [],
        androidCompactActionIndices: loaded ? const [0, 1, 2] : null,
        systemActions: const {MediaAction.seek},
      ),
    );
  }
}
