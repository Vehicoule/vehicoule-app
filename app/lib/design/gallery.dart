/// The design gallery: every component of `design/` in its states, to validate the system
/// against the mockups (plan 5, Task 1). Debug only, no fake API: the test library's real
/// titles and artists, and their real covers looked up through the core when a source
/// answers (online, official source installed). Otherwise every artwork shows the
/// missing-cover look.
///
/// `flutter run -d macos -t lib/design/gallery.dart` (the shell also opens it at
/// `/debug/gallery` in debug builds).
library;

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../bridge/api/app.dart' as core;
import '../bridge/api/catalog.dart' as core;
import '../bridge/api/plugins.dart' as core;
import '../bridge/app.dart' as core show AppConfig, Platform;
import '../bridge/downloads.dart';
import '../bridge/frb_generated.dart';
import '../bridge/error.dart';
import '../bridge/queue.dart';
import '../debug/library.dart';
import '../l10n/app_localizations.dart';
import 'design.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  vRegisterFontLicenses();
  runApp(GalleryApp(covers: await GalleryCovers.start()));
}

/// Real covers through the core: each sample id is searched once ([sampleQuery]) and its
/// first hit's artwork comes from `artworkFile`, like in the app.
class GalleryCovers {
  GalleryCovers._();

  final _ids = <String, Future<String?>>{};

  /// Null when the core can't start; the gallery then shows missing covers.
  static Future<GalleryCovers?> start() async {
    try {
      await RustLib.init();
      final base = '${Directory.systemTemp.path}/vehicoule_gallery';
      await core.initApp(
        cfg: core.AppConfig(
          dataDir: '$base/data',
          cacheDir: '$base/cache',
          downloadsDir: '$base/downloads',
          appVersion: 'gallery',
          region: 'FR',
          platform: Platform.isMacOS
              ? core.Platform.macOs
              : Platform.isAndroid
              ? core.Platform.android
              : Platform.isWindows
              ? core.Platform.windows
              : core.Platform.linux,
          osVersion: Platform.operatingSystemVersion,
          deviceModel: 'design gallery',
        ),
      );
      await core.start();
      await core.setOnline(online: true);
      await core.refreshFeeds();
      return GalleryCovers._();
    } on Object catch (e) {
      debugPrint('gallery: no core ($e), covers stay missing');
      return null;
    }
  }

  Future<String?> _lookup(String id) async {
    final q = sampleQuery(id);
    if (q == null) return null;
    try {
      final r = await core.search(query: q);
      final hits = id.startsWith('track:')
          ? r.tracks.map((t) => t.id)
          : id.startsWith('album:')
          ? r.albums.map((a) => a.id)
          : r.artists.map((a) => a.id);
      return hits.firstOrNull;
    } on Object catch (e) {
      debugPrint('gallery: no cover for $id ($e)');
      return null;
    }
  }

  /// The cover file of a sample id at [px] pixels.
  Future<String?> file(String id, int px) async {
    final real = await (_ids[id] ??= _lookup(id));
    return real == null ? null : core.artworkFile(id: real, size: px);
  }

  Future<ImageProvider?> resolve(String id, int px) async {
    final path = await file(id, px);
    return path == null ? null : FileImage(File(path));
  }
}

enum _Brightness { light, dark, black }

/// The theme's color source: three sample artworks, the system, two presets.
sealed class _Source {
  const _Source();
}

class _Art extends _Source {
  const _Art(this.n);
  final int n;
}

class _System extends _Source {
  const _System();
}

class _Preset extends _Source {
  const _Preset(this.n);
  final int n;
}

