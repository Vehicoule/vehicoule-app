import 'package:flutter/material.dart';

import 'bridge/frb_generated.dart';

/// Skeleton only: plan 5 builds the screens (and calls initApp, checkUpdates after the
/// first frame).
Future<void> main() async {
  await RustLib.init();
  runApp(const MaterialApp(title: 'Vehicoule', home: Scaffold()));
}
