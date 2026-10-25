// Navigation between domains (addendum §3, §11): the routes, the domain read from the
// location, the global sections, the pinned items per domain, the shells' layers.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/app_scope.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/domains.dart';
import 'package:vehicoule/router.dart';
import 'package:vehicoule/shell_desktop/pinned.dart';

import 'rig.dart';

GoTo goTo(WidgetTester tester) =>
    tester.state<VehicouleAppState>(find.byType(VehicouleApp)).router.go;

typedef GoTo = void Function(String location, {Object? extra});

void main() {
  testWidgets('settings is a global section, not a bar destination', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester);
    final bar = tester.widget<VNavigationBar>(find.byType(VNavigationBar));
    expect(bar.destinations.map((d) => d.label), [
      'Accueil',
      'Explorer',
      'Bibliothèque',
    ]);
    await tester.tap(label('Ouvrir le menu').first);
    await settle(tester);
    for (final t in ['Musique', 'Téléchargements', 'Sources', 'Réglages']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.tap(find.text('Réglages'));
    await settle(tester, 12);
    expect(location(tester), '/settings');

    // Desktop: the same three at the bottom of the rail, none of them a destination.
    await r.pump(tester, size: desktop);
    final rail = tester.widget<VNavigationRail>(find.byType(VNavigationRail));
    expect(rail.destinations.map((d) => d.label), [
      'Accueil',
      'Explorer',
      'Bibliothèque',
    ]);
    expect(rail.globals.map((d) => d.label), [
      'Téléchargements',
      'Sources',
      'Réglages',
    ]);
    await key(tester, LogicalKeyboardKey.comma, meta: true);
    expect(location(tester), '/settings');
  }, variant: mac);

  testWidgets('the domain comes from the route', (tester) async {
    expect(domainOf('/music/explore', stored: Domain.music), Domain.music);
    expect(domainOf('/home/music/album/x', stored: Domain.music), Domain.music);
    expect(domainOf('/home', stored: Domain.music), Domain.music);
    expect(
      domainOf('/settings/appearance', stored: Domain.music),
      Domain.music,
    );
    // ui.domain is written when the route names a domain, read at launch.
    final r = Rig();
    await r.pump(tester);
    goTo(tester)('/music/library');
    await settle(tester, 12);
    expect(r.api.prefs['ui.domain'], 'music');
  });

  testWidgets('an album opened from home stays in the home branch', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester);
    final home = tester.element(find.text('Accueil').last);
    openItem(home, 'album:Cheese');
    await settle(tester, 12);
    expect(location(tester), startsWith('/home/music/album/'));
    final bar = tester.widget<VNavigationBar>(find.byType(VNavigationBar));
    expect(bar.selected, 0, reason: 'Accueil stays selected');
    expect(bar.destinations, hasLength(3), reason: 'the music bar');

    goTo(tester)('/music/explore');
    await settle(tester, 12);
    openItem(tester.element(find.text('Explorer').last), 'album:Cheese');
    await settle(tester, 12);
    expect(location(tester), startsWith('/music/explore/album/'));
    expect(
      tester.widget<VNavigationBar>(find.byType(VNavigationBar)).selected,
      1,
    );
  });

  testWidgets('pinned are stored per domain', (tester) async {
    final r = Rig();
    r.api.prefs['ui.pinned.music'] = '["liked"]';
    r.api.prefs['ui.pinned'] = '["downloaded","liked"]';
    final pinned = Pinned(Domain.music);
    await tester.runAsync(pinned.load);
    expect(pinned.ids, ['liked'], reason: 'read from ui.pinned.music');
    await tester.runAsync(() => pinned.pin('playlist:blue'));
    expect(jsonDecode(r.api.prefs['ui.pinned.music']!), [
      'liked',
      'playlist:blue',
    ]);
    expect(r.api.prefs['ui.pinned'], '["downloaded","liked"]');
    expect(
      r.api.calls.where(
        (c) =>
            c.memberName == #crateApiSettingsSetUiPref &&
            c.namedArguments[#key] == 'ui.pinned',
      ),
      isEmpty,
    );
    pinned.dispose();
  });

  testWidgets('home app bar keeps the chip row hidden with one domain', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester);
    // Built, but empty (a zero-height sliver: the finder must look offstage too).
    expect(find.byType(DomainChips, skipOffstage: false), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DomainChips),
        matching: find.byType(VChip),
      ),
      findsNothing,
    );
  });

  testWidgets('the video layer sits between the mini player and the overlays', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester);
    final stack = find
        .ancestor(of: find.byType(VideoLayer), matching: find.byType(Stack))
        .first;
    final children = tester.widget<Stack>(stack).children;
    int at(Finder f) => children.indexWhere(
      (c) => find
          .descendant(of: find.byWidget(c), matching: f, matchRoot: true)
          .evaluate()
          .isNotEmpty,
    );
    final video = at(find.byType(VideoLayer));
    expect(
      at(find.byType(Scaffold)),
      lessThan(video),
      reason: 'over the shell',
    );
    expect(at(find.byType(VFabDock)), lessThan(video));
    expect(video, greaterThanOrEqualTo(0));
    final rect = AppScope.of(tester.element(find.byType(VideoLayer)))
        .miniPlayerRect
        .value;
    expect(rect, tester.getRect(miniPlayer));
  });

  testWidgets('playback shortcuts go through sessionTarget', (tester) async {
    final r = Rig();
    var asked = 0;
    debugSessionTarget = (_) {
      asked++;
      return PlaybackSession.music;
    };
    addTearDown(() => debugSessionTarget = null);
    await r.pump(tester, size: desktop);
    await key(tester, LogicalKeyboardKey.space);
    expect(asked, greaterThan(0));
    expect(r.backend.calls.last, 'play');
  }, variant: mac);
}
