/// The routes (go_router) and what sits above both shells: the app, its theme, what
/// plays ([NowPlayingScope]), the navigation history and the core's notices.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import 'bridge/api/app.dart' show onboarding;
import 'bridge/api/playback.dart' show notices;
import 'bridge/api/settings.dart';
import 'bridge/events.dart';
import 'design/design.dart';
import 'design/gallery.dart' show GalleryApp;
import 'domains.dart';
import 'l10n/app_localizations.dart';
import 'l10n/errors.dart';
import 'now_playing_model.dart';
import 'platform/player.dart';
import 'platform/updates.dart';
import 'screen_fab.dart';
import 'shell_desktop/desktop_shell.dart';
import 'shell_mobile/domain_rail.dart';
import 'shell_mobile/mobile_shell.dart';
import 'theme_controller.dart';

/// The branches (addendum §3): Accueil, then each destination of each domain, then the
/// global sections (Téléchargements, Sources, Réglages), which no bar or rail shows as a
/// destination. Entity pages open inside the branch they come from, prefixed by their
/// domain (`/music/explore/album/:id`, `/home/music/album/:id`, see [openItem]).
GoRouter buildRouter() {
  AppLocalizations l(BuildContext c) => AppLocalizations.of(c);
  Page<void> fade(GoRouterState s, Widget child) =>
      vFadeThroughPage(key: s.pageKey, child: child);
  Page<void> grow(GoRouterState s, Widget child) => vContainerTransformPage(
    key: s.pageKey,
    // The card or row it grows from: route + shelf + id, given by the source.
    heroTag: s.extra ?? s.uri.toString(),
    child: child,
  );
  GoRoute route(
    String path,
    Widget Function(BuildContext c, GoRouterState s) page, {
    bool container = false,
    List<RouteBase> routes = const [],
  }) => GoRoute(
    path: path,
    routes: routes,
    pageBuilder: (c, s) => (container ? grow : fade)(s, page(c, s)),
  );
  List<RouteBase> details(Iterable<String> kinds, {String prefix = ''}) => [
    for (final kind in kinds)
      route(
        '$prefix$kind/:id',
        (c, s) => PlaceholderScreen(
          title: s.pathParameters['id']!,
          icon: VIcons.album,
        ),
        container: true,
      ),
  ];
  // Placeholders until Tasks 6 and 7: each destination with its own FAB.
  void soon() {}
  StatefulShellBranch branch(List<RouteBase> routes) =>
      StatefulShellBranch(routes: routes);
  Widget destination(BuildContext c, String path) => switch (path) {
    '/music/explore' => PlaceholderScreen(
      title: l(c).navExplore,
      icon: VIcons.explore,
    ),
    '/music/library' => PlaceholderScreen(
      title: l(c).navLibrary,
      icon: VIcons.library,
      fab: VAction(l(c).fabNew, VIcons.add, soon),
      fabItems: [
        VAction(l(c).actionNewPlaylist, VIcons.playlistAdd, soon),
        VAction(l(c).actionImportLink, VIcons.addLink, soon),
      ],
    ),
    _ => PlaceholderScreen(title: path, icon: VIcons.musicNote),
  };
  List<RouteBase> under(String path) => switch (path) {
    '/music/explore' => details(kindsUnder(path)),
    '/music/library' => [
      route(
        'liked',
        (c, _) =>
            PlaceholderScreen(title: l(c).likedTracks, icon: VIcons.favorite),
        container: true,
      ),
      route(
        'downloaded',
        (c, _) => PlaceholderScreen(
          title: l(c).downloadedTracks,
          icon: VIcons.downloadDone,
        ),
        container: true,
      ),
      route(
        'top',
        (c, _) => PlaceholderScreen(title: l(c).topTracks, icon: VIcons.album),
        container: true,
      ),
      route(
        'history',
        (c, _) =>
            PlaceholderScreen(title: l(c).historyTitle, icon: VIcons.history),
        container: true,
      ),
      ...details(kindsUnder(path)),
    ],
    _ => const [],
  };
  return GoRouter(
    initialLocation: Routes.home,
    // The keyboard focus stays where the user put it (the rail, a row): a new page
    // doesn't take it, and Tab walks title bar → rail → content → pane (spec UI §4.4).
    requestFocus: false,
    redirect: _onboardingFirst,
    routes: [
      GoRoute(path: '/', redirect: (_, _) => Routes.home),
      route(
        Routes.onboarding,
        (c, _) => PlaceholderScreen(
          title: l(c).onboardingTitle,
          icon: VIcons.musicNote,
        ),
      ),
      if (kDebugMode)
        GoRoute(path: '/debug/gallery', builder: (_, _) => const GalleryApp()),
      StatefulShellRoute(
        builder: (_, _, shell) => AdaptiveShell(shell: shell),
        navigatorContainerBuilder: (_, shell, children) =>
            VFadeThroughStack(index: shell.currentIndex, children: children),
        branches: [
          branch([
            route(
              Routes.home,
              (c, _) => PlaceholderScreen(
                title: l(c).navHome,
                icon: VIcons.home,
                home: true,
                fab: VAction(l(c).fabLaunch, VIcons.play, soon),
                fabItems: [
                  VAction(l(c).launchShuffleLikes, VIcons.shuffle, soon),
                  VAction(l(c).launchRadio, VIcons.radio, soon),
                  VAction(l(c).launchResume, VIcons.history, soon),
                ],
              ),
              // Opened from Accueil, a page stays in its branch: /home/<domain>/…
              routes: [
                for (final d in domains)
                  ...details(homeKinds(d), prefix: '${d.name}/'),
              ],
            ),
          ]),
          for (final d in domains)
            for (final dest in destinationsOf(d))
              branch([
                route(
                  dest.path,
                  (c, _) => destination(c, dest.path),
                  routes: under(dest.path),
                ),
              ]),
          // The global sections: in the shells, never a destination.
          branch([
            route(
              Routes.settings,
              (c, _) => PlaceholderScreen(
                title: l(c).navSettings,
                icon: VIcons.settings,
                global: true,
              ),
              routes: [
                route(
                  'appearance',
                  (c, _) => PlaceholderScreen(
                    title: l(c).settingsAppearance,
                    icon: VIcons.palette,
                  ),
                ),
                route(
                  'diagnostics',
                  (c, _) => PlaceholderScreen(
                    title: l(c).settingsDiagnostics,
                    icon: VIcons.info,
                  ),
                ),
              ],
            ),
            route(
              Routes.sources,
              (c, _) => PlaceholderScreen(
                title: l(c).sourcesTitle,
                icon: VIcons.source,
                global: true,
                fab: VAction(l(c).actionAddSource, VIcons.add, soon),
              ),
            ),
            route(
              Routes.downloads,
              (c, _) => PlaceholderScreen(
                title: l(c).downloadsTitle,
                icon: VIcons.download,
                global: true,
              ),
            ),
          ]),
        ],
      ),
    ],
  );
}

