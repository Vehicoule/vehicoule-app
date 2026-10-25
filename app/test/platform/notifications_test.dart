import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/debug/fake_api.dart';
import 'package:vehicoule/platform/notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.vehicoule/notifications');

  test(
    'notification permission is asked again only at the first download',
    () async {
      final api = FakeApi();
      RustLib.initMock(api: api);
      addTearDown(RustLib.dispose);
      var asks = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            if (c.method == 'request') asks++;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        // Allowed at the first launch: never asked again.
        api.prefs['ui.notif_asked'] = 'done';
        await askNotificationsAtFirstDownload();
        expect(asks, 0);

        // « Plus tard » at the first launch: asked at the first download, then never.
        api.prefs['ui.notif_asked'] = 'later';
        await askNotificationsAtFirstDownload();
        await askNotificationsAtFirstDownload();
        expect(asks, 1);
        expect(api.prefs['ui.notif_asked'], 'done');

        // Elsewhere there is nothing to ask.
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        expect(await requestNotificationPermission(), isTrue);
        expect(asks, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
