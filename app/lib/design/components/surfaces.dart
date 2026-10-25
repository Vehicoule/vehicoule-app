// Navigation, search, carousels, sheets, dialogs and settings groups (spec UI §4, §5.4,
// §5.8, §6.7), each in its Vehicoule configuration on material_3_expressive.
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../symbols.dart';
import '../tokens.dart';
import 'artwork.dart';
import 'controls.dart';
import 'focus_ring.dart';
import 'kit.dart';
import 'menu.dart';

/// A destination of the bar or the rail.
class VDestination {
  const VDestination(this.label, this.icon, {this.badge});

  final String label;
  final IconData icon;
  final int? badge;
}

/// The phone's bottom bar (spec UI §4.1).
class VNavigationBar extends StatelessWidget {
  const VNavigationBar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
    this.safeArea = true,
  });

  final List<VDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  /// Clear of the system's gesture bar; false in the gallery's framed demos.
  final bool safeArea;

  @override
  Widget build(BuildContext context) => M3ENavigationBar(
    selectedIndex: selected,
    onDestinationSelected: onSelected,
    safeArea: safeArea,
    destinations: [
      for (final d in destinations)
        M3ENavigationBarDestination(
          icon: VSymbol(d.icon),
          selectedIcon: VSymbol(d.icon, filled: true),
          label: d.label,
          badgeCount: d.badge,
        ),
    ],
  );
}

/// A pinned collection in the rail: its artwork stands for it when the rail is collapsed.
class VPinned {
  const VPinned(
    this.itemId,
    this.label, {
    this.kind = ArtKind.item,
    this.droppable = false,
    this.subtitle,
  });

  final String itemId, label;
  final ArtKind kind;

  /// Under the title when the rail is expanded (« Playlist », « Titres »).
  final String? subtitle;

  /// Takes dropped tracks (Likés, Téléchargés, a playlist of the user's).
  final bool droppable;
}

/// The rail (spec UI §4.2): the destinations, then « Épinglés »; collapsed (icons and
/// artworks) or [expanded]. Indices run over the destinations, then the pinned items.
class VNavigationRail extends StatelessWidget {
  const VNavigationRail({
    super.key,
    required this.destinations,
    required this.pinned,
    required this.selected,
    required this.onSelected,
    required this.expanded,
    required this.onExpanded,
    this.fab,
    this.fabItems = const [],
    this.trailing,
    this.onDrop,
  });

  /// At the rail's bottom: the domain (spec UI §4.2).
  final Widget? trailing;

  /// Tracks dropped on a pinned item: its index in [pinned] and the track ids. Null: the
  /// pinned items take no drop.
  final void Function(int pinned, List<String> ids)? onDrop;

  /// The selected destination's own FAB (spec UI §5.4), under the menu button: a FAB
  /// collapsed, an extended FAB expanded. Null where the destination has none.
  final VAction? fab;

  /// A FAB menu's actions (Accueil « Lancer », Bibliothèque « Nouvelle »): the FAB opens
  /// them in a menu under it, and [fab]'s own callback isn't used.
  final List<VAction> fabItems;

