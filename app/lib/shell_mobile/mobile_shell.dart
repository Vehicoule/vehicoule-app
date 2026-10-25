// The phone shell (spec UI §4.1): the navigation bar, ☰ and its modal rail, the mini
// player with the screen's FAB above its ⏯, and the player sheet over everything.
// Medium width (spec UI §4.3): the collapsed rail at the left instead of the bar.
import 'dart:math' as math;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../design/design.dart';
import '../features/music/now_playing/now_playing_sheet.dart';
import '../l10n/app_localizations.dart';
import '../router.dart';
import '../screen_fab.dart';
import '../shell_desktop/desktop_shell.dart' show SkipEmptyScopes;
import '../shell_desktop/shortcuts.dart';
import 'domain_rail.dart';
import 'mini_player.dart';

class MobileShell extends StatefulWidget {
  const MobileShell({super.key, required this.shell, this.medium = false});

  final StatefulNavigationShell shell;
  final bool medium;

  static MobileShellState? maybeOf(BuildContext c) =>
      c.findAncestorStateOfType<MobileShellState>();

  @override
  State<MobileShell> createState() => MobileShellState();
}

class MobileShellState extends State<MobileShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _sheet = GlobalKey<NowPlayingSheetState>();
  final _extent = ValueNotifier(0.0);
  final _miniArt = ValueNotifier<Rect?>(null);
  final _bar = GlobalKey();

  /// The top of the corner's dock (screen FAB, mini player), from `VFabDock`.
  double? _dockTop;

  /// Snackbars go above everything in the bottom corner: the screen FAB, the mini
  /// player and the bar (M3: never over a FAB or the navigation).
  void _liftSnacks() {
    if (!mounted) return;
    final bar = _bar.currentContext?.findRenderObject() as RenderBox?;
    final mq = MediaQuery.of(context);
    final tops = [
      ?_dockTop,
      if (bar != null && bar.hasSize) bar.localToGlobal(Offset.zero).dy,
    ];
    vSnackLift.value = tops.isEmpty
        ? 0
        : (mq.size.height - tops.reduce(math.min) - mq.padding.bottom).clamp(
            0,
            mq.size.height,
          );
  }

  /// ☰: the modal rail.
  void openMenu() => _scaffold.currentState?.openDrawer();

  void _go(int i) =>
      widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex);

  @override
  void dispose() {
    _extent.dispose();
    _miniArt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scope = AppScope.of(context);
    final playback = scope.playback;
    final body = ScreenFabHost(
      builder: (context, action, items, bar) => ListenableBuilder(
        listenable: playback,
        builder: (context, _) {
          return VFabDock(
            onTop: (top) {
              _dockTop = top;
              _liftSnacks();
            },
            body: widget.shell,
            fab: action,
            fabItems: items,
            // Nothing loaded: no mini player, the screen's FAB has the corner.
            player:
                bar ??
                (playback.track == null
                    ? null
                    : MiniPlayer(
                        extent: _extent,
                        onArtworkRect: (r) => _miniArt.value = r,
                        onOpen: () => _sheet.currentState?.open(),
                      )),
          );
        },
      ),
    );
    return DesktopShortcuts(
      player: scope.player,
      focusSearch: () => context.go('/explore'),
      child: FocusTraversalGroup(
        policy: SkipEmptyScopes(),
        child: Stack(
          children: [
            // Behind the open player the shell is out of reach: no focus, no
            // screen-reader nodes (spec UI §4.4, §8).
            ValueListenableBuilder(
              valueListenable: _extent,
              builder: (context, extent, shell) => ExcludeFocus(
                excluding: extent >= 1,
                child: ExcludeSemantics(excluding: extent >= 1, child: shell),
              ),
              child: Scaffold(
                key: _scaffold,
                drawer: const DomainRail(),
                body: widget.medium
                    ? Row(
                        children: [
                          SafeArea(
                            right: false,
                            child: VNavigationRail(
                              destinations: shellDestinations(l),
                              pinned: const [],
                              selected: widget.shell.currentIndex,
                              onSelected: _go,
                              expanded: false,
                              onExpanded: (_) => openMenu(),
                            ),
                          ),
                          Expanded(child: body),
                        ],
                      )
                    : body,
                bottomNavigationBar: widget.medium
                    ? null
                    : VNavigationBar(
                        key: _bar,
                        destinations: shellDestinations(l),
                        selected: widget.shell.currentIndex,
                        onSelected: _go,
                      ),
              ),
            ),
            Positioned.fill(
              child: ListenableBuilder(
                listenable: playback,
                builder: (context, _) => playback.track == null
                    ? const SizedBox.shrink()
                    : NowPlayingSheet(
                        key: _sheet,
                        extent: _extent,
                        from: _miniArt,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
