/// `vehicoule://` links, from Android's intent filters and macOS's `CFBundleURLTypes`.
///
/// One hub for the app's life: [startLinks] (main, Task 5) subscribes to app_links once,
/// before any route, so the launch link is caught (app_links hands it to its first
/// listener only). Each link goes to its route by host and is held until that route
/// listens, then delivered once: `add-source` (Task 7), `now-playing` (Task 10).
library;

import 'dart:async';

import 'package:app_links/app_links.dart';

class _Route {
  final _held = <Uri>[];
  late final _out = StreamController<Uri>.broadcast(onListen: _flush);

  void add(Uri u) => _out.hasListener ? _out.add(u) : _held.add(u);

  void _flush() {
    final held = [..._held];
    _held.clear();
    held.forEach(_out.add);
  }
}

final _routes = {'add-source': _Route(), 'now-playing': _Route()};
StreamSubscription<Uri>? _sub;

/// Idempotent. Other schemes and unknown hosts are dropped.
void startLinks() => _sub ??= AppLinks().uriLinkStream.listen((u) {
  if (u.scheme == 'vehicoule') _routes[u.host]?.add(u);
});

Stream<Uri> addSourceLinks() => _routes['add-source']!._out.stream;

Stream<Uri> nowPlayingLinks() => _routes['now-playing']!._out.stream;
