import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

/// The standard side sheet, on the same plane as the content (it pushes it): the
/// desktop "now playing" pane. Built here because `M3ESideSheet` always draws its own
/// title bar, and the pane has its own header.
class VSideSheet extends StatelessWidget {
  const VSideSheet({
    super.key,
    required this.open,
    required this.child,
    this.width = VSize.sideSheet,
    this.card = false,
  });

  final bool open;
  final Widget child;
  final double width;

  /// Detached (desktop-2): a rounded card [VSpace.s8] from what's before it, on the
  /// player's surface, instead of a flush sheet with a border. The gap folds with it.
  final bool card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: open ? 1 : 0),
      duration: vMotion(context, VDurations.medium),
      curve: VCurves.emphasized,
      builder: (context, t, child) => ClipRect(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: t,
          child: Offstage(
            offstage: t == 0,
            child: ExcludeFocus(excluding: !open, child: child!),
          ),
        ),
      ),
      child: card
          ? Padding(
              padding: const EdgeInsetsDirectional.only(start: VSpace.s8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(VRadius.large),
                child: ColoredBox(
                  color: vScreenSurface(scheme),
                  child: SizedBox(width: width, child: child),
                ),
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: BorderDirectional(
                  start: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: SizedBox(width: width, child: child),
            ),
    );
  }
}
