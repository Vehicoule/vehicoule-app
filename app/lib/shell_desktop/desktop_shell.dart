// The desktop shell (spec UI §4.2), from 840 dp: the title bar (desktop platforms only;
// an Android tablet has none), the rail with its pinned items and the destination's
// FAB, the content, the « en lecture » pane or its strip, and the immersive view over
// all of it. Tab goes title bar → rail → content → pane (spec UI §4.4).
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../bridge/api/settings.dart';
import '../design/design.dart';
import '../l10n/app_localizations.dart';
import '../router.dart';
import '../screen_fab.dart';
import 'immersive.dart';
import 'now_playing_pane.dart';
import 'pinned.dart';
import 'shortcuts.dart';
import 'title_bar.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  static const _paneKey = 'ui.now_playing_open', _railKey = 'ui.rail_expanded';

  /// Null until the user chooses: open from [VBreakpoints.paneOpen], live.
  bool? _pane;
  bool _rail = false, _immersive = false;
  final _search = GlobalKey<VSearchBarState>();
  final _pinned = Pinned();

  @override
  void initState() {
    super.initState();
    _pinned
      ..addListener(() => setState(() {}))
      ..load();
    _restore();
    vSnackLift.value = 0;
  }

  Future<void> _restore() async {
    final (pane, rail) = await (
      uiPref(key: _paneKey),
      uiPref(key: _railKey),
    ).wait;
    if (!mounted) return;
    setState(() {
      _pane = pane == null ? null : pane == 'true';
      _rail = rail == 'true';
    });
  }

  @override
  void dispose() {
    _pinned.dispose();
    super.dispose();
  }

  bool get _paneOpen =>
      _pane ?? MediaQuery.sizeOf(context).width >= VBreakpoints.paneOpen;

  void _togglePane() {
    final open = !_paneOpen;
    setState(() => _pane = open);
    setUiPref(key: _paneKey, value: '$open');
  }

  void _toggleRail(bool expanded) {
    setState(() => _rail = expanded);
    setUiPref(key: _railKey, value: '$expanded');
  }

  void _toggleImmersive() {
    if (AppScope.of(context).playback.track == null && !_immersive) return;
    setState(() => _immersive = !_immersive);
  }

  void _select(int i) {
    final destinations = shellDestinations(AppLocalizations.of(context)).length;
    if (i < destinations) {
      widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex);
    } else {
      context.go(Pinned.route(_pinned.ids[i - destinations]));
    }
  }

  /// The pinned item open now, else the destination.
  int _selected(int destinations) {
    final at = GoRouterState.of(context).uri.toString();
    final i = _pinned.ids.indexWhere((id) => Pinned.route(id) == at);
    return i < 0 ? widget.shell.currentIndex : destinations + i;
  }

  Widget _region(int order, Widget child) => FocusTraversalOrder(
    order: NumericFocusOrder(order.toDouble()),
    child: FocusTraversalGroup(policy: SkipEmptyScopes(), child: child),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scope = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final destinations = shellDestinations(l);
    // The domain at the rail's bottom: a chip once the rail is wide enough for its
    // label (as its FAB), an icon while it grows and when collapsed.
    final domain = LayoutBuilder(
      builder: (context, box) => _rail && box.maxWidth >= VSize.railFabExtended
          ? VChip(
              label: l.domainMusic,
              icon: VIcons.musicNote,
              filter: true,
              selected: true,
              onPressed: () {},
            )
          : VIconButton(
              icon: VIcons.musicNote,
              label: l.domainMusic,
              selected: true,
              onPressed: () {},
            ),
    );
    final main = ScreenFabHost(
      builder: (context, action, items, bar) => Row(
        children: [
          _region(
            2,
            VNavigationRail(
              destinations: destinations,
              pinned: _pinned.items(l),
              selected: _selected(destinations.length),
              onSelected: _select,
              expanded: _rail,
              onExpanded: _toggleRail,
              fab: action,
              fabItems: items,
              trailing: Padding(
                padding: const EdgeInsets.all(VSpace.s8),
                child: domain,
              ),
              onDrop: (i, ids) => _pinned.drop(_pinned.ids[i], ids),
            ),
          ),
          Expanded(
            child: _region(
              3,
              Padding(
                padding: const EdgeInsets.only(bottom: VSpace.s8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(VRadius.large),
                  // The content is a card on the window: its own surface, so
                  // the pages' app bars blend in.
                  child: vOnSurface(
                    context,
                    scheme.surfaceContainerLow,
                    Material(
                      color: scheme.surfaceContainerLow,
                      child: Stack(
                        children: [
                          Positioned.fill(child: widget.shell),
                          // A selection's toolbar, where a phone has its mini player.
                          if (bar != null)
                            Positioned(
                              left: VSpace.s16,
                              right: VSpace.s16,
                              bottom: VSpace.s16,
                              child: Center(child: bar),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return DesktopShortcuts(
      player: scope.player,
      focusSearch: () {
        if (hasTitleBar) {
          _search.currentState?.open();
        } else {
          context.go('/explore');
        }
      },
      onPane: _togglePane,
      onImmersive: _toggleImmersive,
      child: Material(
        color: scheme.surface,
        child: Stack(
          children: [
            FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: SafeArea(
                child: Column(
                  children: [
                    if (hasTitleBar) _region(1, TitleBar(search: _search)),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: main),
                          _region(
                            4,
                            NowPlayingPane(
                              open: _paneOpen,
                              onToggle: _togglePane,
                              onImmersive: _toggleImmersive,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_immersive)
              Positioned.fill(child: ImmersivePlayer(onExit: _toggleImmersive)),
          ],
        ),
      ),
    );
  }
}

/// Reading order, minus the pages that hold nothing to focus: a branch's route scope
/// would otherwise take Tab and keep it (an empty or loading page).
class SkipEmptyScopes extends ReadingOrderTraversalPolicy {
  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) => super.sortDescendants(
    descendants.where(
      (n) => n is! FocusScopeNode || n.traversalDescendants.isNotEmpty,
    ),
    currentNode,
  );
}
