// Navigation, search, carousels, sheets, dialogs and settings groups (spec UI §4, §5.4,
// §5.8, §6.7), each in its Vehicoule configuration on material_3_expressive.
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../symbols.dart';
import '../tokens.dart';
import 'artwork.dart';
import 'controls.dart';
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
  });

  final List<VDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => M3ENavigationBar(
    selectedIndex: selected,
    onDestinationSelected: onSelected,
    safeArea: false,
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
  const VPinned(this.itemId, this.label, {this.kind = ArtKind.item});

  final String itemId, label;
  final ArtKind kind;
}

/// The rail (spec UI §4.2): the destinations, then « Épinglés »; collapsed (icons and
/// artworks) or [expanded]. Indices run over the destinations, then the pinned items.
class VNavigationRail extends StatefulWidget {
  const VNavigationRail({
    super.key,
    required this.destinations,
    required this.pinned,
    required this.selected,
    required this.onSelected,
    required this.expanded,
    required this.onExpanded,
    this.fab,
  });

  /// The destination's main action, in the rail's FAB slot at its top (spec UI §5.4).
  final VAction? fab;

  final List<VDestination> destinations;
  final List<VPinned> pinned;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool expanded;
  final ValueChanged<bool> onExpanded;

  @override
  State<VNavigationRail> createState() => _VNavigationRailState();
}

class _VNavigationRailState extends State<VNavigationRail> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final destinations = widget.destinations, pinned = widget.pinned;
    // Collapsed, the FAB (M3EFab). Expanded, M3E's rail would make it an extended FAB
    // laid out while the rail opens from 0 wide, which overflows: the expanded rail
    // keeps its destinations only until the package fixes it.
    final expanded = widget.expanded, fab = expanded ? null : widget.fab;
    return M3ENavigationRail(
      type: expanded
          ? M3ENavigationRailType.expanded
          : M3ENavigationRailType.collapsed,
      onTypeChanged: (t) =>
          widget.onExpanded(t == M3ENavigationRailType.expanded),
      // Room for the FAB's label (« Ajouter une source ») when expanded.
      expandedWidth: VSize.railExpanded,
      // Collapsed: icons and artworks only (spec UI §4.2), the labels are spoken.
      labelBehavior: expanded
          ? M3ENavigationRailLabelBehavior.alwaysShow
          : M3ENavigationRailLabelBehavior.alwaysHide,
      expandTooltip: l.actionExpandMenu,
      collapseTooltip: l.actionCollapseMenu,
      selectedIndex: widget.selected,
      onDestinationSelected: widget.onSelected,
      fab: switch (fab) {
        final a? => M3ENavigationRailFabSlot(
          icon: VSymbol(a.icon, filled: true),
          label: a.label,
          semanticLabel: a.label,
          tooltip: a.label,
          onPressed: a.onSelected,
        ),
        null => null,
      },
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
        if (pinned.isNotEmpty)
          M3ENavigationRailSection(
            header: Text(l.railPinned),
            destinations: [
              for (final p in pinned)
                M3ENavigationRailDestination(
                  icon: VArtwork(
                    itemId: p.itemId,
                    size: VSize.icon,
                    kind: p.kind,
                  ),
                  label: p.label,
                ),
            ],
          ),
      ],
    );
  }
}

/// The search bar; typing opens its suggestions (spec UI §6.2, §4.2). [suggestions]
/// builds them for the current text.
class VSearchBar extends StatefulWidget {
  const VSearchBar({super.key, required this.suggestions, this.onSubmitted});

  final List<Widget> Function(BuildContext context, String text) suggestions;
  final ValueChanged<String>? onSubmitted;

  @override
  State<VSearchBar> createState() => _VSearchBarState();
}

class _VSearchBarState extends State<VSearchBar> {
  final _controller = M3ESearchController();

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
    viewHintText: AppLocalizations.of(context).searchHint,
    onSubmitted: widget.onSubmitted,
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
    titleText: title,
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
