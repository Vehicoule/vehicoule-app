import 'dart:ui' show Locale;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vehicoule/bridge/app.dart';
import 'package:vehicoule/platform/paths.dart';

List<Object> _fields(AppConfig c) => [
  c.dataDir,
  c.cacheDir,
  c.downloadsDir,
  c.appVersion,
  c.region,
  c.platform,
  c.osVersion,
  c.deviceModel,
];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  test('app config fills all eight fields', () async {
    const support = '/Users/u/Library/Application Support/app.vehicoule';
    const cache = '/Users/u/Library/Caches/app.vehicoule';
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (c) async => switch (c.method) {
        'getApplicationSupportDirectory' => support,
        'getApplicationCacheDirectory' => cache,
        _ => null,
      },
    );
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    PackageInfo.setMockInitialValues(
      appName: 'Vehicoule',
      packageName: 'app.vehicoule',
      version: '1.2.3',
      buildNumber: '4',
      buildSignature: '',
    );
    binding.platformDispatcher.localeTestValue = const Locale('fr', 'BE');
    addTearDown(binding.platformDispatcher.clearLocaleTestValue);
    final device = DeviceInfoPlugin.setMockInitialValues(
      macOsDeviceInfo: MacOsDeviceInfo.setMockInitialValues(
        computerName: 'c',
        hostName: 'h',
        arch: 'arm64',
        model: 'Mac15,3',
        modelName: 'MacBook Pro',
        kernelVersion: 'k',
        osRelease: 'r',
        majorVersion: 15,
        minorVersion: 4,
        patchVersion: 1,
        activeCPUs: 8,
        memorySize: 0,
        cpuFrequency: 0,
        systemGUID: 'g',
      ),
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      expect(
        _fields(await appConfig(device: device)),
        _fields(
          const AppConfig(
            dataDir: support,
            cacheDir: cache,
            downloadsDir: '$support/downloads',
            appVersion: '1.2.3',
            region: 'BE',
            platform: Platform.macOs,
            osVersion: '15.4.1',
            deviceModel: 'Mac15,3',
          ),
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
