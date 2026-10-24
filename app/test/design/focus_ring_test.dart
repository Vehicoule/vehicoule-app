import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

void main() {
  testWidgets('focus ring follows the shape and only shows on keyboard', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      harness(
        Center(
          child: VFocusRing(
            shape: const CircleBorder(),
            child: Focus(
              focusNode: node,
              child: const SizedBox.square(dimension: VSize.menuTarget),
            ),
          ),
        ),
      ),
    );
    VFocusRingPainter? ring() => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(VFocusRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((p) => p.foregroundPainter)
        .whereType<VFocusRingPainter>()
        .firstOrNull;

    // Touch: focused, no ring.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    node.requestFocus();
    await tester.pump();
    expect(ring(), isNull);

    // Keyboard: the ring, in the shape given, 3 px secondary.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pump();
    final p = ring();
    expect(p, isNotNull);
    expect(p!.shape, const CircleBorder());
    final scheme = Theme.of(tester.element(find.byType(VFocusRing)))
        .colorScheme;
    expect(p.color, scheme.secondary);
    expect(VFocusRing.width, 3);
    expect(VFocusRing.gap, 2);

    // Unfocused: gone.
    node.unfocus();
    await tester.pump();
    await tester.pump();
    expect(ring(), isNull);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });
}