class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key, this.covers});

  /// Null in tests and without a core: missing covers everywhere.
  final GalleryCovers? covers;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  _Brightness _brightness = _Brightness.light;
  _Source _source = const _Art(1);
  Color _seed = VPresets.seeds.first;
  bool _reduce = false;
  Locale _locale = const Locale('fr');

  @override
  void initState() {
    super.initState();
    _apply(_source);
  }

  Future<void> _apply(_Source s) async {
    setState(() => _source = s);
    final seed = switch (s) {
      _Art(:final n) => await _artSeed(n),
      _System() => await systemSeed(),
      _Preset(:final n) => VPresets.seeds[n - 1],
    };
    if (mounted && seed != null && _source == s) setState(() => _seed = seed);
  }

  /// The seed of sample track [n]'s cover: the 112 px file, as for what's playing.
  Future<Color?> _artSeed(int n) async {
    final path = await widget.covers?.file(sampleTracks[n - 1].id, 112);
    return path == null ? null : seedFromArtwork(path);
  }

  @override
  Widget build(BuildContext context) {
    final dark = _brightness != _Brightness.light;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: vTheme(
        brightness: dark ? Brightness.dark : Brightness.light,
        seed: _seed,
        pureBlack: _brightness == _Brightness.black,
      ),
      themeAnimationDuration: _reduce ? Duration.zero : VDurations.themeFade,
      locale: _locale,
      localizationsDelegates: vLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateTitle: (c) => AppLocalizations.of(c).galleryTitle,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: _reduce),
        child: ArtworkResolver(
          resolve: widget.covers?.resolve ?? _noCover,
          child: vAppBuilder(context, child),
        ),
      ),
      home: _GalleryPage(
        controls: _Controls(
          brightness: _brightness,
          source: _source,
          reduce: _reduce,
          locale: _locale,
          onBrightness: (b) => setState(() => _brightness = b),
          onSource: _apply,
          onReduce: (r) => setState(() => _reduce = r),
          onLocale: (l) => setState(() => _locale = l),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.brightness,
    required this.source,
    required this.reduce,
    required this.locale,
    required this.onBrightness,
    required this.onSource,
    required this.onReduce,
    required this.onLocale,
  });

  final _Brightness brightness;
  final _Source source;
  final bool reduce;
  final Locale locale;
  final ValueChanged<_Brightness> onBrightness;
  final ValueChanged<_Source> onSource;
  final ValueChanged<bool> onReduce;
  final ValueChanged<Locale> onLocale;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget choice(String label, bool on, VoidCallback tap) => VButton(
      label: label,
      style: on ? VButtonStyle.filled : VButtonStyle.outlined,
      onPressed: tap,
    );
    return Wrap(
      spacing: VSpace.s8,
      runSpacing: VSpace.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (b, label) in [
          (_Brightness.light, l.themeLight),
          (_Brightness.dark, l.themeDark),
          (_Brightness.black, l.themePureBlack),
        ])
          choice(label, brightness == b, () => onBrightness(b)),
        for (final n in [1, 2, 3])
          choice(
            l.colorSourceArtwork(n),
            source is _Art && (source as _Art).n == n,
            () => onSource(_Art(n)),
          ),
        choice(
          l.colorSourceSystem,
          source is _System,
          () => onSource(const _System()),
        ),
        for (final n in [1, 2])
          choice(
            l.colorSourcePreset(n),
            source is _Preset && (source as _Preset).n == n,
            () => onSource(_Preset(n)),
          ),
        choice(l.reduceMotion, reduce, () => onReduce(!reduce)),
        for (final lang in AppLocalizations.supportedLocales)
          choice(
            lang.languageCode.toUpperCase(),
            locale == lang,
            () => onLocale(lang),
          ),
      ],
    );
  }
}

class _GalleryPage extends StatelessWidget {
  const _GalleryPage({required this.controls});

