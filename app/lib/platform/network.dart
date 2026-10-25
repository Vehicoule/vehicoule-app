/// Online or not, from the system: the core stops calling sources offline
/// (`setOnline`), and the UI shows it (`online`).
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../bridge/api/app.dart' show setOnline;

class Network {
  Network([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// Online until the system says otherwise: the start never waits for the network.
  final _online = ValueNotifier(true);
  bool? _told;

  ValueListenable<bool> get online => _online;

  void start() {
    _connectivity.checkConnectivity().then(_on);
    _connectivity.onConnectivityChanged.listen(_on);
  }

  void _on(List<ConnectivityResult> r) {
    final on = r.any((c) => c != ConnectivityResult.none);
    _online.value = on;
    if (on == _told) return;
    _told = on;
    setOnline(online: on).ignore();
  }
}