/// Every path the app goes to by name: no other file writes a route (addendum §11.1).
abstract final class Routes {
  static const home = '/home',
      onboarding = '/onboarding',
      downloads = '/downloads',
      sources = '/sources',
      settings = '/settings';

  /// The search results, in the domain's search destination.
  static String search(Domain d, String query) =>
      Uri(path: searchRoot(d), queryParameters: {'q': query}).toString();
}

/// The global sections, in their order in ☰ and at the bottom of the desktop rail.
List<(String, VDestination)> globalSections(AppLocalizations l) => [
  (Routes.downloads, VDestination(l.downloadsTitle, VIcons.download)),
  (Routes.sources, VDestination(l.sourcesTitle, VIcons.source)),
  (Routes.settings, VDestination(l.navSettings, VIcons.settings)),
];

/// The roots of the shell's branches, in branch order: Accueil, each destination of each
/// domain, then the global sections' branch.
final List<String> shellBranchRoots = [
  home.path,
  for (final d in domains)
    for (final dest in destinationsOf(d)) dest.path,
  Routes.settings,
];

/// The branch a location belongs to (the global sections share the last one).
int branchOf(String location) {
  final path = Uri.parse(location).path;
  for (final (i, root) in shellBranchRoots.indexed) {
    if (path == root || path.startsWith('$root/')) return i;
  }
  return shellBranchRoots.length - 1;
}

