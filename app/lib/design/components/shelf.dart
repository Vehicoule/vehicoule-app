import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../symbols.dart';
import '../tokens.dart';
import 'artwork.dart';
import 'controls.dart';

/// A shelf: a title and a horizontal row of cards that snaps to them, at a fixed height
/// that grows with the text size (spec UI §5.4, §8).
class VShelf extends StatelessWidget {
  const VShelf({
    super.key,
    required this.title,
    this.subtitle,
    this.onMore,
    required this.extent,
    required this.items,
    this.itemWidth = VSize.shelfCard,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onMore;

  /// The row's height at 100 % text.
  final double extent;
  final List<Widget> items;

  /// The cards' width, for snapping.
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final margin = VSpace.margin(
      windowClassOf(MediaQuery.sizeOf(context).width),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(start: margin, end: VSpace.s4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleLarge),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (onMore != null)
                VIconButton(
                  icon: VIcons.chevronRight,
                  label: AppLocalizations.of(context).actionSeeAll,
                  onPressed: onMore,
                ),
            ],
          ),
        ),
        const SizedBox(height: VSpace.s8),
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(extent),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: margin),
            physics: _Snap(itemWidth + VSpace.cardGap),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: VSpace.cardGap),
            itemBuilder: (_, i) => items[i],
          ),
        ),
      ],
    );
  }
}

/// Settles on a card edge.
class _Snap extends ScrollPhysics {
  const _Snap(this.step, {super.parent});

  final double step;

  @override
  _Snap applyTo(ScrollPhysics? ancestor) =>
      _Snap(step, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics m, double velocity) {
    if ((velocity <= 0 && m.pixels <= m.minScrollExtent) ||
        (velocity >= 0 && m.pixels >= m.maxScrollExtent)) {
      return super.createBallisticSimulation(m, velocity);
    }
    final projected = m.pixels + velocity * 0.3;
    final target = ((projected / step).round() * step).clamp(
      m.minScrollExtent,
      m.maxScrollExtent,
    );
    if ((target - m.pixels).abs() < toleranceFor(m).distance) return null;
    return ScrollSpringSimulation(
      spring,
      m.pixels,
      target,
      velocity,
      tolerance: toleranceFor(m),
    );
  }
}

/// A 108 card of a shelf: the artwork (shape by meaning), a title and a subtitle.
class VCard extends StatelessWidget {
  const VCard({
    super.key,
    required this.itemId,
    required this.title,
    this.subtitle,
    this.kind = ArtKind.item,
    required this.onTap,
  });

  final String itemId, title;
  final String? subtitle;
  final ArtKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: VSize.shelfCard,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VRadius.small),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VArtwork(itemId: itemId, size: VSize.shelfCard, kind: kind),
            const SizedBox(height: VSpace.s8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A hero card (home discovery, mixes): a large artwork and its title under it.
class VHeroCard extends StatelessWidget {
  const VHeroCard({
    super.key,
    required this.itemId,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final String itemId, title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: VSize.heroCard,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VRadius.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VArtwork(itemId: itemId, size: VSize.heroCard),
            const SizedBox(height: VSpace.s12),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge,
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
