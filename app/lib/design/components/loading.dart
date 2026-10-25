import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart'
    hide CornerRounding, RoundedPolygon;

import '../../l10n/app_localizations.dart';
import '../motion.dart';
import '../tokens.dart';
import 'artwork.dart';

/// The M3E loading indicator (morphing shapes). With "reduce motion" it holds one shape.
///
/// [contained] puts it in its own round container (M3E "contained" variant), for a
/// loading state floating over content; [onContainer] draws it in the colour of what it
/// sits on (inside a FAB or a filled button).
class VLoading extends StatelessWidget {
  const VLoading({
    super.key,
    this.size = VSize.iconLarge,
    this.contained = false,
    this.onContainer = false,
  });

  final double size;
  final bool contained, onContainer;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).loading;
    final color = onContainer ? IconTheme.of(context).color : null;
    if (!reduceMotion(context)) {
      return M3ELoadingIndicator(
        size: size,
        semanticLabel: label,
        color: color,
        variant: contained
            ? M3ELoadingIndicatorVariant.contained
            : M3ELoadingIndicatorVariant.defaultStyle,
      );
    }
    return Semantics(
      label: label,
      child: SizedBox.square(
        dimension: size,
        child: Padding(
          padding: EdgeInsets.all(size / 8),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: color ?? Theme.of(context).colorScheme.primary,
              shape: VPolygonBorder(M3EShapeKind.softBurst.polygon),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pull to refresh with the M3E loading indicator, not a spinner (spec UI §6.9).
class VRefresh extends StatelessWidget {
  const VRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) => M3ERefreshIndicator(
    onRefresh: onRefresh,
    semanticsLabel: AppLocalizations.of(context).loading,
    child: child,
  );
}
