import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// The top of a screen: `surfaceContainer` fading into `surface`, one of the two allowed
/// gradients (spec UI §2.2).
class VScreenBackground extends StatelessWidget {
  const VScreenBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: const Alignment(0, -0.2),
          colors: [scheme.surfaceContainer, scheme.surface],
        ),
      ),
      child: child,
    );
  }
}

/// An album, playlist or artist header, as a sliver: the artwork shrinks into the app bar
/// and the title follows; the extended [actions] give way to [fab]. On expanded windows it
/// lays out horizontally (artwork left, title and actions right; spec UI §4.2).
class VFlexibleHeader extends StatelessWidget {
  const VFlexibleHeader({
    super.key,
    required this.artwork,
    required this.title,
    this.subtitle,
    required this.actions,
    required this.fab,
  });

  final Widget artwork;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget fab;

  static const barKey = ValueKey('header.bar');

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // The header's own width decides (a pane or a split view is narrower than the window).
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final wide = windowClassOf(width) == WindowClass.expanded;
        return SliverPersistentHeader(
          pinned: true,
          delegate: _Delegate(
            header: this,
            top: MediaQuery.paddingOf(context).top,
            width: width,
            wide: wide,
            art: wide ? VSize.headerArtWide : VSize.headerArt,
            // Title, subtitle and the actions row under (or beside) the artwork.
            text: VSize.headerText * scale,
            actionsHeight: VSize.menuTarget + VSpace.s16,
          ),
        );
      },
    );
  }
}

class _Delegate extends SliverPersistentHeaderDelegate {
  _Delegate({
    required this.header,
    required this.top,
    required this.width,
    required this.wide,
    required this.art,
    required this.text,
    required this.actionsHeight,
  });

  final VFlexibleHeader header;
  final double top, width, art, text, actionsHeight;
  final bool wide;

  @override
  double get minExtent => top + VSize.appBar;

  @override
  double get maxExtent => wide
      ? top + VSize.appBar + art + VSpace.s24
      : top + VSize.appBar + art + VSpace.s16 + text + actionsHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final margin = VSpace.margin(windowClassOf(width));
    const bar = VSize.appBar, docked = VSize.dockedArt;

    final artSize = lerpDouble(art, docked, t)!;
    final artLeft = lerpDouble(wide ? margin : (width - art) / 2, margin, t)!;
    final artTop = lerpDouble(top + bar, top + (bar - docked) / 2, t)!;
    final textLeft = lerpDouble(
      wide ? margin + art + VSpace.s24 : margin,
      margin + docked + VSpace.s12,
      t,
    )!;
    final textTop = lerpDouble(
      wide
          ? top + bar + art - text - actionsHeight
          : top + bar + art + VSpace.s16,
      top + (bar - VSpace.s24) / 2,
      t,
    )!;
    final open = (1 - 2 * t).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        Material(
          key: VFlexibleHeader.barKey,
          color: theme.colorScheme.surface,
          elevation: overlapsContent || t == 1 ? 3 : 0,
        ),
        Positioned(
          left: artLeft,
          top: artTop,
          width: artSize,
          height: artSize,
          child: FittedBox(child: header.artwork),
        ),
        Positioned(
          left: textLeft,
          right: margin + (t > 0.5 ? VSize.menuTarget + VSpace.s16 : 0),
          top: textTop,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                header.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle.lerp(
                  theme.textTheme.headlineMedium,
                  theme.textTheme.titleLarge,
                  t,
                ),
              ),
              if (header.subtitle != null && t < 0.5)
                Opacity(
                  opacity: open,
                  child: Text(
                    header.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (open > 0)
          Positioned(
            left: textLeft,
            right: margin,
            top: textTop + text,
            child: Opacity(
              opacity: open,
              child: Wrap(
                spacing: VSpace.s8,
                runSpacing: VSpace.s8,
                children: header.actions,
              ),
            ),
          ),
        if (t > 0.5)
          Positioned(
            right: margin,
            top: top + (bar - VSize.menuTarget) / 2,
            height: VSize.menuTarget,
            child: Opacity(
              opacity: (2 * t - 1).clamp(0.0, 1.0),
              child: FittedBox(child: header.fab),
            ),
          ),
      ],
    );
  }

  @override
  bool shouldRebuild(_Delegate old) =>
      old.header != header ||
      old.top != top ||
      old.width != width ||
      old.wide != wide ||
      old.text != text;
}
