// The dev feed never holds up the start (Task 5 round 2, item C): its first install
// takes seconds, and Android freezes a backgrounded (cached) process, so an app that
// awaited it before runApp stayed blank until it came back to the foreground.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/debug/dev_feed.dart';
import 'package:vehicoule/debug/fake_api.dart';
import 'package:vehicoule/platform/player.dart';

import '../platform/player_test.dart' show FakeBackend;

class _SlowFeed extends FakeApi {
  final installing = Completer<void>();
  var finished = false, added = false;

  @override
  Future<void> crateApiAppFinishOnboarding({required bool telemetry}) async {
    finished = true;
  }

  @override
  Future<void> crateApiPluginsAddFeed({
    required String url,
    required String publicKey,
  }) {
    added = true;
    return installing.future;
  }
}

void main() {
  test('the start skips the first launch without waiting for the feed', () async {
    final api = _SlowFeed();
    RustLib.initMock(api: api);
    addTearDown(RustLib.dispose);
    final player = PlayerAdapter(
      FakeBackend(),
      commands: const Stream.empty(),
      report: (_) {},
    );
    await startDevFeed(
      player,
      url: 'http://127.0.0.1:1/feed.json',
    ).timeout(const Duration(seconds: 1));
    expect(api.finished, isTrue, reason: 'the first launch is skipped first');
    await pumpEventQueue();
    expect(api.added, isTrue, reason: 'the feed is added after, in background');
    api.installing.complete();
  });
}
