import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart'
    show M3EFab, M3EToolbar;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/queue.dart';
import 'package:vehicoule/debug/library.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

NowPlayingData data({
  bool playing = true,
  bool loading = false,
  Duration? sleepLeft,
}) => NowPlayingData(
  track: sampleTracks[1],
  sourceTitle: 'Random Access Memories',
  playing: playing,
  loading: loading,
  durationMs: 369000,
  sleepLeft: sleepLeft,
  liked: true,
  download: null,
  shuffle: false,
  repeat: Repeat.off,
);

final calls = <String>[];
final actions = NowPlayingActions(
  onPlayPause: () => calls.add('playPause'),
  onNext: () => calls.add('next'),
  onPrevious: () => calls.add('previous'),
  onSeek: (ms) => calls.add('seek $ms'),
  onLike: () => calls.add('like'),
  onAddToPlaylist: () => calls.add('add'),
  onDownload: () => calls.add('download'),
  onShuffle: () => calls.add('shuffle'),
  onRepeat: () => calls.add('repeat'),
  onOutput: () => calls.add('output'),
  onMenu: (_) => calls.add('menu'),
  onCollapse: () => calls.add('collapse'),
  onOpen: () => calls.add('open'),
  onStop: () => calls.add('stop'),
);

Widget player({
  PlayerSize size = PlayerSize.large,
  PlayerStyle style = PlayerStyle.disc,
  PlayerView view = PlayerView.player,
  NowPlayingData? d,
  ValueChanged<PlayerView>? onView,
  Axis axis = Axis.horizontal,
  ValueListenable<int>? position,
  bool immersive = false,
  VoidCallback? onImmersive,
}) => VNowPlaying(
  data: d ?? data(),
  position: position ?? ValueNotifier(120000),
  size: size,
  style: style,
  view: view,
  onView: onView ?? (_) {},
  actions: actions,
  lyrics: (_) => const Text('lyrics body'),
  queue: (_) => const Text('queue body'),
  axis: axis,
  immersive: immersive,
  onImmersive: onImmersive,
);

Future<void> show(
  WidgetTester tester,
  Widget w, {
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness(w, reduce: true));
  await tester.pump();
  // M3E button groups run a short selection timer on update.
  await tester.pump(VDurations.short);
}

/// The playing cookie turns forever: wait for the transitions only.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(VDurations.medium);
  await tester.pump(VDurations.medium);
}

