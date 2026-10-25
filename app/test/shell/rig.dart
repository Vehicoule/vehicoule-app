import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/debug/fake_api.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/now_playing_model.dart';
import 'package:vehicoule/platform/player.dart';
import 'package:vehicoule/router.dart';
import 'package:vehicoule/theme_controller.dart';

import '../platform/player_test.dart' show FakeBackend;

const phone = Size(412, 892), desktop = Size(1280, 800);

/// macOS: the custom title bar, the menu bar and ⌘ shortcuts.
final mac = TargetPlatformVariant.only(TargetPlatform.macOS);

/// The app on the fake core, its player on a fake backend.
class Rig {
  Rig({FakeApi? api}) : api = api ?? FakeApi() {
    RustLib.initMock(api: this.api);
    addTearDown(RustLib.dispose);
    player = PlayerAdapter(
      backend,
      commands: const Stream.empty(),
      report: (_) {},
    )..start();
    playback = NowPlayingModel(player)..start();
  }

  final FakeApi api;
  final backend = FakeBackend();
  final online = ValueNotifier(true);
  late final PlayerAdapter player;
  late final NowPlayingModel playback;
  late ThemeController theme;

  /// The core calls, artwork lookups aside (every cover on screen makes one).
  Iterable<Symbol> get names => api.calls
      .map((c) => c.memberName)
      .where((n) => n != #crateApiCatalogArtworkFile);

  Invocation? last(Symbol name) =>
      api.calls.where((c) => c.memberName == name).lastOrNull;

  /// Pumps the whole app at [size]; again with the same rig, it is a relaunch.
  Future<void> pump(
    WidgetTester tester, {
    Size size = phone,
    ThemeController? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The app follows the system's language: French here.
    tester.platformDispatcher.localesTestValue = const [Locale('fr')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    // The macOS menu bar and the window: no platform behind them in tests.
    for (final c in [
      SystemChannels.menu,
      const MethodChannel('window_manager'),
    ]) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        c,
        (_) async => null,
      );
    }
    // No system colour in tests: its plugin never answers here.
    this.theme = theme ?? ThemeController(systemSeedFor: () async => null);
    await this.theme.load();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      VehicouleApp(
        player: player,
        theme: this.theme,
        online: online,
        playback: playback,
        reduceMotion: true,
      ),
    );
    await settle(tester);
  }
}

/// Lets the fake core answer and the routes settle (artwork turns forever: no
/// pumpAndSettle).
Future<void> settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder get miniPlayer => find.byKey(VNowPlaying.compactKey);

Finder strip() =>
    find.byWidgetPredicate((w) => w is VNowPlaying && w.axis == Axis.vertical);

Finder label(String l) => find.bySemanticsLabel(l);

/// The current location of the app's router.
String location(WidgetTester tester) => tester
    .state<VehicouleAppState>(find.byType(VehicouleApp))
    .router
    .routerDelegate
    .currentConfiguration
    .uri
    .toString();

Future<void> key(
  WidgetTester tester,
  LogicalKeyboardKey k, {
  bool meta = false,
  bool shift = false,
  bool alt = false,
}) async {
  final mods = [
    if (meta) LogicalKeyboardKey.metaLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (alt) LogicalKeyboardKey.altLeft,
  ];
  for (final m in mods) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(k);
  for (final m in mods.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await settle(tester, 3);
}

/// A track row's own focus node.
FocusNode rowFocus(WidgetTester tester, Finder row) => tester
    .widget<Focus>(
      find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (w) => w is Focus && w.focusNode?.debugLabel == 'track row',
        ),
      ),
    )
    .focusNode!;
