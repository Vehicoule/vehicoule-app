// The rest of the M3 set the app uses (spec UI §4, §5.4, §5.8, §6), each in its Vehicoule
// configuration: our icons, our labels, our tokens. Built on material_3_expressive;
// screens use these, never the package (guarded in test/design).
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../symbols.dart';
import '../tokens.dart';
import 'artwork.dart';
import 'controls.dart';
import 'menu.dart';

enum VFabSize { small, regular, large }

/// A FAB: one main action of a screen. [label] is spoken and shown as its tooltip.
class VFab extends StatelessWidget {
  const VFab({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = VFabSize.regular,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final VFabSize size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: M3EFab(
      icon: VSymbol(icon, filled: true),
      tooltip: label,
      onPressed: onPressed,
      size: switch (size) {
        VFabSize.small => M3EFabSize.small,
        VFabSize.regular => M3EFabSize.regular,
        VFabSize.large => M3EFabSize.large,
      },
    ),
  );
}

/// The extended FAB that shrinks to a FAB (album « Lire », spec UI §5.4): the screen sets
/// [extended] from its scroll (false once the list moves).
class VExtendedFab extends StatelessWidget {
  const VExtendedFab({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.extended = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool extended;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: M3EExtendedFab(
      icon: VSymbol(icon, filled: true),
      label: label,
      extended: extended,
      onPressed: onPressed,
      // M3 Expressive's default extended FAB is the small one (56).
      size: M3EExtendedFabSize.small,
    ),
  );
}

/// The FAB menu (Bibliothèque: nouvelle playlist, importer un lien).
class VFabMenu extends StatelessWidget {
  const VFabMenu({super.key, required this.items});

  final List<VAction> items;

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppLocalizations.of(context).actionCreate,
    child: M3EFabMenu(
      icon: const VSymbol(VIcons.add),
      closeIcon: const VSymbol(VIcons.close),
      size: M3EFabSize.regular,
      items: [
        for (final a in items)
          M3EFabMenuItem(
            icon: a.leading ?? VSymbol(a.icon),
            label: a.label,
            onPressed: a.onSelected,
          ),
      ],
    ),
  );
}

/// One choice out of a few, as a connected button group with labels (spec UI §6.7:
/// Réglages chooses with connected groups, never radio lists; M3 Expressive replaces
/// segmented buttons with them).
class VChoiceGroup<T> extends StatelessWidget {
  const VChoiceGroup({
    super.key,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> choices;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => M3EButtonGroup(
    type: M3EButtonGroupType.connected,
    style: M3EButtonStyle.tonal,
    size: M3EButtonSize.sm,
    selectionRequired: true,
    selectedIndex: choices.indexWhere((c) => c.$1 == value),
    onSelectedIndexChanged: (i) {
      if (i == null) return;
      VHaptics.selection();
      onChanged(choices[i].$1);
    },
    actions: [
      for (final (_, label) in choices)
        M3EButtonGroupAction(label: Text(label), semanticLabel: label),
    ],
  );
}

/// A toolbar: floating (mini player, selector, multiple selection) or [docked] at the
/// bottom of a screen. [actions] are icon buttons with their spoken labels; a [title]
/// (the selection count) sits before them.
class VToolbar extends StatelessWidget {
  const VToolbar({
    super.key,
    required this.actions,
    this.title,
    this.leading,
    this.docked = false,
  });

  final List<VAction> actions;
  final String? title;
  final Widget? leading;
  final bool docked;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final a in actions)
        M3EToolbarWidget(
          child: VIconButton(
            icon: a.icon,
            label: a.label,
            selected: a.selected ? true : null,
            onPressed: a.onSelected,
          ),
        ),
    ];
    if (docked) {
      return M3EToolbar.docked(
        leading: leading,
        titleText: title,
        actions: items,
        maxInlineActions: items.length,
      );
    }
    return M3EToolbar.floating(
      screenOffset: 0,
      leading: leading,
      titleText: title,
      actions: items,
      maxInlineActions: items.length,
    );
  }
}

/// A chip: [filter] toggles a filter (search, library); otherwise an assist chip.
class VChip extends StatelessWidget {
  const VChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.filter = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool selected, filter;

  @override
  Widget build(BuildContext context) => M3EChip(
    label: label,
    type: filter ? M3EChipType.filter : M3EChipType.assist,
    selected: selected,
    leading: icon == null ? null : VSymbol(icon!, size: VSize.chipIcon),
    onPressed: onPressed,
  );
}

/// The M3E switch, with its spoken label.
class VSwitch extends StatelessWidget {
  const VSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => M3ESwitch(
    value: value,
    onChanged: onChanged,
    semanticLabel: label,
    selectedIcon: const VSymbol(VIcons.check, size: VSize.iconSmall),
  );
}

/// A count or a dot on an icon (downloads running, new in the rail). Never decorative.
class VBadge extends StatelessWidget {
  const VBadge({super.key, required this.child, this.count, this.label});

  final Widget child;
  final int? count;
  final String? label;

  @override
  Widget build(BuildContext context) => M3EBadge(
    count: count,
    showDot: count == null,
    semanticLabel: label,
    child: child,
  );
}

/// The gesture hint (spec UI §5.7): a rich tooltip with a title, one sentence and « OK »,
/// shown once by the screen ([controller].show()).
class VRichTooltip extends StatefulWidget {
  const VRichTooltip({
    super.key,
    required this.title,
    required this.message,
    required this.child,
    this.showOnStart = false,
  });

  final String title, message;
  final Widget child;
  final bool showOnStart;

  @override
  State<VRichTooltip> createState() => _VRichTooltipState();
}

class _VRichTooltipState extends State<VRichTooltip> {
  final _controller = M3ETooltipController();

  @override
  void initState() {
    super.initState();
    if (widget.showOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.show();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => M3ETooltip(
    controller: _controller,
    richTitle: widget.title,
    richMessage: widget.message,
    persistent: true,
    actions: [
      VButton(
        label: AppLocalizations.of(context).actionOk,
        style: VButtonStyle.text,
        onPressed: _controller.hide,
      ),
    ],
    child: widget.child,
  );
}

/// A placeholder at the content's real size while it loads: still, no shimmer (spec UI
/// §2.8). [kind] gives an artwork's shape; text lines are rounded bars.
class VSkeleton extends StatelessWidget {
  const VSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.kind,
  });

  /// A rounded square for an item, a circle for an artist; null for a line of text.
  final ArtKind? kind;
  final double width, height;

  /// A track row's skeleton: artwork, title and artists, at the row's height.
  static Widget row() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: VSpace.s16),
    child: SizedBox(
      height: VSize.trackRow,
      child: Row(
        children: [
          VSkeleton(
            width: VSize.trackArt,
            height: VSize.trackArt,
            kind: ArtKind.item,
          ),
          SizedBox(width: VSpace.s16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: VSkeleton(width: double.infinity, height: VSpace.s12),
                ),
                SizedBox(height: VSpace.s8),
                FractionallySizedBox(
                  widthFactor: 0.4,
                  child: VSkeleton(width: double.infinity, height: VSpace.s8),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: kind == ArtKind.artist
            ? const CircleBorder()
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  kind == null ? height / 2 : VRadius.small,
                ),
              ),
      ),
    ),
  );
}
