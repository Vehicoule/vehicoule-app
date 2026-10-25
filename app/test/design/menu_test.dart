import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

void main() {
  testWidgets('menu: quick row in a connected group, then spaced groups', (
    tester,
  ) async {
    final picked = <String>[];
    VAction a(String l) => VAction(l, VIcons.album, () => picked.add(l));
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showVMenu(
              context,
              anchor: const Rect.fromLTWH(20, 20, 200, 56),
              origin: const Text('origin row'),
              quick: [a('Lire ensuite'), a('Ajouter à la file'), a("J'aime")],
              groups: [
                [a("Aller à l'album"), a("Aller à l'artiste")],
                [a('Télécharger')],
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final quick = find.byKey(VMenu.quickKey);
    expect(quick, findsOneWidget);
    for (final l in ['Lire ensuite', 'Ajouter à la file', "J'aime"]) {
      expect(
        find.descendant(of: quick, matching: find.bySemanticsLabel(l)),
        findsOneWidget,
        reason: l,
      );
    }
    final g1 = tester.getRect(find.text("Aller à l'artiste"));
    final g2 = tester.getRect(find.text('Télécharger'));
    expect(
      g2.top - g1.bottom,
      greaterThanOrEqualTo(VSpace.s8),
      reason: 'groups are spaced',
    );
    expect(tester.getTopLeft(find.byKey(VMenu.quickKey)).dy, lessThan(g1.top));
    // The origin row is lifted above the scrim.
    expect(find.text('origin row'), findsOneWidget);

    await tester.tap(find.text('Télécharger'));
    await tester.pumpAndSettle();
    expect(picked, ['Télécharger']);
    expect(find.byKey(VMenu.quickKey), findsNothing);

    // Escape closes it.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(VMenu.quickKey), findsNothing);
    expect(picked, ['Télécharger']);
  });

  testWidgets(
    'sheets: a bottom sheet on a phone, a dialog wide, never one on another',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext ctx;
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      showVSheet<void>(ctx, builder: (_) => const Text('first'));
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(find.byKey(VSheet.bottomKey), findsOneWidget);
      // A second one while the first is open is refused.
      expect(
        await showVSheet<int>(ctx, builder: (_) => const Text('second')),
        isNull,
      );
      await tester.pumpAndSettle();
      expect(find.text('second'), findsNothing);
      Navigator.of(ctx).pop();
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      showVSheet<void>(ctx, builder: (_) => const Text('wide'));
      await tester.pumpAndSettle();
      expect(find.byKey(VSheet.dialogKey), findsOneWidget);
    },
  );

  testWidgets('the menu takes the keyboard: its first item has focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) => GestureDetector(
            onTap: () => showVMenu(
              context,
              anchor: const Rect.fromLTWH(20, 20, 200, 56),
              quick: const [],
              groups: [
                [
                  VAction("Aller à l'album", VIcons.album, () {}),
                  VAction("Aller à l'artiste", VIcons.person, () {}),
                ],
              ],
            ),
            child: const Text('open'),
          ),
        ),
        reduce: true,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(
      find.ancestor(
        of: find.byWidget(focused!.widget),
        matching: find.byKey(VMenu.panelKey),
      ),
      findsOneWidget,
    );
    // ↓ moves to the next item.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context, isNot(focused));
  });

  testWidgets('a menu with only its quick row still takes the keyboard', (tester) async {
    await tester.pumpWidget(harness(Builder(
      builder: (context) => GestureDetector(
        onTap: () => showVMenu(
          context,
          anchor: const Rect.fromLTWH(20, 20, 200, 56),
          quick: [VAction('Lire ensuite', VIcons.playNext, () {})],
          groups: const [],
        ),
        child: const Text('open'),
      ),
    ), reduce: true));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(find.ancestor(of: find.byWidget(focused!.widget), matching: find.byKey(VMenu.panelKey)), findsOneWidget);
  });
}
