// The two shells (spec UI §4): which one at which width, the bars, the rail, the pane,
// the immersive view, what plays and the offline chip.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/catalog.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/shell_desktop/title_bar.dart';

import 'rig.dart';

void main() {
  testWidgets('narrow width uses the navigation bar and mini player', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester, size: const Size(400, 860));
    expect(find.byType(VNavigationBar), findsOneWidget);
    for (final d in ['Accueil', 'Explorer', 'Bibliothèque', 'Réglages']) {
      expect(
        find.descendant(
          of: find.byType(VNavigationBar),
          matching: find.text(d),
        ),
        findsOneWidget,
        reason: d,
      );
    }
    expect(miniPlayer, findsOneWidget);
    expect(find.byType(VNavigationRail), findsNothing);
    expect(find.byType(TitleBar), findsNothing);
  });

  testWidgets(
    'menu button opens the modal rail with domains and global sections',
    (tester) async {
      final r = Rig();
      await r.pump(tester);
      await tester.tap(label('Ouvrir le menu').first);
      await settle(tester);
      for (final t in ['Musique', 'Sources', 'Téléchargements']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.text('Sources'));
      await settle(tester, 12);
      expect(location(tester), '/settings/sources');
      expect(
        find.text('Musique'),
        findsNothing,
        reason: 'the modal rail closed',
      );
    },
  );

  testWidgets(
    'medium width uses the collapsed rail instead of the bottom bar',
    (tester) async {
      final r = Rig();
      await r.pump(tester, size: const Size(700, 900));
      final rail = tester.widget<VNavigationRail>(find.byType(VNavigationRail));
      expect(rail.expanded, isFalse);
      expect(find.byType(VNavigationBar), findsNothing);
      expect(miniPlayer, findsOneWidget, reason: 'the phone mini player stays');
    },
  );

  testWidgets('900 dp starts with the collapsed strip, no bottom bar', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester, size: const Size(900, 700));
    expect(find.byType(TitleBar), findsOneWidget);
    expect(strip(), findsOneWidget);
    expect(tester.widget<VSideSheet>(find.byType(VSideSheet)).open, isFalse);
    expect(find.byType(VNavigationBar), findsNothing);
    expect(
      miniPlayer,
      findsOneWidget,
      reason: 'the strip is the compact player',
    );
  }, variant: mac);

  testWidgets('android tablet at 900 dp has no title bar', (tester) async {
    final r = Rig();
    await r.pump(tester, size: const Size(900, 700));
    expect(find.byType(VNavigationRail), findsOneWidget);
    expect(find.byType(TitleBar), findsNothing);
    expect(find.byType(VNavigationBar), findsNothing);
  });

  testWidgets('the playing album is a cookie in lists, shortcuts and pinned', (
    tester,
  ) async {
    final r = Rig();
    r.api.prefs['ui.pinned'] = '["liked","downloaded","album:Cheese"]';
    await r.pump(tester, size: desktop);
    r.backend.playings.add(true);
    await settle(tester);
    // The fake queue plays from the album Cheese.
    final pinned = find.descendant(
      of: find.byType(VNavigationRail),
      matching: find.byWidgetPredicate(
        (w) => w is VArtwork && w.itemId == 'album:Cheese',
      ),
    );
    expect(pinned, findsOneWidget);
    expect(
      find.descendant(
        of: pinned,
        matching: find.byKey(VArtwork.shapeKey(ArtShape.cookie)),
      ),
      findsOneWidget,
    );
    // Every screen reads the same scope: what plays is computed once, by the shell.
    final page = tester.element(find.text('Accueil').last);
    expect(NowPlayingScope.isPlaying(page, 'album:Cheese'), isTrue);
    expect(NowPlayingScope.isPlaying(page, 'track:1'), isTrue);
    expect(NowPlayingScope.isPlaying(page, 'album:DAMN.'), isFalse);
  }, variant: mac);

  testWidgets('offline shows the chip under the app bar', (tester) async {
    final r = Rig();
    await r.pump(tester);
    expect(find.byType(VOfflineChip), findsNothing);
    r.online.value = false;
    await settle(tester);
    expect(find.byType(VOfflineChip), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(VNavigationBar),
        matching: find.text('Explorer'),
      ),
    );
    await settle(tester);
    expect(find.byType(VOfflineChip), findsOneWidget);
    r.online.value = true;
    await settle(tester);
    expect(find.byType(VOfflineChip), findsNothing);
  });

  testWidgets('1280 dp starts with the side sheet; collapsing is remembered', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    expect(tester.widget<VSideSheet>(find.byType(VSideSheet)).open, isTrue);
    expect(strip(), findsNothing);
    await tester.tap(label('Réduire'));
    await settle(tester, 12);
    expect(r.api.prefs['ui.now_playing_open'], 'false');
    expect(strip(), findsOneWidget);
    // A relaunch keeps the strip.
    await r.pump(tester, size: desktop);
    expect(tester.widget<VSideSheet>(find.byType(VSideSheet)).open, isFalse);
    expect(strip(), findsOneWidget);
  }, variant: mac);

  testWidgets('immersive opens from the pane icon and closes with Escape', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    Finder immersive() =>
        find.byWidgetPredicate((w) => w is VNowPlaying && w.immersive);
    expect(immersive(), findsNothing);
    await tester.tap(label('Plein écran'));
    await settle(tester);
    expect(immersive(), findsOneWidget);
    expect(tester.widget<VNowPlaying>(immersive()).wide, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(immersive(), findsNothing);
  }, variant: mac);

  testWidgets('dropping tracks on a pinned playlist adds them', (tester) async {
    final r = Rig();
    r.api.playlistRows = const [
      CollectionView(
        id: 'playlist:blue',
        kind: ItemKind.playlist,
        title: 'Blue Hour',
        liked: false,
        isUserPlaylist: true,
      ),
    ];
    r.api.prefs['ui.pinned'] = '["liked","downloaded","playlist:blue"]';
    await r.pump(tester, size: desktop);
    final targets = tester
        .widgetList<DragTarget<List<String>>>(
          find.descendant(
            of: find.byType(VNavigationRail),
            matching: find.byType(DragTarget<List<String>>),
          ),
        )
        .toList();
    expect(targets, hasLength(3));
    void drop(int i, List<String> ids) => targets[i].onAcceptWithDetails!(
      DragTargetDetails(data: ids, offset: Offset.zero),
    );
    drop(2, ['track:2', 'track:3']);
    await settle(tester);
    final add = r.last(#crateApiLibraryAddToPlaylist)!;
    expect(add.namedArguments[#id], 'playlist:blue');
    expect(add.namedArguments[#items], ['track:2', 'track:3']);
    drop(0, ['track:4', 'track:6']);
    await settle(tester);
    expect(
      [
        for (final c in r.api.calls)
          if (c.memberName == #crateApiLibrarySetLiked)
            (c.namedArguments[#id], c.namedArguments[#liked]),
      ],
      [('track:4', true), ('track:6', true)],
    );
    drop(1, ['track:7']);
    await settle(tester);
    expect(r.last(#crateApiLibraryDownload)!.namedArguments[#ids], ['track:7']);
    // The pinned playlist is named (spoken, the rail being collapsed).
    expect(find.bySemanticsLabel(RegExp('^Blue Hour')), findsWidgets);
  }, variant: mac);

  testWidgets('title bar history buttons navigate back and forward', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    expect(location(tester), '/home');
    await tester.tap(
      find.descendant(
        of: find.byType(VNavigationRail),
        matching: find.byIcon(VIcons.explore),
      ),
    );
    await settle(tester);
    expect(location(tester), '/explore');
    await tester.tap(label('Page précédente'));
    await settle(tester);
    expect(location(tester), '/home');
    await tester.tap(label('Page suivante'));
    await settle(tester);
    expect(location(tester), '/explore');
  }, variant: mac);

  testWidgets('first launch redirects to onboarding', (tester) async {
    final r = Rig()..api.onboardingDone = false;
    await r.pump(tester);
    expect(location(tester), '/onboarding');
    expect(find.byType(VNavigationBar), findsNothing);
  });

  testWidgets('the rail expands, with its domain, and stays so', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    await tester.tap(label('Déplier le menu'));
    await settle(tester, 12);
    expect(
      tester.widget<VNavigationRail>(find.byType(VNavigationRail)).expanded,
      isTrue,
    );
    expect(r.api.prefs['ui.rail_expanded'], 'true');
    expect(find.text('Musique'), findsOneWidget);
    await r.pump(tester, size: desktop);
    expect(
      tester.widget<VNavigationRail>(find.byType(VNavigationRail)).expanded,
      isTrue,
    );
    // The tooltip of the last button hovered goes.
    await settle(tester, 10);
  }, variant: mac);
}
