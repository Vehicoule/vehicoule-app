// The mini player's gestures (spec UI §5.3): the shell gives the actions, design/ does
// the gestures.
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicoule/design/design.dart';

import 'rig.dart';

/// The pill of the mini player (its toolbar), where the gestures live.
Finder get _pill => find.descendant(
  of: miniPlayer,
  matching: find.bySemanticsLabel('Mini-lecteur'),
);

void main() {
  testWidgets(
    'mini player swipe left skips, right goes back with the position',
    (tester) async {
      final r = Rig();
      await r.pump(tester);
      r.backend.positions.add(const Duration(seconds: 42));
      await settle(tester);
      await tester.drag(_pill.first, const Offset(-200, 0));
      await settle(tester);
      expect(
        r.names.where((n) => n == #crateApiPlaybackSkipNext),
        hasLength(1),
      );
      await tester.drag(_pill.first, const Offset(200, 0));
      await settle(tester);
      expect(
        r.last(#crateApiPlaybackPrevious)!.namedArguments[#positionMs],
        BigInt.from(42000),
      );
    },
  );

  testWidgets('mini player swipe down stops and Annuler undoes', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester);
    await tester.drag(_pill.first, const Offset(0, 200));
    await settle(tester);
    expect(r.names.where((n) => n == #crateApiPlaybackStop), hasLength(1));
    expect(find.text('Lecture arrêtée'), findsOneWidget);
    // Above the navigation bar, never over it.
    expect(
      tester.getRect(find.text('Lecture arrêtée')).bottom,
      lessThan(tester.getRect(find.byType(VNavigationBar)).top),
    );
    await tester.tap(find.text('Annuler'));
    await settle(tester);
    expect(r.names, contains(#crateApiPlaybackUndoStop));
  });

  testWidgets(
    'without Annuler, one stop and the message goes after the undo window',
    (tester) async {
      final r = Rig();
      await r.pump(tester);
      await tester.drag(_pill.first, const Offset(0, 200));
      await settle(tester);
      expect(find.text('Lecture arrêtée'), findsOneWidget);
      await tester.pump(VDurations.undo);
      await settle(tester, 20);
      expect(r.names.where((n) => n == #crateApiPlaybackStop), hasLength(1));
      expect(r.names, isNot(contains(#crateApiPlaybackUndoStop)));
      expect(find.text('Lecture arrêtée'), findsNothing);
      // Nothing loaded: no mini player, the screen FAB has the corner.
      expect(miniPlayer, findsNothing);
    },
  );

  testWidgets('play/pause marks the tap before a resume', (tester) async {
    final r = Rig();
    await r.pump(tester);
    await tester.tap(
      find.descendant(of: miniPlayer, matching: find.bySemanticsLabel('Lire')),
    );
    await settle(tester);
    expect(r.backend.calls, contains('play'));
  });
}
