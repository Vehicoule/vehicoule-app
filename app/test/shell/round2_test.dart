// Task 5, fix round 2: the user's review of the round 1 captures (U6–U13) and the
// controller's visuals (V9–V12).
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart'
    show M3EFabMenu, M3ESlider;
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/downloads.dart';
import 'package:vehicoule/bridge/queue.dart';
import 'package:vehicoule/debug/library.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/features/music/now_playing/now_playing_sheet.dart';
import 'package:vehicoule/router.dart';

import '../design/harness.dart';
import 'rig.dart';

NowPlayingData _data({DownloadStateView? download}) => NowPlayingData(
  track: sampleTracks[1],
  sourceTitle: 'Random Access Memories',
  playing: true,
  loading: false,
  durationMs: 206000,
  liked: false,
  download: download,
  shuffle: false,
  repeat: Repeat.off,
);

final _views = <PlayerView>[];

NowPlayingActions _actions() => NowPlayingActions(
  onPlayPause: () {},
  onNext: () {},
  onPrevious: () {},
  onSeek: (_) {},
  onLike: () {},
  onAddToPlaylist: () {},
  onDownload: () {},
  onShuffle: () {},
  onRepeat: () {},
  onOutput: () {},
  onCollapse: () {},
);

Widget _player({
  PlayerSize size = PlayerSize.large,
  PlayerStyle style = PlayerStyle.disc,
  bool volume = false,
  bool immersive = false,
  NowPlayingData? data,
  PlayerView view = PlayerView.player,
}) => VNowPlaying(
  data: data ?? _data(),
  position: ValueNotifier(74000),
  size: size,
  style: style,
  view: view,
  onView: _views.add,
  actions: _actions(),
  lyrics: (_) => const SizedBox(),
  queue: (_) => const SizedBox(),
  onImmersive: () {},
  immersive: immersive,
  wide: immersive,
  volume: volume ? VVolume(value: 0.6, onChanged: (_) {}) : null,
);

Future<void> _show(WidgetTester tester, Widget w, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness(w, reduce: true));
  await tester.pump();
  await tester.pump(VDurations.medium);
}

Rect _rect(WidgetTester tester, Finder f) => tester.getRect(f.first);

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is VIconButton && w.label == label);

