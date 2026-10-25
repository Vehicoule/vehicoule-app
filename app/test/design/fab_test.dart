// FABs, FAB menus and split buttons in their app configurations (spec UI §5.4 and its
// « Règle d'emploi »: one FAB or split button per screen).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart'
    show M3ENavigationRail, M3EFab, M3EToolbar;
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/design/gallery.dart';
import 'package:vehicoule/l10n/app_localizations.dart';

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
    // M3 menu items lead with their action's icon.
    expect(find.byIcon(VIcons.album), findsNWidgets(4));
    await tester.tap(find.text('Radio'));
    await tester.pumpAndSettle();
    expect(picked, ['Radio']);
  });

  testWidgets('on a phone the screen FAB sits above the mini player ⏯', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        VFabDock(
          body: ListView(
            children: [for (var i = 0; i < 60; i++) Text('Ligne $i')],
          ),
          fab: VFab(icon: VIcons.play, label: 'Lire', onPressed: noop),
          player: Row(
            children: [
              const Expanded(child: SizedBox(height: VSize.toolbar)),
              VPlayPauseFab(playing: true, loading: false, onPressed: noop),
            ],
          ),
        ),
        reduce: true,
      ),
    );
    await tester.pumpAndSettle();
    final fab = tester.getRect(find.byType(VFab));
    final play = tester.getRect(find.byType(VPlayPauseFab));
    expect(fab.right, closeTo(play.right, 0.5), reason: 'right-aligned');
    expect(play.top - fab.bottom, closeTo(VSpace.s16, 0.5), reason: '16 dp');
    // Scrolling down hides it, scrolling up brings it back.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byType(VFab), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(find.byType(VFab), findsOneWidget);
  });

  testWidgets('the rail shows its destination FAB, collapsed and expanded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <String>[];
    for (final expanded in [false, true]) {
      await tester.pumpWidget(
        harness(
          Align(
            alignment: Alignment.centerLeft,
            child: VNavigationRail(
              destinations: const [
                VDestination('Accueil', VIcons.home),
                VDestination('Bibliothèque', VIcons.library),
              ],
              pinned: const [],
              selected: 1,
              onSelected: (_) {},
              expanded: expanded,
              onExpanded: (_) {},
              fab: VAction('Nouvelle', VIcons.add, noop),
              fabItems: [
                VAction(
                  'Nouvelle playlist',
                  VIcons.playlistAdd,
                  () => picked.add('playlist'),
                ),
                VAction('Importer un lien', VIcons.addLink, noop),
              ],
            ),
          ),
          reduce: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no overflow');
      // Drawn by us, outside the package's slot.
      expect(
        tester.widget<M3ENavigationRail>(find.byType(M3ENavigationRail)).fab,
        isNull,
      );
      expect(find.bySemanticsLabel('Nouvelle'), findsOneWidget);
      if (expanded) expect(find.text('Nouvelle'), findsOneWidget);
      // A FAB menu: the creations open in a menu under it.
      await tester.tap(find.bySemanticsLabel('Nouvelle'));
      await tester.pumpAndSettle();
      expect(find.text('Importer un lien'), findsOneWidget);
      await tester.tap(find.text('Nouvelle playlist'));
      await tester.pumpAndSettle();
    }
    expect(picked, ['playlist', 'playlist']);
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
    expect(screens.evaluate().length, greaterThanOrEqualTo(6));
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
    // The phone: the screen's FAB with the mini player's ⏯, which is the player's.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('fab.demo.phone'), skipOffstage: false),
        matching: find.byType(VPlayPauseFab, skipOffstage: false),
      ),
      findsOneWidget,
    );
    // The rail's FAB is the selected destination's: Bibliothèque, « Nouvelle ».
    final l = lookupAppLocalizations(const Locale('fr'));
    final railFabs = tester.widgetList<VFab>(
      find.descendant(
        of: find.byType(VNavigationRail, skipOffstage: false),
        matching: find.byType(VFab, skipOffstage: false),
      ),
    );
    expect(railFabs.map((f) => f.label), contains(l.fabNew));
    await tester.pumpWidget(const SizedBox());
  });
}
