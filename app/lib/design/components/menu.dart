import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../symbols.dart';
import '../tokens.dart';
import 'controls.dart';

/// One action of a menu, a quick row or a connected group.
class VAction {
  const VAction(
    this.label,
    this.icon,
    this.onSelected, {
    this.selected = false,
    this.leading,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  /// A toggle that is on (liked, downloaded).
  final bool selected;

  /// Replaces the icon (the morphing download icon).
  final Widget? leading;
}

abstract final class VMenu {
  static const quickKey = ValueKey('vmenu.quick'),
      panelKey = ValueKey('vmenu.panel');
}

/// The expressive menu (spec UI §5.2), the same on mobile and desktop: the [quick] row as
/// a connected group, then [groups] separated by a gap. It opens next to its trigger
/// ([anchor], global coordinates): right-aligned under a ⋮ button, at the pointer for a
/// zero-size rect (right click), beside the row for a long press; above when there is no
/// room below, always inside the window. [origin] (the row or card it comes from) is
/// drawn lifted at [originRect] (default [anchor]).
Future<void> showVMenu(
  BuildContext c, {
  required Rect anchor,
  required List<VAction> quick,
  required List<List<VAction>> groups,
  Widget? origin,
  Rect? originRect,
}) => Navigator.of(c, rootNavigator: true).push(
  _MenuRoute(
    anchor: anchor,
    quick: quick,
    groups: groups,
    origin: origin,
    originRect: originRect ?? anchor,
    barrierLabel: MaterialLocalizations.of(c).modalBarrierDismissLabel,
  ),
);

class _MenuRoute extends PopupRoute<void> {
  _MenuRoute({
    required this.anchor,
    required this.quick,
    required this.groups,
    required this.origin,
    required this.originRect,
    required this.barrierLabel,
  });

  final Rect anchor, originRect;
  final List<VAction> quick;
  final List<List<VAction>> groups;
  final Widget? origin;

  @override
  final String barrierLabel;

  bool get _reduced {
    final c = navigator?.context;
    return c != null && reduceMotion(c);
  }

  @override
  Duration get transitionDuration =>
      _reduced ? Duration.zero : VDurations.short;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> a,
    Animation<double> s,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: a,
      curve: VCurves.emphasizedDecelerate,
    );
    return FadeTransition(opacity: curved, child: child);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> a,
    Animation<double> s,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final m3e = M3ETheme.of(context);
    final menu = m3e.menuTheme;
    void run(VAction action) {
      Navigator.of(context).pop();
      action.onSelected();
    }

    // The M3 Expressive vertical menu with gaps: each section is a surface of the menu
    // container colour, 16 corners, level-2 elevation, 2 apart (m3.material.io menus,
    // specs).
    Widget surface(Widget child, {Key? key}) => DecoratedBox(
      key: key,
      decoration: ShapeDecoration(
        color: menu.colors(m3e.colorScheme).container,
        shape: menu.containerShape,
        shadows: M3EElevation.shadows(
          menu.elevation,
          shadowColor: m3e.colorScheme.shadow,
        ),
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: menu.containerShape),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: menu.verticalPadding),
          child: child,
        ),
      ),
    );

    final sections = <Widget>[
      // The quick row (spec UI §5.2) is the menu's first section: a connected group.
      if (quick.isNotEmpty)
        surface(
          key: VMenu.quickKey,
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VSpace.s8,
              vertical: VSpace.s4,
            ),
            child: VConnectedGroup(
              // With no groups below, the quick row takes the keyboard.
              autofocusFirst: groups.isEmpty,
              actions: [
                for (final q in quick)
                  VAction(
                    q.label,
                    q.icon,
                    () => run(q),
                    selected: q.selected,
                    leading: q.leading,
                  ),
              ],
            ),
          ),
        ),
      for (final (gi, group) in groups.indexed)
        surface(
          M3EMenuContent(
            closeOnSelect: true,
            // The menu takes the keyboard: its first item has focus, ↑/↓ move.
            autofocusFirst: gi == 0,
            applyGroupShapes: false,
            onSelect: (_) {},
            nodes: [
              for (final e in group)
                M3EMenuEntry(
                  label: e.label,
                  leading: e.leading ?? VSymbol(e.icon),
                  onPressed: () => run(e),
                ),
            ],
          ),
        ),
    ];
    final panel = ConstrainedBox(
      key: VMenu.panelKey,
      constraints: BoxConstraints(
        minWidth: menu.minWidth,
        maxWidth: VSize.menu,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, w) in sections.indexed) ...[
              if (i > 0) SizedBox(height: menu.sectionGap),
              w,
            ],
          ],
        ),
      ),
    );

    return Stack(
      children: [
        if (origin != null)
          Positioned.fromRect(
            rect: originRect,
            child: IgnorePointer(
              child: Material(
                color: scheme.surfaceContainerHigh,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(VRadius.small),
                ),
                clipBehavior: Clip.antiAlias,
                child: origin,
              ),
            ),
          ),
        CustomSingleChildLayout(delegate: _MenuPlacement(anchor), child: panel),
      ],
    );
  }
}

/// Next to the trigger: a point (right click) is the menu's top-left corner, or its
/// top-right when there is no room on the right; a rect (⋮, a lifted row) has the menu
/// under it, right-aligned. Above when there is no room below; always on screen.
class _MenuPlacement extends SingleChildLayoutDelegate {
  const _MenuPlacement(this.anchor);

  final Rect anchor;

  static const _edge = VSpace.s8, _gap = VSpace.s4;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints.loose(c.biggest).deflate(const EdgeInsets.all(_edge));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final point = anchor.isEmpty;
    final gap = point ? 0.0 : _gap;
    final maxX = size.width - child.width - _edge;
    final maxY = size.height - child.height - _edge;
    final x = point
        ? (anchor.left <= maxX ? anchor.left : anchor.left - child.width)
        : anchor.right - child.width;
    final below = anchor.bottom + gap;
    final y = below <= maxY ? below : anchor.top - gap - child.height;
    return Offset(
      x.clamp(_edge, maxX < _edge ? _edge : maxX),
      y.clamp(_edge, maxY < _edge ? _edge : maxY),
    );
  }

  @override
  bool shouldRelayout(_MenuPlacement old) => old.anchor != anchor;
}

abstract final class VSheet {
  static const bottomKey = ValueKey('vsheet.bottom');
  static const dialogKey = ValueKey('vsheet.dialog');
  static bool _open = false;
}

/// The app's sheets (spec UI §5.8): a bottom sheet below the expanded width, a dialog
/// beyond. Never one over another: while one is open, this returns null at once.
Future<T?> showVSheet<T>(
  BuildContext c, {
  required WidgetBuilder builder,
}) async {
  if (VSheet._open) return null;
  VSheet._open = true;
  try {
    if (windowClassOf(MediaQuery.sizeOf(c).width) == WindowClass.expanded) {
      return await showDialog<T>(
        context: c,
        builder: (context) => Dialog(
          key: VSheet.dialogKey,
          child: Padding(
            padding: const EdgeInsets.all(VSpace.s24),
            child: builder(context),
          ),
        ),
      );
    }
    return await M3EBottomSheet.show<T>(
      c,
      builder: (context) =>
          KeyedSubtree(key: VSheet.bottomKey, child: builder(context)),
    );
  } finally {
    VSheet._open = false;
  }
}
