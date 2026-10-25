// Fix round 5 (review 4): dead bands, the Vague bleed, reduce motion in M3E, the dark
// switch, the collapsed rail, list rows, the extent flight hooks, the strip's ⏯, the
// mini player at 200 %, the light ring track.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart'
    show
        M3ETheme,
        M3EListItem,
        M3EMenuItem,
        M3EButtonGroup,
        M3EButtonDecoration;
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/queue.dart';
import 'package:vehicoule/debug/library.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

NowPlayingData data({bool playing = true}) => NowPlayingData(
  track: sampleTracks[1],
  sourceTitle: 'Random Access Memories',
  playing: playing,
  loading: false,
  durationMs: 369000,
  liked: true,
  download: null,
  shuffle: false,
  repeat: Repeat.off,
);

void noop() {}

final actions = NowPlayingActions(
  onPlayPause: noop,
  onNext: noop,
  onPrevious: noop,
  onSeek: (_) {},
  onLike: noop,
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
  Axis axis = Axis.horizontal,
  bool artworkVisible = true,
  ValueChanged<Rect>? onArtworkRect,
}) => VNowPlaying(
  data: data(),
  position: ValueNotifier(120000),
  size: size,
  style: style,
  view: PlayerView.player,
  onView: (_) {},
  actions: actions,
  lyrics: (_) => const SizedBox(),
  queue: (_) => const SizedBox(),
  axis: axis,
  artworkVisible: artworkVisible,
  onArtworkRect: onArtworkRect,
);

Future<void> show(
  WidgetTester tester,
  Widget w, {
  Size size = const Size(412, 892),
  bool reduce = true,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness(w, reduce: reduce, brightness: brightness));
  await tester.pump();
  await tester.pump(VDurations.short);
}

