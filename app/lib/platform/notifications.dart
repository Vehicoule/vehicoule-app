/// The notification permission (Android 13+), asked at the first launch and, after
/// « Plus tard », once more at the first download (spec UI §6.7).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../bridge/api/settings.dart';

const _channel = MethodChannel('app.vehicoule/notifications');

/// `later` (« Plus tard » at the first launch) or `done`.
const notifAskedKey = 'ui.notif_asked';

/// Asks the system; true when notifications may show (always, outside Android).
Future<bool> requestNotificationPermission() async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  return await _channel.invokeMethod<bool>('request') ?? false;
}

/// Before a download: asks again if the first launch said « Plus tard », then never.
Future<void> askNotificationsAtFirstDownload() async {
  if (await uiPref(key: notifAskedKey) != 'later') return;
  await setUiPref(key: notifAskedKey, value: 'done');
  await requestNotificationPermission();
}
