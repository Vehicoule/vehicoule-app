/// A screen's main action (spec UI §5.4). The screen declares it with [ScreenFab]; the
/// shell's [ScreenFabHost] places it: above the mini player's ⏯ on a phone (`VFabDock`),
/// at the top of the rail on desktop (`VNavigationRail.fab`).
library;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'design/design.dart';

/// [action] is the FAB; with [items] it is a FAB menu. [bar] takes the mini player's
/// place while it is set (a selection's toolbar).
class ScreenFab extends StatefulWidget {
  const ScreenFab({
    super.key,
    this.action,
    this.items = const [],
    this.bar,
    required this.child,
  });

  final VAction? action;
  final List<VAction> items;
  final Widget? bar;
  final Widget child;

  @override
  State<ScreenFab> createState() => _ScreenFabState();
}

class _ScreenFabState extends State<ScreenFab> {
  _ScreenFabHostState? _host;

  /// On the current route of the shown branch: the screen the user sees.
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled;
    final host = context.findAncestorStateOfType<_ScreenFabHostState>();
    if (host != _host) _host?._remove(this);
    _host = host?.._update(this);
  }

  @override
  void didUpdateWidget(ScreenFab old) {
    super.didUpdateWidget(old);
    _host?._update(this);
  }

  @override
  void dispose() {
    _host?._remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Builds the shell's corner from the [ScreenFab] the user sees, if any.
class ScreenFabHost extends StatefulWidget {
  const ScreenFabHost({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    VAction? action,
    List<VAction> items,
    Widget? bar,
  )
  builder;

  @override
  State<ScreenFabHost> createState() => _ScreenFabHostState();
}

class _ScreenFabHostState extends State<ScreenFabHost> {
  final _fabs = <_ScreenFabState>[];
  ScreenFab? _shown;

  void _update(_ScreenFabState f) {
    _fabs
      ..remove(f)
      ..add(f);
    _refresh();
  }

  void _remove(_ScreenFabState f) {
    _fabs.remove(f);
    _refresh();
  }

  /// The last visible one wins: a page pushed over another, or the one just shown.
  void _refresh() {
    void apply() {
      final shown = _fabs.where((f) => f._visible).lastOrNull?.widget;
      if (mounted && !identical(shown, _shown)) {
        setState(() => _shown = shown);
      }
    }

    // Screens report while the tree builds or unmounts: the host follows after.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      apply();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _shown?.action,
    _shown?.items ?? const [],
    _shown?.bar,
  );
}