  final List<VDestination> destinations;
  final List<VPinned> pinned;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool expanded;
  final ValueChanged<bool> onExpanded;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // The menu button and the FAB are drawn here, not in M3E's slots: its slot lays an
    // extended FAB out while the rail opens from 0 wide, which overflows.
    final rail = M3ETheme.of(context).navigationRailTheme;
    final header = Column(
      crossAxisAlignment: expanded
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        // Expanded, the header keeps the destinations' columns: ≡ over their glyphs,
        // the FAB's edge on their indicator's.
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: expanded
                ? rail.expandedItemInset +
                      rail.indicatorLeading -
                      (VSize.menuTarget - VSize.icon) / 2
                : 0,
          ),
          child: VIconButton(
            icon: expanded ? VIcons.menuOpen : VIcons.menu,
            label: expanded ? l.actionCollapseMenu : l.actionExpandMenu,
            onPressed: () => onExpanded(!expanded),
          ),
        ),
        if (fab case final fab?) ...[
          const SizedBox(height: VSpace.s8),
          // Extended once the rail is wide enough for the label (a plain FAB while
          // it grows); a FAB menu opens from its start edge, toward the content.
          LayoutBuilder(
            builder: (context, box) => Padding(
              padding: EdgeInsetsDirectional.only(
                start: expanded ? rail.expandedItemInset : 0,
              ),
              child: VScreenFab(
                action: fab,
                items: fabItems,
                extended: expanded && box.maxWidth >= VSize.railFabExtended,
                startAligned: true,
              ),
            ),
          ),
        ],
      ],
    );
    // « Épinglés » is ours, not an M3E section: 32 dp covers with a subtitle, a whole
    // row as drop target, the header on the items' column (desktop-2).
    final destinationCount = destinations.length;
    final railed = M3ENavigationRail(
      type: expanded
          ? M3ENavigationRailType.alwaysExpand
          : M3ENavigationRailType.alwaysCollapse,
      expandedWidth: VSize.railExpanded,
      // Collapsed: icons and artworks only (spec UI §4.2), the labels are spoken.
      labelBehavior: expanded
          ? M3ENavigationRailLabelBehavior.alwaysShow
          : M3ENavigationRailLabelBehavior.alwaysHide,
      leading: SizedBox(width: double.infinity, child: header),
      trailing: pinned.isEmpty
          ? null
          : _PinnedList(
              pinned: pinned,
              expanded: expanded,
              selected: selected - destinationCount,
              onSelected: (i) => onSelected(destinationCount + i),
              onDrop: onDrop,
              // Room under the last item for the domain.
              bottom: trailing == null ? 0 : VSize.menuTarget + VSpace.s16,
            ),
      trailingAtBottom: false,
      selectedIndex: selected,
      onDestinationSelected: onSelected,
      sections: [
        M3ENavigationRailSection(
          destinations: [
            for (final d in destinations)
              M3ENavigationRailDestination(
                icon: VSymbol(d.icon),
                selectedIcon: VSymbol(d.icon, filled: true),
                label: d.label,
                badgeCount: d.badge,
              ),
          ],
        ),
      ],
    );
    final bottom = trailing;
    if (bottom == null) return railed;
    // The domain stays at the rail's bottom, over the end of a long list.
    return Stack(
      children: [
        railed,
        Positioned(
          left: 0,
          right: 0,
          bottom: VSpace.s8,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: expanded ? rail.expandedItemInset : 0,
            ),
            child: Align(
              alignment: expanded
                  ? AlignmentDirectional.centerStart
                  : Alignment.center,
              child: bottom,
            ),
          ),
        ),
      ],
    );
  }
}

/// The pinned collections under the destinations: cover (and, expanded, title and
/// subtitle), selectable, each row a drop target outlined while a selection hovers it.
class _PinnedList extends StatelessWidget {
  const _PinnedList({
    required this.pinned,
    required this.expanded,
    required this.selected,
    required this.onSelected,
    required this.onDrop,
    required this.bottom,
  });

  final List<VPinned> pinned;
  final bool expanded;
  final int selected;
  final ValueChanged<int> onSelected;
  final void Function(int pinned, List<String> ids)? onDrop;
  final double bottom;

  /// M3E pads the rail's trailing slot by this much on each side.
  static const _slotInset = 16.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rail = M3ETheme.of(context).navigationRailTheme;
    // The covers' and the header's start: the destinations' glyph column, minus the
    // cover's extra width.
    final start =
        rail.expandedItemInset +
        rail.indicatorLeading -
        (VSize.pinnedArt - VSize.icon) / 2 -
        _slotInset;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (expanded)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: start,
                top: VSpace.s16,
                bottom: VSpace.s8,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  l.railPinned,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: VSpace.s16),
          for (final (i, p) in pinned.indexed)
            DragTarget<List<String>>(
              onWillAcceptWithDetails: (_) => onDrop != null && p.droppable,
              onAcceptWithDetails: (d) => onDrop?.call(i, d.data),
              builder: (context, hovered, _) => _PinnedRow(
                item: p,
                expanded: expanded,
                selected: i == selected,
                dropping: hovered.isNotEmpty,
                start: start,
                onTap: () => onSelected(i),
              ),
            ),
          SizedBox(height: bottom),
        ],
      ),
    );
  }
}

class _PinnedRow extends StatelessWidget {
  const _PinnedRow({
    required this.item,
    required this.expanded,
    required this.selected,
    required this.dropping,
    required this.start,
    required this.onTap,
  });

