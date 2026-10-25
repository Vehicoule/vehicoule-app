import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicoule/bridge/downloads.dart';
import 'package:vehicoule/bridge/events.dart';
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/debug/fake_api.dart';
import 'package:vehicoule/debug/library.dart';
import 'package:vehicoule/platform/downloads_service.dart';

import 'player_test.dart' show settle;

DownloadProgress _p(
  String id,
  DownloadStateView state, {
  int done = 0,
  int? total,
}) => DownloadProgress(
  id: id,
  bytesDone: BigInt.from(done),
  bytesTotal: total == null ? null : BigInt.from(total),
  state: state,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.vehicoule/downloads');
  late FakeApi api;
  late List<MethodCall> native;

  setUp(() {
    api = FakeApi();
    RustLib.initMock(api: api);
    native = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          native.add(c);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    RustLib.dispose();
  });

  String show(MethodCall c) => '${c.method} ${c.arguments ?? ''}'.trim();

  test(
    'downloads service starts on first running download and stops when idle',
    () async {
      final a = sampleTracks[0], b = sampleTracks[1];
      DownloadsService().start();

      // Queued (offline, say): the queue waits without a service.
      api.downloadEvents.add(_p(a.id, DownloadStateView.queued));
      await settle();
      expect(native, isEmpty);

      api.downloadEvents.add(
        _p(a.id, DownloadStateView.running, done: 100, total: 1000),
      );
      await settle();
      api.downloadEvents.add(_p(b.id, DownloadStateView.running, done: 5));
      await settle();
      api.downloadEvents.add(
        _p(a.id, DownloadStateView.done, done: 1000, total: 1000),
      );
      await settle();
      api.downloadEvents.add(_p(b.id, DownloadStateView.failed, done: 5));
      await settle();

      expect(native.map(show), [
        'start {title: ${a.title}, done: 100, total: 1000, count: 1}',
        'update {title: ${b.title}, done: 5, total: -1, count: 2}',
        'update {title: ${b.title}, done: 5, total: -1, count: 1}',
        'stop',
      ]);
    },
  );

  test('a cancelled download stops the service too', () async {
    final a = sampleTracks[0];
    DownloadsService().start();
    api.downloadEvents.add(
      _p(a.id, DownloadStateView.running, done: 1, total: 9),
    );
    await settle();
    // Cancelling forgets the row without a progress event: only the library changes.
    api.downloadRows = [];
    api.libraryEvents.add(const LibraryChanged.downloads());
    await settle();
    expect(native.map((c) => c.method), ['start', 'stop']);
  });

  test('a download done at once starts then stops the service, in order', () async {
    final a = sampleTracks[0];
    DownloadsService().start();
    // Running then Done back to back (a tiny file): stop never overtakes start.
    api.downloadEvents.add(
      _p(a.id, DownloadStateView.running, done: 1, total: 2),
    );
    api.downloadEvents.add(_p(a.id, DownloadStateView.done, done: 2, total: 2));
    await settle();
    await settle();
    expect(native.map((c) => c.method), ['start', 'stop']);
  });

  test('a service the system refuses is reported as an error', () async {
    DownloadsService().start();
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(
            const MethodCall(
              'failed',
              'ForegroundServiceStartNotAllowedException: dataSync',
            ),
          ),
          (_) {},
        );
    expect(reported, hasLength(1));
    expect(reported.single.library, 'downloads');
    expect(
      reported.single.exception.toString(),
      contains('ForegroundServiceStartNotAllowedException'),
    );
  });
}
