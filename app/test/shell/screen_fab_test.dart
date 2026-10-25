// A screen's FAB (spec UI §5.4): only the visible screen publishes it; a phone puts it
// above the mini player's ⏯, the desktop rail at its top; a selection bar takes the mini
// player's place.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/screen_fab.dart';

import '../design/harness.dart';
import 'rig.dart';

void main() {
  testWidgets('only the visible screen publishes its FAB', (tester) async {
    final r = Rig();
    await r.pump(tester);
    // Accueil: « Lancer », extended, above the ⏯.
    final fab = find.descendant(
      of: find.byType(VScreenFab),
      matching: find.text('Lancer'),
    );
    expect(fab, findsOneWidget);
    final play = tester.getRect(find.byType(VPlayPauseFab));
    expect(tester.getRect(fab).bottom, lessThan(play.top));
    expect(tester.getRect(find.byType(VScreenFab)).right, play.right);

    await tester.tap(
      find.descendant(
        of: find.byType(VNavigationBar),
        matching: find.text('Explorer'),
      ),
    );
    await settle(tester);
    expect(find.byType(VScreenFab), findsNothing, reason: 'Accueil is hidden');
    await tester.tap(
      find.descendant(
        of: find.byType(VNavigationBar),
        matching: find.text('Bibliothèque'),
      ),
    );
    await settle(tester);
    expect(find.text('Nouvelle'), findsOneWidget);
  });

  testWidgets('desktop: the rail carries the destination FAB', (tester) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    Finder inRail(String l) => find.descendant(
      of: find.byType(VNavigationRail),
      matching: find.bySemanticsLabel(l),
    );
    expect(inRail('Lancer'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(VNavigationRail),
        matching: find.byIcon(VIcons.explore),
      ),
    );
    await settle(tester);
    expect(inRail('Lancer'), findsNothing);
    expect(find.byType(VScreenFab), findsNothing);
  }, variant: mac);

  testWidgets('a pushed page hides the FAB of the page under it', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      harness(
        ScreenFabHost(
          builder: (context, action, items, bar) => Column(
            children: [
              Text(action?.label ?? 'none'),
              Expanded(
                child: Navigator(
                  key: nav,
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    pageBuilder: (_, _, _) => ScreenFab(
                      action: VAction('first', VIcons.add, () {}),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('first'), findsOneWidget);
    nav.currentState!.push(
      PageRouteBuilder<void>(pageBuilder: (_, _, _) => const SizedBox.expand()),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('none'), findsOneWidget);
    nav.currentState!.pop();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('first'), findsOneWidget);
  });

  testWidgets('a selection bar replaces the mini player while it is set', (
    tester,
  ) async {
    var selecting = true;
    late StateSetter set;
    await tester.pumpWidget(
      harness(
        ScreenFabHost(
          builder: (context, action, items, bar) => VFabDock(
            body: StatefulBuilder(
              builder: (context, s) {
                set = s;
                return ScreenFab(
                  bar: selecting ? const Text('selection') : null,
                  child: const SizedBox.expand(),
                );
              },
            ),
            fab: action,
            fabItems: items,
            player: bar ?? const Text('mini'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('selection'), findsOneWidget);
    expect(find.text('mini'), findsNothing);
    set(() => selecting = false);
    await tester.pump();
    await tester.pump();
    expect(find.text('selection'), findsNothing);
    expect(find.text('mini'), findsOneWidget);
  });
}