  final VPinned item;
  final bool expanded, selected, dropping;
  final double start;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(VRadius.small),
    );
    final subtitle = [
      ?item.subtitle,
      if (dropping) l.pinnedDropHere,
    ].join(' · ');
    final cover = VArtwork(
      itemId: item.itemId,
      size: VSize.pinnedArt,
      kind: item.kind,
    );
    Widget content(bool wide) => wide
        ? Row(
            children: [
              cover,
              const SizedBox(width: VSpace.s12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          )
        : Center(child: cover);
    return Semantics(
      button: true,
      selected: selected,
      label: [item.label, if (subtitle.isNotEmpty) subtitle].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: VFocusRing(
        shape: shape,
        child: Material(
          color: dropping
              ? scheme.surfaceContainerHighest
              : selected
              ? scheme.secondaryContainer
              : scheme.surface.withValues(alpha: 0),
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: CustomPaint(
              foregroundPainter: dropping
                  ? _DashedOutline(color: scheme.primary, shape: shape)
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: VSize.menuTarget),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: expanded ? start : 0,
                    end: expanded ? VSpace.s8 : 0,
                    top: VSpace.s4,
                    bottom: VSpace.s4,
                  ),
                  // Title and subtitle once the rail is wide enough (not while it
                  // grows from collapsed).
                  child: LayoutBuilder(
                    builder: (context, box) => content(
                      expanded && box.maxWidth >= VSize.railFabExtended - start,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A key's name in a small outlined cap (the search bar's « ⌘F »).
class _Keycap extends StatelessWidget {
  const _Keycap({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(VSpace.s8),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VSpace.s8,
          vertical: VSpace.s4,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A dashed outline along [shape] (« déposer ici », desktop-2).
class _DashedOutline extends CustomPainter {
  _DashedOutline({required this.color, required this.shape});

  final Color color;
  final ShapeBorder shape;

  static const _dash = 6.0, _gap = 4.0, _stroke = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape.getOuterPath((Offset.zero & size).deflate(_stroke / 2));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) =>
      old.color != color || old.shape != shape;
}

/// The search bar; typing opens its suggestions (spec UI §6.2, §4.2). [suggestions]
/// builds them for the current text.
class VSearchBar extends StatefulWidget {
  const VSearchBar({
    super.key,
    required this.suggestions,
    this.onSubmitted,
    this.shortcut,
  });

  final List<Widget> Function(BuildContext context, String text) suggestions;
  final ValueChanged<String>? onSubmitted;

  /// The key that opens it (« ⌘F »), shown as a keycap at the bar's end.
  final String? shortcut;

  @override
  State<VSearchBar> createState() => VSearchBarState();
}

class VSearchBarState extends State<VSearchBar> {
  final _controller = M3ESearchController();

  /// Opens the search, its field focused (⌘F).
  void open() {
    if (!_controller.isOpen) _controller.openView();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => M3ESearchAnchor.bar(
    searchController: _controller,
    barHintText: AppLocalizations.of(context).searchHint,
    barLeading: const VSymbol(VIcons.search),
    barTrailing: [
      if (widget.shortcut case final key?)
        ExcludeSemantics(child: _Keycap(label: key)),
    ],
    viewHintText: AppLocalizations.of(context).searchHint,
    onSubmitted: widget.onSubmitted,
    // The docked view is as tall as its suggestions: no empty panel.
    shrinkWrap: true,
    suggestionsBuilder: (context, c) => widget.suggestions(context, c.text),
  );
}

enum VCarouselKind { hero, multiBrowse, uncontained }

/// An item of a carousel: an artwork, its title and a line under it.
class VCarouselItem {
  const VCarouselItem({
    required this.itemId,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final String itemId, title;
  final String? subtitle;
  final VoidCallback onTap;
}

/// Carousels (spec UI §5.4): hero (Accueil: discovery, mixes), multi-browse (Artiste:
/// albums), uncontained.
class VCarousel extends StatelessWidget {
  const VCarousel({
    super.key,
    required this.kind,
    required this.items,
    required this.height,
  });

  final VCarouselKind kind;
  final List<VCarouselItem> items;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scrim = theme.colorScheme.scrim;
    // Light text on the band below; the same in both themes (it sits on a cover).
    final light = theme.brightness == Brightness.light
        ? theme.colorScheme.surface
        : theme.colorScheme.onSurface;
    return M3ECarousel(
      height: height,
      type: switch (kind) {
        VCarouselKind.hero => M3ECarouselType.hero,
        VCarouselKind.multiBrowse => M3ECarouselType.contained,
        VCarouselKind.uncontained => M3ECarouselType.uncontained,
      },
      childElementBorderRadius: VRadius.large,
      children: [
        for (final i in items)
          M3ECarouselItem(
            // The cover stays vivid: a band under the text only, and only on an item
            // wide enough to show text (M3E shows the title on large slots only).
            image: LayoutBuilder(
              builder: (context, box) => Stack(
                fit: StackFit.expand,
                children: [
                  VArtworkPicture(itemId: i.itemId, size: height),
                  if (box.maxWidth >= VSize.carouselText)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: VSize.carouselBand,
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                scrim.withValues(alpha: 0),
                                scrim.withValues(alpha: VSize.carouselScrim),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Title and artist together: shown on large slots only, none on the narrow
            // ones (no 6 px captions).
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  i.title,
                  style: theme.textTheme.titleMedium?.copyWith(color: light),
                ),
                if (i.subtitle case final sub?)
                  Text(
                    sub,
                    style: theme.textTheme.bodyMedium?.copyWith(color: light),
                  ),
              ],
            ),
            semanticLabel: i.title,
            onTap: i.onTap,
          ),
      ],
    );
  }
}

/// A basic dialog (desktop sheets, spec UI §5.8): one main action on the right,
/// « Annuler » as a text button.
Future<bool?> showVDialog(
  BuildContext c, {
  required String title,
  required String message,
  required String action,
  String? cancel,
}) => M3EDialog.show<bool>(
  c,
  dialog: Builder(
    builder: (context) {
      final l = AppLocalizations.of(context);
      return M3EDialog(
        title: title,
        content: Text(message),
        actions: [
          VButton(
            label: cancel ?? l.actionCancel,
            style: VButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          VButton(
            label: action,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    },
  ),
);

M3ESideSheetLabels _sideLabels(BuildContext c) {
  final m = MaterialLocalizations.of(c);
  return M3ESideSheetLabels(
    close: m.closeButtonLabel,
    back: m.backButtonTooltip,
    scrim: m.modalBarrierDismissLabel,
  );
}

/// The modal side sheet (desktop: queue and lyrics at narrow widths, details).
Future<void> showVSideSheet(
  BuildContext c, {
  required String title,
  required Widget body,
}) => M3ESideSheet.show<void>(
  c,
  title: title,
  body: body,
  labels: _sideLabels(c),
  closeIcon: const VSymbol(VIcons.close),
);

/// A standard bottom sheet, part of the screen (the add-source flow's details, a
/// filter panel): it rests collapsed and drags open.
class VStandardSheet extends StatelessWidget {
  const VStandardSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final m = MaterialLocalizations.of(context);
    return M3EBottomSheet.standard(
      labels: M3EBottomSheetLabels(
        dismiss: m.modalBarrierDismissLabel,
        close: m.closeButtonLabel,
        scrim: m.modalBarrierDismissLabel,
        expand: m.expandedIconTapHint,
        collapse: m.collapsedIconTapHint,
      ),
      child: child,
    );
  }
}

/// A settings group (spec UI §6.7): rows in one rounded group, its label inside the first
/// (the Réglages mockup).
class VListGroup extends StatelessWidget {
  const VListGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return M3EList(
      itemCount: children.length,
      itemBuilder: (context, i) => i > 0
          ? children[i]
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    VSpace.s16,
                    VSpace.s12,
                    VSpace.s16,
                    0,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                children[0],
              ],
            ),
    );
  }
}

/// A row of a settings group: the M3E list item (a title, an optional line under it,
/// what it holds: a switch), or a choice under it (a connected group), which the M3E item
/// has no slot for.
class VListRow extends StatelessWidget {
  const VListRow({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    this.below,
    this.onTap,
  }) : assert(title != null || below != null);

  /// Null for a row that is only a choice (the group's label names it).
  final String? title;
  final String? subtitle;
  final Widget? trailing, below;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final choice = below;
    if (choice == null) {
      return M3EListItem(
        headline: title!,
        supportingText: subtitle,
        trailing: trailing,
        onTap: onTap,
      );
    }
    // A choice spans the row under its optional title: a custom row, inside the same
    // M3E segment as the items.
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VSpace.s16,
        vertical: VSpace.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title!, style: theme.textTheme.bodyLarge),
            const SizedBox(height: VSpace.s12),
          ],
          choice,
        ],
      ),
    );
  }
}

/// The large app bar that folds on scroll, at the top of each tab (spec UI §4.1): a
/// sliver.
class VLargeAppBar extends StatelessWidget {
  const VLargeAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => M3EAppBar.sliver(
    // One line, shrunk to fit: M3E wraps a long title (« Bibliothèque » on a phone)
    // past the height it gives it.
    title: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(title, maxLines: 1),
    ),
    leading: leading,
    actions: actions,
    variant: M3EAppBarVariant.largeFlexible,
  );
}

/// A circular progress (a download on its own, a page loading by steps); wavy while it
/// moves.
class VCircularProgress extends StatelessWidget {
  const VCircularProgress({
    super.key,
    required this.value,
    this.size = VSize.iconLarge,
  });

  final double? value;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppLocalizations.of(context).loading,
    value: value == null ? null : '${(value! * 100).round()} %',
    child: M3EProgressIndicator.circularWavy(value: value, size: size),
  );
}
