// Polish (round 6): header, times, download, timer, theme from the artwork, ring track,
// Vague height, motion, focus, pure black, sliders.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart'
    show M3EProgressIndicator, M3ESlider, M3EButton, M3ETheme, M3EExtendedFab;
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/downloads.dart';
import 'package:vehicoule/bridge/queue.dart';
import 'package:vehicoule/debug/library.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/design/gallery.dart';
import 'package:vehicoule/l10n/app_localizations.dart';

import 'harness.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

NowPlayingData data({bool liked = true}) => NowPlayingData(
  track: sampleTracks[1],
  sourceTitle: 'Random Access Memories',
  playing: true,
  loading: false,
  durationMs: 369000,
  liked: liked,
  download: null,
  shuffle: false,
  repeat: Repeat.off,
  sleepLeft: const Duration(minutes: 24),
);

void noop() {}

NowPlayingActions acts({VoidCallback? onLike}) => NowPlayingActions(
  onPlayPause: noop,
  onNext: noop,
  onPrevious: noop,
  onSeek: (_) {},
  onLike: onLike ?? noop,
  onAddToPlaylist: noop,
  onDownload: noop,
  onShuffle: noop,
  onRepeat: noop,
  onOutput: noop,
  onMenu: (_) {},
  onCollapse: noop,
  onOpen: noop,
  onStop: noop,
);

VNowPlaying player({
  PlayerSize size = PlayerSize.large,
  PlayerStyle style = PlayerStyle.disc,
  NowPlayingData? d,
}) => VNowPlaying(
  data: d ?? data(),
  position: ValueNotifier(120000),
  size: size,
  style: style,
  view: PlayerView.player,
  onView: (_) {},
  actions: acts(),
  lyrics: (_) => const SizedBox(),
  queue: (_) => const SizedBox(),
);

Future<void> show(
  WidgetTester tester,
  Widget w, {
  Size size = const Size(412, 892),
  bool reduce = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness(w, reduce: reduce));
  await tester.pump();
  await tester.pump(VDurations.short);
}

/// A generated one-colour 112 px PNG (no cover art in the repo).
Future<String> swatch(Color c, String name) async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec)
      .drawRect(const Rect.fromLTWH(0, 0, 112, 112), Paint()..color = c);
  final img = await rec.endRecording().toImage(112, 112);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  final f = File(
    '${Directory.systemTemp.createTempSync('vswatch').path}/$name.png',
  )..writeAsBytesSync(png!.buffer.asUint8List());
  return f.path;
}