void main() {
  testWidgets('I-1: no dead band in the large phone player', (tester) async {
    await show(tester, player());
    final header = tester.getRect(find.byKey(VNowPlaying.headerKey));
    final art = tester.getRect(find.byKey(VNowPlaying.artworkKey));
    final controls = tester.getRect(find.byKey(VNowPlaying.controlsKey));
    final selector = tester.getRect(find.byKey(VNowPlaying.selectorKey));
    expect(art.top - header.bottom, lessThanOrEqualTo(VSpace.s32));
    expect(
      selector.top - controls.bottom,
      lessThanOrEqualTo(VSpace.s32 + VSpace.s16),
    );
    // Large controls where the height allows it.
    expect(controls.height, greaterThanOrEqualTo(VSize.controlTall));
  });

  testWidgets('I-2: the Vague artwork runs under the header to the top', (
    tester,
  ) async {
    await show(tester, player(style: PlayerStyle.wave));
    final header = tester.getRect(find.byKey(VNowPlaying.headerKey));
    final art = tester.getRect(find.byKey(VNowPlaying.artworkKey));
    expect(art.top, lessThanOrEqualTo(header.top + 0.5));
    expect(art.width, closeTo(412, 0.5));
  });

  testWidgets('I-3: reduce motion makes the M3E springs instant', (
    tester,
  ) async {
    late BuildContext ctx;
    Widget probe() => Builder(
      builder: (c) {
        ctx = c;
        return const SizedBox();
      },
    );
    await show(tester, probe(), reduce: true);
    var t = M3ETheme.of(ctx);
    for (final s in [
      t.buttonGroupTheme.neighborSquishSpring,
      t.buttonTheme.shapeSpring,
      t.toolbarTheme.labelSpring,
      t.toolbarTheme.expandSpring,
    ]) {
      expect(s.stiffness, greaterThanOrEqualTo(10000));
      expect(s.damping, 1);
    }
    await show(tester, probe(), reduce: false);
    t = M3ETheme.of(ctx);
    expect(t.buttonTheme.shapeSpring.stiffness, lessThan(10000));
  });

  testWidgets('I-4: the switch off state reads in dark (thumb, outline)', (
    tester,
  ) async {
    for (final b in Brightness.values) {
      await show(
        tester,
        Center(
          child: VListGroup(
            title: 'g',
            children: [
              VListRow(
                title: 'Noir pur',
                trailing: VSwitch(value: false, onChanged: (_) {}, label: 'n'),
              ),
            ],
          ),
        ),
        brightness: b,
      );
      final s = Theme.of(tester.element(find.byType(VSwitch))).colorScheme;
      final boxes = tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: find.byType(VSwitch),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>();
      final track = boxes.firstWhere((d) => d.border != null);
      final border = (track.border! as Border).top.color;
      expect(
        contrast(border, track.color!),
        greaterThanOrEqualTo(3),
        reason: '$b outline on track',
      );
      expect(
        contrast(border, s.surfaceContainer),
        greaterThanOrEqualTo(3),
        reason: '$b outline on its group',
      );
      final thumb = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(VSwitch),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.shape == BoxShape.circle && (d.color?.a ?? 0) > 0.5)
          .single;
      expect(
        contrast(thumb.color!, track.color!),
        greaterThanOrEqualTo(3),
        reason: '$b thumb on track',
      );
    }
  });

  testWidgets('I-5: the collapsed rail shows icons and artworks only', (
    tester,
  ) async {
    Widget rail(bool expanded) => VNavigationRail(
      destinations: const [
        VDestination('Accueil', VIcons.home),
        VDestination('Bibliothèque', VIcons.library),
      ],
      pinned: const [VPinned('playlist:x', 'Titres likés')],
      selected: 0,
      onSelected: (_) {},
      expanded: expanded,
      onExpanded: (_) {},
    );
    await show(tester, rail(false), size: const Size(800, 700));
    expect(find.text('Bibliothèque'), findsNothing);
    expect(find.text('Titres likés'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Bibliothèque')), findsWidgets);
    await show(tester, rail(true), size: const Size(800, 700));
    expect(find.text('Bibliothèque'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('I-6: a settings row is the M3E list item', (tester) async {
    await show(
      tester,
      VListGroup(
        title: 'g',
        children: [
          VListRow(
            title: 'Radio',
            subtitle: 'quand la file se termine',
            onTap: noop,
          ),
          VListRow(
            below: VChoiceGroup<int>(
              choices: const [(0, 'a'), (1, 'b')],
              value: 0,
              onChanged: (_) {},
            ),
          ),
        ],
      ),
    );
    expect(find.byType(M3EListItem), findsOneWidget);
    expect(find.text('Radio'), findsOneWidget);
  });

  testWidgets('I-7: the player reports where its artwork is and can hide it', (
    tester,
  ) async {
    final rects = <Rect>[];
    await show(tester, player(onArtworkRect: rects.add));
    await tester.pump();
    expect(rects, isNotEmpty);
    expect(rects.last, tester.getRect(find.byKey(VNowPlaying.artworkKey)));
    // The mini player reports its own artwork too: the two ends of the flight.
    final mini = <Rect>[];
    await show(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: player(size: PlayerSize.compact, onArtworkRect: mini.add),
      ),
    );
    await tester.pump();
    expect(mini.last, tester.getRect(find.byType(VArtwork)));
    // Hidden while the flight draws it.
    await show(tester, player(artworkVisible: false));
    final hide = tester.widget<Opacity>(
      find
          .ancestor(of: find.byType(VArtwork), matching: find.byType(Opacity))
          .first,
    );
    expect(hide.opacity, 0);
  });

  testWidgets('I-8: the strip ⏯ is a round, non-toggle button', (tester) async {
    await show(
      tester,
      Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: VSize.strip,
          child: player(size: PlayerSize.compact, axis: Axis.vertical),
        ),
      ),
    );
    final play = tester.widget<VIconButton>(
      find
          .ancestor(
            of: find.bySemanticsLabel('Mettre en pause'),
            matching: find.byType(VIconButton),
          )
          .first,
    );
    expect(play.selected, isNull);
    expect(play.style, VIconStyle.filled);
  });

  testWidgets('I-10: the mini player grows with the text up to 200 %', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = old);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: player(size: PlayerSize.compact),
      ),
      size: const Size(412, 800),
    );
    FlutterError.onError = old;
    for (final e in errors) {
      debugPrint(e.toString());
    }
    expect(errors.map((e) => e.exceptionAsString()), isEmpty);
    final title = tester.widget<RichText>(
      find.descendant(
        of: find.text('Get Lucky'),
        matching: find.byType(RichText),
      ),
    );
    expect(title.textScaler.scale(10), 20, reason: 'really 200 %');
    final r = tester.getRect(find.text('Get Lucky'));
    expect(r.height, greaterThanOrEqualTo(32));
  });

  testWidgets('light ring: the unplayed track shows on the tinted player', (
    tester,
  ) async {
    for (final b in Brightness.values) {
      await show(
        tester,
        const Center(
          child: VArtwork(
            itemId: 'a',
            size: 200,
            playing: false,
            progress: 0.3,
          ),
        ),
        brightness: b,
      );
      final s = Theme.of(tester.element(find.byType(VArtwork))).colorScheme;
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<VRingPainter>()
          .single;
      // The player's background (a plain surfaceContainer) and the screens' surface.
      for (final bg in [s.surfaceContainer, s.surface]) {
        final track = Color.alphaBlend(painter.track, bg);
        expect(
          contrast(track, bg),
          greaterThanOrEqualTo(1.8),
          reason: '$b track on $bg',
        );
        expect(
          contrast(painter.played, track),
          greaterThanOrEqualTo(1.5),
          reason: '$b played vs track',
        );
      }
    }
  });

  testWidgets('menu: the M3E vertical menu, its quick row the first section', (
    tester,
  ) async {
    late BuildContext ctx;
    await show(
      tester,
      Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        },
      ),
    );
    VAction a(String l) => VAction(l, VIcons.album, () {});
    showVMenu(
      ctx,
      anchor: const Rect.fromLTWH(300, 100, 48, 48),
      quick: [a('Lire ensuite'), a('Ajouter à la file')],
      groups: [
        [a('Ajouter à une playlist'), a('Télécharger')],
        [a('Retirer')],
      ],
    );
    await tester.pump();
    await tester.pump();
    final panel = tester.getRect(find.byKey(VMenu.panelKey));
    final quick = tester.getRect(find.byKey(VMenu.quickKey));
    expect(quick.top, closeTo(panel.top, 0.5), reason: 'first section');
    expect(quick.width, closeTo(panel.width, 0.5), reason: 'inside the menu');
    final m = M3ETheme.of(tester.element(find.byKey(VMenu.panelKey))).menuTheme;
    final surfaces = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(VMenu.panelKey),
            matching: find.byType(DecoratedBox),
          ),
        )
        .where((d) => d.decoration is ShapeDecoration)
        .toList();
    expect(surfaces, hasLength(3), reason: 'quick row + 2 groups');
    final rects = [for (final d in surfaces) tester.getRect(find.byWidget(d))]
      ..sort((x, y) => x.top.compareTo(y.top));
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].top - rects[i - 1].bottom, closeTo(m.sectionGap, 0.5));
    }
    // M3 menu items: 48 high.
    expect(
      tester.getSize(find.byType(M3EMenuItem).first).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('the player sits on a plain surface, no gradient', (
    tester,
  ) async {
    await show(tester, player());
    final s = Theme.of(tester.element(find.byType(VNowPlaying))).colorScheme;
    expect(
      find.descendant(
        of: find.byType(VNowPlaying),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == s.surfaceContainer,
        ),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(VNowPlaying),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient != null,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('a small ring is thinner and closer', (tester) async {
    await show(
      tester,
      const Center(
        child: VArtwork(
          itemId: 'a',
          size: VSize.compactArt,
          playing: true,
          progress: 0.3,
        ),
      ),
    );
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<VRingPainter>()
        .single;
    expect(painter.stroke, VSize.ringStrokeSmall);
  });

  testWidgets('B-1: the strip ⏯ and ⏭ have filled glyphs', (tester) async {
    await show(
      tester,
      Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: VSize.strip,
          child: player(size: PlayerSize.compact, axis: Axis.vertical),
        ),
      ),
    );
    for (final icon in [VIcons.pause, VIcons.skipNext]) {
      final symbol = tester.widget<VSymbol>(
        find.byWidgetPredicate((w) => w is VSymbol && w.icon == icon),
      );
      expect(symbol.filled, isTrue, reason: '$icon');
    }
  });

  testWidgets('B-2: the Vague cover runs under the status bar', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(player(style: PlayerStyle.wave), reduce: true),
    );
    await tester.pump();
    final art = tester.getRect(find.byKey(VNowPlaying.artworkKey));
    final header = tester.getRect(find.byKey(VNowPlaying.headerKey));
    expect(art.top, 0);
    expect(
      header.top,
      greaterThanOrEqualTo(24),
      reason: 'the header clears it',
    );
    // The Disc keeps its safe area.
    await tester.pumpWidget(harness(player(), reduce: true));
    await tester.pump();
    expect(
      tester.getRect(find.byKey(VNowPlaying.headerKey)).top,
      greaterThanOrEqualTo(24),
    );
  });

  testWidgets('selected toggles are primary, like ⏯ and the selector', (
    tester,
  ) async {
    await show(
      tester,
      Column(
        children: [
          VConnectedGroup(
            actions: [VAction('a', VIcons.favorite, () {}, selected: true)],
          ),
          VChoiceGroup<int>(
            choices: const [(0, 'a'), (1, 'b')],
            value: 0,
            onChanged: (_) {},
          ),
          VControls(
            playing: true,
            loading: false,
            shuffle: true,
            repeat: Repeat.all,
            onPlayPause: () {},
            onNext: () {},
            onPrevious: () {},
            onShuffle: () {},
            onRepeat: () {},
          ),
        ],
      ),
    );
    final s = Theme.of(tester.element(find.byType(VControls))).colorScheme;
    const selected = {WidgetState.selected};
    for (final g in tester.widgetList<M3EButtonGroup>(
      find.byType(M3EButtonGroup),
    )) {
      final decorations = [
        g.decoration,
        for (final a in g.actions) a.decoration,
      ].whereType<M3EButtonDecoration>();
      expect(decorations, isNotEmpty);
      for (final d in decorations) {
        expect(d.backgroundColor?.resolve(selected), s.primary);
      }
    }
  });
}
