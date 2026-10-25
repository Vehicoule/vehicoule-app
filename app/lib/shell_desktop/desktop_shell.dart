// The desktop shell (spec UI §4.2), from 840 dp: the title bar (desktop platforms only;
// an Android tablet has none), the rail with its pinned items and the destination's
// FAB, the content, the « en lecture » pane or its strip, and the immersive view over
// all of it. Tab goes title bar → rail → content → pane (spec UI §4.4).
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../bridge/api/settings.dart';
import '../design/design.dart';
import '../domains.dart';
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
  final _paneBox = GlobalKey();

  /// The strip's or the pane's rect for the video window (addendum §5.2).
  void _reportPane() {
    if (!mounted) return;
    final box = _paneBox.currentContext?.findRenderObject() as RenderBox?;
    AppScope.of(context)
        .miniPlayerRect
        .value = box == null || !box.hasSize || box.size.isEmpty
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
  }

  /// The current domain's pinned items (`ui.pinned.<domain>`), reloaded with the domain.
  Pinned? _pinned;

  Pinned _pinnedOf(Domain d) {
    final p = _pinned;
    if (p != null && p.domain == d) return p;
    p?.dispose();
    return _pinned = Pinned(d)
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..load();
  }

  @override
  void initState() {
    super.initState();
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
    _pinned?.dispose();
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

  Widget _region(int order, Widget child) => FocusTraversalOrder(
    order: NumericFocusOrder(order.toDouble()),
    child: FocusTraversalGroup(policy: SkipEmptyScopes(), child: child),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scope = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportPane());
    final history = NavHistory.of(context);
    final domain = history.domain;
    final pinned = _pinnedOf(domain);
    final visible = visibleDestinations(domain);
    final destinations = [
      for (final d in visible) VDestination(d.label(l), d.icon),
    ];
    final at = Uri.parse(history.location).path;
    final pinnedAt = pinned.ids.indexWhere((id) => pinned.route(id) == at);
    final selected = pinnedAt >= 0
        ? destinations.length + pinnedAt
        : selectedDestination(history.location, domain) ?? -1;
    final globals = globalSections(l);
    final global = globals.indexWhere(
      (g) => at == g.$1 || at.startsWith('${g.$1}/'),
    );
    // Changing domain: a FAB menu of the domains, hidden while there is one (U12).
    final domainMenu = domains.length < 2
        ? null
        : LayoutBuilder(
            builder: (context, box) => VScreenFab(
              action: VAction(
                domainLabel(l, domain),
                domainIcon(domain),
                () {},
              ),
              items: [
                for (final d in domains)
                  VAction(
                    domainLabel(l, d),
                    domainIcon(d),
                    () => goDestination(widget.shell, history.destinationOf(d)),
                    selected: d == domain,
                  ),
              ],
              extended: _rail && box.maxWidth >= VSize.railFabExtended,
              startAligned: true,
            ),
          );
    final main = ScreenFabHost(
      builder: (context, action, items, bar) => Row(
        children: [
          _region(
            2,
            VNavigationRail(
              destinations: destinations,
              pinned: pinned.items(l),
              selected: selected,
              onSelected: (i) => i < destinations.length
                  ? goDestination(widget.shell, visible[i].path)
                  : context.go(
                      pinned.route(pinned.ids[i - destinations.length]),
                    ),
              expanded: _rail,
              onExpanded: _toggleRail,
              fab: action,
              fabItems: items,
              trailing: domainMenu,
              globals: [for (final g in globals) g.$2],
              globalSelected: global < 0 ? null : global,
              onGlobal: (i) => context.go(globals[i].$1),
              onDrop: (i, ids) => pinned.drop(pinned.ids[i], ids),
            ),
          ),
          Expanded(
            child: _region(
              3,
              Padding(
                padding: const EdgeInsets.only(bottom: VSpace.s8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(VRadius.large),
                  // The content is a card on the window, like the pane and the
                  // strip (desktop-2): its own surface, so the pages' app bars
                  // blend in.
                  child: vOnSurface(
                    context,
                    vScreenSurface(scheme),
                    Material(
                      color: vScreenSurface(scheme),
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
        // The search is hidden behind the immersive view.
        if (_immersive) return;
        if (hasTitleBar) {
          _search.currentState?.open();
        } else {
          context.go(searchRoot(domain));
        }
      },
      onPane: _togglePane,
      onImmersive: _toggleImmersive,
      child: Material(
        color: scheme.surface,
        child: Stack(
          children: [
            // Behind the immersive view the shell is out of reach: no focus, no
            // screen-reader nodes (spec UI §4.4, §8).
            ExcludeFocus(
              excluding: _immersive,
              child: ExcludeSemantics(
                excluding: _immersive,
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: SafeArea(
                    child: Column(
                      children: [
                        if (hasTitleBar) _region(1, TitleBar(search: _search)),
                        Expanded(
                          child: Padding(
                            // The cards' even gutter: content · pane · edge.
                            padding: const EdgeInsetsDirectional.only(
                              end: VSpace.s8,
                            ),
                            child: Row(
                              children: [
                                Expanded(child: main),
                                _region(
                                  4,
                                  NowPlayingPane(
                                    key: _paneBox,
                                    open: _paneOpen,
                                    onToggle: _togglePane,
                                    onImmersive: _toggleImmersive,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The floating video window's layer: over the pane and the strip, under
            // the immersive view and the overlays.
            const VideoLayer(),
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
