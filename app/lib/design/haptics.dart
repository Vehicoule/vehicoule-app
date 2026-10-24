/// The app's only haptics (spec UI §5.6): mobile only, always tied to a movement. The
/// system setting is honoured by the OS itself (Android and iOS drop the call when
/// haptics are off).
library;

import 'package:flutter/foundation.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

abstract final class VHaptics {
  static bool get _mobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Like, play/pause.
  static void light() {
    if (_mobile) M3EHaptics.trigger(M3EHapticFeedback.light);
  }

  /// A player view changes; a gesture crosses its threshold.
  static void selection() {
    if (_mobile) M3EHaptics.selection();
  }

  /// Stop by swiping down; a reordered item drops.
  static void medium() {
    if (_mobile) M3EHaptics.trigger(M3EHapticFeedback.medium);
  }
}
