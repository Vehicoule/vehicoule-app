import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
);

Widget player({
  PlayerSize size = PlayerSize.large,
  PlayerStyle style = PlayerStyle.disc,
  PlayerView view = PlayerView.player,
  NowPlayingData? d,
  ValueChanged<PlayerView>? onView,
  Axis axis = Axis.horizontal,
  ValueListenable<int>? position,
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
        expect(
          find.text('Lecture depuis Random Access Memories'),
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
    final active = tester
        .getSize(find.byKey(VViewSelector.segmentKey(PlayerView.player)))
        .width;
    final idle = tester
        .getSize(find.byKey(VViewSelector.segmentKey(PlayerView.lyrics)))
        .width;
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
      await tester.pump(VDurations.short);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        tester.getRect(find.byKey(VNowPlaying.artworkKey)).width,
        closeTo(VSize.compactArt, 0.5),
      );
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

  testWidgets('the pane header never cuts « Lecture depuis … »', (
    tester,
  ) async {
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
    final from = find.text('Lecture depuis Random Access Memories');
    expect(from, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(from).didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('the shrink lands on the slot at any text size, and fades the views both ways', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final view = ValueNotifier(PlayerView.player);
    await tester.pumpWidget(harness(ValueListenableBuilder(
      valueListenable: view,
      builder: (context, v, _) => player(view: v, onView: (n) => view.value = n),
    )));
    await settle(tester);
    view.value = PlayerView.lyrics;
    await tester.pump();
    await settle(tester);
    final art = tester.getRect(find.byKey(VNowPlaying.artworkKey));
    final slot = tester.getRect(find.byKey(VNowPlaying.compactArtKey));
    expect(art.center.dy, closeTo(slot.center.dy, 0.5), reason: 'measured, not assumed 48 tall');
    expect(art.center.dx, closeTo(slot.center.dx, 0.5));
    // Back to the player: the lyrics fade out with the header, they don't vanish.
    view.value = PlayerView.player;
    await tester.pump();
    await tester.pump(VDurations.medium * 0.4);
    expect(find.text('lyrics body'), findsOneWidget);
    await settle(tester);
    expect(find.text('lyrics body'), findsNothing);
  });

  testWidgets('wave to disc cross-fades in the middle of the flight', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final view = ValueNotifier(PlayerView.player);
    await tester.pumpWidget(harness(ValueListenableBuilder(
      valueListenable: view,
      builder: (context, v, _) => player(view: v, style: PlayerStyle.wave, onView: (n) => view.value = n),
    )));
    await settle(tester);
    expect(find.byType(VWaveArtwork), findsOneWidget);
    view.value = PlayerView.lyrics;
    await tester.pump();
    var both = false;
    for (var i = 0; i < 40 && !both; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      final fading = tester
          .widgetList<Opacity>(find.ancestor(of: find.byType(VWaveArtwork), matching: find.byType(Opacity)))
          .any((o) => o.opacity > 0 && o.opacity < 1);
      both = fading && find.byType(VArtwork).evaluate().length == 1;
    }
    expect(both, isTrue, reason: 'a frame where the wave fades out over the disc');
    await settle(tester);
    expect(find.byType(VWaveArtwork), findsNothing);
    expect(find.byType(VArtwork), findsOneWidget);
  });
}
