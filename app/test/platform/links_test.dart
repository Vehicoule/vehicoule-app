import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicoule/platform/links.dart';

import 'player_test.dart' show settle;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('links emits each vehicoule uri once', () async {
    var listens = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          const EventChannel('com.llfbandit.app_links/events'),
          MockStreamHandler.inline(
            onListen: (_, sink) {
              listens++;
              sink.success('vehicoule://add-source?link=https%3A%2F%2Fa.b');
              sink.success('https://vehicoule.app/other');
              sink.success('vehicoule://now-playing');
            },
          ),
        );

    final first = <Uri>[], second = <Uri>[];
    final a = links().listen(first.add);
    await settle();
    // A later listener (another route) gets the next links, not the same ones again.
    final b = links().listen(second.add);
    await settle();
    await a.cancel();
    await b.cancel();

    expect(first, [
      Uri.parse('vehicoule://add-source?link=https%3A%2F%2Fa.b'),
      Uri.parse('vehicoule://now-playing'),
    ]);
    expect(second, isEmpty);
    expect(listens, 1);
  });
}
