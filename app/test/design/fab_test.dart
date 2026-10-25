// FABs, FAB menus and split buttons in their app configurations (spec UI §5.4 and its
// « Règle d'emploi »: one FAB or split button per screen).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart'
    show M3ENavigationRail, M3EFab, M3EToolbar;
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/design/gallery.dart';

import 'harness.dart';

void noop() {}

void main() {
  testWidgets('a split button opens its listed actions', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(
      harness(
        Center(
          child: VSplitButton(
            label: 'Aléatoire',
            icon: VIcons.shuffle,
            onPressed: noop,
            items: [
              for (final l in [
                "Lire dans l'ordre",
                'Radio',
                'Lire ensuite',
                'Ajouter à la file',
              ])
                VAction(l, VIcons.album, () => picked.add(l)),
            ],
          ),
        ),
        reduce: true,
      ),
    );
    // The trailing ▾ segment: the split's last ink.
    await tester.tap(
      find
          .descendant(
            of: find.byType(VSplitButton),
            matching: find.byType(InkWell),
          )
          .last,
    );
    await tester.pumpAndSettle();
    // Held to its own height, so the menu opens on screen under the chevron.
    expect(
      tester.getSize(find.byType(VSplitButton)).height,
      lessThan(VSize.fab),
    );
    for (final l in [
      "Lire dans l'ordre",
      'Radio',
      'Lire ensuite',
      'Ajouter à la file',
    ]) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    await tester.tap(find.text('Radio'));
    await tester.pumpAndSettle();
    expect(picked, ['Radio']);
  });

  testWidgets('a split button shrinks to a FAB once the list scrolls', (
    tester,
  ) async {
    Widget split(bool collapsed) => Center(
      child: VSplitFab(
        label: 'Lire',
        icon: VIcons.play,
        onPressed: noop,
        items: [VAction('Aléatoire', VIcons.shuffle, noop)],
        collapsed: collapsed,
      ),
    );
    await tester.pumpWidget(harness(split(false), reduce: true));
    await tester.pumpAndSettle();
    expect(find.byType(VSplitButton), findsOneWidget);
    expect(find.byType(VFab), findsNothing);
    await tester.pumpWidget(harness(split(true), reduce: true));
    await tester.pumpAndSettle();
    expect(find.byType(VFab), findsOneWidget);
    expect(find.byType(VSplitButton), findsNothing);
    expect(find.bySemanticsLabel('Lire'), findsOneWidget);
  });

  testWidgets('the rail carries its destination FAB at the top', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final expanded in [false]) {
      await tester.pumpWidget(
        harness(
          VNavigationRail(
            destinations: const [VDestination('Accueil', VIcons.home)],
            pinned: const [],
            selected: 0,
            onSelected: (_) {},
            expanded: expanded,
            onExpanded: (_) {},
            fab: VAction('Ajouter une source', VIcons.add, noop),
          ),
          reduce: true,
        ),
      );
      await tester.pump();
      expect(
        tester.widget<M3ENavigationRail>(find.byType(M3ENavigationRail)).fab,
        isNotNull,
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('multiple selection: the floating toolbar and its FAB « Lire »', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        Align(
          alignment: Alignment.bottomCenter,
          child: VToolbar(
            title: '3 sélectionnés',
            actions: [VAction('Télécharger', VIcons.download, noop)],
            fab: VFab(icon: VIcons.play, label: 'Lire', onPressed: noop),
          ),
        ),
        reduce: true,
      ),
    );
    await tester.pump();
    expect(find.byType(M3EToolbar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(M3EToolbar),
        matching: find.byType(M3EFab),
      ),
      findsOneWidget,
    );
  });

  testWidgets('each demo screen in the gallery has one FAB or split button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GalleryApp());
    await tester.pump(const Duration(milliseconds: 500));
    final screens = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('fab.demo.'),
      skipOffstage: false,
    );
    expect(screens.evaluate().length, greaterThanOrEqualTo(5));
    for (final e in screens.evaluate()) {
      final f = find.byElementPredicate((x) => x == e, skipOffstage: false);
      final mains = [VFab, VExtendedFab, VFabMenu, VSplitButton]
          .map(
            (t) => find
                .descendant(
                  of: f,
                  matching: find.byType(t),
                  skipOffstage: false,
                )
                .evaluate()
                .length,
          )
          .fold(0, (a, b) => a + b);
      expect(mains, 1, reason: '${e.widget.key}');
    }
    await tester.pumpWidget(const SizedBox());
  });
}
