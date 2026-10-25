// The rest of the M3 set the app uses (spec UI §4, §5.4, §5.8, §6), each in its Vehicoule
// configuration: our icons, our labels, our tokens. Built on material_3_expressive;
// screens use these, never the package (guarded in test/design).
import 'dart:math' as math;

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../motion.dart';
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
    this.secondary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool extended;

  /// `secondaryContainer`: a screen's FAB above the mini player's ⏯ (which is
  /// `primaryContainer`), so the two never read as one pair.
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    Widget fab(bool extended, [Key? key]) => M3EExtendedFab(
      key: key,
      icon: VSymbol(icon, filled: true),
      label: label,
      extended: extended,
      onPressed: onPressed,
      color: secondary ? M3EFabColor.secondary : M3EFabColor.primary,
      // M3 Expressive's default extended FAB is the small one (56).
      size: M3EExtendedFabSize.small,
    );
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      // M3E springs the width with a fixed motion: with reduce motion, the two states
      // cross-fade instead (spec UI §2.6).
      child: reduceMotion(context)
          ? AnimatedSwitcher(
              duration: VDurations.reduced,
              // Both states keep the end edge, as the morph does.
              layoutBuilder: (current, previous) => Stack(
                alignment: AlignmentDirectional.centerEnd,
                children: [...previous, ?current],
              ),
              child: fab(extended, ValueKey(extended)),
            )
          : fab(extended),
    );
  }
}

/// A screen's main action as a FAB (spec UI §5.4): [action], or a FAB menu whose [items]
/// open in a menu anchored to it (above it when there is no room below). Extended with
/// its label when [extended]; [secondary] off the ⏯'s `primaryContainer`.
/// [startAligned]: the menu opens from the FAB's start edge (a rail's FAB).
class VScreenFab extends StatelessWidget {
  const VScreenFab({
    super.key,
    required this.action,
    this.items = const [],
    this.extended = true,
    this.secondary = false,
    this.startAligned = false,
  });

  final VAction action;
  final List<VAction> items;
  final bool extended, secondary, startAligned;

  @override
  Widget build(BuildContext context) {
    void press() {
      if (items.isEmpty) return action.onSelected();
      final b = context.findRenderObject()! as RenderBox;
      showVMenu(
        context,
        anchor: b.localToGlobal(Offset.zero) & b.size,
        quick: const [],
        groups: [items],
        startAligned: startAligned,
      );
    }

    return extended
        ? VExtendedFab(
            icon: action.icon,
            label: action.label,
            onPressed: press,
            secondary: secondary,
          )
        : VFab(icon: action.icon, label: action.label, onPressed: press);
  }
}

/// A phone screen's bottom corner (spec UI §5.4): the mini player, and the screen's FAB
/// above its ⏯, right-aligned, 16 dp apart, extended with its label and in
/// `secondaryContainer`. The FAB hides while [body] scrolls down and comes back when it
/// scrolls up. A header split button that has scrolled away becomes [fab] (the screen
/// passes it once its header is gone). The dock's height is added to [body]'s bottom
/// padding, so a list's last row scrolls clear of it.
class VFabDock extends StatefulWidget {
  const VFabDock({
    super.key,
    required this.body,
    this.fab,
    this.fabItems = const [],
    this.player,
  });

  /// The fade behind the mini player.
  static const protectionKey = ValueKey('vfabdock.protection');

  final Widget body;

  /// The screen's main action; [fabItems] make it a FAB menu.
  final VAction? fab;
  final List<VAction> fabItems;

  /// The mini player; without it (desktop, nothing playing) the FAB has the corner.
  final Widget? player;

  @override
  State<VFabDock> createState() => _VFabDockState();
}

class _VFabDockState extends State<VFabDock> {
  final _dock = GlobalKey(), _player = GlobalKey();
  bool _shown = true;
  double _height = 0, _playerHeight = 0;

  bool _onScroll(UserScrollNotification n) {
    final shown = switch (n.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _shown,
    };
    if (shown != _shown) setState(() => _shown = shown);
    return false;
  }

