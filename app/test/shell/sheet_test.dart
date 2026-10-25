// The phone player sheet and the artwork that flies with it (spec UI §5.6, audit 13d).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/features/music/now_playing/now_playing_sheet.dart';

import 'rig.dart';

Finder get _big => find.byWidgetPredicate(
  (w) => w is VNowPlaying && w.size == PlayerSize.large,
);

void expectRect(Rect a, Rect b, {String? reason}) {
  for (final (x, y) in [
    (a.left, b.left),
    (a.top, b.top),
    (a.width, b.width),
    (a.height, b.height),
  ]) {
    expect(x, moreOrLessEquals(y, epsilon: 1), reason: reason);
  }
}

void main() {
  testWidgets('the artwork flies with the sheet extent, no Hero', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester);
    final sheet = tester.state<NowPlayingSheetState>(
      find.byType(NowPlayingSheet),
    );
    final disc = tester.getRect(
      find.descendant(of: miniPlayer, matching: find.byType(VArtwork)),
    );
    expect(find.byType(VExtentFlight), findsNothing, reason: 'at rest');

    sheet.controller.jumpTo(0.5);
    await settle(tester, 2);
    final half = tester.widget<VExtentFlight>(find.byType(VExtentFlight));
    expectRect(half.from, disc, reason: 'from: the mini player disc');
    final at = tester.getRect(find.byType(VExtentFlight));
    expectRect(at, Rect.lerp(half.from, half.to, 0.5)!);
    // Both players hide their own artwork while it flies.
    for (final p in tester.widgetList<VNowPlaying>(find.byType(VNowPlaying))) {
      expect(p.artworkVisible, isFalse, reason: '${p.size}');
    }

    sheet.controller.jumpTo(0.9);
    await settle(tester, 2);
    final near = tester.widget<VExtentFlight>(find.byType(VExtentFlight));

    sheet.controller.jumpTo(1);
    await settle(tester, 2);
    expect(find.byType(VExtentFlight), findsNothing, reason: 'landed');
    final art = tester.getRect(
      find.descendant(of: _big, matching: find.byType(VArtwork)).first,
    );
    // `to` rides with the sheet's top: at 0.5 and 0.9 it is where it lands at 1,
    // lowered by the part of the sheet still hidden.
    expectRect(
      half.to,
      art.shift(Offset(0, phone.height * 0.5)),
      reason: 'to at 0.5',
    );
    expectRect(
      near.to,
      art.shift(Offset(0, phone.height * 0.1)),
      reason: 'to at 0.9',
    );
    expect(tester.widget<VNowPlaying>(_big).artworkVisible, isTrue);
    expect(
      find.descendant(
        of: find.byType(NowPlayingSheet),
        matching: find.byType(Hero),
      ),
      findsNothing,
    );
  });

  testWidgets('a tap on the mini player opens the sheet; ⌄ closes it', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester);
    final sheet = tester.state<NowPlayingSheetState>(
      find.byType(NowPlayingSheet),
    );
    expect(sheet.controller.size, 0);
    await tester.tap(
      find.descendant(of: miniPlayer, matching: find.text('Alors on danse')),
    );
    await settle(tester, 12);
    expect(sheet.controller.size, 1);
    await tester.tap(
      find.descendant(of: _big, matching: find.bySemanticsLabel('Réduire')),
    );
    await settle(tester, 12);
    expect(sheet.controller.size, 0);
  });

  testWidgets('back closes the open player, not the app', (tester) async {
    final r = Rig();
    await r.pump(tester);
    final sheet = tester.state<NowPlayingSheetState>(
      find.byType(NowPlayingSheet),
    );
    sheet.open();
    await settle(tester, 12);
    expect(sheet.controller.size, 1);
    await tester.binding.handlePopRoute();
    await settle(tester, 12);
    expect(sheet.controller.size, 0);
    expect(location(tester), '/home');
  });
}
