import 'package:flutter/services.dart';
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

  testWidgets('cards show the ring in their shape, the cookie when playing', (
    tester,
  ) async {
    VFocusRingPainter? ring() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.foregroundPainter)
        .whereType<VFocusRingPainter>()
        .firstOrNull;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );

    for (final (name, card, shape) in [
      (
        'card',
        VCard(itemId: 'album:a', title: 'Cheese', onTap: () {}),
        isA<RoundedRectangleBorder>(),
      ),
      (
        'artist',
        VCard(
          itemId: 'artist:a',
          title: 'Stromae',
          kind: ArtKind.artist,
          onTap: () {},
        ),
        isA<CircleBorder>(),
      ),
      (
        'hero',
        VHeroCard(itemId: 'album:b', title: 'OK Computer', onTap: () {}),
        isA<RoundedRectangleBorder>(),
      ),
      (
        'playing',
        NowPlayingScope(
          trackId: 't',
          contextId: 'album:c',
          playing: true,
          child: VCard(itemId: 'album:c', title: 'DAMN.', onTap: () {}),
        ),
        isA<VPolygonBorder>(),
      ),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(harness(Center(child: card), reduce: true));
      expect(ring(), isNull, reason: name);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(ring()?.shape, shape, reason: name);
    }
  });
}
