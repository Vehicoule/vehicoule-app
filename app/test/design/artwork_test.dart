import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/components/artwork.dart' show VArtworkPicture;
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

double angle(WidgetTester tester) {
  final t = tester.widget<Transform>(
    find
        .descendant(of: find.byType(VArtwork), matching: find.byType(Transform))
        .first,
  );
  return t.transform.getRotation().entry(1, 0);
}

void main() {
  testWidgets(
    'artwork shape follows meaning: idle rounded, playing cookie, artist circle, selected check',
    (tester) async {
      expect(
        artShapeFor(kind: ArtKind.item, playing: false, selected: false),
        ArtShape.roundedSquare,
      );
      expect(
        artShapeFor(kind: ArtKind.item, playing: true, selected: false),
        ArtShape.cookie,
      );
      expect(
        artShapeFor(kind: ArtKind.artist, playing: true, selected: false),
        ArtShape.circle,
      );
      expect(
        artShapeFor(kind: ArtKind.artist, playing: false, selected: true),
        ArtShape.cookie,
      );
      expect(
        artShapeFor(kind: ArtKind.item, playing: false, selected: true),
        ArtShape.cookie,
      );

      Future<void> show(Widget w) async {
        await tester.pumpWidget(harness(Center(child: w), reduce: true));
        await tester.pump();
      }

      await show(const VArtwork(itemId: 'a', size: 120, playing: false));
      expect(
        find.byKey(VArtwork.shapeKey(ArtShape.roundedSquare)),
        findsOneWidget,
      );
      await show(const VArtwork(itemId: 'a', size: 120, playing: true));
      expect(find.byKey(VArtwork.shapeKey(ArtShape.cookie)), findsOneWidget);
      await show(
        const VArtwork(
          itemId: 'a',
          size: 120,
          kind: ArtKind.artist,
          playing: true,
        ),
      );
      expect(find.byKey(VArtwork.shapeKey(ArtShape.circle)), findsOneWidget);
      expect(
        find.bySemanticsLabel('En lecture'),
        findsOneWidget,
        reason: 'artist playing: equalizer',
      );
      await show(const VArtwork(itemId: 'a', size: 120, selected: true));
      expect(find.byKey(VArtwork.shapeKey(ArtShape.cookie)), findsOneWidget);
      expect(find.bySemanticsLabel('Sélectionné'), findsOneWidget);

      // Without an override, the scope decides: only the playing id is a cookie.
      await show(
        const NowPlayingScope(
          trackId: 'b',
          contextId: 'album',
          playing: true,
          child: Row(
            children: [
              VArtwork(itemId: 'a', size: 60),
              VArtwork(itemId: 'b', size: 60),
              VArtwork(itemId: 'album', size: 60),
            ],
          ),
        ),
      );
      expect(find.byKey(VArtwork.shapeKey(ArtShape.cookie)), findsNWidgets(2));
      expect(
        find.byKey(VArtwork.shapeKey(ArtShape.roundedSquare)),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'playing cookie stops spinning and morphs back when paused or with reduce motion',
    (tester) async {
      final playing = ValueNotifier(true);
      await tester.pumpWidget(
        harness(
          Center(
            child: ValueListenableBuilder(
              valueListenable: playing,
              builder: (context, p, _) =>
                  VArtwork(itemId: 'a', size: 200, playing: p),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final a1 = angle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(
        angle(tester),
        isNot(closeTo(a1, 1e-6)),
        reason: 'it turns while playing',
      );

      playing.value = false;
      await tester.pumpAndSettle();
      expect(
        find.byKey(VArtwork.shapeKey(ArtShape.roundedSquare)),
        findsOneWidget,
      );
      expect(angle(tester), closeTo(0, 1e-6), reason: 'the square is upright');
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'stopped');

      // Reduce motion: the cookie shows but doesn't turn.
      await tester.pumpWidget(
        harness(
          const Center(child: VArtwork(itemId: 'a', size: 200, playing: true)),
          reduce: true,
        ),
      );
      await tester.pump();
      expect(find.byKey(VArtwork.shapeKey(ArtShape.cookie)), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  test('decorFor is stable per id and spreads over the shapes', () {
    expect(decorFor('Rock'), decorFor('Rock'));
    final seen = {for (var i = 0; i < 200; i++) decorFor('genre $i')};
    expect(seen, VDecorShape.values.toSet());
  });

  testWidgets('mosaic artwork tiles 1, 2, 4 and 0 items', (tester) async {
    Future<void> show(List<String> ids) => tester.pumpWidget(
      harness(Center(child: VMosaicArtwork(itemIds: ids, size: 200))),
    );
    int pictures() => find.byType(VArtworkPicture).evaluate().length;

    await show(['a']);
    expect(find.byType(VArtwork), findsOneWidget);
    expect(pictures(), 1);
    await show(['a', 'b']);
    expect(pictures(), 4, reason: '2 tiles repeat into 2×2');
    await show(['a', 'b', 'a', 'c', 'd', 'e']);
    expect(pictures(), 4, reason: 'first four distinct');
    await show([]);
    expect(pictures(), 0);
    expect(find.byIcon(VIcons.musicNote), findsOneWidget);
  });

  testWidgets('disc ring and wave edge seek like a slider', (tester) async {
    final seeks = <double>[];
    await tester.pumpWidget(
      harness(
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VArtwork(
                itemId: 'a',
                size: 200,
                playing: true,
                progress: 0.2,
                onSeek: seeks.add,
                seekStep: 0.1,
              ),
              VWaveArtwork(
                itemId: 'a',
                width: 200,
                progress: 0.2,
                playing: true,
                onSeek: seeks.add,
              ),
            ],
          ),
        ),
      ),
    );
    final ring = find.byType(VArtwork);
    final c = tester.getCenter(ring);
    // A tap on the right of the ring is a quarter of the way.
    await tester.tapAt(c + const Offset(98, 0));
    expect(seeks.last, closeTo(0.25, 0.02));
    // A drag along the ring seeks as it goes.
    await tester.dragFrom(c + const Offset(0, 98), const Offset(-60, -40));
    expect(seeks.last, inInclusiveRange(0.5, 0.9));
    // The keyboard steps.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(seeks.last, closeTo(0.3, 1e-9));
    // An accessible slider.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Position de lecture').first),
      isSemantics(isSlider: true),
    );

    // The wave edge: the middle of the bottom edge is halfway.
    final wave = tester.getRect(find.byType(VWaveArtwork));
    await tester.tapAt(Offset(wave.center.dx, wave.bottom - 4));
    expect(seeks.last, closeTo(0.5, 0.02));
    await tester.pump(const Duration(seconds: 1));
  });
}
