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
/// a connected group, then [groups] separated by a gap. [origin] (the row or card it
/// comes from) is drawn lifted at [anchor], in global coordinates.
Future<void> showVMenu(
  BuildContext c, {
  required Rect anchor,
  required List<VAction> quick,
  required List<List<VAction>> groups,
  Widget? origin,
}) => Navigator.of(c, rootNavigator: true).push(
  _MenuRoute(
    anchor: anchor,
    quick: quick,
    groups: groups,
    origin: origin,
    barrierLabel: MaterialLocalizations.of(c).modalBarrierDismissLabel,
  ),
);

class _MenuRoute extends PopupRoute<void> {
  _MenuRoute({
    required this.anchor,
    required this.quick,
    required this.groups,
    required this.origin,
    required this.barrierLabel,
  });

  final Rect anchor;
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
    void run(VAction action) {
      Navigator.of(context).pop();
      action.onSelected();
    }

    Widget surface(Widget child) => Material(
      color: scheme.surfaceContainer,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VRadius.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    final panel = ConstrainedBox(
      key: VMenu.panelKey,
      constraints: const BoxConstraints(maxWidth: VSize.menu),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (quick.isNotEmpty)
              Center(
                key: VMenu.quickKey,
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
            for (final (gi, group) in groups.indexed) ...[
              const SizedBox(height: VSpace.s8),
              surface(
                M3EMenuContent(
                  closeOnSelect: true,
                  // The menu takes the keyboard: its first item has focus, ↑/↓ move.
                  autofocusFirst: gi == 0,
                  onSelect: (_) {},
                  nodes: [
                    M3EMenuGroup.entries(
                      entries: [
                        for (final e in group)
                          M3EMenuEntry(
                            label: e.label,
                            leading: e.leading ?? VSymbol(e.icon),
                            onPressed: () => run(e),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Stack(
      children: [
        if (origin != null)
          Positioned.fromRect(
            rect: anchor,
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

/// Below the anchor, start-aligned with it; above when there is no room; always on screen.
class _MenuPlacement extends SingleChildLayoutDelegate {
  const _MenuPlacement(this.anchor);

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints.loose(c.biggest).deflate(const EdgeInsets.all(VSpace.s8));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final below = anchor.bottom + VSpace.s8;
    final y = below + child.height <= size.height - VSpace.s8
        ? below
        : (anchor.top - VSpace.s8 - child.height).clamp(VSpace.s8, size.height);
    final x = anchor.left.clamp(
      VSpace.s8,
      size.width - child.width - VSpace.s8,
    );
    return Offset(x.toDouble(), y.toDouble());
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
