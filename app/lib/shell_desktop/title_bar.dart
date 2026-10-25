// The desktop's own title bar (spec UI §4.2) and the window it belongs to: ← → through
// the history, the search in the middle, downloads and Sources at the right; room for
// the macOS window buttons at the left. The window keeps its size and place, and
// closing it keeps the music (the app stays in the Dock).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../bridge/api/settings.dart';
import '../design/design.dart';
import '../l10n/app_localizations.dart';
import '../router.dart';

/// The desktop platforms, where the app draws its own title bar.
bool get hasTitleBar => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

class TitleBar extends StatelessWidget {
  const TitleBar({super.key, required this.search});

  /// ⌘F opens it.
  final GlobalKey<VSearchBarState> search;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final history = NavHistory.of(context);
    return SizedBox(
      height: VSize.titleBar,
      child: DragToMoveArea(
        child: Row(
          children: [
            SizedBox(
              width: defaultTargetPlatform == TargetPlatform.macOS
                  ? VSize.windowButtons
                  : VSpace.s8,
            ),
            VIconButton(
              icon: VIcons.arrowBack,
              label: l.actionHistoryBack,
              onPressed: history.canGoBack ? history.back : null,
            ),
            VIconButton(
              icon: VIcons.arrowForward,
              label: l.actionHistoryForward,
              onPressed: history.canGoForward ? history.forward : null,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: VSize.titleSearch,
                  ),
                  child: VSearchBar(
                    key: search,
                    shortcut: defaultTargetPlatform == TargetPlatform.macOS
                        ? l.shortcutSearchApple
                        : l.shortcutSearchOther,
                    // Task 6: suggestions_view.dart.
                    suggestions: (_, _) => const [],
                    onSubmitted: (q) => context.go(
                      Uri(
                        path: '/explore',
                        queryParameters: {'q': q},
                      ).toString(),
                    ),
                  ),
                ),
              ),
            ),
            VIconButton(
              icon: VIcons.download,
              label: l.downloadsTitle,
              onPressed: () => context.go('/downloads'),
            ),
            VIconButton(
              icon: VIcons.source,
              label: l.sourcesTitle,
              onPressed: () => context.go('/settings/sources'),
            ),
            const SizedBox(width: VSpace.s8),
          ],
        ),
      ),
    );
  }
}

/// The window: its smallest size, its saved bounds (`ui.window_bounds`), and a close
/// that only hides it, the music going on. macOS brings it back from the Dock; Windows
/// and Linux have no Dock, so a tray icon does (Lecture ou pause, Afficher, Quitter).
class WindowKeeper with WindowListener, TrayListener {
  WindowKeeper({this.onPlayPause});

  static const _key = 'ui.window_bounds';
  static const trayPlay = 'play', trayShow = 'show', trayQuit = 'quit';

  /// The tray's « Lecture ou pause ».
  final VoidCallback? onPlayPause;
  Timer? _save;

  /// Where a closed window lives on: the tray (Windows, Linux) or the Dock (macOS).
  static bool get usesTray => switch (defaultTargetPlatform) {
    TargetPlatform.windows || TargetPlatform.linux => true,
    _ => false,
  };

  /// Before the first frame shows: the title bar is ours, the bounds the last ones.
  static Future<void> setUp({VoidCallback? onPlayPause}) async {
    await windowManager.ensureInitialized();
    final saved = await uiPref(key: _key);
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        minimumSize: const Size(
          VBreakpoints.expanded,
          VBreakpoints.windowMinHeight,
        ),
        // The first launch: the reference size, centred.
        size: saved == null
            ? const Size(VBreakpoints.windowWidth, VBreakpoints.windowHeight)
            : null,
        center: saved == null,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await restore();
        await windowManager.show();
      },
    );
    await windowManager.setPreventClose(true);
    final keeper = WindowKeeper(onPlayPause: onPlayPause);
    windowManager.addListener(keeper);
    if (usesTray) {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      await keeper.startTray(
        lookupAppLocalizations(
          basicLocaleListResolution(
            dispatcher.locales,
            AppLocalizations.supportedLocales,
          ),
        ),
      );
    }
  }

  /// The tray icon and its menu.
  Future<void> startTray(AppLocalizations l) async {
    await trayManager.setIcon(
      defaultTargetPlatform == TargetPlatform.windows
          ? 'assets/brand/tray.ico'
          : 'assets/brand/tray.png',
    );
    await trayManager.setToolTip(l.appName);
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: trayPlay, label: l.actionPlayPause),
          MenuItem(key: trayShow, label: l.trayShow),
          MenuItem.separator(),
          MenuItem(key: trayQuit, label: l.trayQuit),
        ],
      ),
    );
    trayManager.addListener(this);
  }

  static Future<void> restore() async {
    final saved = await uiPref(key: _key);
    if (saved == null) return;
    try {
      final b = (jsonDecode(saved) as Map).cast<String, num>();
      await windowManager.setBounds(
        Rect.fromLTWH(
          b['x']!.toDouble(),
          b['y']!.toDouble(),
          b['width']!.toDouble(),
          b['height']!.toDouble(),
        ),
      );
    } on Object {
      // A malformed value: the system's default place.
    }
  }

  @override
  void onWindowResized() => _later();

  @override
  void onWindowMoved() => _later();

  /// The music goes on; ⌘Q, the Dock's or the tray's « Quitter » quits.
  @override
  void onWindowClose() => windowManager.hide();

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case trayPlay:
        onPlayPause?.call();
      case trayShow:
        _show();
      case trayQuit:
        _quit();
    }
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  void _later() {
    _save?.cancel();
    _save = Timer(VDurations.debounce, () async {
      final b = await windowManager.getBounds();
      await setUiPref(
        key: _key,
        value: jsonEncode({
          'x': b.left,
          'y': b.top,
          'width': b.width,
          'height': b.height,
        }),
      );
    });
  }
}
