import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicoule/platform/links.dart';

import 'player_test.dart' show settle;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'each link reaches its route once, the cold-start one included',
    () async {
      const events = EventChannel('com.llfbandit.app_links/events');
      late MockStreamHandlerEventSink platform;
      var listens = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            events,
            MockStreamHandler.inline(
              onListen: (_, sink) {
                listens++;
                platform = sink;
                // app_links hands the launch link to its first listener only.
                sink.success('vehicoule://add-source?link=https%3A%2F%2Fa.b');
              },
            ),
          );

      startLinks();
      startLinks();
      await settle();

      // The now-playing route subscribes first: the launch link isn't its.
      final playing = <Uri>[];
      final p = nowPlayingLinks().listen(playing.add);
      await settle();
      expect(playing, isEmpty);

      // The add-source route comes later and still gets it.
      final added = <Uri>[];
      final a = addSourceLinks().listen(added.add);
      await settle();
      expect(added, [
        Uri.parse('vehicoule://add-source?link=https%3A%2F%2Fa.b'),
      ]);

      // Live links, each to its route; others are dropped.
      platform.success('vehicoule://now-playing');
      platform.success('https://vehicoule.app/other');
      platform.success('vehicoule://add-source?link=x');
      await settle();
      expect(playing, [Uri.parse('vehicoule://now-playing')]);
      expect(added, hasLength(2));

      // Once: a route that listens again gets nothing already delivered…
      await a.cancel();
      final again = <Uri>[];
      final b = addSourceLinks().listen(again.add);
      await settle();
      expect(again, isEmpty);
      // …but a link that came while nobody listened waits for it.
      await b.cancel();
      platform.success('vehicoule://add-source?link=y');
      await settle();
      final late = <Uri>[];
      final c = addSourceLinks().listen(late.add);
      await settle();
      expect(late, [Uri.parse('vehicoule://add-source?link=y')]);

      await p.cancel();
      await c.cancel();
      expect(listens, 1);
    },
  );
}
