import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/components/artwork.dart' show VArtworkPicture;
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

String pct(double p) => NumberFormat.percentPattern('fr').format(p);

double angle(WidgetTester tester) {
  final t = tester.widget<Transform>(
    find
        .descendant(of: find.byType(VArtwork), matching: find.byType(Transform))
        .first,
  );
  return t.transform.getRotation().entry(1, 0);
}

void main() {
  ringGeometryTests();
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

    // The keyboard steps, at once, from the progress the parent passes: here the
    // player never applied the drag, so 0.2.
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

  testWidgets('a fast play, pause, play still ends as a turning cookie', (
    tester,
  ) async {
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
    await tester.pump(const Duration(milliseconds: 500));
    // Toggle twice within the spring (60 ms apart), like a double tap on ⏯.
    playing.value = false;
    await tester.pump(const Duration(milliseconds: 60));
    playing.value = true;
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(VArtwork.shapeKey(ArtShape.cookie)), findsOneWidget);
    expect(angle(tester).abs(), greaterThan(0.01), reason: 'turning at 2 s');
    await tester.pump(const Duration(seconds: 3));
    expect(angle(tester).abs(), greaterThan(0.01), reason: 'turning at 5 s');
    // And the other way: pause, play, pause ends as a still square.
    playing.value = false;
    await tester.pump(const Duration(milliseconds: 60));
    playing.value = true;
    await tester.pump(const Duration(milliseconds: 60));
    playing.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.byKey(VArtwork.shapeKey(ArtShape.roundedSquare)),
      findsOneWidget,
    );
    expect(angle(tester), closeTo(0, 1e-6));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a seek shows the given progress with no timer left', (
    tester,
  ) async {
    final progress = ValueNotifier(0.2);
    final seeks = <double>[];
    await tester.pumpWidget(
      harness(
        Center(
          child: ValueListenableBuilder(
            valueListenable: progress,
            builder: (context, p, _) => VArtwork(
              itemId: 'a',
              size: 200,
              playing: false,
              progress: p,
              onSeek: seeks.add,
            ),
          ),
        ),
        reduce: true,
      ),
    );
    final c = tester.getCenter(find.byType(VArtwork));
    String shown() => tester
        .getSemantics(find.bySemanticsLabel('Position de lecture').first)
        .value;
    await tester.dragFrom(
      c + const Offset(0, 97),
      const Offset(-1, -1),
    ); // about 50 %
    await tester.pump();
    expect(seeks, hasLength(1));
    // The player adapter publishes the target at once; the ring holds nothing itself.
    expect(shown(), pct(0.2));
    progress.value = seeks.single;
    await tester.pump();
    expect(shown(), pct(seeks.single));
    await tester.tapAt(c + const Offset(97, 0)); // about 25 %
    await tester.pump();
    expect(seeks, hasLength(2));
    expect(shown(), pct(seeks.first));
    // No pump to wait out: a timer left behind would fail the test here.
  });

  testWidgets('arrow keys step from the progress the parent passes', (
    tester,
  ) async {
    final progress = ValueNotifier(0.2);
    final seeks = <double>[];
    await tester.pumpWidget(
      harness(
        Center(
          child: ValueListenableBuilder(
            valueListenable: progress,
            builder: (context, p, _) => VArtwork(
              itemId: 'a',
              size: 200,
              playing: false,
              progress: p,
              onSeek: seeks.add,
              seekStep: 0.1,
            ),
          ),
        ),
        reduce: true,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // The parent hasn't passed the new progress yet: the next press starts at 0.2 again.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    progress.value = 0.3;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(seeks, [closeTo(0.3, 1e-9), closeTo(0.3, 1e-9), closeTo(0.4, 1e-9)]);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Position de lecture').first)
          .value,
      pct(0.3),
    );
  });
}

double _clockwise(Offset p, Offset c) {
  final a = math.atan2(p.dx - c.dx, -(p.dy - c.dy));
  return a < 0 ? a + 2 * math.pi : a;
}

void ringGeometryTests() {
  const box = Rect.fromLTWH(0, 0, 200, 200);
  final c = box.center;
  double radius(Offset p) => (p - c).distance;

  test("the ring is the artwork's outline, from 12 o'clock clockwise", () {
    for (final shape in ArtShape.values) {
      final g = VRingGeometry(vRingOutline(shape, box), c);
      for (final turn in [0.0, 0.4, 2.0]) {
        final why = '$shape turned $turn';
        final played = g.played(0.25, turn: turn);
        expect(
          played.first.dx,
          closeTo(c.dx, 3),
          reason: '$why: starts at the top',
        );
        expect(played.first.dy, lessThan(c.dy), reason: why);
        expect(
          played.last.dx,
          greaterThan(c.dx),
          reason: '$why: ends at 3 o\'clock',
        );
        expect(played.last.dy, closeTo(c.dy, 3), reason: why);
        var last = -1.0;
        for (final p in played) {
          final a = _clockwise(p, c);
          expect(
            a,
            greaterThanOrEqualTo(last - 1e-6),
            reason: '$why: clockwise',
          );
          last = a;
        }
        // The rest runs from the played part's end back to the top, end to end.
        final rest = g.rest(0.25, turn: turn);
        expect(rest.first, played.last, reason: '$why: no hole at the head');
        expect(rest.last, played.first, reason: '$why: none at 12 o\'clock');
        for (final p in rest.skip(1).take(rest.length - 2)) {
          final a = _clockwise(p, c);
          expect(a, inExclusiveRange(math.pi / 2, 2 * math.pi), reason: why);
        }
      }
      expect(g.played(0, turn: 0), isEmpty);
      expect(g.rest(1, turn: 0), isEmpty);
    }
    final cookie = VRingGeometry(vRingOutline(ArtShape.cookie, box), c);
    final radii = cookie.played(1, turn: 0).map(radius);
    expect(
      radii.reduce(math.max) / radii.reduce(math.min),
      greaterThan(1.05),
      reason: 'the cookie\'s lobes make the line wavy',
    );
    final circle = VRingGeometry(vRingOutline(ArtShape.circle, box), c);
    final round = circle.played(1, turn: 0).map(radius);
    expect(round.reduce(math.max) - round.reduce(math.min), lessThan(1));
    final square = VRingGeometry(vRingOutline(ArtShape.roundedSquare, box), c);
    final corners = square.played(1, turn: 0).map(radius);
    expect(
      corners.reduce(math.max),
      greaterThan(corners.reduce(math.min) * 1.2),
      reason: 'a rounded square, corners farther than edges',
    );
  });

  testWidgets('the ring takes the shape of the artwork it surrounds', (
    tester,
  ) async {
    Future<ArtShape> ringOf(VArtwork a) async {
      await tester.pumpWidget(harness(Center(child: a), reduce: true));
      await tester.pump();
      final paints = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<VRingPainter>();
      expect(paints, hasLength(1));
      return paints.single.shape;
    }

    expect(
      await ringOf(
        const VArtwork(itemId: 'a', size: 200, playing: true, progress: 0.3),
      ),
      ArtShape.cookie,
    );
    expect(
      await ringOf(
        const VArtwork(itemId: 'b', size: 200, playing: false, progress: 0.3),
      ),
      ArtShape.roundedSquare,
    );
    expect(
      await ringOf(
        const VArtwork(
          itemId: 'c',
          size: 200,
          kind: ArtKind.artist,
          playing: true,
          progress: 0.3,
        ),
      ),
      ArtShape.circle,
    );
    // The ring is the playing sign: no equalizer on an artwork that carries one.
    expect(find.byType(VEqualizer), findsNothing);
  });
}
