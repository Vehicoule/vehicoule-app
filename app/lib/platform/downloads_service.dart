/// Downloads keep going in the background: on Android, a foreground service with a progress
/// notification runs while a download is `Running` (MainActivity, DownloadService.kt).
/// A `Queued` one (offline, say) waits without it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bridge/api/library.dart';
import '../bridge/downloads.dart';
import '../bridge/events.dart';

class DownloadsService {
  DownloadsService();

  static const _channel = MethodChannel('app.vehicoule/downloads');

  /// The running downloads, by id, in the order they started.
  final _running = <String, DownloadProgress>{};
  final _titles = <String, String>{};
  var _active = false;
  Future<void> _chain = Future.value();

  /// Android only: elsewhere the app itself keeps running.
  void start() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    downloadProgress().listen(
      (p) => _then(() async {
        if (p.state == DownloadStateView.running) {
          _running[p.id] = p;
          _titles[p.id] ??= await _title(p.id);
        } else {
          _running.remove(p.id);
        }
        await _sync(_running.containsKey(p.id) ? p : null);
      }),
    );
    // A cancel forgets a download without a progress event.
    libraryChanges()
        .where((c) => c is LibraryChanged_Downloads)
        .listen(
          (_) => _then(() async {
            final rows = await downloads();
            final still = {
              for (final r in rows)
                if (r.state == DownloadStateView.running) r.id,
            };
            _running.removeWhere((id, _) => !still.contains(id));
            await _sync(null);
          }),
        );
  }

  /// One event at a time, in order.
  void _then(Future<void> Function() f) => _chain = _chain
      .then((_) => f())
      .catchError(
        (Object e, StackTrace s) => FlutterError.reportError(
          FlutterErrorDetails(exception: e, stack: s, library: 'downloads'),
        ),
      );

  Future<String> _title(String id) async {
    final t = await tracks(ids: [id]);
    return t.isEmpty ? '' : t.first.title;
  }

  /// [latest]: the download that just moved, shown in the notification.
  Future<void> _sync(DownloadProgress? latest) async {
    if (_running.isEmpty) {
      if (!_active) return;
      _active = false;
      await _channel.invokeMethod<void>('stop');
      return;
    }
    final p = latest ?? _running.values.last;
    final args = {
      'title': _titles[p.id] ?? '',
      'done': p.bytesDone.toInt(),
      'total': p.bytesTotal?.toInt() ?? -1,
      'count': _running.length,
    };
    final method = _active ? 'update' : 'start';
    _active = true;
    await _channel.invokeMethod<void>(method, args);
  }
}
