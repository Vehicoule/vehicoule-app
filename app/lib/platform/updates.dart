/// Installing an update: Android downloads and verifies the APK (Rust), then hands it to
/// the system installer; macOS opens the release page.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/api/system.dart' show downloadUpdate;
import '../bridge/updates.dart';

Future<void> installUpdate(UpdateInfo u) async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    final path = await downloadUpdate(info: u);
    await const MethodChannel('app.vehicoule/update')
        .invokeMethod<void>('install', {'path': path});
    return;
  }
  await launchUrl(Uri.parse(u.pageUrl), mode: LaunchMode.externalApplication);
}