/// The destinations the bar and the rail show at [location]: Accueil, then those of the
/// current domain (addendum §2.1).
List<DomainDestination> visibleDestinations(Domain d) => [
  home,
  ...destinationsOf(d),
];

/// Which of [visibleDestinations] is selected at [location]; null on a global section.
int? selectedDestination(String location, Domain d) {
  final root = shellBranchRoots[branchOf(location)];
  final i = visibleDestinations(d).indexWhere((x) => x.path == root);
  return i < 0 ? null : i;
}

/// Goes to a destination, its branch keeping its own stack.
void goDestination(StatefulNavigationShell shell, String path) {
  final i = shellBranchRoots.indexOf(path);
  shell.goBranch(i, initialLocation: i == shell.currentIndex);
}

/// The first launch goes through /onboarding until `onboarding().done`.
Future<String?> _onboardingFirst(BuildContext _, GoRouterState s) async {
  final bool done;
  try {
    done = (await onboarding()).done;
  } on Object {
    return null;
  }
  final there = s.matchedLocation == '/onboarding';
  if (!done && !there) return '/onboarding';
  if (done && there) return '/home';
  return null;
}

/// Opens an album, artist, playlist or category page inside the current branch,
/// prefixed by its domain (`/home/music/album/:id`, `/music/explore/album/:id`); from a
/// global section, in the domain's search destination. [heroTag] is the source's (route
/// + shelf + id) for the container transform. The one builder of entity paths.
void openItem(
  BuildContext context,
  String id, {
  Object? heroTag,
  Domain domain = Domain.music,
}) {
  final kind = id.split(':').first;
  final at = GoRouterState.of(context).uri.path;
  final root = shellBranchRoots[branchOf(at)];
  final String base;
  if (root == home.path) {
    base = '${home.path}/${domain.name}';
  } else if (root.startsWith('/${domain.name}/') &&
      kindsUnder(root).contains(kind)) {
    base = root;
  } else {
    base = searchRoot(domain);
  }
  context.go('$base/$kind/${Uri.encodeComponent(id)}', extra: heroTag);
}

/// A screen still to come (Tasks 6 and 7): its large app bar (☰ on a phone), Accueil's
/// domain chips, the offline chip, its design empty state (`VEmptyState`) and its FAB.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    this.fab,
    this.fabItems = const [],
    this.home = false,
    this.global = false,
  });

  final String title;
  final IconData icon;
  final VAction? fab;
  final List<VAction> fabItems;

  /// Accueil: the domain chips under its title (addendum §4).
  final bool home;

  /// A global section: on a phone, ← back to where the user was (it isn't in the bar).
  final bool global;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final back = global && MobileShell.maybeOf(context) != null;
    return ScreenFab(
      action: fab,
      items: fabItems,
      // Its own surface: a route outside the shells (onboarding) has nothing behind it.
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: CustomScrollView(
          slivers: [
            VLargeAppBar(
              title: title,
              leading: back
                  ? VIconButton(
                      icon: VIcons.arrowBack,
                      label: l.actionHistoryBack,
                      onPressed: NavHistory.of(context).back,
                    )
                  : domainMenuButton(context),
            ),
            if (home) const DomainChips(),
            const OfflineChipSliver(),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: VEmptyState(icon: icon, message: l.emptyScreen),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Accueil's filter chips under its title (Tout · Musique · Anime · Livres, addendum §4):
/// hidden while there is one domain, a choice with nothing to choose.
class DomainChips extends StatelessWidget {
  const DomainChips({super.key});

  @override
  Widget build(BuildContext context) {
    if (domains.length < 2) return const SliverToBoxAdapter();
    final l = AppLocalizations.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VSpace.s16,
          vertical: VSpace.s8,
        ),
        child: Wrap(
          spacing: VSpace.s8,
          children: [
            for (final d in domains)
              VChip(
                label: domainLabel(l, d),
                icon: domainIcon(d),
                filter: true,
                onPressed: () {},
              ),
          ],
        ),
      ),
    );
  }
}

