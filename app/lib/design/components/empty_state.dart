import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../symbols.dart';
import '../tokens.dart';
import 'artwork.dart';

/// An empty list: a large decor shape with an icon, one sentence and an action (spec UI
/// §6.9). No external picture; the shape is stable per message.
class VEmptyState extends StatelessWidget {
  const VEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(VSpace.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VDecor(
            shape: decorFor(message),
            size: VSize.emptyDecor,
            child: VSymbol(
              icon,
              size: VSize.iconLarge,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: VSpace.s24),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          if (action != null) ...[const SizedBox(height: VSpace.s16), action!],
        ],
      ),
    );
  }
}

/// "Offline · your downloads are still here": a quiet chip under the app bar, no banner.
class VOfflineChip extends StatelessWidget {
  const VOfflineChip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: scheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VSpace.s12,
            vertical: VSpace.s8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              VSymbol(
                VIcons.cloudOff,
                size: VSize.iconSmall,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: VSpace.s8),
              Flexible(
                child: Text(
                  AppLocalizations.of(context).offlineChip,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
