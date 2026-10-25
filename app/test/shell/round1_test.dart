// Task 5, fix round 1 (review Q1–Q3, V1–V8).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart'
    show M3ESliderThumb;
import 'package:material_ui/material_ui.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:vehicoule/bridge/catalog.dart';
import 'package:vehicoule/bridge/error.dart';
import 'package:vehicoule/bridge/events.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/features/music/now_playing/now_playing_sheet.dart';
import 'package:vehicoule/l10n/app_localizations.dart';
import 'package:vehicoule/router.dart';
import 'package:vehicoule/shell_desktop/title_bar.dart';

import 'rig.dart';

const _blue = CollectionView(
  id: 'playlist:blue',
  kind: ItemKind.playlist,
  title: 'Blue Hour',
  liked: false,
  isUserPlaylist: true,
);

bool _typing() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>() !=
    null;

bool _inside(Finder f) {
  final c = FocusManager.instance.primaryFocus?.context;
  if (c == null) return false;
  var found = false;
  final targets = f.evaluate().toSet();
  c.visitAncestorElements((e) => !(found = targets.contains(e)));
  return found;
}

void main() {
  testWidgets(
    'Q1: back over a detail page closes the player, location unchanged',
    (tester) async {
      final r = Rig();
      await r.pump(tester);
      tester
          .state<VehicouleAppState>(find.byType(VehicouleApp))
          .router
          .go('/home/music/album/${Uri.encodeComponent('album:Cheese')}');
      await settle(tester, 12);
      final at = location(tester);
      expect(at, startsWith('/home/music/album/'));
      final sheet = tester.state<NowPlayingSheetState>(
        find.byType(NowPlayingSheet),
      );
      sheet.open();
      await settle(tester, 12);
      expect(sheet.controller.size, 1);
      await tester.binding.handlePopRoute();
      await settle(tester, 12);
      expect(sheet.controller.size, 0, reason: 'the player closed first');
      expect(location(tester), at, reason: 'the page under it stayed');
      await tester.binding.handlePopRoute();
      await settle(tester, 12);
      expect(location(tester), '/home', reason: 'then pages pop');
    },
  );

  group('Q2: the window lives on in the tray (Windows, Linux)', () {
    late List<MethodCall> window, tray;
    setUp(() {
      window = [];
      tray = [];
      final m =
          TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
      m.setMockMethodCallHandler(const MethodChannel('window_manager'), (
        c,
      ) async {
        window.add(c);
        return c.method.startsWith('is') ? false : null;
      });
      m.setMockMethodCallHandler(const MethodChannel('tray_manager'), (
        c,
      ) async {
        tray.add(c);
        return null;
      });
    });
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('closing hides; the tray menu plays, shows and quits', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(WindowKeeper.usesTray, isTrue);
      var played = 0;
      final keeper = WindowKeeper(onPlayPause: () => played++);
      await keeper.startTray(lookupAppLocalizations(const Locale('fr')));
      final icon = tray.firstWhere((c) => c.method == 'setIcon');
      expect((icon.arguments as Map)['iconPath'], endsWith('tray.ico'));
      final menu = tray.firstWhere((c) => c.method == 'setContextMenu');
      final labels = [
        for (final i
            in ((menu.arguments as Map)['menu'] as Map)['items'] as List)
          (i as Map)['label'],
      ].whereType<String>().where((l) => l.isNotEmpty);
      expect(labels, ['Lecture ou pause', 'Afficher Vehicoule', 'Quitter']);

      keeper.onWindowClose();
      await pumpEventQueue();
      expect(window.map((c) => c.method), contains('hide'));
      expect(window.map((c) => c.method), isNot(contains('destroy')));

      keeper.onTrayMenuItemClick(MenuItem(key: WindowKeeper.trayPlay));
      expect(played, 1);
      keeper.onTrayMenuItemClick(MenuItem(key: WindowKeeper.trayShow));
      await pumpEventQueue();
      expect(window.map((c) => c.method), containsAll(['show', 'focus']));
      keeper.onTrayIconMouseDown();
      await pumpEventQueue();
      keeper.onTrayMenuItemClick(MenuItem(key: WindowKeeper.trayQuit));
      await pumpEventQueue();
      expect(tray.map((c) => c.method), contains('destroy'));
      expect(window.map((c) => c.method), containsAllInOrder(['destroy']));
    });

    test('Linux uses the PNG; macOS keeps the Dock', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await WindowKeeper().startTray(
        lookupAppLocalizations(const Locale('en')),
      );
      final icon = tray.firstWhere((c) => c.method == 'setIcon');
      expect((icon.arguments as Map)['iconPath'], endsWith('tray.png'));
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(WindowKeeper.usesTray, isFalse);
    });
  });

  testWidgets('Q3: behind the immersive view, no focus, no ⌘F, no semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final r = Rig();
    await r.pump(tester, size: desktop);
    await key(tester, LogicalKeyboardKey.keyF, meta: true, shift: true);
    await settle(tester, 6);
    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_inside(find.byType(TitleBar)), isFalse, reason: 'tab $i');
      expect(_inside(find.byType(VNavigationRail)), isFalse, reason: 'tab $i');
    }
    await key(tester, LogicalKeyboardKey.keyF, meta: true);
    expect(_typing(), isFalse, reason: 'the hidden search stays closed');
    expect(find.semantics.byLabel('Page précédente'), findsNothing);
    expect(find.semantics.byLabel('Accueil'), findsNothing);
    semantics.dispose();
  }, variant: mac);

  testWidgets('Q3: behind the open player, the phone shell has no semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final r = Rig();
    await r.pump(tester);
    expect(find.semantics.byLabel('Ouvrir le menu'), findsOne);
    tester.state<NowPlayingSheetState>(find.byType(NowPlayingSheet)).open();
    await settle(tester, 12);
    for (final l in ['Ouvrir le menu', 'Explorer', 'Mini-lecteur', 'Lancer']) {
      expect(find.semantics.byLabel(l), findsNothing, reason: l);
    }
    semantics.dispose();
  });

  testWidgets(
    'Accueil\'s FAB menu is « Lancer » with ▶, on a phone and in the rail',
    (tester) async {
      final r = Rig();
      await r.pump(tester);
      final fab = tester.widget<VScreenFab>(find.byType(VScreenFab));
      expect(fab.action.label, 'Lancer');
      expect(fab.action.icon, VIcons.play);
      await r.pump(tester, size: desktop);
      final rail = tester.widget<VNavigationRail>(find.byType(VNavigationRail));
      expect(rail.fab!.icon, VIcons.play);
    },
  );

  testWidgets('V2: the volume handle stays inside the component', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    await r.player.setVolume(1);
    await settle(tester);
    for (final volume in find.byType(VVolume).evaluate()) {
      final box = tester.getRect(find.byWidget(volume.widget));
      final handle = tester.getRect(
        find.descendant(
          of: find.byWidget(volume.widget),
          matching: find.byType(M3ESliderThumb),
        ),
      );
      expect(handle.right, lessThanOrEqualTo(box.right + 0.5));
      expect(handle.left, greaterThanOrEqualTo(box.left - 0.5));
    }
  }, variant: mac);

  testWidgets(
    'V3, V5: pinned covers are 32 dp, subtitled when expanded, header aligned',
    (tester) async {
      final r = Rig();
      r.api.playlistRows = const [_blue];
      r.api.prefs['ui.pinned.music'] = '["liked","downloaded","playlist:blue"]';
      await r.pump(tester, size: desktop);
      Finder cover(String id) => find.descendant(
        of: find.byType(VNavigationRail),
        matching: find.byWidgetPredicate(
          (w) => w is VArtwork && w.itemId == id,
        ),
      );
      expect(tester.getSize(cover('playlist:blue')), const Size(32, 32));
      expect(find.text('Playlist'), findsNothing, reason: 'collapsed: covers');
      await tester.tap(label('Déplier le menu'));
      await settle(tester, 12);
      expect(tester.getSize(cover('playlist:blue')), const Size(32, 32));
      expect(find.text('Blue Hour'), findsOneWidget);
      expect(find.text('Playlist'), findsOneWidget);
      expect(find.text('Titres'), findsNWidgets(2));
      expect(
        tester.getRect(find.text('Épinglés')).left,
        moreOrLessEquals(tester.getRect(cover('liked')).left, epsilon: 1),
      );
      await settle(tester, 10);
    },
    variant: mac,
  );

  testWidgets(
    'V4: the pane, the strip and the content are cards, evenly apart',
    (tester) async {
      final r = Rig();
      await r.pump(tester, size: desktop);
      final cards = tester
          .widgetList<ClipRRect>(find.byType(ClipRRect))
          .where((c) => c.borderRadius == BorderRadius.circular(VRadius.large));
      expect(cards.length, greaterThanOrEqualTo(2));
      Rect rect(Finder f) => tester.getRect(
        find.ancestor(of: f, matching: find.byType(ClipRRect)).first,
      );
      final pane = rect(find.byKey(VNowPlaying.headerKey));
      final content = rect(find.text('Accueil').last);
      expect(pane.left - content.right, VSpace.s8);
      expect(desktop.width - pane.right, VSpace.s8);
      await tester.tap(label('Réduire'));
      await settle(tester, 12);
      final strip = rect(find.byKey(VNowPlaying.compactKey));
      final content2 = rect(find.text('Accueil').last);
      expect(strip.left - content2.right, VSpace.s8);
      expect(desktop.width - strip.right, VSpace.s8);
    },
    variant: mac,
  );

  testWidgets('V6: the title bar search is wide, with its ⌘F hint', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    final bar = tester.getRect(find.byType(VSearchBar));
    expect(bar.width, greaterThanOrEqualTo(560));
    expect(find.text('⌘F'), findsOneWidget);
  }, variant: mac);

  testWidgets(
    'V7: dragging a track row over a pinned row outlines it, then drops',
    (tester) async {
      final r = Rig();
      r.api.prefs['ui.rail_expanded'] = 'true';
      await r.pump(tester, size: desktop);
      await tester.tap(
        find.descendant(
          of: find.byType(VSideSheet),
          matching: find.bySemanticsLabel('File'),
        ),
      );
      await settle(tester, 10);
      final row = find.descendant(
        of: find.byType(VSideSheet),
        matching: find.byType(VTrackRow),
      );
      final target = tester.getCenter(find.text('Titres likés'));
      final g = await tester.startGesture(tester.getCenter(row.first));
      await g.moveBy(const Offset(-40, 0));
      await tester.pump();
      await g.moveTo(target);
      await settle(tester, 3);
      expect(find.textContaining('déposer ici'), findsOneWidget);
      await g.up();
      await settle(tester, 3);
      final like = r.last(#crateApiLibrarySetLiked)!;
      expect(like.namedArguments[#id], 'track:2');
      expect(like.namedArguments[#liked], isTrue);
      expect(find.textContaining('déposer ici'), findsNothing);
    },
    variant: mac,
  );

  testWidgets('V8: a message sits above the bar, the mini player and the FAB', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester);
    r.api.noticeEvents.add(const Notice.error(CoreError.network()));
    await settle(tester, 6);
    final snack = tester.getRect(
      find
          .ancestor(
            of: find.text(
              'La connexion ne répond pas. Réessaie dans un moment.',
            ),
            matching: find.byType(Padding),
          )
          .first,
    );
    for (final f in [
      find.byType(VScreenFab),
      miniPlayer,
      find.byType(VNavigationBar),
    ]) {
      expect(
        snack.bottom,
        lessThanOrEqualTo(tester.getRect(f).top),
        reason: '$f',
      );
    }
    await tester.pump(VDurations.snack);
    await settle(tester, 10);
  });
}