  /// The dock's height after layout, for the body's inset.
  void _measure() {
    final box = _dock.currentContext?.findRenderObject() as RenderBox?;
    if (!mounted || box == null || !box.hasSize) return;
    final h = box.size.height + VSpace.s16;
    final p = (_player.currentContext?.findRenderObject() as RenderBox?)?.size;
    final ph = p == null ? 0.0 : p.height + VSpace.s16;
    if (h != _height || ph != _playerHeight) {
      setState(() {
        _height = h;
        _playerHeight = ph;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final fab = _shown ? widget.fab : null;
    final current = ValueKey(fab == null ? 'none' : 'fab');
    final mq = MediaQuery.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(bottom: mq.padding.bottom + _height),
            ),
            child: NotificationListener<UserScrollNotification>(
              onNotification: _onScroll,
              child: widget.body,
            ),
          ),
        ),
        // Behind the mini player, the surface rises in an eased fade: rows dim behind
        // it instead of showing through its gaps.
        if (widget.player != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: mq.padding.bottom + _playerHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                key: VFabDock.protectionKey,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      for (var i = 0; i <= 8; i++)
                        Theme.of(context).colorScheme.surface.withValues(
                          alpha: (1 + math.cos(math.pi * i / 8)) / 2,
                        ),
                    ],
                    stops: [for (var i = 0; i <= 8; i++) i / 8],
                  ),
                ),
              ),
            ),
          ),
        PositionedDirectional(
          start: VSpace.s16,
          end: VSpace.s16,
          bottom: mq.padding.bottom + VSpace.s16,
          child: Column(
            key: _dock,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: vMotion(context, VDurations.short),
                // Scaled and faded to nothing; a leaving FAB is out of hit testing
                // and semantics at once.
                transitionBuilder: (child, a) {
                  final leaving = child.key != current;
                  return IgnorePointer(
                    ignoring: leaving,
                    child: ExcludeSemantics(
                      excluding: leaving,
                      child: ScaleTransition(
                        scale: a,
                        alignment: AlignmentDirectional.bottomEnd.resolve(
                          Directionality.of(context),
                        ),
                        child: FadeTransition(opacity: a, child: child),
                      ),
                    ),
                  );
                },
                child: fab == null
                    ? const SizedBox.shrink(key: ValueKey('none'))
                    : Padding(
                        key: const ValueKey('fab'),
                        // 16 dp to the ⏯ itself, which sits centred beside the
                        // taller toolbar.
                        padding: EdgeInsets.only(
                          bottom: widget.player == null
                              ? 0
                              : VSpace.s16 - (VSize.toolbar - VSize.fab) / 2,
                        ),
                        child: VScreenFab(
                          action: fab,
                          items: widget.fabItems,
                          secondary: widget.player != null,
                        ),
                      ),
              ),
              if (widget.player case final player?)
                KeyedSubtree(key: _player, child: player),
            ],
          ),
        ),
      ],
    );
  }
}

/// The FAB menu (Bibliothèque: nouvelle playlist, importer un lien).
///
/// [label] names it (« Nouvelle », « Lancer »); [icon] is its closed glyph.
class VFabMenu extends StatelessWidget {
  const VFabMenu({
    super.key,
    required this.items,
    required this.label,
    this.icon = VIcons.add,
  });

  final List<VAction> items;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: M3EFabMenu(
      icon: VSymbol(icon, filled: true),
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
    // The chosen one is primary, as everywhere in the app.
    decoration: M3EButtonDecoration.styleFrom(
      selectedBackgroundColor: Theme.of(context).colorScheme.primary,
      selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
    ),
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
    this.fab,
  });

  final List<VAction> actions;
  final String? title;
  final Widget? leading;
  final bool docked;

  /// The FAB beside a floating toolbar (multiple selection: « Lire »).
  final Widget? fab;

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
      floatingActionButton: fab,
      fabExpandsToolbar: false,
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
