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

  testWidgets(
    'a playlist mosaic is a VArtwork: 1, 2, 4 and 0 tiles, cookie and check',
    (tester) async {
      Future<void> show(Widget w) =>
          tester.pumpWidget(harness(Center(child: w), reduce: true));
      int pictures() => find.byType(VArtworkPicture).evaluate().length;
      VArtwork mosaic(
        List<String> ids, {
        bool? playing = false,
        bool selected = false,
      }) => VArtwork(
        itemId: 'playlist:mine',
        size: 200,
        mosaic: ids,
        playing: playing,
        selected: selected,
      );

      await show(mosaic(['a']));
      expect(pictures(), 1);
      await show(mosaic(['a', 'b']));
      expect(pictures(), 4, reason: '2 tiles repeat into 2×2');
      await show(mosaic(['a', 'b', 'a', 'c', 'd', 'e']));
      expect(pictures(), 4, reason: 'first four distinct');
      await show(mosaic([]));
      expect(pictures(), 0);
      expect(find.byIcon(VIcons.musicNote), findsOneWidget);
      expect(
        find.byKey(VArtwork.shapeKey(ArtShape.roundedSquare)),
        findsOneWidget,
      );

      // The shape language applies: playing → cookie, selected → cookie + check.
      await show(mosaic(['a', 'b'], playing: true));
      expect(find.byKey(VArtwork.shapeKey(ArtShape.cookie)), findsOneWidget);
      await show(mosaic(['a', 'b'], selected: true));
      expect(find.bySemanticsLabel('Sélectionné'), findsOneWidget);
      await show(
        NowPlayingScope(
          trackId: 'a',
          contextId: 'playlist:mine',
          playing: true,
          child: mosaic(['a', 'b'], playing: null),
        ),
      );
      expect(find.byKey(VArtwork.shapeKey(ArtShape.cookie)), findsOneWidget);
    },
  );

  testWidgets('pictures are fetched at a few bucketed sizes', (tester) async {
    final asked = <int>[];
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        const Column(
          children: [
            VArtwork(itemId: 'a', size: VSize.trackArt, playing: false),
            VArtwork(itemId: 'b', size: 200, playing: false),
            VArtwork(itemId: 'c', size: 201, playing: false),
          ],
        ),
        resolve: (id, px) async {
          asked.add(px);
          return null;
        },
      ),
    );
    expect(asked, [64, 256, 256]);
  });

  testWidgets('the missing-cover note stays upright while the cookie turns', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const Center(child: VArtwork(itemId: 'a', size: 200, playing: true)),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    final note = find.byIcon(VIcons.musicNote);
    final box = tester.renderObject<RenderBox>(note);
    final rect = tester.getRect(note);
    expect(rect.width, closeTo(box.size.width, 0.5), reason: 'not rotated');
    expect(rect.height, closeTo(box.size.height, 0.5));
    await tester.pumpWidget(const SizedBox());
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
    final c = tester.getCenter(find.byType(VArtwork));
    String shown() => tester
        .getSemantics(find.bySemanticsLabel('Position de lecture').first)
        .value;

    // The cover itself isn't the slider: only the ring is.
    await tester.tapAt(c);
    expect(seeks, isEmpty);
    // A tap on the right of the ring is a quarter of the way, at once.
    await tester.tapAt(c + const Offset(97, 0));
    expect(seeks.single, closeTo(0.25, 0.02));

    // A drag previews as it goes and seeks once, on release.
    final drag = await tester.startGesture(c + const Offset(0, 97)); // 50 %
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await drag.moveBy(const Offset(-12, -10));
      await tester.pump();
    }
    expect(seeks, hasLength(1), reason: 'nothing while dragging');
    expect(
      shown(),
      isNot('20 %'),
      reason: 'the ring shows where the finger is',
    );
    await drag.up();
    await tester.pump();
    expect(seeks, hasLength(2));
    expect(seeks.last, inInclusiveRange(0.55, 0.85));

    // Dragging across 12 o'clock stops at the end instead of jumping back to 0.
    final top = await tester.startGesture(
      c + const Offset(-60, -76),
    ); // about 90 %
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await top.moveBy(const Offset(15, 0));
      await tester.pump();
    }
    await top.up();
    await tester.pump();
    expect(seeks.last, 1.0);

    // The keyboard steps, at once.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(seeks.last, closeTo(0.3, 1e-9));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Position de lecture').first),
      isSemantics(isSlider: true),
    );

    // The wave edge: the middle of the bottom edge is halfway; a drag seeks once.
    final wave = tester.getRect(find.byType(VWaveArtwork));
    await tester.tapAt(Offset(wave.center.dx, wave.bottom - 4));
    expect(seeks.last, closeTo(0.5, 0.02));
    final before = seeks.length;
    await tester.dragFrom(
      Offset(wave.left + 20, wave.bottom - 8),
      const Offset(100, 0),
    );
    await tester.pump();
    expect(seeks.length, before + 1);
    await tester.pump(const Duration(seconds: 1));
  });
}
