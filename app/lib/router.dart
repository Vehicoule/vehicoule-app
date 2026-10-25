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
import 'bridge/events.dart';
import 'design/design.dart';
import 'design/gallery.dart' show GalleryApp;
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

/// Destinations: /home, /explore, /library, /settings, each a branch that keeps its own
/// stack. Album, artist, playlist and category pages open inside the branch they come
/// from (`/<branch>/album/:id`, see [openItem]), so the rail keeps its selection and ←
/// goes back where the user was.
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
  List<RouteBase> details() => [
    for (final kind in ['album', 'artist', 'playlist', 'category'])
      route(
        '$kind/:id',
        (c, s) => PlaceholderScreen(title: s.pathParameters['id']!),
        container: true,
      ),
  ];
  // Placeholders until Tasks 6 and 7: each destination with its own FAB.
  void soon() {}
  return GoRouter(
    initialLocation: '/home',
    // The keyboard focus stays where the user put it (the rail, a row): a new page
    // doesn't take it, and Tab walks title bar → rail → content → pane (spec UI §4.4).
    requestFocus: false,
    redirect: _onboardingFirst,
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      route(
        '/onboarding',
        (c, _) => PlaceholderScreen(title: l(c).onboardingTitle),
      ),
      if (kDebugMode)
        GoRoute(path: '/debug/gallery', builder: (_, _) => const GalleryApp()),
      StatefulShellRoute(
        builder: (_, _, shell) => AdaptiveShell(shell: shell),
        navigatorContainerBuilder: (_, shell, children) =>
            VFadeThroughStack(index: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(
            routes: [
              route(
                '/home',
                (c, _) => PlaceholderScreen(
                  title: l(c).navHome,
                  fab: VAction(l(c).fabLaunch, VIcons.play, soon),
                  fabItems: [
                    VAction(l(c).launchShuffleLikes, VIcons.shuffle, soon),
                    VAction(l(c).launchRadio, VIcons.radio, soon),
                    VAction(l(c).launchResume, VIcons.history, soon),
                  ],
                ),
                routes: details(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              route(
                '/explore',
                (c, _) => PlaceholderScreen(title: l(c).navExplore),
                routes: details(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              route(
                '/library',
                (c, _) => PlaceholderScreen(
                  title: l(c).navLibrary,
                  fab: VAction(l(c).fabNew, VIcons.add, soon),
                  fabItems: [
                    VAction(l(c).actionNewPlaylist, VIcons.playlistAdd, soon),
                    VAction(l(c).actionImportLink, VIcons.addLink, soon),
                  ],
                ),
                routes: [
                  route(
                    'liked',
                    (c, _) => PlaceholderScreen(title: l(c).likedTracks),
                    container: true,
                  ),
                  route(
                    'downloaded',
                    (c, _) => PlaceholderScreen(title: l(c).downloadedTracks),
                    container: true,
                  ),
                  route(
                    'top',
                    (c, _) => PlaceholderScreen(title: l(c).topTracks),
                    container: true,
                  ),
                  route(
                    'history',
                    (c, _) => PlaceholderScreen(title: l(c).historyTitle),
                    container: true,
                  ),
                  ...details(),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              route(
                '/settings',
                (c, _) => PlaceholderScreen(title: l(c).navSettings),
                routes: [
                  route(
                    'sources',
                    (c, _) => PlaceholderScreen(
                      title: l(c).sourcesTitle,
                      fab: VAction(l(c).actionAddSource, VIcons.add, soon),
                    ),
                  ),
                  route(
                    'appearance',
                    (c, _) => PlaceholderScreen(title: l(c).settingsAppearance),
                  ),
                  route(
                    'diagnostics',
                    (c, _) =>
                        PlaceholderScreen(title: l(c).settingsDiagnostics),
                  ),
                ],
              ),
              route(
                '/downloads',
                (c, _) => PlaceholderScreen(title: l(c).downloadsTitle),
              ),
            ],
          ),
        ],
      ),
    ],
  );
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

/// Opens an album, artist, playlist or category page inside the current destination;
/// [heroTag] is the source's (route + shelf + id) for the container transform.
void openItem(BuildContext context, String id, {Object? heroTag}) {
  final kind = id.split(':').first;
  final at = GoRouterState.of(context).uri.pathSegments.firstOrNull;
  final branch = const {'home', 'library'}.contains(at) ? at : 'explore';
  context.go('/$branch/$kind/${Uri.encodeComponent(id)}', extra: heroTag);
}

/// The destinations of the bar and the rail, in branch order.
List<VDestination> shellDestinations(AppLocalizations l) => [
  VDestination(l.navHome, VIcons.home),
  VDestination(l.navExplore, VIcons.explore),
  VDestination(l.navLibrary, VIcons.library),
  VDestination(l.navSettings, VIcons.settings),
];

/// A screen still to come (Tasks 6 and 7): its large app bar (☰ on a phone), the offline
/// chip, and its FAB.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    this.fab,
    this.fabItems = const [],
  });

  final String title;
  final VAction? fab;
  final List<VAction> fabItems;

  @override
  Widget build(BuildContext context) => ScreenFab(
    action: fab,
    items: fabItems,
    child: CustomScrollView(
      slivers: [
        VLargeAppBar(title: title, leading: domainMenuButton(context)),
        const OfflineChipSliver(),
        const SliverFillRemaining(hasScrollBody: false),
      ],
    ),
  );
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
  }

  final GoRouter _router;
  final _back = <String>[], _forward = <String>[];
  String? _at;
  bool _travelling = false;

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
    notifyListeners();
  }

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

  /// A context under the root overlay, where snackbars go.
  BuildContext? get _overlay {
    BuildContext? inside;
    router.routerDelegate.navigatorKey.currentState?.overlay?.context
        .visitChildElements((e) => inside = e);
    return inside;
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
