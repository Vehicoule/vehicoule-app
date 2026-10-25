import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/catalog.dart';
import 'package:vehicoule/debug/library.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

final track = sampleTracks.first; // Alors on danse — Stromae

class Calls {
  int tap = 0, doubleTap = 0, next = 0, remove = 0, menu = 0;
}

Widget row(
  Calls c, {
  TrackView? t,
  int? number,
  bool? playing,
  bool offline = false,
  bool wide = false,
  bool removable = false,
}) => VTrackRow(
  track: t ?? track,
  number: number,
  playing: playing,
  offline: offline,
  wide: wide,
  onTap: () => c.tap++,
  onDoubleTap: () => c.doubleTap++,
  onPlayNext: () => c.next++,
  onRemove: removable ? () => c.remove++ : null,
  quick: [VAction('Lire ensuite', VIcons.playNext, () => c.menu++)],
  groups: [
    [VAction("Aller à l'album", VIcons.album, () => c.menu++)],
  ],
);

void main() {
  testWidgets('VTrackRow: number replaces artwork, same height', (
    tester,
  ) async {
    final c = Calls();
    await tester.pumpWidget(
      harness(Column(children: [row(c), row(c, number: 7)])),
    );
    final rows = find.byType(VTrackRow);
    expect(tester.getSize(rows.at(0)).height, VSize.trackRow);
    expect(tester.getSize(rows.at(1)).height, VSize.trackRow);
    expect(
      find.descendant(of: rows.at(0), matching: find.byType(VArtwork)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rows.at(1), matching: find.byType(VArtwork)),
      findsNothing,
    );
    expect(
      find.descendant(of: rows.at(1), matching: find.text('7')),
      findsOneWidget,
    );
  });

  testWidgets('VTrackRow: playing is primary with equalizer label', (
    tester,
  ) async {
    await tester.pumpWidget(harness(row(Calls(), playing: true)));
    final scheme = Theme.of(tester.element(find.byType(VTrackRow))).colorScheme;
    final title = tester.widget<Text>(find.text(track.title));
    expect(title.style?.color, scheme.primary);
    expect(find.bySemanticsLabel(RegExp('En lecture')), findsOneWidget);
    // Not playing: no equalizer, normal color.
    await tester.pumpWidget(harness(row(Calls(), playing: false)));
    expect(find.bySemanticsLabel(RegExp('En lecture')), findsNothing);
    expect(
      tester.widget<Text>(find.text(track.title)).style?.color,
      isNot(scheme.primary),
    );
  });

  testWidgets('VTrackRow: offline dims and explains on tap', (tester) async {
    final c = Calls();
    await tester.pumpWidget(harness(row(c, offline: true)));
    final dim = tester.widget<Opacity>(
      find
          .ancestor(of: find.text(track.title), matching: find.byType(Opacity))
          .first,
    );
    expect(dim.opacity, 0.38);
    await tester.tap(find.byType(VTrackRow));
    await tester.pump();
    await tester.pump(VDurations.short);
    expect(c.tap, 0);
    expect(find.text(fr().offlineTrack), findsOneWidget);
    await tester.pump(VDurations.snack + VDurations.long);
  });

  testWidgets('VTrackRow: swipe right calls onPlayNext', (tester) async {
    final c = Calls();
    await tester.pumpWidget(harness(row(c, removable: true)));
    await tester.drag(find.byType(VTrackRow), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(c.next, 1);
    expect(c.remove, 0);
    expect(
      tester.getTopLeft(find.text(track.title)).dx,
      lessThan(200),
      reason: 'springs back',
    );
    // Left removes, when the list allows it.
    await tester.drag(find.byType(VTrackRow), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(c.remove, 1);
    // A short drag does nothing.
    await tester.drag(find.byType(VTrackRow), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(c.next, 1);
    expect(c.tap, 0);
  });

  testWidgets('VTrackRow: long press and secondary tap open the menu', (
    tester,
  ) async {
    final c = Calls();
    await tester.pumpWidget(harness(row(c)));
    await tester.longPress(find.byType(VTrackRow));
    await tester.pumpAndSettle();
    expect(find.text("Aller à l'album"), findsOneWidget);
    await tester.tap(find.text("Aller à l'album"));
    await tester.pumpAndSettle();
    expect(c.menu, 1);
    expect(
      find.text("Aller à l'album"),
      findsNothing,
      reason: 'closes after a choice',
    );

    await tester.tap(find.byType(VTrackRow), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text("Aller à l'album"), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Lire ensuite').last);
    await tester.pumpAndSettle();
    expect(c.menu, 2);

    // ⋮ too: the menu is right-aligned to the button, just under it (kept 8 inside the
    // window, which the row's ⋮ nearly touches).
    final more = tester.getRect(find.bySemanticsLabel(fr().actionMore));
    await tester.tap(find.bySemanticsLabel(fr().actionMore));
    await tester.pumpAndSettle();
    expect(find.text("Aller à l'album"), findsOneWidget);
    final panel = tester.getRect(find.byKey(VMenu.panelKey));
    expect(panel.right, closeTo(math.min(more.right, 800 - VSpace.s8), 0.5));
    expect(panel.top - more.bottom, inInclusiveRange(0, VSpace.s8));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // A right click opens it at the pointer.
    final at = tester.getCenter(find.text(track.title));
    await tester.tapAt(at, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(VMenu.panelKey)), at);
  });

  testWidgets('VTrackRow exposes a semantic label', (tester) async {
    final t = sampleTracks[1]; // Get Lucky — three artists
    await tester.pumpWidget(harness(row(Calls(), t: t)));
    expect(
      find.bySemanticsLabel(
        RegExp('^Get Lucky, Daft Punk, Pharrell Williams, Nile Rodgers'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'VTrackRow: wide is a table row; click selects, double-click plays',
    (tester) async {
      final c = Calls();
      await tester.pumpWidget(harness(row(c, wide: true, number: 2)));
      expect(find.text(track.album!.title), findsOneWidget);
      expect(find.text('3:26'), findsOneWidget);
      await tester.tap(find.text(track.title));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      expect(c.tap, 1);
      await tester.tap(find.text(track.title));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text(track.title));
      await tester.pumpAndSettle();
      expect(c.doubleTap, 1);
      expect(c.tap, 1);
    },
  );

  testWidgets('VTrackRow: badges for explicit and downloaded', (tester) async {
    await tester.pumpWidget(
      harness(
        Column(
          children: [
            row(Calls(), t: sampleTracks[3]), // HUMBLE. — explicit
            row(Calls(), t: sampleTracks[2]), // La vie en rose — downloaded
          ],
        ),
      ),
    );
    expect(
      find.bySemanticsLabel(RegExp('^HUMBLE.*, Explicite')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('^La vie en rose.*, Téléchargé')),
      findsOneWidget,
    );
  });
}
