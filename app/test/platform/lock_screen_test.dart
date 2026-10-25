import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicoule/bridge/catalog.dart';
import 'package:vehicoule/bridge/events.dart';
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/debug/fake_api.dart';
import 'package:vehicoule/platform/lock_screen.dart';

import 'player_test.dart' show Rig, playCmd, settle;

/// The fake core, with a now-playing stream the test drives.
class _Api extends FakeApi {
  final now = StreamController<NowPlaying>.broadcast(sync: true);

  @override
  Stream<NowPlaying> crateApiPlaybackNowPlaying() => now.stream;
}

const _track = TrackView(
  id: 'track:7',
  title: 'Halo',
  artists: [
    ArtistRefView(id: 'artist:a', name: 'Ana'),
    ArtistRefView(id: 'artist:b', name: 'Bo'),
  ],
  album: AlbumRefView(id: 'album:l', title: 'Lumen'),
  durationMs: 200000,
  explicit: false,
  liked: false,
  downloaded: false,
);

const _labels = MediaLabels(
  like: 'J’aime',
  unlike: 'Je n’aime plus',
  stop: 'Arrêter',
  channel: 'Lecture',
);

Iterable<Symbol> _names(FakeApi api) => api.calls.map((c) => c.memberName);

void main() {
  late _Api api;
  setUp(() {
    api = _Api();
    RustLib.initMock(api: api);
  });
  tearDown(RustLib.dispose);

  test('lock screen skip goes through Rust, play/pause stays local', () async {
    final r = Rig();
    final ls = LockScreen(r.adapter, labels: _labels)..start();
    r.commands.add(playCmd('e1', 'a'));
    await settle();
    r.backend.indexes.add(0);
    r.backend.playings.add(true);
    r.backend.positions.add(const Duration(seconds: 3));
    await settle();
    r.backend.calls.clear();

    final loading = <bool>[];
    r.adapter.loading.listen(loading.add);
    await ls.skipToNext();
    await settle();
    expect(_names(api), contains(#crateApiPlaybackSkipNext));
    // A track change from the lock screen is a tap: loading until the first sound.
    expect(loading, [true]);

    await ls.pause();
    await ls.play();
    expect(r.backend.calls, ['pause', 'play']);
    expect(_names(api).where((n) => n != #crateApiPlaybackNowPlaying), [
      #crateApiPlaybackSkipNext,
    ]);
  });

  test('lock screen previous passes the current position', () async {
    final r = Rig();
    final ls = LockScreen(r.adapter, labels: _labels)..start();
    r.commands.add(playCmd('e1', 'a'));
    await settle();
    r.backend.indexes.add(0);
    r.backend.positions.add(const Duration(milliseconds: 42000));
    await settle();

    await ls.skipToPrevious();
    final call = api.calls.singleWhere(
      (c) => c.memberName == #crateApiPlaybackPrevious,
    );
    expect(call.namedArguments[#positionMs], BigInt.from(42000));
  });

  test('now playing becomes a media item with a file artUri', () async {
    final r = Rig();
    final ls = LockScreen(r.adapter, labels: _labels)..start();
    api.now.add(
      NowPlaying(
        track: _track,
        artworkPath: '/data/art/track 7.jpg',
        durationMs: BigInt.from(200000),
      ),
    );
    await settle();

    final item = ls.mediaItem.value!;
    expect(item.id, 'track:7');
    expect(item.title, 'Halo');
    expect(item.artist, 'Ana, Bo');
    expect(item.album, 'Lumen');
    expect(item.duration, const Duration(seconds: 200));
    expect(item.artUri, Uri.file('/data/art/track 7.jpg'));
    expect(item.artUri!.scheme, 'file');

    // Nothing loaded: no item, no controls.
    api.now.add(const NowPlaying());
    await settle();
    expect(ls.mediaItem.value, isNull);
    expect(ls.playbackState.value.controls, isEmpty);
  });

  test('media notification exposes like and stop actions', () async {
    final r = Rig();
    final ls = LockScreen(r.adapter, labels: _labels)..start();
    api.now.add(const NowPlaying(track: _track));
    await settle();

    MediaControl custom(String name) => ls.playbackState.value.controls
        .singleWhere((c) => c.customAction?.name == name);
    expect(custom('like').label, 'J’aime');
    expect(custom('like').androidIcon, 'drawable/ic_notif_like');
    expect(custom('stop').label, 'Arrêter');
    expect(custom('stop').androidIcon, 'drawable/ic_notif_close');
    // ⏮ ⏯ ⏭ in the compact view.
    expect(ls.playbackState.value.androidCompactActionIndices, [0, 1, 2]);

    await ls.customAction('like');
    final like = api.calls.singleWhere(
      (c) => c.memberName == #crateApiLibrarySetLiked,
    );
    expect(like.namedArguments, {#id: 'track:7', #liked: true});
    // The heart fills at once.
    expect(custom('like').androidIcon, 'drawable/ic_notif_liked');
    expect(custom('like').label, 'Je n’aime plus');

    await ls.customAction('stop');
    expect(_names(api), contains(#crateApiPlaybackStop));
  });
}