/// The shell for the window's width class (spec UI §4.3): compact and medium → the
/// phone shell, expanded → the desktop one. Above both, what plays.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final playback = AppScope.of(context).playback;
    return ListenableBuilder(
      listenable: playback,
      builder: (context, child) => NowPlayingScope(
        trackId: playback.track?.id,
        contextId: playback.contextId,
        playing: playback.playing,
        child: child!,
      ),
      child: LayoutBuilder(
        builder: (context, box) => switch (windowClassOf(box.maxWidth)) {
          WindowClass.expanded => DesktopShell(shell: shell),
          WindowClass.medium => MobileShell(shell: shell, medium: true),
          WindowClass.compact => MobileShell(shell: shell),
        },
      ),
    );
  }
}

/// Back and forward through the locations visited (the title bar's ← →, ⌘[ ⌘]).
class NavHistory extends ChangeNotifier {
  NavHistory(this._router) {
    _router.routerDelegate.addListener(_moved);
    _restoreDomain();
  }

  static const _domainKey = 'ui.domain';

  final GoRouter _router;
  final _back = <String>[], _forward = <String>[];
  String? _at;
  bool _travelling = false;

  /// `ui.domain`: the domain of Accueil alone and of the global sections.
  Domain _stored = domains.first;

  /// The last destination visited in each domain (changing domain goes back to it).
  final _last = <Domain, String>{};

  /// Where the user is.
  String get location => _at ?? Routes.home;

  /// The current domain (addendum §3): the location's, else `ui.domain`.
  Domain get domain => domainOf(_at ?? Routes.home, stored: _stored);

  /// Where switching to [d] lands: its last destination, its first at the first visit.
  String destinationOf(Domain d) => _last[d] ?? destinationsOf(d).first.path;

  Future<void> _restoreDomain() async {
    try {
      final saved = await uiPref(key: _domainKey);
      final d = Domain.values.asNameMap()[saved];
      if (d != null && namedDomain(_at ?? '') == null) {
        _stored = d;
        notifyListeners();
      }
    } on Object {
      // No core yet (tests without one): the first domain.
    }
  }

  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;

  static NavHistory of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_HistoryScope>()!.notifier!;

  void _moved() {
    final to = _router.routerDelegate.currentConfiguration.uri.toString();
    if (to.isEmpty || to == _at) return;
    if (!_travelling && _at != null) {
      _back.add(_at!);
      _forward.clear();
    }
    _travelling = false;
    _at = to;
    // The domain follows the content: a location naming one makes it the current one,
    // remembered for Accueil, the global sections and the next launch.
    final named = namedDomain(to);
    if (named != null) {
      final root = shellBranchRoots[branchOf(to)];
      if (destinationsOf(named).any((d) => d.path == root)) _last[named] = root;
      if (named != _stored) {
        _stored = named;
        setUiPref(key: _domainKey, value: named.name).ignore();
      } else {
        // Written at each change, and once at the first visit.
        _written ??= setUiPref(key: _domainKey, value: named.name)..ignore();
      }
    }
    notifyListeners();
  }

  Future<void>? _written;

  void back() => _travel(_back, _forward);

  void forward() => _travel(_forward, _back);

