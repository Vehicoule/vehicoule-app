// Polish (round 6): header, times, download, timer, theme from the artwork, ring track,
// Vague height, motion, focus, pure black, sliders.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart'
    show
        M3EProgressIndicator,
        M3ESlider,
        M3EButton,
        M3ETheme,
        M3EExtendedFab,
        M3EFab,
        M3EFabColor;
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

NowPlayingData data({bool liked = true, VCoverTop? coverTop}) => NowPlayingData(
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
  coverTop: coverTop,
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

/// A busy cover: black and white stripes, 8 px wide (no cover art in the repo).
Future<String> stripes(String name) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 112, 112),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  for (var x = 0.0; x < 112; x += 16) {
    c.drawRect(
      Rect.fromLTWH(x, 0, 8, 112),
      Paint()..color = const Color(0xFF000000),
    );
  }
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

  testWidgets('2: the times read the ring, centred right under it', (
    tester,
  ) async {
    await show(tester, player());
    final art = tester.getRect(find.byKey(VNowPlaying.artworkKey));
    final times = tester.getRect(find.byKey(VNowPlaying.progressKey));
    expect(times.center.dx, closeTo(art.center.dx, 0.5));
    expect(times.top, greaterThanOrEqualTo(art.bottom));
    expect(
      times.top,
      lessThanOrEqualTo(art.bottom + VSpace.s8 + 0.5),
      reason: 'right under it',
    );
  });

  testWidgets('3: a download shows its icon in a progress ring, then filled', (
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
      find.byWidgetPredicate(
        (w) => w is VSymbol && w.icon == VIcons.downloaded && w.filled,
      ),
      findsOneWidget,
    );
    expect(find.byType(M3EProgressIndicator), findsNothing);
  });

  testWidgets('4: the timer is a tonal chip before the header actions', (
    tester,
  ) async {
    await show(tester, player());
    final chip = tester.getRect(find.text('24 min'));
    final more = tester.getRect(find.bySemanticsLabel("Plus d'options"));
    final label = tester.getRect(find.text('Lecture depuis'));
    expect(chip.center.dy, closeTo(more.center.dy, 4));
    expect(chip.left, greaterThan(label.right));
    expect(chip.right, lessThanOrEqualTo(more.left));
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
      // No stop indicator on a closed ring (ring_test: no played dot before 12).
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
    // Under the wave: its times, then the title, no dead band.
    expect(title.top - art.bottom, lessThanOrEqualTo(3 * VSpace.s32));
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

  // I-2 (surface scrim) is superseded by N-1 (dark scrim, ruling).

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

  // Fix pass 2.

  testWidgets('V-1: the cover\'s top band is measured with the seed, once', (
    tester,
  ) async {
    late String white, black, busy;
    VCoverTop? w, k, z;
    var quantized = 0;
    await tester.runAsync(() async {
      white = await swatch(const Color(0xFFFFFFFF), 'v1white');
      black = await swatch(const Color(0xFF000000), 'v1black');
      busy = await stripes('v1busy');
      w = await coverTopFromArtwork(white);
      k = await coverTopFromArtwork(black);
      await seedFromArtwork(busy);
      quantized = debugQuantizations;
      z = await coverTopFromArtwork(busy);
    });
    expect(debugQuantizations, quantized, reason: 'cached with the seed');
    expect(w!.low, greaterThan(0.9));
    expect(k!.high, lessThan(0.05));
    expect(z!.low, lessThan(0.05));
    expect(z!.high, greaterThan(0.9));
    expect(vOnCoverFor(w), VOnCover.dark);
    expect(vOnCoverFor(k), VOnCover.light);
    expect(vOnCoverFor(z), VOnCover.scrim);
    expect(vOnCoverFor(null), VOnCover.scrim, reason: 'unknown: safe');
  });

  testWidgets('V-2: the Vague header adapts to its cover (4.5:1, 3:1)', (
    tester,
  ) async {
    final covers = <String, (VCoverTop, List<Color>)>{};
    await tester.runAsync(() async {
      for (final (name, c) in [
        ('white', const Color(0xFFFFFFFF)),
        ('black', const Color(0xFF000000)),
        ('grey', const Color(0xFF808080)),
      ]) {
        covers[name] = (
          (await coverTopFromArtwork(await swatch(c, 'v2$name')))!,
          [c],
        );
      }
      covers['busy'] = (
        (await coverTopFromArtwork(await stripes('v2busy')))!,
        const [Color(0xFF000000), Color(0xFFFFFFFF)],
      );
    });
    for (final b in Brightness.values) {
      for (final MapEntry(key: name, value: (top, under)) in covers.entries) {
        await tester.pumpWidget(
          harness(
            player(
              style: PlayerStyle.wave,
              d: data(coverTop: top),
            ),
            reduce: true,
            brightness: b,
          ),
        );
        await tester.pump();
        final scrim = find.byKey(VNowPlaying.scrimKey);
        if (name != 'busy') {
          expect(scrim, findsNothing, reason: '$b $name: no scrim needed');
        } else {
          expect(scrim, findsOneWidget, reason: '$b busy: a scrim');
        }
        double alphaAt(double y) {
          if (scrim.evaluate().isEmpty) return 0;
          final g =
              (tester.widget<DecoratedBox>(scrim).decoration as BoxDecoration)
                      .gradient!
                  as LinearGradient;
          final box = tester.getRect(scrim);
          // Eased: no flat hold, a soft end.
          expect(g.colors.length, greaterThanOrEqualTo(6));
          expect(g.colors[1].a, lessThan(g.colors[0].a));
          expect(g.colors.last.a, 0);
          final t = ((y - box.top) / box.height).clamp(0.0, 1.0);
          final st = g.stops!;
          for (var i = 1; i < st.length; i++) {
            if (t <= st[i]) {
              final f = (t - st[i - 1]) / (st[i] - st[i - 1]);
              return g.colors[i - 1].a +
                  (g.colors[i].a - g.colors[i - 1].a) * f;
            }
          }
          return 0;
        }

        Color bg(Element e, double y, Color cover) {
          var c = Color.alphaBlend(
            const Color(0xFF000000).withValues(alpha: alphaAt(y)),
            cover,
          );
          e.visitAncestorElements((a) {
            final w = a.widget;
            if (w is DecoratedBox && w.decoration is ShapeDecoration) {
              final fill = (w.decoration as ShapeDecoration).color;
              if (fill != null) c = Color.alphaBlend(fill, c);
              return false;
            }
            return a.widget.key != VNowPlaying.headerKey;
          });
          return c;
        }

        final header = find.byKey(VNowPlaying.headerKey);
        for (final cover in under) {
          for (final e
              in find
                  .descendant(of: header, matching: find.byType(RichText))
                  .evaluate()) {
            final t = e.widget as RichText;
            final r = tester.getRect(find.byElementPredicate((x) => x == e));
            expect(
              contrast(t.text.style!.color!, bg(e, r.bottom, cover)),
              greaterThanOrEqualTo(4.5),
              reason: '$b $name « ${t.text.toPlainText()} » over $cover',
            );
          }
          for (final e
              in find
                  .descendant(of: header, matching: find.byType(Icon))
                  .evaluate()) {
            final r = tester.getRect(find.byElementPredicate((x) => x == e));
            final color = (e.widget as Icon).color ?? IconTheme.of(e).color!;
            expect(
              contrast(color, bg(e, r.bottom, cover)),
              greaterThanOrEqualTo(3),
              reason: '$b $name icon over $cover',
            );
          }
        }
      }
    }
  });

  Widget dock(List<int> tapped, {bool fab = true}) => VFabDock(
    body: ListView(
      children: [
        for (var i = 0; i < 40; i++)
          ListTile(title: Text('Ligne $i'), onTap: () => tapped.add(i)),
      ],
    ),
    fab: fab ? VAction('Lire', VIcons.play, noop) : null,
    player: player(size: PlayerSize.compact),
  );

  testWidgets('N-2: the phone FAB is extended, secondary, above the ⏯', (
    tester,
  ) async {
    await show(tester, dock([]), size: const Size(412, 800));
    final fab = find.descendant(
      of: find.byType(VFabDock),
      matching: find.byType(M3EExtendedFab),
    );
    expect(tester.widget<M3EExtendedFab>(fab).color, M3EFabColor.secondary);
    expect(tester.widget<M3EExtendedFab>(fab).extended, isTrue);
    expect(
      find.descendant(of: find.byType(VFabDock), matching: find.text('Lire')),
      findsOneWidget,
    );
    final play = find.byType(VPlayPauseFab);
    expect(
      tester
          .widget<M3EFab>(
            find.descendant(of: play, matching: find.byType(M3EFab)),
          )
          .color,
      M3EFabColor.primary,
    );
    // The real mini player: right edges aligned, 16 dp to the ⏯.
    final f = tester.getRect(fab), p = tester.getRect(play);
    expect(f.right, closeTo(p.right, 0.5));
    expect(p.top - f.bottom, closeTo(VSpace.s16, 0.5));
    // Hides on scroll down, back on scroll up.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Lire'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(find.text('Lire'), findsOneWidget);
  });

  testWidgets('V-4: a hiding FAB leaves hit testing and semantics at once', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var pressed = 0;
    await show(
      tester,
      VFabDock(
        body: ListView(
          children: [for (var i = 0; i < 40; i++) ListTile(title: Text('$i'))],
        ),
        fab: VAction('Lire', VIcons.play, () => pressed++),
        player: player(size: PlayerSize.compact),
      ),
      size: const Size(412, 800),
      reduce: false,
    );
    await tester.pump(const Duration(seconds: 1));
    final was = tester.getRect(find.byType(M3EExtendedFab));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // Mid-way through hiding: still painted, but out of reach.
    expect(find.byType(M3EExtendedFab), findsOneWidget);
    expect(find.semantics.byLabel('Lire'), findsNothing);
    await tester.tapAt(was.center);
    await tester.pump(const Duration(seconds: 1));
    expect(pressed, 0);
    expect(find.byType(M3EExtendedFab), findsNothing);
    handle.dispose();
  });

  testWidgets('V-3: list rows don\'t show around the mini player', (
    tester,
  ) async {
    await show(tester, dock([], fab: false), size: const Size(412, 800));
    final mini = tester.getRect(find.byKey(VNowPlaying.compactKey));
    final guard = tester.getRect(find.byKey(VFabDock.protectionKey));
    expect(guard.top, lessThanOrEqualTo(mini.top));
    expect(guard.bottom, greaterThanOrEqualTo(mini.bottom));
  });

  testWidgets('N-3: the last row scrolls clear of the dock', (tester) async {
    final tapped = <int>[];
    await show(tester, dock(tapped), size: const Size(412, 800));
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    final last = tester.getRect(find.text('Ligne 39'));
    final mini = tester.getRect(find.byKey(VNowPlaying.compactKey));
    expect(last.bottom, lessThanOrEqualTo(mini.top), reason: 'clear of it');
    // Hit-testable down to its bottom edge.
    final row = tester.getRect(find.widgetWithText(ListTile, 'Ligne 39'));
    await tester.tapAt(Offset(row.center.dx, row.bottom - 1));
    expect(tapped, [39]);
  });
}
