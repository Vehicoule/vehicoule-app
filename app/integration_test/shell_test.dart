// The desktop shell in the real macOS app (Task 5 review Q4, Q5), on the fake core:
// `cd app && flutter test integration_test/shell_test.dart -d macos`.
//
// What a test harness can't drive is said where it stops: the keys come as Flutter key
// events (not AppKit's), and the Dock can't be clicked.
import 'dart:convert';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/debug/fake_api.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/now_playing_model.dart';
import 'package:vehicoule/platform/player.dart';
import 'package:vehicoule/router.dart';
import 'package:vehicoule/shell_desktop/title_bar.dart';
import 'package:vehicoule/theme_controller.dart';
import 'package:window_manager/window_manager.dart';

import '../test/platform/player_test.dart' show FakeBackend;

final api = FakeApi();
final backend = FakeBackend();
late PlayerAdapter player;
late NowPlayingModel playback;

/// Real time passes (window events, debounce), frames go on.
Future<void> wait(WidgetTester tester, [int ms = 600]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

Future<void> app(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = const [Locale('fr')];
  final theme = ThemeController(systemSeedFor: () async => null);
  await theme.load();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    VehicouleApp(
      player: player,
      theme: theme,
      online: ValueNotifier(true),
      playback: playback,
    ),
  );
  await wait(tester);
}

Future<void> meta(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(k);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await wait(tester, 300);
}

bool typing() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>() !=
    null;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    RustLib.initMock(api: api);
    player = PlayerAdapter(
      backend,
      commands: const Stream.empty(),
      report: (_) {},
    )..start();
    playback = NowPlayingModel(player)..start();
    await WindowKeeper.setUp(onPlayPause: playback.playPause);
    await windowManager.setSize(const Size(1280, 800));
    // Frames come only once the window is on screen and key.
    await windowManager.show();
    await windowManager.focus();
  });

  testWidgets(
    'typing in the title-bar search plays, pauses and seeks nothing',
    (tester) async {
      await app(tester);
      // The first test runs as the window comes up: let it settle.
      await wait(tester, 1500);
      await meta(tester, LogicalKeyboardKey.keyF);
      await wait(tester, 500);
      expect(typing(), isTrue, reason: '⌘F focused the search field');
      final before = [...backend.calls];
      for (final k in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
      ]) {
        await tester.sendKeyEvent(k);
        await wait(tester, 200);
      }
      expect(backend.calls, before, reason: 'no play, pause or seek');
      expect(typing(), isTrue, reason: 'the field kept the keys and the focus');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await wait(tester, 300);
    },
  );

  testWidgets('a live resize across 1000 px folds the pane into the strip', (
    tester,
  ) async {
    api.prefs.remove('ui.now_playing_open');
    await app(tester);
    Future<bool> open() async {
      await wait(tester, 800);
      return tester.widget<VSideSheet>(find.byType(VSideSheet)).open;
    }

    await windowManager.setSize(const Size(1100, 800));
    expect(await open(), isTrue);
    await windowManager.setSize(const Size(900, 760));
    expect(await open(), isFalse);
    expect(
      find.byWidgetPredicate(
        (w) => w is VNowPlaying && w.axis == Axis.vertical,
      ),
      findsOneWidget,
    );
    await windowManager.setSize(const Size(1280, 800));
    expect(await open(), isTrue);
  });

  testWidgets('a window move is remembered', (tester) async {
    await app(tester);
    await windowManager.setPosition(const Offset(120, 140));
    await wait(tester, 800);
    final saved = jsonDecode(api.prefs['ui.window_bounds']!) as Map;
    expect((saved['x'] as num).round(), 120);
    expect((saved['y'] as num).round(), 140);
    expect((saved['width'] as num).round(), 1280);
  });

  testWidgets('closing the window keeps the music; showing it again', (
    tester,
  ) async {
    await app(tester);
    backend.playings.add(true);
    await wait(tester, 300);
    final calls = backend.calls.length;
    expect(await windowManager.isPreventClose(), isTrue);
    await windowManager.close();
    // No frames while the window is hidden: wait without pumping.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(
      await windowManager.isVisible(),
      isFalse,
      reason: 'hidden, not quit',
    );
    expect(backend.calls.skip(calls), isNot(contains('pause')));
    expect(playback.playing, isTrue);
    // The Dock click itself (AppDelegate.applicationShouldHandleReopen) can't be
    // driven from here: show() is what it ends in.
    await windowManager.show();
    await wait(tester, 800);
    expect(await windowManager.isVisible(), isTrue);
    expect(playback.playing, isTrue);
  });

  testWidgets('dragging a queue row onto a pinned item likes the track', (
    tester,
  ) async {
    api.prefs['ui.rail_expanded'] = 'true';
    api.prefs['ui.now_playing_open'] = 'true';
    await app(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(VSideSheet),
        matching: find.bySemanticsLabel('File'),
      ),
    );
    await wait(tester);
    final row = find.descendant(
      of: find.byType(VSideSheet),
      matching: find.byType(VTrackRow),
    );
    final g = await tester.startGesture(
      tester.getCenter(row.first),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(-40, 0));
    await wait(tester, 100);
    await g.moveTo(tester.getCenter(find.text('Titres likés')));
    await wait(tester, 300);
    expect(find.textContaining('déposer ici'), findsOneWidget);
    await g.up();
    await wait(tester, 300);
    final like = api.calls.lastWhere(
      (c) => c.memberName == #crateApiLibrarySetLiked,
    );
    expect(like.namedArguments[#liked], isTrue);
  });
}