  final Widget controls;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final margin = VSpace.margin(
      windowClassOf(MediaQuery.sizeOf(context).width),
    );
    return Scaffold(
      body: VScreenBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(margin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.galleryTitle, style: theme.textTheme.displaySmall),
                const SizedBox(height: VSpace.s16),
                controls,
                for (final (title, body) in [
                  (l.galleryArtwork, const _ArtworkSection()),
                  (l.galleryTrackRows, const _RowsSection()),
                  (l.galleryPlayer, const _PlayerSection()),
                  (l.galleryButtons, const _ButtonsSection()),
                  (l.galleryShelf, const _ShelfSection()),
                  (l.galleryTransitions, const _TransitionsSection()),
                  (l.galleryFeedback, const _FeedbackSection()),
                  (l.galleryListStates, const _ListStatesSection()),
                  (l.galleryTypography, const _TypeSection()),
                  (l.gallerySpacing, const _SpacingSection()),
                ]) ...[
                  const SizedBox(height: VSpace.s32),
                  Text(title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: VSpace.s16),
                  body,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sample data ─────────────────────────────────────────────────────────────────────

final _track = sampleTracks[1]; // Get Lucky

NowPlayingData _data({
  bool playing = true,
  bool loading = false,
  bool liked = true,
}) => NowPlayingData(
  track: _track,
  sourceTitle: _track.album!.title,
  playing: playing,
  loading: loading,
  durationMs: _track.durationMs!,
  liked: liked,
  download: DownloadStateView.running,
  downloadProgress: 0.4,
  shuffle: false,
  repeat: Repeat.all,
  sleepLeft: const Duration(minutes: 24),
);

void _noop() {}

Future<ImageProvider?> _noCover(String id, int px) async => null;

/// Where the still players stand.
final _fixedPosition = ValueNotifier(137000);

final _actions = NowPlayingActions(
  onPlayPause: _noop,
  onNext: _noop,
  onPrevious: _noop,
  onSeek: (_) {},
  onLike: _noop,
  onAddToPlaylist: _noop,
  onDownload: _noop,
  onShuffle: _noop,
  onRepeat: _noop,
  onOutput: _noop,
  onMenu: (_) {},
  onCollapse: _noop,
);

List<VAction> _quick(AppLocalizations l) => [
  VAction(l.actionPlayNext, VIcons.playNext, _noop),
  VAction(l.actionAddToQueue, VIcons.addToQueue, _noop),
  VAction(l.actionLike, VIcons.favorite, _noop, selected: true),
];

List<List<VAction>> _groups(AppLocalizations l) => [
  [
    VAction(l.actionAddToPlaylist, VIcons.playlistAdd, _noop),
    VAction(l.actionDownload, VIcons.download, _noop),
  ],
  [VAction(l.actionRemove, VIcons.delete, _noop)],
];

Widget _frame(double w, double h, Widget child) => Builder(
  builder: (context) => Container(
    width: w,
    height: h,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(VRadius.medium),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  ),
);

Widget _wrap(List<Widget> children) => Wrap(
  spacing: VSpace.s16,
  runSpacing: VSpace.s16,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: children,
);

/// Wider than the screen: scrolls sideways instead of overflowing.
Widget _wide(double width, Widget child) => SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: SizedBox(width: width, child: child),
);

// ── Sections ────────────────────────────────────────────────────────────────────────

class _ArtworkSection extends StatefulWidget {
  const _ArtworkSection();

  @override
  State<_ArtworkSection> createState() => _ArtworkSectionState();
}

class _ArtworkSectionState extends State<_ArtworkSection> {
  bool _playing = true;
  double _progress = 0.35;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ids = [for (final t in sampleTracks) t.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _wrap([
          VArtwork(itemId: ids[0], size: VSize.shelfCard, playing: false),
          VArtwork(itemId: ids[1], size: VSize.shelfCard, playing: true),
          VArtwork(
            itemId: 'artist:Stromae',
            size: VSize.shelfCard,
            kind: ArtKind.artist,
            playing: false,
          ),
          VArtwork(
            itemId: 'artist:Indila',
            size: VSize.shelfCard,
            kind: ArtKind.artist,
            playing: true,
          ),
          VArtwork(itemId: ids[2], size: VSize.shelfCard, selected: true),
          VArtwork(
            itemId: 'artist:ZAZ',
            size: VSize.shelfCard,
            kind: ArtKind.artist,
            selected: true,
          ),
          VArtwork(
            itemId: ids[3],
            size: VSize.heroCard * 0.6,
            playing: _playing,
            progress: _progress,
            onSeek: (p) => setState(() => _progress = p),
          ),
          VButton(
            label: _playing
                ? AppLocalizations.of(context).actionPause
                : AppLocalizations.of(context).actionPlay,
            style: VButtonStyle.tonal,
            onPressed: () => setState(() => _playing = !_playing),
          ),
        ]),
        const SizedBox(height: VSpace.s24),
        _wrap([
          for (final (i, s) in VDecorShape.values.indexed)
            VDecor(
              shape: s,
              size: VSize.shelfCard * 0.75,
              tilt: i.isEven ? 0 : 0.05,
              child: VSymbol(
                [
                  VIcons.musicNote,
                  VIcons.album,
                  VIcons.explore,
                  VIcons.favorite,
                ][i % 4],
                color: scheme.onSecondaryContainer,
              ),
            ),
        ]),
        const SizedBox(height: VSpace.s24),
        _wrap([
          for (final (i, m) in [
            <String>[],
            [ids[4]],
            [ids[5], ids[6]],
            ids.sublist(7, 11),
          ].indexed)
            VArtwork(
              itemId: 'playlist:$i',
              size: VSize.shelfCard,
              mosaic: m,
              playing: i == 3,
              selected: i == 2,
            ),
        ]),
        const SizedBox(height: VSpace.s24),
        _wrap([
          const VDownloadIcon(state: null),
          const VDownloadIcon(state: DownloadStateView.queued),
          const VDownloadIcon(state: DownloadStateView.running, progress: 0.6),
          const VDownloadIcon(state: DownloadStateView.done),
        ]),
        const SizedBox(height: VSpace.s24),
        SizedBox(
          width: VSize.heroCard,
          child: Column(
            children: [
              VWaveProgress(
                progress: _progress,
                playing: _playing,
                onSeek: (p) => setState(() => _progress = p),
              ),
              VWaveProgress(progress: 0.7, playing: false, onSeek: null),
            ],
          ),
        ),
        const SizedBox(height: VSpace.s24),
        VWaveArtwork(
          itemId: ids[5],
          width: VSize.heroCard,
          progress: _progress,
          playing: _playing,
          onSeek: (p) => setState(() => _progress = p),
        ),
      ],
    );
  }
}

