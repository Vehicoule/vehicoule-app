/// The core's configuration (`initApp`): where it keeps its data, cache and downloads,
/// and what it tells sources and telemetry about the device.
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../bridge/app.dart';

/// [device]: for the tests.
Future<AppConfig> appConfig({DeviceInfoPlugin? device}) async {
  final info = device ?? DeviceInfoPlugin();
  final data = (await getApplicationSupportDirectory()).path;
  final (platform, os, model) = switch (defaultTargetPlatform) {
    TargetPlatform.android => await info.androidInfo.then(
      (d) =>
          (Platform.android, d.version.release, '${d.manufacturer} ${d.model}'),
    ),
    TargetPlatform.iOS => await info.iosInfo.then(
      (d) => (Platform.ios, d.systemVersion, d.utsname.machine),
    ),
    TargetPlatform.macOS => await info.macOsInfo.then(
      (d) => (
        Platform.macOs,
        '${d.majorVersion}.${d.minorVersion}.${d.patchVersion}',
        d.model,
      ),
    ),
    TargetPlatform.windows => await info.windowsInfo.then(
      (d) => (Platform.windows, d.displayVersion, d.productName),
    ),
    _ => await info.linuxInfo.then((d) => (Platform.linux, d.prettyName, '')),
  };
  return AppConfig(
    dataDir: data,
    cacheDir: (await getApplicationCacheDirectory()).path,
    // Android: the app's own folder on shared storage (no permission, removed with
    // the app); elsewhere next to the data.
    downloadsDir: platform == Platform.android
        ? '${(await getExternalStorageDirectory())?.path ?? data}/music'
        : '$data/downloads',
    appVersion: (await PackageInfo.fromPlatform()).version,
    region:
        WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? 'US',
    platform: platform,
    osVersion: os,
    deviceModel: model,
  );
}