void main() {
  testWidgets('1: header actions are standard icon buttons', (tester) async {
    await show(tester, player());
    for (final l in ['Réduire', 'Sortie audio', "Plus d'options"]) {
      final b = tester.widget<VIconButton>(
        find
            .ancestor(
              of: find.bySemanticsLabel(l),
              matching: find.byType(VIconButton),
            )
            .first,
      );
      expect(b.style, VIconStyle.standard, reason: l);
    }
  });

  testWidgets('2: the times flank the base of the ring', (tester) async {
    await show(tester, player());
    final art = tester.getRect(find.byKey(VNowPlaying.artworkKey));
    final times = tester.getRect(find.byKey(VNowPlaying.progressKey));
    expect(times.left, closeTo(art.left, VSpace.s16));
    expect(times.right, closeTo(art.right, VSpace.s16));
    expect(times.top, greaterThanOrEqualTo(art.bottom - VSpace.s32));
    expect(
      times.bottom,
      lessThanOrEqualTo(art.bottom + VSpace.s24),
      reason: 'right under it',
    );
  });

  testWidgets('3: a download shows its icon in a progress ring, then a check', (
    tester,
  ) async {
    await show(
      tester,
      const VDownloadIcon(state: DownloadStateView.running, progress: 0.4),
    );
    expect(
      find.byWidgetPredicate((w) => w is VSymbol && w.icon == VIcons.download),
      findsOneWidget,
    );
    expect(find.byType(M3EProgressIndicator), findsOneWidget);
    await show(tester, const VDownloadIcon(state: DownloadStateView.done));
    expect(
      find.byWidgetPredicate((w) => w is VSymbol && w.icon == VIcons.check),
      findsOneWidget,
    );
    expect(find.byType(M3EProgressIndicator), findsNothing);
  });

  testWidgets('4: the timer is a tonal chip beside the output', (tester) async {
    await show(tester, player());
    final chip = tester.getRect(find.text('24 min'));
    final output = tester.getRect(find.bySemanticsLabel('Sortie audio'));
    final label = tester.getRect(find.text('Lecture depuis'));
    expect(chip.center.dy, closeTo(output.center.dy, 4));
    expect(chip.left, greaterThan(label.right));
    expect(chip.right, lessThanOrEqualTo(output.left));
  });

  testWidgets('5: the theme follows the playing artwork', (tester) async {
    late String red, blue;
    await tester.runAsync(() async {
      red = await swatch(const Color(0xFFD32F2F), 'red');
      blue = await swatch(const Color(0xFF1565C0), 'blue');
    });
    // A different picture gives a different seed.
    Color? a, b;
    await tester.runAsync(() async {
      a = await seedFromArtwork(red);
      b = await seedFromArtwork(blue);
    });
    expect(a, isNotNull);
    expect(a, isNot(b));
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GalleryApp(seedFile: (id) async => id == sampleTracks[1].id ? red : blue),
    );
    Future<Color> primary() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
      return Theme.of(tester.element(find.byType(Scaffold).first))
          .colorScheme
          .primary;
    }

    final first = await primary();
    final l = lookupAppLocalizations(const Locale('fr'));
    await tester.tap(find.widgetWithText(VButton, l.actionNext).first);
    final next = await primary();
    expect(next, isNot(first), reason: 'a new track retints everything');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('6: the ring track is tinted and visible in every theme', (
    tester,
  ) async {
    for (final (b, black) in [
      (Brightness.light, false),
      (Brightness.dark, false),
      (Brightness.dark, true),
    ]) {
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: vTheme(
            brightness: b,
            seed: VPresets.seeds.first,
            pureBlack: black,
          ),
          home: const Scaffold(
            body: Center(
              child: VArtwork(
                itemId: 'a',
                size: 200,
                playing: false,
                progress: 0.3,
              ),
            ),
          ),
        ),
      );
      final s = Theme.of(tester.element(find.byType(VArtwork))).colorScheme;
      final p = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<VRingPainter>()
          .single;
      expect(
        p.track.withValues(alpha: 1),
        s.secondary,
        reason: 'tinted by the theme',
      );
      for (final bg in [s.surfaceContainer, s.surface]) {
        final t = Color.alphaBlend(p.track, bg);
        expect(contrast(t, bg), greaterThanOrEqualTo(1.8), reason: '$b $black');
      }
      expect(p.stop, isTrue, reason: 'the M3E stop indicator');
    }
    tester.view.reset();
  });

  testWidgets('7: on a tall screen the Vague cover grows to fill the gap', (
    tester,
  ) async {
    await show(
      tester,
      player(style: PlayerStyle.wave),
      size: const Size(412, 892),
    );
    final art = tester.getRect(find.byKey(VNowPlaying.artworkKey));
    final title = tester.getRect(find.byKey(VNowPlaying.titleKey));
    expect(art.height, greaterThan(art.width));
    expect(art.height, lessThanOrEqualTo(art.width * 1.15 + 0.5));
    expect(title.top - art.bottom, lessThanOrEqualTo(VSpace.s32 + VSpace.s16));
  });

  testWidgets('8a: the heart fills with a spring; reduce motion is instant', (
    tester,
  ) async {
    var liked = false;
    await tester.pumpWidget(
      harness(
        StatefulBuilder(
          builder: (context, set) => VIconButton(
            icon: VIcons.favorite,
            label: 'like',
            selected: liked,
            onPressed: () => set(() => liked = !liked),
          ),
        ),
        reduce: false,
      ),
    );
    await tester.tap(find.byType(VIconButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final mid = tester.widget<Icon>(find.byType(Icon)).fill!;
    expect(mid, inExclusiveRange(0, 1), reason: 'animating');
    await tester.pumpAndSettle();
    expect(tester.widget<Icon>(find.byType(Icon)).fill, 1);
    // Reduce motion: no frame in between.
    liked = false;
    await tester.pumpWidget(
      harness(
        StatefulBuilder(
          builder: (context, set) => VIconButton(
            icon: VIcons.favorite,
            label: 'like',
            selected: liked,
            onPressed: () => set(() => liked = !liked),
          ),
        ),
        reduce: true,
      ),
    );
    await tester.tap(find.byType(VIconButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.widget<Icon>(find.byType(Icon)).fill, 1);
  });

  testWidgets('8b: the mini toolbar follows the finger and springs back', (
    tester,
  ) async {
    await show(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: player(size: PlayerSize.compact),
      ),
      reduce: false,
    );
    final title = find.text('Get Lucky');
    final start = tester.getCenter(title);
    final g = await tester.startGesture(start);
    await g.moveBy(const Offset(-30, 0));
    await g.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(
      tester.getCenter(title).dx,
      lessThan(start.dx - 20),
      reason: 'follows',
    );
    await g.up();
    await tester.pump(const Duration(milliseconds: 50));
    final mid = tester.getCenter(title).dx;
    expect(mid, lessThan(start.dx), reason: 'still springing back');
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getCenter(title).dx, closeTo(start.dx, 0.5));
  });

  testWidgets('8c: the selector widths morph; instant with reduce motion', (
    tester,
  ) async {
    var view = PlayerView.player;
    Widget sel() => Center(
      child: StatefulBuilder(
        builder: (context, set) =>
            VViewSelector(value: view, onChanged: (v) => set(() => view = v)),
      ),
    );
    await show(tester, sel(), reduce: false);
    final before = tester.getSize(find.bySemanticsLabel('Paroles').first).width;
    await tester.tap(find.bySemanticsLabel('Paroles').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final mid = tester.getSize(find.bySemanticsLabel('Paroles').first).width;
    await tester.pumpAndSettle();
    final after = tester.getSize(find.bySemanticsLabel('Paroles').first).width;
    expect(after, greaterThan(before));
    expect(mid, inExclusiveRange(before, after), reason: 'morphs');
  });

  testWidgets('8d: a pressed control widens (button group squish)', (
    tester,
  ) async {
    await show(
      tester,
      Center(
        child: SizedBox(
          width: 380,
          child: VControls(
            playing: true,
            loading: false,
            shuffle: false,
            repeat: Repeat.off,
            onPlayPause: noop,
            onNext: noop,
            onPrevious: noop,
            onShuffle: noop,
            onRepeat: noop,
          ),
        ),
      ),
      reduce: false,
    );
    final f = find.byType(M3EButton).at(3);
    final rest = tester.getSize(f).width;
    final g = await tester.startGesture(tester.getCenter(f));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(tester.getSize(f).width, greaterThan(rest));
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('11: sliders use the thicker M3E sizes from the tokens', (
    tester,
  ) async {
    await show(
      tester,
      Column(
        children: [
          VSlider(value: 0.5, onChanged: (_) {}, label: 's'),
          VVolume(value: 0.5, onChanged: (_) {}),
        ],
      ),
    );
    final sliders = tester
        .widgetList<M3ESlider>(find.byType(M3ESlider))
        .toList();
    expect(sliders[0].size.trackHeight, VSize.sliderTrack);
    expect(sliders[1].size.trackHeight, VSize.volumeTrack);
    expect(VSize.sliderTrack, greaterThanOrEqualTo(24));
  });

  test('8e: the spring curve lands on 1 and is not the standard easing', () {
    expect(VCurves.spring.transform(0), 0);
    expect(VCurves.spring.transform(1), 1);
    expect(
      (VCurves.spring.transform(0.3) - VCurves.standard.transform(0.3)).abs(),
      greaterThan(0.01),
    );
  });

  // Polish review fixes.

  testWidgets('I-1: no band between the times and the title (Disc)', (
    tester,
  ) async {
    for (final (size, screen) in [
      (PlayerSize.large, const Size(412, 892)),
      (PlayerSize.medium, const Size(360, 800)),
    ]) {
      await show(tester, player(size: size), size: screen);
      final times = tester.getRect(find.byKey(VNowPlaying.progressKey));
      final title = tester.getRect(find.byKey(VNowPlaying.titleKey));
      expect(
        title.top - times.bottom,
        lessThanOrEqualTo(VSpace.s24),
        reason: '$size: the title follows the times',
      );
    }
  });

  testWidgets('I-2: the Vague header reads on any cover (scrim ≥ 3:1)', (
    tester,
  ) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(
        harness(player(style: PlayerStyle.wave), reduce: true, brightness: b),
      );
      await tester.pump();
      final scrim = tester.widget<DecoratedBox>(
        find.byKey(VNowPlaying.scrimKey),
      );
      final g = (scrim.decoration as BoxDecoration).gradient! as LinearGradient;
      final cs = Theme.of(tester.element(find.byType(VNowPlaying))).colorScheme;
      expect(g.colors.first.withValues(alpha: 1), cs.surface);
      // The header's icons sit within the scrim's solid part.
      final box = tester.getRect(find.byKey(VNowPlaying.scrimKey));
      final icons = tester.getRect(find.bySemanticsLabel('Réduire'));
      expect(
        icons.bottom,
        lessThanOrEqualTo(box.top + box.height * g.stops![1]),
      );
      for (final cover in [const Color(0xFF000000), const Color(0xFFFFFFFF)]) {
        final under = Color.alphaBlend(g.colors.first, cover);
        expect(
          contrast(cs.onSurfaceVariant, under),
          greaterThanOrEqualTo(3),
          reason: '$b over $cover',
        );
      }
    }
  });

  testWidgets('I-3: pure black keeps the full-screen player at 0', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        player(),
        reduce: true,
        brightness: Brightness.dark,
        pureBlack: true,
      ),
    );
    await tester.pump();
    final bg = tester
        .widget<ColoredBox>(
          find
              .descendant(
                of: find.byType(VNowPlaying),
                matching: find.byType(ColoredBox),
              )
              .first,
        )
        .color;
    expect(bg, const Color(0xFF000000));
  });

  testWidgets('I-4: a colourless cover gives the fallback seed, not the last', (
    tester,
  ) async {
    late String red, grey;
    await tester.runAsync(() async {
      red = await swatch(const Color(0xFFD32F2F), 'red4');
      grey = await swatch(const Color(0xFF808080), 'grey4');
    });
    const fallback = Color(0xFF6F8F72);
    Color? s;
    await tester.runAsync(() async {
      s = await seedForArtwork(grey, fallback: fallback);
    });
    expect(s, fallback);
    // In the gallery: red, then grey → the preset's theme, not red's.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GalleryApp(seedFile: (id) async => id == sampleTracks[1].id ? red : grey),
    );
    Future<Color> primary() async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
      return Theme.of(tester.element(find.byType(Scaffold).first))
          .colorScheme
          .primary;
    }

    final preset = vTheme(
      brightness: Brightness.light,
      seed: VPresets.seeds.first,
    ).colorScheme.primary;
    expect(await primary(), isNot(preset), reason: 'red first');
    final l = lookupAppLocalizations(const Locale('fr'));
    await tester.tap(find.widgetWithText(VButton, l.actionNext).first);
    expect(await primary(), preset, reason: 'grey falls back');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('I-5: reduce motion makes the FAB menu instant', (tester) async {
    await show(tester, const SizedBox());
    final t = M3ETheme.of(tester.element(find.byType(SizedBox).last))
        .fabMenuTheme;
    expect(t.expandSpring.stiffness, greaterThanOrEqualTo(10000));
    expect(t.fabShapeSpring.stiffness, greaterThanOrEqualTo(10000));
    expect(t.expandStagger, Duration.zero);
  });

  testWidgets('I-5: reduce motion swaps the extended FAB without a morph', (
    tester,
  ) async {
    Widget fab(bool e) => Center(
      child: VExtendedFab(
        icon: VIcons.add,
        label: 'Ajouter une source',
        extended: e,
        onPressed: noop,
      ),
    );
    await show(tester, fab(true));
    final wide = tester.getSize(find.byType(VExtendedFab)).width;
    await tester.pumpWidget(harness(fab(false), reduce: true));
    await tester.pump(const Duration(milliseconds: 16));
    // One frame on, the newest FAB is already the collapsed one (it fades in).
    expect(
      tester.getSize(find.byType(M3EExtendedFab).last).width,
      lessThan(wide / 2),
      reason: 'no width spring',
    );
  });
}
