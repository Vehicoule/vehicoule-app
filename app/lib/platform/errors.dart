/// Uncaught Dart errors go to the core, which drops them unless telemetry is on.
library;

import 'package:flutter/foundation.dart';

import '../bridge/api/system.dart' show reportDartError;

void installErrorHooks() {
  final flutter = FlutterError.onError;
  FlutterError.onError = (d) {
    flutter?.call(d);
    _report(d.exception, d.stack);
  };
  final platform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (e, s) {
    _report(e, s);
    return platform?.call(e, s) ?? false;
  };
}

void _report(Object e, StackTrace? s) {
  try {
    reportDartError(
      kind: e.runtimeType.toString(),
      stack: (s ?? StackTrace.empty).toString(),
    ).ignore();
  } catch (_) {
    // The core isn't up (an error before RustLib.init): nothing to report to.
  }
}
