// The shells' animations, timed in a profile build on the fake core (spec UI §8; the
// target is 120 fps, p99 ≤ 8.3 ms):
//
//   cd app && flutter drive --profile -d macos \
//     --driver test_driver/perf_driver.dart --target integration_test/perf_test.dart
//
// Each animation runs a few times inside `watchPerformance`; the build and raster
// times (average, p90, p99, worst) land in build/perf_timings.json.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/debug/fake_api.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/features/music/now_playing/now_playing_sheet.dart';
import 'package:vehicoule/now_playing_model.dart';
import 'package:vehicoule/platform/player.dart';
import 'package:vehicoule/router.dart';
import 'package:vehicoule/theme_controller.dart';
import 'package:window_manager/window_manager.dart';

import '../test/platform/player_test.dart' show FakeBackend;

final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
late PlayerAdapter player;
late NowPlayingModel playback;

/// Real time passes, the frames come from the engine.
Future<void> idle([int ms = 700]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// The physical keys, given: a profile build has no key maps to look them up in.
final _physical = {
  LogicalKeyboardKey.metaLeft: PhysicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.shiftLeft: PhysicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.altLeft: PhysicalKeyboardKey.altLeft,
  LogicalKeyboardKey.keyB: PhysicalKeyboardKey.keyB,
  LogicalKeyboardKey.keyF: PhysicalKeyboardKey.keyF,
  LogicalKeyboardKey.escape: PhysicalKeyboardKey.escape,
};

Future<void> down(WidgetTester t, LogicalKeyboardKey k) =>
    t.sendKeyDownEvent(k, physicalKey: _physical[k]);

Future<void> up(WidgetTester t, LogicalKeyboardKey k) =>
    t.sendKeyUpEvent(k, physicalKey: _physical[k]);

Future<void> press(WidgetTester t, LogicalKeyboardKey k) async {
  await down(t, k);
  await up(t, k);
}

Future<void> keys(
  WidgetTester tester,
  LogicalKeyboardKey k, {
  bool shift = false,
  bool alt = false,
}) async {
  await down(tester, LogicalKeyboardKey.metaLeft);
  if (shift) await down(tester, LogicalKeyboardKey.shiftLeft);
  if (alt) await down(tester, LogicalKeyboardKey.altLeft);
  await press(tester, k);
  if (alt) await up(tester, LogicalKeyboardKey.altLeft);
  if (shift) await up(tester, LogicalKeyboardKey.shiftLeft);
  await up(tester, LogicalKeyboardKey.metaLeft);
}

Future<void> app(WidgetTester tester, Size size) async {
  await windowManager.setMinimumSize(const Size(320, 480));
  await windowManager.setSize(size);
  await idle(800);
  tester.platformDispatcher.localesTestValue = const [Locale('fr')];
  final theme = ThemeController(systemSeedFor: () async => null);
  await theme.load();
  await tester.pumpWidget(
    VehicouleApp(
      player: player,
      theme: theme,
      online: ValueNotifier(true),
      playback: playback,
    ),
  );
  await idle(1500);
}

Future<void> timed(String key, Future<void> Function() run) =>
    binding.watchPerformance(run, reportKey: key);

void main() {
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    RustLib.initMock(api: FakeApi());
    player = PlayerAdapter(
      FakeBackend(),
      commands: const Stream.empty(),
      report: (_) {},
    )..start();
    playback = NowPlayingModel(player)..start();
    await windowManager.ensureInitialized();
    await windowManager.show();
    await windowManager.focus();
  });

  testWidgets('phone: the player sheet and the artwork flight', (tester) async {
    await app(tester, const Size(412, 860));
    final sheet = tester.state<NowPlayingSheetState>(
      find.byType(NowPlayingSheet),
    );
    await timed('sheet_open_close', () async {
      for (var i = 0; i < 4; i++) {
        sheet.open();
        await idle();
        sheet.close();
        await idle();
      }
    });
    await timed('mini_player_swipes', () async {
      final bar = find.byKey(VNowPlaying.compactKey);
      for (var i = 0; i < 3; i++) {
        await tester.timedDrag(
          bar,
          const Offset(-160, 0),
          const Duration(milliseconds: 250),
        );
        await idle();
        await tester.timedDrag(
          bar,
          const Offset(160, 0),
          const Duration(milliseconds: 250),
        );
        await idle();
      }
    });
    await timed('phone_fab_menu', () async {
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Lancer'));
        await idle();
        await tester.tapAt(const Offset(40, 300));
        await idle();
      }
    });
  });

  testWidgets('desktop: pane, strip, immersive, views, search', (
    tester,
  ) async {
    await app(tester, const Size(1280, 800));
    await timed('pane_strip', () async {
      for (var i = 0; i < 4; i++) {
        await keys(tester, LogicalKeyboardKey.keyB, alt: true);
        await idle();
      }
    });
    await timed('immersive', () async {
      for (var i = 0; i < 3; i++) {
        await keys(tester, LogicalKeyboardKey.keyF, shift: true);
        await idle();
        await press(tester, LogicalKeyboardKey.escape);
        await idle();
      }
    });
    await timed('view_change', () async {
      for (final v in [
        PlayerView.lyrics,
        PlayerView.player,
        PlayerView.queue,
        PlayerView.player,
      ]) {
        playback.view = v;
        await idle();
      }
    });
    await timed('view_menu', () async {
      final menu = find.descendant(
        of: find.byKey(VNowPlaying.selectorKey),
        matching: find.byType(VSymbol),
      );
      for (var i = 0; i < 3; i++) {
        await tester.tap(menu.first);
        await idle();
        await press(tester, LogicalKeyboardKey.escape);
        await idle();
      }
    });
    await timed('search_open_close', () async {
      for (var i = 0; i < 3; i++) {
        await keys(tester, LogicalKeyboardKey.keyF);
        await idle();
        await press(tester, LogicalKeyboardKey.escape);
        await idle();
      }
    });
    await timed('rail_fab_menu', () async {
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byType(VScreenFab));
        await idle();
        await press(tester, LogicalKeyboardKey.escape);
        await idle();
      }
    });
  });
}