void main() {
  layoutTests();
  testWidgets('VNowPlaying keeps the block order in every size and style', (
    tester,
  ) async {
    for (final size in [PlayerSize.medium, PlayerSize.large]) {
      for (final style in PlayerStyle.values) {
        await show(tester, player(size: size, style: style));
        final why = '$size $style';
        double top(Key k) {
          expect(find.byKey(k), findsOneWidget, reason: '$why: $k');
          return tester.getTopLeft(find.byKey(k)).dy;
        }

        final order = [
          VNowPlaying.headerKey,
          VNowPlaying.artworkKey,
          VNowPlaying.titleKey,
          VNowPlaying.actionsKey,
          VNowPlaying.controlsKey,
          VNowPlaying.selectorKey,
        ].map(top).toList();
        for (var i = 1; i < order.length; i++) {
          // The Vague runs under the header, from the top (lecteur-v3, style C).
          if (i == 1 && style == PlayerStyle.wave) {
            expect(
              order[1],
              lessThanOrEqualTo(order[0]),
              reason: '$why: bleeds',
            );
            continue;
          }
          expect(order[i], greaterThan(order[i - 1]), reason: '$why: block $i');
        }
        final times = top(VNowPlaying.progressKey);
        if (style == PlayerStyle.wave) {
          final title = tester.getRect(find.byKey(VNowPlaying.titleKey));
          expect(
            times - title.bottom,
            greaterThanOrEqualTo(VSpace.s8),
            reason: 'a gap under the artists',
          );
        }
        expect(
          times,
          greaterThan(order[1]),
          reason: '$why: times under the artwork',
        );
        expect(
          times,
          lessThan(order[4]),
          reason: '$why: times above the controls',
        );
        expect(find.text('2:00'), findsOneWidget, reason: why);
        expect(find.text('6:09'), findsOneWidget, reason: why);
        expect(find.text('Lecture depuis'), findsOneWidget, reason: why);
        expect(
          find.text('Random Access Memories'),
          findsOneWidget,
          reason: why,
        );
      }
    }
    // Wide (landscape, immersive): artwork left of the blocks.
    await show(
      tester,
      VNowPlaying(
        position: ValueNotifier(120000),
        data: data(),
        size: PlayerSize.large,
        style: PlayerStyle.disc,
        view: PlayerView.player,
        onView: (_) {},
        actions: actions,
        lyrics: (_) => const SizedBox(),
        queue: (_) => const SizedBox(),
        wide: true,
      ),
      size: const Size(1200, 700),
    );
    expect(
      tester.getCenter(find.byKey(VNowPlaying.artworkKey)).dx,
      lessThan(tester.getTopLeft(find.byKey(VNowPlaying.controlsKey)).dx),
    );
  });

  testWidgets(
    'VNowPlaying compact is artwork, title, like and play/pause only',
    (tester) async {
      await show(tester, player(size: PlayerSize.compact));
      expect(find.byType(VArtwork), findsOneWidget);
      expect(find.text('Get Lucky'), findsOneWidget);
      expect(find.bySemanticsLabel("J'aime"), findsOneWidget);
      expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);
      for (final gone in [
        'Titre suivant',
        'Titre précédent',
        'Lecture aléatoire',
        'Paroles',
      ]) {
        expect(find.bySemanticsLabel(gone), findsNothing, reason: gone);
      }
      expect(find.byKey(VNowPlaying.headerKey), findsNothing);
      // The desktop strip: the same bricks in a column, plus next.
      await show(
        tester,
        SizedBox(
          width: VSize.strip,
          child: player(size: PlayerSize.compact, axis: Axis.vertical),
        ),
      );
      expect(find.byType(VArtwork), findsOneWidget);
      expect(find.bySemanticsLabel('Titre suivant'), findsOneWidget);
    },
  );

  testWidgets('view selector switches views and widens the active one', (
    tester,
  ) async {
    final views = <PlayerView>[];
    await show(
      tester,
      Center(
        child: VViewSelector(value: PlayerView.player, onChanged: views.add),
      ),
    );
    final active = tester.getSize(find.bySemanticsLabel('Lecteur').first).width;
    final idle = tester.getSize(find.bySemanticsLabel('Paroles').first).width;
    expect(active, greaterThan(idle));
    expect(find.text('Lecteur'), findsOneWidget);
    expect(
      find.text('Paroles'),
      findsNothing,
      reason: 'only the active one shows its label',
    );
    await tester.tap(find.bySemanticsLabel('Paroles'));
    expect(views, [PlayerView.lyrics]);
  });

  testWidgets('lyrics and queue views show the compact header', (tester) async {
    for (final (view, body) in [
      (PlayerView.lyrics, 'lyrics body'),
      (PlayerView.queue, 'queue body'),
    ]) {
      await show(tester, player(view: view));
      expect(find.text(body), findsOneWidget);
      expect(find.byKey(VNowPlaying.compactKey), findsOneWidget);
      expect(find.byKey(VNowPlaying.controlsKey), findsNothing);
      expect(find.byKey(VNowPlaying.selectorKey), findsOneWidget);
    }
  });

  testWidgets('loading turns play/pause into the loading indicator', (
    tester,
  ) async {
    await show(
      tester,
      Column(
        children: [
          VControls(
            playing: false,
            loading: true,
            shuffle: false,
            repeat: Repeat.off,
            onPlayPause: () {},
            onNext: () {},
            onPrevious: () {},
            onShuffle: () {},
            onRepeat: () {},
          ),
          VPlayPauseFab(playing: false, loading: true, onPressed: () {}),
        ],
      ),
    );
    expect(find.byType(VLoading), findsNWidgets(2));
    expect(find.bySemanticsLabel('Lire'), findsNothing);
    await show(
      tester,
      VPlayPauseFab(
        playing: false,
        loading: false,
        onPressed: () => calls.add('fab'),
      ),
    );
    expect(find.byType(VLoading), findsNothing);
    await tester.tap(find.bySemanticsLabel('Lire'));
    expect(calls.last, 'fab');
  });

  testWidgets('player controls call their actions', (tester) async {
    calls.clear();
    await show(tester, player());
    for (final (label, call) in [
      ('Titre suivant', 'next'),
      ('Titre précédent', 'previous'),
      ('Mettre en pause', 'playPause'),
      ('Lecture aléatoire', 'shuffle'),
      ('Répéter', 'repeat'),
      ("J'aime", 'like'),
      ('Ajouter à une playlist', 'add'),
      ('Télécharger', 'download'),
    ]) {
      await tester.tap(find.bySemanticsLabel(label).first);
      await tester.pump();
      expect(calls.last, call, reason: label);
    }
  });

  testWidgets('position ticks rebuild only the ring and the times', (
    tester,
  ) async {
    final position = ValueNotifier(120000);
    await show(tester, player(position: position));
    final controls = tester.widget(find.byType(VControls));
    final header = tester.widget(find.byKey(VNowPlaying.headerKey));
    position.value = 130000;
    await tester.pump();
    expect(find.text('2:10'), findsOneWidget);
    expect(identical(tester.widget(find.byType(VControls)), controls), isTrue);
    expect(
      identical(tester.widget(find.byKey(VNowPlaying.headerKey)), header),
      isTrue,
    );
  });

  testWidgets(
    'lyrics and queue shrink the big artwork into the compact header',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final view = ValueNotifier(PlayerView.player);
      Future<void> pumpPlayer({required bool reduce}) => tester.pumpWidget(
        harness(
          ValueListenableBuilder(
            valueListenable: view,
            builder: (context, v, _) =>
                player(view: v, onView: (n) => view.value = n),
          ),
          reduce: reduce,
        ),
      );
      await pumpPlayer(reduce: false);
      await settle(tester);
      final big = tester.getRect(find.byKey(VNowPlaying.artworkKey));
      expect(big.width, greaterThan(200));

      view.value = PlayerView.lyrics;
      await tester.pump();
      await tester.pump(VDurations.medium * 0.5);
      expect(
        find.byType(VArtwork),
        findsOneWidget,
        reason: 'one artwork that moves',
      );
      final mid = tester.getRect(find.byKey(VNowPlaying.artworkKey));
      expect(mid.width, lessThan(big.width));
      expect(mid.width, greaterThan(VSize.compactArt));
      await settle(tester);
      final small = tester.getRect(find.byKey(VNowPlaying.artworkKey));
      expect(small.width, closeTo(VSize.compactArt, 0.5));
      final slot = tester.getRect(find.byKey(VNowPlaying.compactArtKey));
      expect(small.center.dx, closeTo(slot.center.dx, 0.5));
      expect(small.center.dy, closeTo(slot.center.dy, 0.5));
      expect(find.text('lyrics body'), findsOneWidget);

      // Back: it grows again.
      view.value = PlayerView.player;
      await settle(tester);
      expect(
        tester.getRect(find.byKey(VNowPlaying.artworkKey)).width,
        closeTo(big.width, 0.5),
      );

      // Reduce motion: a 150 ms fade, nothing flies.
      await pumpPlayer(reduce: true);
      view.value = PlayerView.queue;
      await tester.pump();
      await tester.pump(VDurations.reduced);
      // Already in the header: it faded there, it didn't fly. (The M3E toolbar's own
      // label spring may still settle; the player schedules nothing more.)
      expect(
        tester.getRect(find.byKey(VNowPlaying.artworkKey)).width,
        closeTo(VSize.compactArt, 0.5),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('the sleep timer shows whole minutes left', (tester) async {
    await show(tester, player(d: data(sleepLeft: const Duration(minutes: 30))));
    expect(find.text('30 min'), findsOneWidget);
    await show(
      tester,
      player(d: data(sleepLeft: const Duration(minutes: 29, seconds: 1))),
    );
    expect(find.text('30 min'), findsOneWidget);
  });

  testWidgets(
    'the header is one row: fold · « Lecture depuis » over the source · ⤢ · ⋮',
    (tester) async {
      await show(
        tester,
        SizedBox(
          width: VSize.sideSheet,
          child: VNowPlaying(
            data: data(sleepLeft: const Duration(minutes: 24)),
            position: ValueNotifier(0),
            size: PlayerSize.medium,
            style: PlayerStyle.disc,
            view: PlayerView.player,
            onView: (_) {},
            actions: actions,
            lyrics: (_) => const SizedBox(),
            queue: (_) => const SizedBox(),
            onImmersive: () {},
          ),
        ),
      );
      final from = tester.getRect(find.text('Random Access Memories'));
      expect(
        tester.getRect(find.text('Lecture depuis')).bottom,
        lessThanOrEqualTo(from.top + 0.5),
        reason: 'the label over the source',
      );
      final collapse = tester.getRect(find.bySemanticsLabel('Réduire'));
      final more = tester.getRect(find.bySemanticsLabel("Plus d'options"));
      final block = tester
          .getRect(find.text('Lecture depuis'))
          .expandToInclude(from);
      expect(block.center.dy, closeTo(collapse.center.dy, 2));
      expect(block.center.dy, closeTo(more.center.dy, 2));
      expect(from.left, greaterThanOrEqualTo(collapse.right));
      expect(from.right, lessThanOrEqualTo(more.left));
      expect(find.text('24\u00a0min'), findsOneWidget);
    },
  );

  testWidgets(
    'the shrink lands on the slot at any text size, and fades the views both ways',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final view = ValueNotifier(PlayerView.player);
      await tester.pumpWidget(
        harness(
          ValueListenableBuilder(
            valueListenable: view,
            builder: (context, v, _) =>
                player(view: v, onView: (n) => view.value = n),
          ),
        ),
      );
      await settle(tester);
      view.value = PlayerView.lyrics;
      await tester.pump();
      await settle(tester);
      final art = tester.getRect(find.byKey(VNowPlaying.artworkKey));
      final slot = tester.getRect(find.byKey(VNowPlaying.compactArtKey));
      expect(
        art.center.dy,
        closeTo(slot.center.dy, 0.5),
        reason: 'measured, not assumed 48 tall',
      );
      expect(art.center.dx, closeTo(slot.center.dx, 0.5));
      // Back to the player: the lyrics fade out with the header, they don't vanish.
      view.value = PlayerView.player;
      await tester.pump();
      await tester.pump(VDurations.medium * 0.4);
      expect(find.text('lyrics body'), findsOneWidget);
      await settle(tester);
      expect(find.text('lyrics body'), findsNothing);
    },
  );

  testWidgets('wave to disc cross-fades in the middle of the flight', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final view = ValueNotifier(PlayerView.player);
    await tester.pumpWidget(
      harness(
        ValueListenableBuilder(
          valueListenable: view,
          builder: (context, v, _) => player(
            view: v,
            style: PlayerStyle.wave,
            onView: (n) => view.value = n,
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(VWaveArtwork), findsOneWidget);
    view.value = PlayerView.lyrics;
    await tester.pump();
    var both = false;
    for (var i = 0; i < 40 && !both; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      final fading = tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byType(VWaveArtwork),
              matching: find.byType(Opacity),
            ),
          )
          .any((o) => o.opacity > 0 && o.opacity < 1);
      both = fading && find.byType(VArtwork).evaluate().length == 1;
    }
    expect(
      both,
      isTrue,
      reason: 'a frame where the wave fades out over the disc',
    );
    await settle(tester);
    expect(find.byType(VWaveArtwork), findsNothing);
    expect(find.byType(VArtwork), findsOneWidget);
  });

  testWidgets('the wave and the disc keep their state through the cross-fade', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final view = ValueNotifier(PlayerView.player);
    await tester.pumpWidget(
      harness(
        ValueListenableBuilder(
          valueListenable: view,
          builder: (context, v, _) => player(
            view: v,
            style: PlayerStyle.wave,
            onView: (n) => view.value = n,
          ),
        ),
      ),
    );
    await settle(tester);
    // Way out: the wave keeps its state for as long as it shows.
    final wave = tester.state(find.byType(VWaveArtwork));
    view.value = PlayerView.lyrics;
    await tester.pump();
    for (
      var i = 0;
      i < 40 && find.byType(VWaveArtwork).evaluate().isNotEmpty;
      i++
    ) {
      expect(
        identical(tester.state(find.byType(VWaveArtwork)), wave),
        isTrue,
        reason: 'frame $i out',
      );
      await tester.pump(const Duration(milliseconds: 8));
    }
    await settle(tester);
    // Way back: the disc that turned in the header keeps its state while it shows.
    final disc = tester.state(find.byType(VArtwork));
    view.value = PlayerView.player;
    await tester.pump();
    for (
      var i = 0;
      i < 40 && find.byType(VArtwork).evaluate().isNotEmpty;
      i++
    ) {
      expect(
        identical(tester.state(find.byType(VArtwork)), disc),
        isTrue,
        reason: 'frame $i back',
      );
      await tester.pump(const Duration(milliseconds: 8));
    }
    await settle(tester);
  });
}

