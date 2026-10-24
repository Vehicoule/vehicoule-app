import 'package:material_ui/material_ui.dart';

import '../motion.dart';
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
  });

  final bool open;
  final Widget child;
  final double width;

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
      child: DecoratedBox(
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