  void _travel(List<String> from, List<String> to) {
    if (from.isEmpty || _at == null) return;
    to.add(_at!);
    _travelling = true;
    _router.go(from.removeLast());
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_moved);
    super.dispose();
  }
}

class _HistoryScope extends InheritedNotifier<NavHistory> {
  const _HistoryScope({required super.notifier, required super.child});
}

/// The app: [AppScope] over `MaterialApp.router`, the theme following
/// [ThemeController], one listener for the core's notices.
class VehicouleApp extends StatefulWidget {
  const VehicouleApp({
    super.key,
    required this.player,
    required this.theme,
    required this.online,
    required this.playback,
    this.splash = false,
    this.reduceMotion,
  });

  final PlayerAdapter player;
  final ThemeController theme;
  final ValueListenable<bool> online;
  final NowPlayingModel playback;

  /// The desktop splash over the first frame (spec UI §6.10).
  final bool splash;

  /// Tests: "reduce motion" without the system.
  final bool? reduceMotion;

  @override
  State<VehicouleApp> createState() => VehicouleAppState();
}

class VehicouleAppState extends State<VehicouleApp> {
  final router = buildRouter();
  late final _history = NavHistory(router);
  final _miniPlayerRect = ValueNotifier<Rect?>(null);
  late final StreamSubscription<Notice> _notices;

  @override
  void initState() {
    super.initState();
    _notices = notices().listen(_onNotice);
  }

  @override
  void dispose() {
    _notices.cancel();
    _history.dispose();
    router.dispose();
    super.dispose();
  }

  /// A context inside the root overlay (under an entry's), where snackbars go.
  BuildContext? get _overlay {
    BuildContext? found;
    void search(Element e, int depth) {
      if (found != null || depth > 6) return;
      if (Overlay.maybeOf(e, rootOverlay: true) != null) {
        found = e;
        return;
      }
      e.visitChildElements((c) => search(c, depth + 1));
    }

    router.routerDelegate.navigatorKey.currentState?.overlay?.context
        .visitChildElements((e) => search(e, 0));
    return found;
  }

  void _onNotice(Notice n) {
    final c = _overlay;
    if (c == null) return;
    final l = AppLocalizations.of(c);
    switch (n) {
      case Notice_Skipped(:final title):
        showVSnack(c, l.trackSkipped(title));
      // Task 7 replaces this with the update sheet.
      case Notice_UpdateAvailable(field0: final update):
        showVSnack(
          c,
          l.updateTitle,
          actionLabel: l.actionInstall,
          onAction: () => installUpdate(update),
        );
      case Notice_Error(field0: final e):
        showVSnack(c, errorMessage(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce =
        widget.reduceMotion ??
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    return AppScope(
      player: widget.player,
      theme: widget.theme,
      online: widget.online,
      playback: widget.playback,
      miniPlayerRect: _miniPlayerRect,
      child: _HistoryScope(
        notifier: _history,
        child: ListenableBuilder(
          listenable: widget.theme,
          builder: (context, _) => MaterialApp.router(
            routerConfig: router,
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (c) => AppLocalizations.of(c).appName,
            theme: widget.theme.light,
            darkTheme: widget.theme.dark,
            themeMode: widget.theme.mode,
            // The theme fades to a new track's colour, at once with "reduce motion".
            themeAnimationDuration: reduce
                ? Duration.zero
                : VDurations.themeFade,
            themeAnimationCurve: VCurves.standard,
            localizationsDelegates: vLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) {
              final app = Builder(
                builder: (context) => vAppBuilder(
                  context,
                  widget.splash
                      ? SplashOverlay(child: child ?? const SizedBox.shrink())
                      : child,
                ),
              );
              return widget.reduceMotion == null
                  ? app
                  : MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(disableAnimations: widget.reduceMotion),
                      child: app,
                    );
            },
          ),
        ),
      ),
    );
  }
}
