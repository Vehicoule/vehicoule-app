import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/queue.dart';
import 'package:vehicoule/debug/library.dart';
import 'package:vehicoule/design/design.dart';

import 'harness.dart';

NowPlayingData data({bool playing = true, bool loading = false}) =>
    NowPlayingData(
      track: sampleTracks[1],
      sourceTitle: 'Random Access Memories',
      playing: playing,
      loading: loading,
      positionMs: 120000,
      durationMs: 369000,
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
}) => VNowPlaying(
  data: d ?? data(),
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
}
