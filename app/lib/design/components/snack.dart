import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../motion.dart';

/// The app's discreet messages (errors, "Undo"). [duration] stays 4 s unless a caller
/// needs the undo window (`VDurations.undo`).
void showVSnack(
  BuildContext c,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = VDurations.snack,
}) => M3ESnackbar.show(
  c,
  message: message,
  actionLabel: actionLabel,
  onAction: onAction,
  duration: duration,
);
