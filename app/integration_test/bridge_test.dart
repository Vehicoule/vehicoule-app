import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vehicoule/bridge/api/app.dart';
import 'package:vehicoule/bridge/api/browse.dart';
import 'package:vehicoule/bridge/api/catalog.dart';
import 'package:vehicoule/bridge/api/library.dart';
import 'package:vehicoule/bridge/api/playback.dart';
import 'package:vehicoule/bridge/api/plugins.dart';
import 'package:vehicoule/bridge/api/system.dart';
import 'package:vehicoule/bridge/app.dart';
import 'package:vehicoule/bridge/error.dart';
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/bridge/player.dart';

import 'fixture.dart';

/// Serves the fixture feed (fake-catalog plugin, signed by a throwaway key) on 127.0.0.1.
Future<io.HttpServer> serveFixture() async {
  final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final body = fixtureFiles[req.uri.pathSegments.last];
    if (body == null) {
      req.response.statusCode = 404;
    } else {
      req.response.add(base64.decode(body));
    }
    req.response.close();
  });
  return server;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late io.Directory dir;

  // The app's boot: init, subscribe to every stream, then start.
  setUpAll(() async {
    await RustLib.init();
    dir = await io.Directory.systemTemp.createTemp('vehicoule-it');
    await initApp(
      cfg: AppConfig(
        dataDir: '${dir.path}/data',
        cacheDir: '${dir.path}/cache',
        downloadsDir: '${dir.path}/downloads',
        appVersion: '0.1.0',
        region: 'FR',
        platform: io.Platform.isAndroid ? Platform.android : Platform.macOs,
        osVersion: 'test',
        deviceModel: 'test',
      ),
    );
    for (final s in <Stream<Object>>[
      playerCommands(),
      queueStates(),
      nowPlaying(),
      notices(),
      libraryChanges(),
      downloadProgress(),
    ]) {
      s.listen((_) {});
    }
    await start();
  });

  tearDownAll(() => dir.delete(recursive: true));

  // First: before any plugin is installed.
  testWidgets('home feed and browse on an empty base', (t) async {
    final page = await homeFeed(cursor: null);
    expect(page.shelves.last.kind, ShelfKindView.end);
    expect(page.next, isNull);
    await expectLater(browseCategories(), throwsA(isA<CoreError_NoPlugin>()));
  });

  testWidgets('core boots and searches through a local feed', (t) async {
    // Plain http and this key: accepted by debug builds only (release feeds are https).
    final server = await serveFixture();
    addTearDown(() => server.close(force: true));
    await addFeed(
      url: 'http://127.0.0.1:${server.port}/feed.json',
      publicKey: fixtureKey,
    );
    final r = await search(query: 'halo');
    expect(r.tracks, isNotEmpty);
  });

  testWidgets('stop then undo', (t) async {
    // Nothing queued: both are no-ops, not errors.
    await stop();
    await undoStop();
    // No timer running: cancelling one is a no-op too.
    await setSleepTimer(timer: const SleepTimer.off());
  });

  testWidgets('player events are sync and fire-and-forget', (t) async {
    // Returns at once (void, not a Future); a late event for no entry is ignored.
    playerEvent(e: const PlayerEvent.ended(entry: 'gone'));
    playerEvent(
      e: PlayerEvent.error(
        entry: 'gone',
        kind: PlayerErrorKind.network,
        message: '',
        positionMs: BigInt.zero,
      ),
    );
    await skipNext(); // queued behind them: they were handled without a crash
  });

  testWidgets('bad input is a typed error, not a crash', (t) async {
    await expectLater(
      entity(id: 'not-a-uuid'),
      throwsA(isA<CoreError_Internal>()),
    );
  });

  testWidgets('https works', (t) async {
    // updates.vehicoule.app is not deployed yet: a typed error is fine, a panic (Android
    // verifier not initialised) is not.
    try {
      expect(await checkUpdates(force: true), anything);
    } on CoreError catch (_) {}
    // A real TLS handshake: example.com answers, its page is not a feed. Without the JNI
    // init the handshake fails (Network).
    await expectLater(
      previewFeed(url: 'https://example.com/', publicKey: fixtureKey),
      throwsA(isA<CoreError_InvalidFeed>()),
    );
  });
}
