import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../motion.dart';

/// How far above the window's bottom (past its safe area) snackbars sit: a phone shell
/// sets it to the top of its mini player or bar (spec UI §5.3: never over the
/// navigation), the desktop to 0.
final vSnackLift = ValueNotifier(0.0);

/// The app's discreet messages (errors, "Undo"). [duration] stays 4 s unless a caller
/// needs the undo window (`VDurations.undo`).
void showVSnack(
  BuildContext c,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = VDurations.snack,
}) => M3ESnackbar.defaultController.present(
  c,
  duration: duration,
  child: ValueListenableBuilder(
    valueListenable: vSnackLift,
    builder: (context, lift, child) => Padding(
      padding: EdgeInsets.only(bottom: lift),
      child: child,
    ),
    child: M3ESnackbar(
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  ),
);