class _RowsSection extends StatefulWidget {
  const _RowsSection();

  @override
  State<_RowsSection> createState() => _RowsSectionState();
}

class _RowsSectionState extends State<_RowsSection> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    VTrackRow row(
      int i, {
      int? number,
      bool? playing,
      bool offline = false,
      bool wide = false,
      double swipe = 0,
    }) => VTrackRow(
      track: sampleTracks[i],
      number: number,
      playing: playing ?? false,
      offline: offline,
      wide: wide,
      selected: _selected == i,
      debugSwipe: swipe,
      onTap: () => setState(() => _selected = i),
      onDoubleTap: _noop,
      onPlayNext: _noop,
      onRemove: _noop,
      quick: _quick(l),
      groups: _groups(l),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: VBreakpoints.medium),
          child: Column(
            children: [
              row(0),
              row(3),
              row(4),
              row(1, playing: true),
              row(2, offline: true),
              row(5, number: 4),
              row(6, number: 5, playing: true),
              row(7, swipe: VSize.swipe),
            ],
          ),
        ),
        const SizedBox(height: VSpace.s16),
        _wide(
          VBreakpoints.expanded + VSpace.s32,
          Column(
            children: [
              for (final (i, t) in sampleTracks.take(6).indexed)
                row(
                  sampleTracks.indexOf(t),
                  number: i + 1,
                  wide: true,
                  playing: i == 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerSection extends StatefulWidget {
  const _PlayerSection();

  @override
  State<_PlayerSection> createState() => _PlayerSectionState();
}

class _PlayerSectionState extends State<_PlayerSection> {
  // The live one: every control works.
  bool _playing = true, _liked = false, _shuffle = false;
  Repeat _repeat = Repeat.off;
  PlayerView _view = PlayerView.player;
  final _position = ValueNotifier(137000);

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = NowPlayingData(
      track: _track,
      sourceTitle: _track.album!.title,
      playing: _playing,
      loading: false,
      durationMs: _track.durationMs!,
      liked: _liked,
      download: null,
      shuffle: _shuffle,
      repeat: _repeat,
    );
    final actions = NowPlayingActions(
      onPlayPause: () => setState(() => _playing = !_playing),
      onNext: _noop,
      onPrevious: () => _position.value = 0,
      onSeek: (ms) => _position.value = ms,
      onLike: () => setState(() => _liked = !_liked),
      onAddToPlaylist: _noop,
      onDownload: _noop,
      onShuffle: () => setState(() => _shuffle = !_shuffle),
      onRepeat: () =>
          setState(() => _repeat = Repeat.values[(_repeat.index + 1) % 3]),
      onOutput: _noop,
      onCollapse: _noop,
      onMenu: (anchor) => showVMenu(
        context,
        anchor: anchor,
        quick: _quick(AppLocalizations.of(context)),
        groups: _groups(AppLocalizations.of(context)),
      ),
    );
    Widget lyrics(BuildContext c) => Padding(
      padding: const EdgeInsets.all(VSpace.s24),
      child: Text(
        sampleTracks.map((t) => t.title).join('\n\n'),
        style: Theme.of(c).textTheme.headlineSmall,
      ),
    );
    Widget queue(BuildContext c) => ListView(
      children: [
        for (final (i, t) in sampleTracks.skip(2).indexed)
          VTrackRow(
            track: t,
            playing: false,
            handleIndex: i,
            onTap: _noop,
            onPlayNext: _noop,
            onRemove: _noop,
            quick: const [],
            groups: const [],
          ),
      ],
    );
    VNowPlaying player(
      PlayerSize size,
      PlayerStyle style,
      PlayerView view, {
      NowPlayingData? data,
      bool wide = false,
    }) => VNowPlaying(
      position: _position,
      data: data ?? _data(),
      size: size,
      style: style,
      view: view,
      onView: (_) {},
      actions: _actions,
      lyrics: lyrics,
      queue: queue,
      wide: wide,
    );
    const medium = Size(VSize.sideSheet, 720),
        large = Size(412, 860),
        compact = Size(VSize.sideSheet, 72);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _wrap([
          _frame(
            large.width,
            large.height,
            VNowPlaying(
              position: _position,
              data: live,
              size: PlayerSize.large,
              style: PlayerStyle.disc,
              view: _view,
              onView: (v) => setState(() => _view = v),
              actions: actions,
              lyrics: lyrics,
              queue: queue,
            ),
          ),
          _frame(
            large.width,
            large.height,
            VNowPlaying(
              position: _position,
              data: live,
              size: PlayerSize.large,
              style: PlayerStyle.wave,
              view: _view,
              onView: (v) => setState(() => _view = v),
              actions: actions,
              lyrics: lyrics,
              queue: queue,
            ),
          ),
        ]),
        const SizedBox(height: VSpace.s24),
        for (final style in PlayerStyle.values) ...[
          _wrap([
            for (final view in PlayerView.values) ...[
              _frame(
                medium.width,
                medium.height,
                player(PlayerSize.medium, style, view),
              ),
              _frame(
                large.width,
                large.height,
                player(PlayerSize.large, style, view),
              ),
            ],
          ]),
          const SizedBox(height: VSpace.s24),
          _wrap([
            for (final view in PlayerView.values)
              _frame(
                compact.width,
                compact.height,
                Padding(
                  padding: const EdgeInsets.all(VSpace.s12),
                  child: player(PlayerSize.compact, style, view),
                ),
              ),
          ]),
          const SizedBox(height: VSpace.s24),
        ],
        // Playing, paused, loading; the desktop strip; wide (landscape, immersive).
        _wrap([
          for (final d in [
            _data(),
            _data(playing: false),
            _data(loading: true),
          ])
            _frame(
              compact.width,
              compact.height,
              Padding(
                padding: const EdgeInsets.all(VSpace.s12),
                child: player(
                  PlayerSize.compact,
                  PlayerStyle.disc,
                  PlayerView.player,
                  data: d,
                ),
              ),
            ),
          _frame(
            VSize.strip,
            300,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: VSpace.s8),
              child: VNowPlaying(
                position: _position,
                data: _data(),
                size: PlayerSize.compact,
                style: PlayerStyle.disc,
                view: PlayerView.player,
                onView: (_) {},
                actions: _actions,
                lyrics: lyrics,
                queue: queue,
                axis: Axis.vertical,
              ),
            ),
          ),
          _frame(
            medium.width,
            medium.height,
            player(
              PlayerSize.medium,
              PlayerStyle.disc,
              PlayerView.player,
              data: _data(playing: false),
            ),
          ),
          _frame(
            medium.width,
            medium.height,
            player(
              PlayerSize.medium,
              PlayerStyle.wave,
              PlayerView.player,
              data: _data(loading: true, playing: false),
            ),
          ),
        ]),
        const SizedBox(height: VSpace.s24),
        _wide(
          900,
          _frame(
            900,
            520,
            player(
              PlayerSize.large,
              PlayerStyle.disc,
              PlayerView.player,
              wide: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _ButtonsSection extends StatefulWidget {
  const _ButtonsSection();

  @override
  State<_ButtonsSection> createState() => _ButtonsSectionState();
}

class _ButtonsSectionState extends State<_ButtonsSection> {
  bool _playing = false, _liked = true;
  PlayerView _view = PlayerView.player;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _wrap([
      VSplitButton(
        label: l.actionPlay,
        icon: VIcons.play,
        onPressed: _noop,
        items: [
          VAction(l.actionShuffle, VIcons.shuffle, _noop),
          VAction(l.actionPlayNext, VIcons.playNext, _noop),
          VAction(l.actionAddToQueue, VIcons.addToQueue, _noop),
        ],
      ),
      VConnectedGroup(
        actions: [
          VAction(
            l.actionLike,
            VIcons.favorite,
            () => setState(() => _liked = !_liked),
            selected: _liked,
          ),
          VAction(l.actionAddToPlaylist, VIcons.playlistAdd, _noop),
          VAction(
            l.actionDownload,
            VIcons.download,
            _noop,
            leading: const VDownloadIcon(state: DownloadStateView.done),
          ),
        ],
      ),
      VControls(
        playing: _playing,
        loading: false,
        shuffle: true,
        repeat: Repeat.one,
        onPlayPause: () => setState(() => _playing = !_playing),
        onNext: _noop,
        onPrevious: _noop,
        onShuffle: _noop,
        onRepeat: _noop,
      ),
      VPlayPauseFab(
        playing: _playing,
        loading: false,
        onPressed: () => setState(() => _playing = !_playing),
      ),
      VPlayPauseFab(playing: false, loading: true, onPressed: _noop),
      VViewSelector(value: _view, onChanged: (v) => setState(() => _view = v)),
      for (final s in VButtonStyle.values)
        VButton(label: l.actionRetry, style: s, onPressed: _noop),
      VIconButton(
        icon: VIcons.favorite,
        label: l.actionLike,
        selected: _liked,
        onPressed: () => setState(() => _liked = !_liked),
      ),
      Builder(
        builder: (b) => VButton(
          label: l.galleryOpenMenu,
          icon: VIcons.more,
          style: VButtonStyle.tonal,
          onPressed: () {
            final box = b.findRenderObject()! as RenderBox;
            showVMenu(
              b,
              anchor: box.localToGlobal(Offset.zero) & box.size,
              quick: _quick(l),
              groups: _groups(l),
            );
          },
        ),
      ),
      const VOfflineChip(),
    ]);
  }
}

class _ShelfSection extends StatelessWidget {
  const _ShelfSection();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cardHeight = VSize.shelfCard + VSpace.s8 + VSpace.s16 * 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VShelf(
          title: l.shelfAlbums,
          onMore: _noop,
          extent: cardHeight,
          items: [
            for (final (id, title, sub) in sampleCollections)
              VCard(itemId: id, title: title, subtitle: sub, onTap: _noop),
          ],
        ),
        const SizedBox(height: VSpace.sectionGap),
        VShelf(
          title: l.shelfArtists,
          extent: cardHeight,
          items: [
            for (final t in sampleTracks.take(8))
              VCard(
                itemId: t.artists.first.id,
                title: t.artists.first.name,
                kind: ArtKind.artist,
                onTap: _noop,
              ),
          ],
        ),
        const SizedBox(height: VSpace.sectionGap),
        VShelf(
          title: l.shelfPlaylists,
          extent: VSize.heroCard + VSpace.s12 + VSpace.s24 * 2,
          itemWidth: VSize.heroCard,
          items: [
            for (final (id, title, sub) in sampleCollections.take(4))
              VHeroCard(itemId: id, title: title, subtitle: sub, onTap: _noop),
          ],
        ),
        const SizedBox(height: VSpace.sectionGap),
        _frame(
          VBreakpoints.medium * 0.6,
          480,
          CustomScrollView(
            slivers: [
              VFlexibleHeader(
                artwork: VArtwork(
                  itemId: sampleCollections.first.$1,
                  size: 220,
                  playing: false,
                ),
                title: sampleCollections.first.$2,
                subtitle: sampleCollections.first.$3,
                actions: [
                  VSplitButton(
                    label: l.actionPlay,
                    icon: VIcons.play,
                    onPressed: _noop,
                    items: [VAction(l.actionShuffle, VIcons.shuffle, _noop)],
                  ),
                ],
                fab: VPlayPauseFab(
                  playing: false,
                  loading: false,
                  onPressed: _noop,
                ),
              ),
              SliverList.builder(
                itemCount: sampleTracks.length,
                itemBuilder: (_, i) => VTrackRow(
                  track: sampleTracks[i],
                  number: i + 1,
                  playing: false,
                  onTap: _noop,
                  onPlayNext: _noop,
                  quick: _quick(l),
                  groups: _groups(l),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransitionsSection extends StatefulWidget {
  const _TransitionsSection();

  @override
  State<_TransitionsSection> createState() => _TransitionsSectionState();
}

class _TransitionsSectionState extends State<_TransitionsSection> {
  List<Page<void>> _pages = [];
  int _axis = 0;

  Widget _page(String title) => Builder(
    builder: (c) => ColoredBox(
      color: Theme.of(c).colorScheme.surfaceContainer,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: VSpace.s16),
            VIconButton(
              icon: VIcons.arrowBack,
              label: AppLocalizations.of(c).actionCollapse,
              onPressed: () =>
                  setState(() => _pages = _pages.sublist(0, _pages.length - 1)),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final first = sampleCollections.first;
    final home = MaterialPage<void>(
      key: const ValueKey('home'),
      child: Center(
        child: vContainerSource(
          heroTag: first.$1,
          child: VCard(
            itemId: first.$1,
            title: first.$2,
            subtitle: first.$3,
            onTap: () => setState(
              () => _pages = [
                vContainerTransformPage(
                  key: const ValueKey('album'),
                  heroTag: first.$1,
                  child: _page(first.$2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return _wrap([
      _frame(
        VSize.sideSheet,
        260,
        Navigator(
          pages: [home, ..._pages],
          onDidRemovePage: (p) =>
              setState(() => _pages = [..._pages]..remove(p)),
        ),
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VButton(
            label: l.transitionContainer,
            style: VButtonStyle.tonal,
            onPressed: () => setState(
              () => _pages = [
                vContainerTransformPage(
                  key: const ValueKey('album'),
                  heroTag: first.$1,
                  child: _page(first.$2),
                ),
              ],
            ),
          ),
          const SizedBox(height: VSpace.s8),
          VButton(
            label: l.transitionFadeThrough,
            style: VButtonStyle.tonal,
            onPressed: () => setState(
              () => _pages = [
                vFadeThroughPage(
                  key: ValueKey('dest${_pages.length}'),
                  child: _page(l.viewQueue),
                ),
              ],
            ),
          ),
          const SizedBox(height: VSpace.s8),
          VButton(
            label: l.transitionSharedAxis,
            style: VButtonStyle.tonal,
            onPressed: () => setState(() => _axis = (_axis + 1) % 3),
          ),
        ],
      ),
      _frame(
        VSize.sideSheet,
        120,
        Center(
          child: vSharedAxis(
            key: _axis,
            child: Text(
              [l.viewPlayer, l.viewLyrics, l.viewQueue][_axis],
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
        ),
      ),
    ]);
  }
}

class _FeedbackSection extends StatefulWidget {
  const _FeedbackSection();

  @override
  State<_FeedbackSection> createState() => _FeedbackSectionState();
}

class _FeedbackSectionState extends State<_FeedbackSection> {
  bool _sheet = true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _wrap([
          const VLoading(),
          const VLoading(size: VSize.playIcon),
          VButton(
            label: l.galleryShowSnack,
            style: VButtonStyle.tonal,
            onPressed: () => showVSnack(
              context,
              l.playbackStopped,
              actionLabel: l.actionUndo,
              onAction: _noop,
              duration: VDurations.undo,
            ),
          ),
          VButton(
            label: l.galleryToggleSheet,
            style: VButtonStyle.tonal,
            onPressed: () => setState(() => _sheet = !_sheet),
          ),
        ]),
        const SizedBox(height: VSpace.s16),
        _wide(
          VBreakpoints.expanded,
          _frame(
            VBreakpoints.expanded,
            420,
            Row(
              children: [
                Expanded(
                  child: VRefresh(
                    onRefresh: () async {},
                    child: ListView(
                      children: [
                        for (final t in sampleTracks)
                          VTrackRow(
                            track: t,
                            playing: false,
                            onTap: _noop,
                            onPlayNext: _noop,
                            quick: _quick(l),
                            groups: _groups(l),
                          ),
                      ],
                    ),
                  ),
                ),
                VSideSheet(
                  open: _sheet,
                  child: VNowPlaying(
                    position: _fixedPosition,
                    data: _data(),
                    size: PlayerSize.medium,
                    style: PlayerStyle.disc,
                    view: PlayerView.player,
                    onView: (_) {},
                    actions: _actions,
                    lyrics: (_) => const SizedBox(),
                    queue: (_) => const SizedBox(),
                    onImmersive: _noop,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ListStatesSection extends StatelessWidget {
  const _ListStatesSection();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget list(Future<List<String>> Function() load) => _frame(
      VSize.sideSheet * 0.75,
      400,
      CustomScrollView(
        slivers: [
          VAsyncList<String>(
            load: load,
            builder: (_, items) => SliverList.builder(
              itemCount: items.length,
              itemBuilder: (_, i) => Text(items[i]),
            ),
            empty: VEmptyState(icon: VIcons.favorite, message: l.emptyLikes),
            errorText: (_) => l.errorNetwork,
          ),
        ],
      ),
    );
    return _wrap([
      list(() => Completer<List<String>>().future),
      list(() async => []),
      list(() async => throw const CoreError.network()),
      list(() async => throw const CoreError.offline()),
    ]);
  }
}

class _TypeSection extends StatelessWidget {
  const _TypeSection();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final styles = [
      t.displayLarge,
      t.displayMedium,
      t.displaySmall,
      t.headlineLarge,
      t.headlineMedium,
      t.headlineSmall,
      t.titleLarge,
      t.titleMedium,
      t.titleSmall,
      t.bodyLarge,
      t.bodyMedium,
      t.bodySmall,
      t.labelLarge,
      t.labelMedium,
      t.labelSmall,
    ];
    final muted = t.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, s) in styles.indexed) ...[
          Text(
            '${s?.fontSize?.round()} · ${s?.fontWeight?.value}',
            style: muted,
          ),
          Text(
            sampleTracks[i % sampleTracks.length].title,
            style: s,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: VSpace.s8),
        ],
      ],
    );
  }
}

class _SpacingSection extends StatelessWidget {
  const _SpacingSection();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.labelMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _wrap([
          for (final s in [
            VSpace.s4,
            VSpace.s8,
            VSpace.s12,
            VSpace.s16,
            VSpace.s24,
            VSpace.s32,
          ])
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: s, height: VSpace.s32, color: scheme.primary),
                const SizedBox(height: VSpace.s4),
                Text('${s.round()}', style: muted),
              ],
            ),
        ]),
        const SizedBox(height: VSpace.s16),
        _wrap([
          for (final r in [VRadius.small, VRadius.medium, VRadius.large])
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: VSize.shelfCard * 0.6,
                  height: VSize.shelfCard * 0.6,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(r),
                  ),
                ),
                const SizedBox(height: VSpace.s4),
                Text('${r.round()}', style: muted),
              ],
            ),
        ]),
      ],
    );
  }
}