/// Labels that must always be reachable in a full player.
const reachable = [
  'Réduire',
  'Sortie audio',
  "Plus d'options",
  'Lecture aléatoire',
  'Titre précédent',
  'Mettre en pause',
  'Titre suivant',
  'Répéter',
];

void layoutTests() {
  testWidgets('at 200 % text the mini player and the strip never overflow', (
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
      size: const Size(360, 800),
    );
    await show(
      tester,
      Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: VSize.strip,
          child: player(size: PlayerSize.compact, axis: Axis.vertical),
        ),
      ),
      size: const Size(800, 800),
    );
    FlutterError.onError = old;
    expect(errors.map((e) => e.exceptionAsString()), isEmpty);
    expect(find.bySemanticsLabel('Titre suivant'), findsOneWidget);
  });

  testWidgets('the mini player is a floating toolbar with its FAB beside it', (
    tester,
  ) async {
    await show(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: player(size: PlayerSize.compact),
      ),
    );
    final bar = find.byType(M3EToolbar);
    expect(bar, findsOneWidget);
    final fab = find.byType(VPlayPauseFab);
    expect(fab, findsOneWidget);
    final pill = tester.getRect(
      find
          .ancestor(of: find.text('Get Lucky'), matching: find.byType(Material))
          .first,
    );
    final button = tester.getRect(fab);
    expect(button.left, greaterThanOrEqualTo(pill.right), reason: 'beside');
    expect(button.width, closeTo(button.height, 0.5), reason: 'square FAB');
    // The pill holds the artwork, the title, the artists and like.
    for (final f in [
      find.byType(VArtwork),
      find.text('Get Lucky'),
      find.bySemanticsLabel("J'aime"),
    ]) {
      final r = tester.getRect(f.first);
      expect(pill.contains(r.center), isTrue, reason: '$f in the pill');
    }
    // The turning cookie is the playing sign: no equalizer, no scrim.
    expect(find.byType(VEqualizer), findsNothing);
  });

  testWidgets('the FAB becomes the loading indicator inside its container', (
    tester,
  ) async {
    await show(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: player(size: PlayerSize.compact, d: data(loading: true)),
      ),
    );
    final fab = find.byType(M3EFab);
    expect(
      find.descendant(of: fab, matching: find.byType(VLoading)),
      findsOneWidget,
    );
    expect(tester.getSize(fab).width, greaterThanOrEqualTo(VSize.fab));
  });

  testWidgets('mini player gestures, and the same in its menu', (tester) async {
    await show(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: player(size: PlayerSize.compact),
      ),
    );
    final title = find.text('Get Lucky');
    for (final (offset, call) in [
      (const Offset(-160, 0), 'next'),
      (const Offset(160, 0), 'previous'),
      (const Offset(0, -160), 'open'),
      (const Offset(0, 160), 'stop'),
    ]) {
      calls.clear();
      await tester.drag(title, offset);
      await tester.pump(VDurations.long);
      expect(calls, [call], reason: '$offset');
    }
    calls.clear();
    await tester.tap(title);
    expect(calls, ['open']);
    // The toolbar's menu (long press) has every gesture.
    await tester.longPress(title);
    await tester.pumpAndSettle();
    for (final l in [
      'Titre suivant',
      'Titre précédent',
      'Ouvrir le lecteur',
      'Arrêter la lecture',
    ]) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
  });

  for (final style in PlayerStyle.values) {
    for (final (name, size, playerSize, immersive) in [
      ('phone', const Size(412, 860), PlayerSize.large, false),
      ('small phone', const Size(360, 640), PlayerSize.large, false),
      ('pane', const Size(VSize.sideSheet, 760), PlayerSize.medium, false),
      ('immersive', const Size(1280, 800), PlayerSize.large, true),
      ('narrow immersive', const Size(900, 600), PlayerSize.large, true),
    ]) {
      testWidgets('nothing is clipped: $name, $style', (tester) async {
        final errors = <FlutterErrorDetails>[];
        final old = FlutterError.onError;
        FlutterError.onError = errors.add;
        await show(
          tester,
          player(
            size: playerSize,
            style: style,
            immersive: immersive,
            onImmersive: () {},
            view: immersive ? PlayerView.lyrics : PlayerView.player,
          ),
          size: size,
        );
        FlutterError.onError = old;
        expect(errors.map((e) => e.exceptionAsString()), isEmpty);
        final bounds = Offset.zero & size;
        for (final l in [
          for (final r in reachable)
            immersive && r == 'Réduire' ? 'Quitter le plein écran' : r,
          if (!immersive) 'Lecteur',
          'Paroles',
          'File',
        ]) {
          final f = find.bySemanticsLabel(l);
          expect(f, findsWidgets, reason: l);
          final r = tester.getRect(f.first);
          expect(
            bounds.contains(r.topLeft) &&
                bounds.contains(r.bottomRight - const Offset(0.01, 0.01)),
            isTrue,
            reason: '$l at $r',
          );
          expect(
            f.first.hitTestable(),
            findsOneWidget,
            reason: '$l hit-testable',
          );
        }
        // ⏯ is the widest of the five controls.
        final play = tester
            .getSize(find.bySemanticsLabel('Mettre en pause').first)
            .width;
        for (final l in [
          'Lecture aléatoire',
          'Titre précédent',
          'Titre suivant',
          'Répéter',
        ]) {
          expect(
            play,
            greaterThan(tester.getSize(find.bySemanticsLabel(l).first).width),
            reason: l,
          );
        }
      });
    }
  }

  testWidgets('a tall phone centres the player between header and selector', (
    tester,
  ) async {
    await show(tester, player(), size: const Size(412, 1100));
    final header = tester.getRect(find.byKey(VNowPlaying.headerKey));
    final art = tester.getRect(find.byKey(VNowPlaying.artworkKey));
    final controls = tester.getRect(find.byKey(VNowPlaying.controlsKey));
    final selector = tester.getRect(find.byKey(VNowPlaying.selectorKey));
    final above = art.top - header.bottom;
    final below = selector.top - controls.bottom;
    expect(above, greaterThan(VSpace.s32), reason: 'room to spare');
    expect((above - below).abs(), lessThan(VSpace.s24));
  });

  testWidgets(
    'immersive: artwork left, lyrics right, controls below, Esc exits',
    (tester) async {
      var exits = 0;
      await show(
        tester,
        player(
          immersive: true,
          view: PlayerView.lyrics,
          onImmersive: () => exits++,
        ),
        size: const Size(1280, 800),
      );
      final art = tester.getRect(find.byKey(VNowPlaying.artworkKey));
      final lyrics = tester.getRect(find.text('lyrics body'));
      final controls = tester.getRect(find.byKey(VNowPlaying.controlsKey));
      expect(art.right, lessThanOrEqualTo(lyrics.left));
      expect(controls.top, greaterThanOrEqualTo(art.bottom));
      expect(art.width, greaterThan(300));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(exits, 1);
    },
  );
}