void main() {
  testWidgets('U6: the size toggle is the last button, top right', (
    tester,
  ) async {
    for (final (size, screen, toggle) in [
      (PlayerSize.large, const Size(400, 860), 'Réduire'),
      (PlayerSize.medium, const Size(360, 780), 'Réduire'),
    ]) {
      await _show(tester, _player(size: size, volume: true), screen);
      final header = _rect(tester, find.byKey(VNowPlaying.headerKey));
      final t = _rect(tester, _button(toggle));
      expect(t.right, moreOrLessEquals(screen.width - VSpace.s8, epsilon: 1));
      expect(t.center.dy, moreOrLessEquals(header.center.dy, epsilon: 1));
      for (final other
          in find
              .descendant(
                of: find.byKey(VNowPlaying.headerKey),
                matching: find.byType(VIconButton),
              )
              .evaluate()) {
        expect(
          tester.getRect(find.byWidget(other.widget)).left,
          lessThanOrEqualTo(t.left),
          reason: '$size: nothing after the toggle',
        );
      }
    }
    // Immersive: the same place, ⤡.
    await _show(tester, _player(immersive: true), const Size(1280, 800));
    expect(
      _rect(tester, _button('Quitter le plein écran')).right,
      moreOrLessEquals(1280 - VSpace.s8, epsilon: 1),
    );
  });

  testWidgets('U6, U11: the strip opens the pane from its top', (tester) async {
    final r = Rig();
    r.api.prefs['ui.now_playing_open'] = 'false';
    await r.pump(tester, size: desktop);
    final open = _rect(tester, _button('Ouvrir le lecteur'));
    final art = tester.getRect(
      find.descendant(of: strip(), matching: find.byType(VArtwork)),
    );
    expect(open.bottom, lessThanOrEqualTo(art.top), reason: 'above the disc');
    final play = _rect(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is VIconButton &&
            (w.label == 'Lire' || w.label == 'Mettre en pause'),
      ),
    );
    final next = _rect(tester, _button('Titre suivant'));
    final like = _rect(tester, _button("J'aime"));
    final volume = tester.getRect(
      find.descendant(of: strip(), matching: find.byType(VVolume)),
    );
    // Three groups: top, middle, bottom; ⏯ the biggest.
    expect(art.bottom, lessThan(play.top));
    expect(play.bottom, lessThan(next.top));
    expect(next.bottom, lessThan(like.top));
    expect(like.bottom, lessThan(volume.top));
    expect(play.width, greaterThan(next.width));
    expect(play.width, greaterThan(like.width));
    expect(volume.height, lessThanOrEqualTo(VSize.stripVolume));
    final card = tester.getRect(
      find.ancestor(of: strip(), matching: find.byType(ClipRRect)).first,
    );
    expect(card.bottom - volume.bottom, lessThanOrEqualTo(VSpace.s24));
    expect(
      volume.top - like.bottom,
      greaterThan(VSpace.s24),
      reason: 'the groups spread over the height',
    );
  }, variant: mac);

  testWidgets('U8: the ring stays inside its box, clear of the header', (
    tester,
  ) async {
    for (final (size, screen) in [
      (PlayerSize.large, const Size(360, 740)),
      (PlayerSize.large, const Size(400, 860)),
      (PlayerSize.medium, const Size(360, 760)),
      (PlayerSize.large, const Size(1280, 800)),
    ]) {
      await _show(tester, _player(size: size), screen);
      final paint = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is VRingPainter,
      );
      final box = tester.getRect(find.byKey(VNowPlaying.artworkKey));
      final ringBox = tester.getRect(paint.first);
      final ring =
          tester.widget<CustomPaint>(paint.first).painter! as VRingPainter;
      final center = ring.geometry.center;
      // Whatever the turn: the farthest point plus half the stroke.
      final reach =
          ring.geometry.points
              .map((p) => (p - center).distance)
              .reduce(math.max) +
          ring.stroke / 2;
      final painted = Rect.fromCircle(
        center: ringBox.topLeft + center,
        radius: reach,
      );
      final why = '$size at $screen';
      expect(box.inflate(0.5).contains(painted.topLeft), isTrue, reason: why);
      expect(
        box.inflate(0.5).contains(painted.bottomRight),
        isTrue,
        reason: why,
      );
      final header = tester.getRect(find.byKey(VNowPlaying.headerKey));
      expect(
        painted.top - header.bottom,
        greaterThanOrEqualTo(VSpace.s8),
        reason: '$why: a token space above',
      );
    }
  });

  testWidgets('U10: one column, times under the ring, buttons by the title', (
    tester,
  ) async {
    for (final (size, screen) in [
      (PlayerSize.large, const Size(400, 860)),
      (PlayerSize.medium, const Size(360, 780)),
    ]) {
      await _show(
        tester,
        _player(size: size, volume: size == PlayerSize.medium),
        screen,
      );
      final why = '$size';
      final art = _rect(tester, find.byKey(VNowPlaying.artworkKey));
      // The times: « 1:14 / 3:26 », one line centred under the ring.
      final times = _rect(tester, find.text('1:14 / 3:26'));
      expect(times.center.dx, moreOrLessEquals(art.center.dx, epsilon: 1));
      expect(times.top, greaterThanOrEqualTo(art.bottom), reason: why);
      final title = _rect(tester, find.byKey(VNowPlaying.titleKey));
      expect(times.bottom, lessThan(title.top), reason: why);
      // Like, playlist, download: standard icon buttons right of the title.
      expect(find.byType(VConnectedGroup), findsNothing, reason: why);
      for (final l in ["J'aime", 'Ajouter à une playlist', 'Télécharger']) {
        final b = _rect(tester, _button(l));
        expect(b.left, greaterThan(title.right - 1), reason: '$why: $l');
        expect(b.center.dy, inInclusiveRange(title.top, title.bottom));
        expect(
          tester.widget<VIconButton>(_button(l)).style,
          VIconStyle.standard,
        );
      }
      // The controls: the whole column's width, ⏯ the widest and ≥ 64 high, and
      // nothing in the column bigger.
      final controls = _rect(tester, find.byKey(VNowPlaying.controlsKey));
      expect(
        controls.width,
        moreOrLessEquals(screen.width - 2 * VSpace.s16, epsilon: 1),
      );
      final play = _rect(tester, find.bySemanticsLabel('Mettre en pause'));
      expect(play.height, greaterThanOrEqualTo(VSize.control), reason: why);
      // All five inside the column.
      for (final l in ['Lecture aléatoire', 'Répéter']) {
        final b = _rect(tester, find.bySemanticsLabel(l));
        expect(b.left, greaterThanOrEqualTo(controls.left - 0.5), reason: l);
        expect(b.right, lessThanOrEqualTo(controls.right + 0.5), reason: l);
      }
      for (final l in ['Titre suivant', 'Titre précédent', 'Répéter']) {
        expect(
          play.width,
          greaterThan(_rect(tester, find.bySemanticsLabel(l)).width),
        );
      }
      // The bottom row: the volume (desktop) at the start, at most 240, and the
      // view menu at the end.
      final menu = _rect(tester, find.byKey(VNowPlaying.selectorKey));
      expect(menu.top, greaterThan(controls.bottom), reason: why);
      expect(find.byType(M3EFabMenu), findsOneWidget, reason: why);
      if (size == PlayerSize.medium) {
        final volume = _rect(tester, find.byType(VVolume));
        expect(volume.width, lessThanOrEqualTo(VSize.volumeMax));
        expect(volume.center.dy, moreOrLessEquals(menu.center.dy, epsilon: 2));
        expect(volume.right, lessThan(menu.left));
      } else {
        // A phone: the output takes the volume's place.
        final output = _rect(tester, _button('Sortie audio'));
        expect(output.center.dy, moreOrLessEquals(menu.center.dy, epsilon: 2));
      }
    }
  });

  testWidgets('U10: the Vague keeps its times at both ends under the wave', (
    tester,
  ) async {
    await _show(tester, _player(style: PlayerStyle.wave), const Size(400, 860));
    final art = _rect(tester, find.byKey(VNowPlaying.artworkKey));
    final start = _rect(tester, find.text('1:14'));
    final end = _rect(tester, find.text('3:26'));
    expect(start.top, greaterThanOrEqualTo(art.bottom));
    expect(start.left, lessThan(art.center.dx));
    expect(end.right, greaterThan(art.center.dx));
    expect(end.top, moreOrLessEquals(start.top));
  });

  testWidgets('U10: the view menu shows the current view and switches', (
    tester,
  ) async {
    _views.clear();
    await _show(tester, _player(), const Size(400, 860));
    final fab = find.byKey(VNowPlaying.selectorKey);
    expect(
      find.descendant(
        of: fab,
        matching: find.byWidgetPredicate(
          (w) => w is VSymbol && w.icon == VIcons.musicNote,
        ),
      ),
      findsOneWidget,
      reason: 'closed, the current view’s icon',
    );
    await tester.tap(find.descendant(of: fab, matching: find.byType(VSymbol)));
    await tester.pump();
    await tester.pump(VDurations.long);
    // Open upwards: Paroles · Lecteur · File, the current one checked.
    final lyrics = _rect(tester, find.text('Paroles'));
    final queue = _rect(tester, find.text('File'));
    final player = _rect(tester, find.text('Lecteur'));
    expect(lyrics.top, lessThan(player.top));
    expect(player.top, lessThan(queue.top));
    expect(queue.bottom, lessThan(_rect(tester, fab).top + 1));
    expect(
      find.byWidgetPredicate((w) => w is VSymbol && w.icon == VIcons.check),
      findsOneWidget,
    );
    await tester.tap(find.text('File'));
    await tester.pump(VDurations.long);
    expect(_views, [PlayerView.queue]);
  });

  testWidgets('V10: the volume is a thin slider with its handle inside', (
    tester,
  ) async {
    for (final vertical in [false, true]) {
      await _show(
        tester,
        Center(
          child: SizedBox(
            width: vertical ? VSize.strip : VSize.volumeMax,
            height: vertical ? VSize.stripVolume : null,
            child: VVolume(value: 1, onChanged: (_) {}, vertical: vertical),
          ),
        ),
        const Size(400, 400),
      );
      final slider = tester.widget<M3ESlider>(find.byType(M3ESlider));
      expect(slider.size.trackHeight, lessThanOrEqualTo(VSize.sliderTrack));
      final box = _rect(tester, find.byType(VVolume));
      final speaker = _rect(
        tester,
        find.byWidgetPredicate((w) => w is VSymbol && w.icon == VIcons.volume),
      );
      expect(box.contains(speaker.center), isTrue);
      if (vertical) {
        expect(
          speaker.top,
          greaterThan(_rect(tester, find.byType(M3ESlider)).top),
        );
      }
    }
  });

  testWidgets('V11: a downloaded track shows the download glyph, filled', (
    tester,
  ) async {
    await _show(
      tester,
      _player(data: _data(download: DownloadStateView.done)),
      const Size(400, 860),
    );
    expect(find.bySemanticsLabel('Téléchargé'), findsWidgets);
    expect(
      find.byWidgetPredicate((w) => w is VSymbol && w.icon == VIcons.check),
      findsNothing,
      reason: 'no bare ✓',
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is VSymbol && w.icon == VIcons.downloaded && w.filled,
      ),
      findsOneWidget,
    );
  });

  testWidgets('U9: the top bar breathes, its search centred on the content', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    final search = _rect(tester, find.byType(VSearchBar));
    final content = _rect(
      tester,
      find.ancestor(
        of: find.text('Rien ici pour l\'instant.'),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(search.height, VSize.titleSearchHeight);
    expect(search.top, greaterThanOrEqualTo(VSpace.s8));
    expect(content.top - search.bottom, greaterThanOrEqualTo(VSpace.s8));
    expect(search.center.dy, moreOrLessEquals(VSize.titleBar / 2, epsilon: 1));
    expect(search.center.dx, moreOrLessEquals(content.center.dx, epsilon: 1));
    expect(search.width, inInclusiveRange(360, 560));
    // ← → and the global actions on the same line as the search.
    for (final l in ['Page précédente', 'Téléchargements', 'Sources']) {
      expect(
        _rect(tester, _button(l)).center.dy,
        moreOrLessEquals(search.center.dy, epsilon: 1),
        reason: l,
      );
    }
    // The pane open or folded, the rail expanded: still on the content.
    await tester.tap(label('Déplier le menu'));
    await settle(tester, 12);
    final moved = _rect(
      tester,
      find.ancestor(
        of: find.text('Rien ici pour l\'instant.'),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(
      _rect(tester, find.byType(VSearchBar)).center.dx,
      moreOrLessEquals(moved.center.dx, epsilon: 1),
    );
  }, variant: mac);

  testWidgets('U9: a click on the search keeps its field and icons in place', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    Rect field() => tester.getRect(find.byType(EditableText).last);
    final rest = field();
    final icon = _rect(
      tester,
      find.byWidgetPredicate((w) => w is VSymbol && w.icon == VIcons.search),
    );
    await tester.tap(find.byType(EditableText).first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      // The open view's field starts and ends where the bar's did: no jump.
      expect(
        field().left,
        moreOrLessEquals(rest.left, epsilon: 1),
        reason: '$i',
      );
      expect(
        field().right,
        moreOrLessEquals(rest.right, epsilon: 1),
        reason: '$i',
      );
      // The leading search icon stays (no ← swapped in), so does the keycap.
      final shown = find.byWidgetPredicate(
        (w) => w is VSymbol && w.icon == VIcons.search,
      );
      expect(
        tester.getRect(shown.last).center.dx,
        moreOrLessEquals(icon.center.dx, epsilon: 1),
        reason: '$i',
      );
      expect(find.text('⌘F'), findsWidgets, reason: '$i');
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 12);
    expect(field(), rest);
  }, variant: mac);

  testWidgets('U12: the domain menu is hidden with one domain', (tester) async {
    final r = Rig();
    await r.pump(tester, size: desktop);
    final rail = tester.widget<VNavigationRail>(find.byType(VNavigationRail));
    expect(rail.trailing, isNull);
    expect(find.text('Musique'), findsNothing);
  }, variant: mac);

  testWidgets('U12: the domain menu opens on the domains, current checked', (
    tester,
  ) async {
    final picked = <String>[];
    await _show(
      tester,
      Align(
        alignment: Alignment.bottomLeft,
        // Where the rail puts it: 16 from the window's edge.
        child: Padding(
          padding: const EdgeInsets.all(VSpace.s16),
          child: VDomainMenu(
            extended: true,
            domains: [
              for (final (i, d) in ['Musique', 'Anime', 'Livres'].indexed)
                VAction(
                  d,
                  VIcons.musicNote,
                  () => picked.add(d),
                  selected: i == 0,
                ),
            ],
          ),
        ),
      ),
      const Size(400, 600),
    );
    expect(find.text('Musique'), findsOneWidget, reason: 'its name, expanded');
    await tester.tap(find.byType(M3EFabMenu));
    // The items come in one after the other, on springs.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (final d in ['Anime', 'Livres']) {
      expect(find.text(d), findsOneWidget, reason: d);
    }
    expect(
      find.byWidgetPredicate((w) => w is VSymbol && w.icon == VIcons.check),
      findsOneWidget,
    );
    await tester.tap(find.text('Anime'));
    await tester.pump(VDurations.long);
    expect(picked, ['Anime']);
  });

  testWidgets(
    'U13: the pane folds and unfolds in motion, the tree stays whole',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final r = Rig();
      await r.pump(tester, size: desktop);
      await tester.pumpWidget(
        VehicouleApp(
          player: r.player,
          theme: r.theme,
          online: r.online,
          playback: r.playback,
          reduceMotion: false,
        ),
      );
      await settle(tester, 12);
      Future<void> frames(int n) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      for (var k = 0; k < 2; k++) {
        await key(tester, LogicalKeyboardKey.keyB, meta: true, alt: true);
        await frames(60);
      }
      // A tap after the round trip (overlapping layers once broke the semantics).
      await tester.tap(find.bySemanticsLabel("J'aime").first);
      await frames(30);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
    variant: mac,
  );

  testWidgets('U13: the player sheet opens and closes without a jump back', (
    tester,
  ) async {
    final r = Rig();
    await r.pump(tester);
    final sheet = tester.state<NowPlayingSheetState>(
      find.byType(NowPlayingSheet),
    );
    final extents = <double>[];
    sheet.open();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      extents.add(sheet.widget.extent.value);
    }
    for (var i = 1; i < extents.length; i++) {
      expect(
        extents[i],
        greaterThanOrEqualTo(extents[i - 1] - 0.001),
        reason: 'never back down while opening ($i)',
      );
    }
    expect(extents.last, moreOrLessEquals(1, epsilon: 0.01));
  });
}
