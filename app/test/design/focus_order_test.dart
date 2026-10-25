// Keyboard focus across the gallery's controls (spec UI §4.4). Its own file: M3E keeps
// a process-wide « keyboard or pointer » state that earlier pointer tests would leave.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart'
    show M3EFocusRing;
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/debug/library.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

void noop() {}

Future<void> show(WidgetTester tester, Widget w, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness(w, reduce: true));
  await tester.pump();
}

void main() {
  testWidgets('Tab reaches every control, each with its focus ring', (
    tester,
  ) async {
    final row = VTrackRow(
      track: sampleTracks[0],
      playing: false,
      onTap: noop,
      onPlayNext: noop,
      quick: const [],
      groups: const [],
    );
    await show(
      tester,
      Column(
        children: [
          VIconButton(icon: VIcons.favorite, label: 'a', onPressed: noop),
          VButton(label: 'b', onPressed: noop),
          VChip(label: 'c', onPressed: noop),
          VSwitch(value: false, onChanged: (_) {}, label: 'd'),
          row,
          VCard(itemId: 'album:x', title: 'e', onTap: noop),
          VFab(icon: VIcons.play, label: 'f', onPressed: noop),
        ],
      ),
      size: const Size(600, 900),
    );
    tester.binding.focusManager.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    final seen = <Object>{};
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final focus = FocusManager.instance.primaryFocus?.context;
      if (focus == null) continue;
      // A visible ring: an M3E ring that is focused, or ours.
      // A visible ring: ours (it follows the shape) or an M3E one, focused.
      final ring =
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .any((p) => p.foregroundPainter is VFocusRingPainter) ||
          tester
              .widgetList<M3EFocusRing>(find.byType(M3EFocusRing))
              .any((r) => r.focused);
      final owner = [
        for (final t in [
          VIconButton,
          VButton,
          VChip,
          VSwitch,
          VTrackRow,
          VCard,
          VFab,
        ])
          if (find
              .ancestor(
                of: find.byWidget(focus.widget),
                matching: find.byType(t),
              )
              .evaluate()
              .isNotEmpty)
            t,
      ];
      expect(ring, isTrue, reason: 'focus in $owner');
      seen.add(focus);
    }
    expect(seen.length, greaterThanOrEqualTo(7));
    tester.binding.focusManager.highlightStrategy =
        FocusHighlightStrategy.automatic;
  });
}
