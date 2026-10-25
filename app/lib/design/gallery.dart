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
import '../bridge/catalog.dart';
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
      // Debug only: a local feed, `--dart-define=VEHICOULE_DEV_FEED=<url> --dart-define=
      // VEHICOULE_DEV_FEED_KEY=<public key>` (debug builds of the core accept http).
      const devFeed = String.fromEnvironment('VEHICOULE_DEV_FEED');
      if (devFeed.isNotEmpty) {
        await core.addFeed(
          url: devFeed,
          publicKey: const String.fromEnvironment('VEHICOULE_DEV_FEED_KEY'),
        );
      }
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

/// The theme's color source: what's playing (the default, spec UI §2.2), the system,
/// two presets.
sealed class _Source {
  const _Source();
}

class _NowPlaying extends _Source {
  const _NowPlaying();
}

class _System extends _Source {
  const _System();
}

class _Preset extends _Source {
  const _Preset(this.n);
  final int n;
}

class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key, this.covers, this.resolve, this.seedFile});

  /// Null in tests and without a core: missing covers everywhere.
  final GalleryCovers? covers;

  /// Pictures from elsewhere (screenshots of the gallery); [covers] wins.
  final ArtworkSource? resolve;

  /// The 112 px cover file of a sample id, for the theme's seed (tests); [covers] wins.
  final Future<String?> Function(String itemId)? seedFile;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  _Brightness _brightness = _Brightness.light;
  _Source _source = const _NowPlaying();

  /// The sample track that plays: the gallery's players show it, and with « Ce qui
  /// joue » the theme takes its seed from its cover.
  int _playing = 1;
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
    final playing = _playing;
    final seed = switch (s) {
      _NowPlaying() => await _artSeed(sampleTracks[playing].id),
      _System() => await systemSeed(),
      _Preset(:final n) => VPresets.seeds[n - 1],
    };
    if (mounted && seed != null && _source == s && _playing == playing) {
      setState(() => _seed = seed);
    }
  }

  /// The seed of a track's cover: its 112 px file, extracted once per cover
  /// (`seedFromArtwork`, pastel, cached).
  Future<Color?> _artSeed(String id) async {
    final path =
        await (widget.covers?.file(id, 112) ?? widget.seedFile?.call(id));
    return path == null ? null : seedFromArtwork(path);
  }

  /// The next sample track plays: the players follow, and so does the theme.
  void _next() {
    setState(() => _playing = (_playing + 1) % sampleTracks.length);
    if (_source is _NowPlaying) _apply(_source);
  }

  @override
  Widget build(BuildContext context) {
    _playingIndex = _playing;
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
          resolve: widget.covers?.resolve ?? widget.resolve ?? _noCover,
          child: vAppBuilder(context, child),
        ),
      ),
      home: _GalleryTrack(
        index: _playing,
        next: _next,
        child: _GalleryPage(
          controls: _Controls(
            brightness: _brightness,
            source: _source,
            reduce: _reduce,
            locale: _locale,
            onBrightness: (b) => setState(() => _brightness = b),
            onSource: _apply,
            onReduce: (r) => setState(() => _reduce = r),
            onLocale: (l) => setState(() => _locale = l),
            onNext: _next,
          ),
        ),
      ),
    );
  }
}

/// The playing sample track, for the sections that show it.
class _GalleryTrack extends InheritedWidget {
  const _GalleryTrack({
    required this.index,
    required this.next,
    required super.child,
  });

  final int index;
  final VoidCallback next;

  static _GalleryTrack? watch(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_GalleryTrack>();

  @override
  bool updateShouldNotify(_GalleryTrack old) => old.index != index;
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
    required this.onNext,
  });

  final VoidCallback onNext;
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
        choice(
          l.colorSourceNowPlaying,
          source is _NowPlaying,
          () => onSource(const _NowPlaying()),
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
        VButton(
          label: l.actionNext,
          icon: VIcons.skipNext,
          style: VButtonStyle.tonal,
          onPressed: onNext,
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

/// The gallery's sections, in order: a jump list at the top leads to each.
class _GalleryPage extends StatefulWidget {
  const _GalleryPage({required this.controls});

  final Widget controls;

  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage> {
  final _keys = <int, GlobalKey>{};

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final margin = VSpace.margin(
      windowClassOf(MediaQuery.sizeOf(context).width),
    );
    final sections = [
      (l.galleryArtwork, const _ArtworkSection()),
      (l.galleryTrackRows, const _RowsSection()),
      (l.galleryMiniPlayer, const _MiniSection()),
      (l.galleryPlayer, const _PlayerSection()),
      (l.galleryButtons, const _ButtonsSection()),
      (l.galleryFabs, const _FabSection()),
      (l.galleryButtonGroups, const _GroupsSection()),
      (l.galleryToolbars, const _ToolbarSection()),
      (l.galleryMenus, const _MenuSection()),
      (l.gallerySheets, const _SheetSection()),
      (l.galleryNavigation, const _NavigationSection()),
      (l.gallerySearch, const _SearchSection()),
      (l.galleryCarousels, const _CarouselSection()),
      (l.gallerySettings, const _SettingsSection()),
      (l.galleryStates, const _StatesSection()),
      (l.galleryListStates, const _ListStatesSection()),
      (l.galleryTransitions, const _TransitionsSection()),
      (l.galleryTypography, const _TypeSection()),
      (l.gallerySpacing, const _SpacingSection()),
    ];
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
                widget.controls,
                const SizedBox(height: VSpace.s24),
                Text(l.galleryJump, style: theme.textTheme.titleMedium),
                const SizedBox(height: VSpace.s8),
                Wrap(
                  spacing: VSpace.s8,
                  runSpacing: VSpace.s8,
                  children: [
                    for (final (i, (title, _)) in sections.indexed)
                      VChip(
                        label: title,
                        onPressed: () {
                          final c = _keys[i]?.currentContext;
                          if (c != null) Scrollable.ensureVisible(c);
                        },
                      ),
                  ],
                ),
                for (final (i, (title, body)) in sections.indexed) ...[
                  const SizedBox(height: VSpace.s32),
                  Text(
                    title,
                    key: _keys.putIfAbsent(i, GlobalKey.new),
                    style: theme.textTheme.headlineSmall,
                  ),
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

/// The playing sample track (Get Lucky first); « Titre suivant » moves it on.
int _playingIndex = 1;
TrackView get _track => sampleTracks[_playingIndex];

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
  onOpen: _noop,
  onStop: _noop,
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

List<VDestination> _destinations(AppLocalizations l) => [
  VDestination(l.navHome, VIcons.home),
  VDestination(l.navExplore, VIcons.explore),
  VDestination(l.navLibrary, VIcons.library, badge: 2),
  VDestination(l.navSettings, VIcons.settings),
];

Widget _lyrics(BuildContext c) => ListView(
  padding: const EdgeInsets.all(VSpace.s24),
  children: [
    for (final (i, t) in sampleTracks.indexed)
      Padding(
        padding: const EdgeInsets.only(bottom: VSpace.s16),
        child: Text(
          t.title,
          style: i == 2
              ? Theme.of(c).textTheme.headlineMedium
              : Theme.of(c).textTheme.titleLarge
                    ?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant),
        ),
      ),
  ],
);

Widget _queue(BuildContext c) => ListView(
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

/// A screen-shaped frame: what a component looks like in place, not on a card.
Widget _screen(double w, double h, Widget child) => Builder(
  builder: (context) => Container(
    width: w,
    height: h,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(VRadius.large),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  ),
);

/// Filler content behind floating components: skeleton rows, cut by the frame.
Widget _filler(int rows) => ListView(
  physics: const NeverScrollableScrollPhysics(),
  padding: const EdgeInsets.only(top: VSpace.s8),
  children: [for (var i = 0; i < rows; i++) VSkeleton.row()],
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
        ]),
        const SizedBox(height: VSpace.s24),
        // The ring is the artwork's own outline: cookie, square in pause, circle.
        _wrap([
          VArtwork(
            itemId: ids[3],
            size: VSize.heroCard * 0.7,
            playing: _playing,
            progress: _progress,
            onSeek: (p) => setState(() => _progress = p),
          ),
          VArtwork(
            itemId: 'artist:Indila',
            kind: ArtKind.artist,
            size: VSize.heroCard * 0.5,
            playing: _playing,
            progress: _progress,
            onSeek: (p) => setState(() => _progress = p),
          ),
          VArtwork(
            itemId: ids[3],
            size: VSize.compactArt,
            playing: _playing,
            progress: _progress,
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

/// The mini player where it lives: floating over the bar, playing, paused and loading;
/// the desktop strip at the window's edge.
class _MiniSection extends StatefulWidget {
  const _MiniSection();

  @override
  State<_MiniSection> createState() => _MiniSectionState();
}

class _MiniSectionState extends State<_MiniSection> {
  int _tab = 0;
  double _volume = 0.6;

  @override
  Widget build(BuildContext context) {
    // The playing sample track: rebuilt when it changes.
    _GalleryTrack.watch(context);
    final l = AppLocalizations.of(context);
    Widget phone(NowPlayingData d, {bool hint = false}) {
      final mini = VNowPlaying(
        position: _fixedPosition,
        data: d,
        size: PlayerSize.compact,
        style: PlayerStyle.disc,
        view: PlayerView.player,
        onView: (_) {},
        actions: _actions,
        lyrics: _lyrics,
        queue: _queue,
      );
      return _screen(
        VSize.sideSheet,
        VSize.sideSheet,
        Column(
          children: [
            Expanded(child: ClipRect(child: _filler(4))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.s16),
              child: hint
                  ? VRichTooltip(
                      title: l.gestureHintTitle,
                      message: l.gestureHint,
                      child: mini,
                    )
                  : mini,
            ),
            const SizedBox(height: VSpace.s8),
            VNavigationBar(
              destinations: _destinations(l),
              selected: _tab,
              onSelected: (i) => setState(() => _tab = i),
            ),
          ],
        ),
      );
    }

    return _wrap([
      const _FlightDemo(),
      phone(_data(), hint: true),
      phone(_data(playing: false)),
      phone(_data(playing: false, loading: true)),
      _screen(
        VSize.sideSheet,
        VSize.sideSheet * 1.6,
        Row(
          children: [
            Expanded(child: ClipRect(child: _filler(9))),
            Builder(
              builder: (context) => ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: SizedBox(
                  width: VSize.strip,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: VSpace.s16),
                    child: VNowPlaying(
                      position: _fixedPosition,
                      data: _data(),
                      size: PlayerSize.compact,
                      style: PlayerStyle.disc,
                      view: PlayerView.player,
                      onView: (_) {},
                      actions: _actions,
                      lyrics: _lyrics,
                      queue: _queue,
                      axis: Axis.vertical,
                      volume: SizedBox(
                        height: VSize.shelfCard * 1.5,
                        child: VVolume(
                          value: _volume,
                          vertical: true,
                          onChanged: (v) => setState(() => _volume = v),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

/// The mini player → player flight driven by a sheet's extent (here a slider): both
/// players hide their own artwork, [VExtentFlight] draws it between the rects they report.
class _FlightDemo extends StatefulWidget {
  const _FlightDemo();

  @override
  State<_FlightDemo> createState() => _FlightDemoState();
}

class _FlightDemoState extends State<_FlightDemo> {
  final _stack = GlobalKey();
  double _extent = 0;
  Rect? _from, _to;

  /// A global rect, in the frame's coordinates.
  Rect? _local(Rect? global) {
    final box = _stack.currentContext?.findRenderObject() as RenderBox?;
    if (global == null || box == null || !box.hasSize) return null;
    return box.globalToLocal(global.topLeft) & global.size;
  }

  void _set(Rect r, {required bool mini}) {
    if (mini ? r == _from : r == _to) return;
    setState(() => mini ? _from = r : _to = r);
  }

  @override
  Widget build(BuildContext context) {
    // The playing sample track: rebuilt when it changes.
    _GalleryTrack.watch(context);
    final l = AppLocalizations.of(context);
    final from = _local(_from), to = _local(_to);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _screen(
          VSize.sideSheet,
          VSize.sideSheet * 1.8,
          Stack(
            key: _stack,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _extent < 1,
                  child: Opacity(
                    opacity: _extent,
                    child: VNowPlaying(
                      position: _fixedPosition,
                      data: _data(),
                      size: PlayerSize.large,
                      style: PlayerStyle.disc,
                      view: PlayerView.player,
                      onView: (_) {},
                      actions: _actions,
                      lyrics: _lyrics,
                      queue: _queue,
                      artworkVisible: false,
                      onArtworkRect: (r) => _set(r, mini: false),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: VSpace.s16,
                right: VSpace.s16,
                bottom: VSpace.s16,
                child: Opacity(
                  opacity: 1 - _extent,
                  child: VNowPlaying(
                    position: _fixedPosition,
                    data: _data(),
                    size: PlayerSize.compact,
                    style: PlayerStyle.disc,
                    view: PlayerView.player,
                    onView: (_) {},
                    actions: _actions,
                    lyrics: _lyrics,
                    queue: _queue,
                    artworkVisible: false,
                    onArtworkRect: (r) => _set(r, mini: true),
                  ),
                ),
              ),
              if (from != null && to != null)
                VExtentFlight(
                  extent: _extent,
                  from: from,
                  to: to,
                  builder: (context, side) => VArtwork(
                    itemId: _track.id,
                    size: side,
                    playing: true,
                    progress: 0.37,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: VSpace.s8),
        SizedBox(
          width: VSize.sideSheet,
          child: VSlider(
            value: _extent,
            label: l.actionOpenPlayer,
            onChanged: (v) => setState(() => _extent = v),
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
  double _volume = 0.6;
  final _position = ValueNotifier(137000);

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The playing sample track: rebuilt when it changes.
    final playing = _GalleryTrack.watch(context);
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
      onNext: playing?.next ?? _noop,
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
    VNowPlaying player(
      PlayerSize size,
      PlayerStyle style,
      PlayerView view, {
      NowPlayingData? data,
      bool immersive = false,
      Widget? volume,
    }) => VNowPlaying(
      position: _position,
      data: data ?? _data(),
      size: size,
      style: style,
      view: view,
      onView: (_) {},
      actions: _actions,
      lyrics: _lyrics,
      queue: _queue,
      immersive: immersive,
      onImmersive: size == PlayerSize.medium || immersive ? _noop : null,
      volume: volume,
    );
    const medium = Size(VSize.sideSheet, 760), large = Size(412, 892);
    Widget volume() =>
        VVolume(value: _volume, onChanged: (v) => setState(() => _volume = v));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _wrap([
          for (final style in PlayerStyle.values)
            _screen(
              large.width,
              large.height,
              VNowPlaying(
                position: _position,
                data: live,
                size: PlayerSize.large,
                style: style,
                view: _view,
                onView: (v) => setState(() => _view = v),
                actions: actions,
                lyrics: _lyrics,
                queue: _queue,
              ),
            ),
        ]),
        const SizedBox(height: VSpace.s24),
        for (final style in PlayerStyle.values) ...[
          _wrap([
            for (final view in VViewSelector.order)
              _screen(
                large.width,
                large.height,
                player(PlayerSize.large, style, view),
              ),
            for (final view in VViewSelector.order)
              _screen(
                medium.width,
                medium.height,
                player(PlayerSize.medium, style, view, volume: volume()),
              ),
          ]),
          const SizedBox(height: VSpace.s24),
        ],
        _wrap([
          _screen(
            medium.width,
            medium.height,
            player(
              PlayerSize.medium,
              PlayerStyle.disc,
              PlayerView.player,
              data: _data(playing: false),
              volume: volume(),
            ),
          ),
          _screen(
            medium.width,
            medium.height,
            player(
              PlayerSize.medium,
              PlayerStyle.wave,
              PlayerView.player,
              data: _data(loading: true, playing: false),
              volume: volume(),
            ),
          ),
        ]),
        const SizedBox(height: VSpace.s24),
        // The desktop immersive view (⤢ in the pane; ⤡ or Esc to leave).
        for (final style in PlayerStyle.values) ...[
          _wide(
            1280,
            _screen(
              1280,
              800,
              player(
                PlayerSize.large,
                style,
                style == PlayerStyle.disc
                    ? PlayerView.lyrics
                    : PlayerView.queue,
                immersive: true,
              ),
            ),
          ),
          const SizedBox(height: VSpace.s16),
        ],
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
  bool _liked = true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _wrap([
          for (final s in VButtonStyle.values)
            VButton(label: l.actionRetry, style: s, onPressed: _noop),
          VButton(label: l.actionPlay, icon: VIcons.play, onPressed: _noop),
        ]),
        const SizedBox(height: VSpace.s16),
        _wrap([
          for (final s in VIconStyle.values)
            VIconButton(
              icon: VIcons.playlistAdd,
              label: l.actionAddToPlaylist,
              style: s,
              onPressed: _noop,
            ),
          // Toggles: the heart fills, the shape morphs.
          for (final s in VIconStyle.values)
            VIconButton(
              icon: VIcons.favorite,
              label: l.actionLike,
              selected: _liked,
              style: s,
              onPressed: () => setState(() => _liked = !_liked),
            ),
        ]),
        const SizedBox(height: VSpace.s16),
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
      ],
    );
  }
}

/// FABs: three sizes; the album's extended « Lire » that shrinks on scroll; the
/// library's FAB menu.
class _FabSection extends StatefulWidget {
  const _FabSection();

  @override
  State<_FabSection> createState() => _FabSectionState();
}

class _FabSectionState extends State<_FabSection> {
  bool _extended = true;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _wrap([
      for (final s in VFabSize.values)
        VFab(icon: VIcons.play, label: l.actionPlay, size: s, onPressed: _noop),
      _screen(
        VSize.sideSheet,
        VSize.sideSheet,
        Stack(
          children: [
            NotificationListener<ScrollUpdateNotification>(
              onNotification: (n) {
                final next = n.metrics.pixels <= VSpace.s8;
                if (next != _extended) setState(() => _extended = next);
                return false;
              },
              child: ListView(
                children: [
                  for (final (i, t) in sampleTracks.indexed)
                    VTrackRow(
                      track: t,
                      number: i + 1,
                      playing: false,
                      onTap: _noop,
                      onPlayNext: _noop,
                      quick: const [],
                      groups: const [],
                    ),
                ],
              ),
            ),
            PositionedDirectional(
              end: VSpace.s16,
              bottom: VSpace.s16,
              child: VExtendedFab(
                icon: VIcons.play,
                label: l.actionPlay,
                extended: _extended,
                onPressed: _noop,
              ),
            ),
          ],
        ),
      ),
      _screen(
        VSize.sideSheet,
        VSize.sideSheet,
        Stack(
          children: [
            _filler(5),
            PositionedDirectional(
              end: VSpace.s16,
              bottom: VSpace.s16,
              child: VFabMenu(
                items: [
                  VAction(l.actionNewPlaylist, VIcons.playlistAdd, _noop),
                  VAction(l.actionImportLink, VIcons.addLink, _noop),
                ],
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

/// Standard (the player's controls) and connected (like / playlist / download, the
/// menu's quick row) button groups, and a choice.
class _GroupsSection extends StatefulWidget {
  const _GroupsSection();

  @override
  State<_GroupsSection> createState() => _GroupsSectionState();
}

class _GroupsSectionState extends State<_GroupsSection> {
  bool _playing = false, _liked = true;
  PlayerStyle _style = PlayerStyle.disc;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: VSize.sideSheet,
          child: VControls(
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
        ),
        const SizedBox(height: VSpace.s16),
        SizedBox(
          width: VSize.sideSheet * 0.6,
          child: VConnectedGroup(
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
        ),
        const SizedBox(height: VSpace.s16),
        SizedBox(
          width: VSize.sideSheet,
          child: VChoiceGroup<PlayerStyle>(
            choices: [
              (PlayerStyle.disc, l.playerStyleDisc),
              (PlayerStyle.wave, l.playerStyleWave),
            ],
            value: _style,
            onChanged: (s) => setState(() => _style = s),
          ),
        ),
      ],
    );
  }
}

/// Floating (the mini player's, the view selector, multiple selection) and docked.
class _ToolbarSection extends StatefulWidget {
  const _ToolbarSection();

  @override
  State<_ToolbarSection> createState() => _ToolbarSectionState();
}

class _ToolbarSectionState extends State<_ToolbarSection> {
  PlayerView _view = PlayerView.lyrics;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final selection = [
      VAction(l.actionPlayNext, VIcons.playNext, _noop),
      VAction(l.actionAddToPlaylist, VIcons.playlistAdd, _noop),
      VAction(l.actionDownload, VIcons.download, _noop),
    ];
    return _wrap([
      VViewSelector(value: _view, onChanged: (v) => setState(() => _view = v)),
      VToolbar(
        title: l.selectionCount(3),
        leading: VIconButton(
          icon: VIcons.close,
          label: l.actionCancel,
          onPressed: _noop,
        ),
        actions: selection,
      ),
      _screen(
        VSize.sideSheet,
        VSize.shelfCard * 2,
        Column(
          children: [
            Expanded(child: ClipRect(child: _filler(3))),
            VToolbar(
              docked: true,
              actions: [
                VAction(l.actionSelectAll, VIcons.selectAll, _noop),
                ...selection,
              ],
            ),
          ],
        ),
      ),
    ]);
  }
}

/// The expressive menu next to its trigger: ⋮ at the right edge and near the bottom.
class _MenuSection extends StatelessWidget {
  const _MenuSection();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget opener(String label) => Builder(
      builder: (b) => VIconButton(
        icon: VIcons.more,
        label: label,
        style: VIconStyle.tonal,
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
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: opener(l.galleryOpenMenuEdge),
        ),
        const SizedBox(height: VSpace.s8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: VBreakpoints.medium),
          child: VTrackRow(
            track: sampleTracks[4],
            playing: false,
            onTap: _noop,
            onPlayNext: _noop,
            quick: _quick(l),
            groups: _groups(l),
          ),
        ),
      ],
    );
  }
}

/// Side sheets (the desktop pane, standard; a modal one), bottom sheets (add to a
/// playlist, add a source; a standard one), a dialog, a snackbar.
class _SheetSection extends StatefulWidget {
  const _SheetSection();

  @override
  State<_SheetSection> createState() => _SheetSectionState();
}

class _SheetSectionState extends State<_SheetSection> {
  bool _pane = true;

  Widget _addToPlaylist(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.actionAddToPlaylist, style: theme.textTheme.titleLarge),
        const SizedBox(height: VSpace.s16),
        VButton(
          label: l.actionNewPlaylist,
          icon: VIcons.add,
          style: VButtonStyle.tonal,
          onPressed: _noop,
        ),
        const SizedBox(height: VSpace.s8),
        for (final (i, (id, title, sub)) in sampleCollections.take(4).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: VSpace.s4),
            child: Row(
              children: [
                // Those that already hold the song: cookie + check (spec UI §5.8).
                VArtwork(itemId: id, size: VSize.trackArt, selected: i == 1),
                const SizedBox(width: VSpace.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(sub, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _addSource(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.actionAddSource, style: theme.textTheme.titleLarge),
        const SizedBox(height: VSpace.s8),
        Text(l.addSourceWarning, style: theme.textTheme.bodyMedium),
        const SizedBox(height: VSpace.s24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            VButton(
              label: l.actionCancel,
              style: VButtonStyle.text,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: VSpace.s8),
            VButton(
              label: l.actionAdd,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The playing sample track: rebuilt when it changes.
    _GalleryTrack.watch(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _wrap([
          VButton(
            label: l.galleryShowSheet,
            style: VButtonStyle.tonal,
            onPressed: () => showVSheet<void>(context, builder: _addToPlaylist),
          ),
          VButton(
            label: l.galleryShowSourceSheet,
            style: VButtonStyle.tonal,
            onPressed: () => showVSheet<void>(context, builder: _addSource),
          ),
          VButton(
            label: l.galleryShowSideSheet,
            style: VButtonStyle.tonal,
            onPressed: () => showVSideSheet(
              context,
              title: l.viewQueue,
              body: _queue(context),
            ),
          ),
          VButton(
            label: l.galleryShowDialog,
            style: VButtonStyle.tonal,
            onPressed: () => showVDialog(
              context,
              title: l.updateTitle,
              message: l.updateBody('1.2', '18 Mo'),
              action: l.actionInstall,
              cancel: l.actionLater,
            ),
          ),
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
            onPressed: () => setState(() => _pane = !_pane),
          ),
        ]),
        const SizedBox(height: VSpace.s16),
        _wide(
          VBreakpoints.expanded,
          _screen(
            VBreakpoints.expanded,
            640,
            Row(
              children: [
                Expanded(
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
                VSideSheet(
                  open: _pane,
                  child: VNowPlaying(
                    position: _fixedPosition,
                    data: _data(),
                    size: PlayerSize.medium,
                    style: PlayerStyle.disc,
                    view: PlayerView.player,
                    onView: (_) {},
                    actions: _actions,
                    lyrics: _lyrics,
                    queue: _queue,
                    onImmersive: _noop,
                    volume: VVolume(value: 0.6, onChanged: (_) {}),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: VSpace.s16),
        _screen(
          VSize.sideSheet,
          VSize.sideSheet,
          Stack(
            children: [
              _filler(5),
              VStandardSheet(
                child: Padding(
                  padding: const EdgeInsets.all(VSpace.s16),
                  child: Text(
                    l.addSourceWarning,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The phone's bar, the desktop rail collapsed and expanded with its pinned items.
class _NavigationSection extends StatefulWidget {
  const _NavigationSection();

  @override
  State<_NavigationSection> createState() => _NavigationSectionState();
}

class _NavigationSectionState extends State<_NavigationSection> {
  int _tab = 1;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pinned = [
      VPinned('playlist:liked', l.likedTracks),
      VPinned(sampleCollections.first.$1, sampleCollections.first.$2),
      VPinned('artist:Stromae', 'Stromae', kind: ArtKind.artist),
    ];
    Widget rail(bool expanded) => _screen(
      expanded ? VSize.sideSheet : VSize.strip + VSpace.s32,
      VSize.sideSheet * 1.6,
      VNavigationRail(
        destinations: _destinations(l),
        pinned: pinned,
        selected: _tab,
        onSelected: (i) => setState(() => _tab = i),
        expanded: expanded,
        onExpanded: (_) {},
      ),
    );
    return _wrap([
      SizedBox(
        width: VSize.sideSheet + VSpace.s32,
        child: VNavigationBar(
          destinations: _destinations(l),
          selected: _tab.clamp(0, 3),
          onSelected: (i) => setState(() => _tab = i),
        ),
      ),
      rail(false),
      rail(true),
    ]);
  }
}

/// The search bar with its suggestions, and the chips that filter results.
class _SearchSection extends StatefulWidget {
  const _SearchSection();

  @override
  State<_SearchSection> createState() => _SearchSectionState();
}

class _SearchSectionState extends State<_SearchSection> {
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: VBreakpoints.medium),
          child: VSearchBar(
            suggestions: (context, text) => [
              for (final t in sampleTracks.where(
                (t) => t.title.toLowerCase().contains(text.toLowerCase()),
              ))
                VTrackRow(
                  track: t,
                  playing: false,
                  onTap: _noop,
                  onPlayNext: _noop,
                  quick: const [],
                  groups: const [],
                ),
            ],
          ),
        ),
        const SizedBox(height: VSpace.s16),
        Wrap(
          spacing: VSpace.s8,
          runSpacing: VSpace.s8,
          children: [
            for (final (i, label) in [
              l.shelfTracks,
              l.shelfAlbums,
              l.shelfArtists,
              l.shelfPlaylists,
            ].indexed)
              VChip(
                label: label,
                filter: true,
                selected: _filter == i,
                onPressed: () => setState(() => _filter = i),
              ),
            VChip(
              label: l.actionShuffle,
              icon: VIcons.shuffle,
              onPressed: _noop,
            ),
          ],
        ),
      ],
    );
  }
}

/// Hero (home), multi-browse (artist), uncontained; the shelves; the flexible header.
class _CarouselSection extends StatelessWidget {
  const _CarouselSection();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = [
      for (final (id, title, sub) in sampleCollections)
        VCarouselItem(itemId: id, title: title, subtitle: sub, onTap: _noop),
    ];
    final cardHeight = VSize.shelfCard + VSpace.s8 + VSpace.s16 * 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: VBreakpoints.medium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.discoveryTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: VSpace.s8),
              VCarousel(
                kind: VCarouselKind.hero,
                items: items,
                height: VSize.heroCard * 0.8,
              ),
              const SizedBox(height: VSpace.sectionGap),
              Text(
                l.shelfAlbums,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: VSpace.s8),
              VCarousel(
                kind: VCarouselKind.multiBrowse,
                items: items,
                height: VSize.heroCard * 0.6,
              ),
              const SizedBox(height: VSpace.sectionGap),
              VCarousel(
                kind: VCarouselKind.uncontained,
                items: items,
                height: VSize.shelfCard * 1.5,
              ),
            ],
          ),
        ),
        const SizedBox(height: VSpace.sectionGap),
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
        _wrap([
          _screen(
            VSize.sideSheet,
            480,
            CustomScrollView(
              slivers: [
                VLargeAppBar(
                  title: l.greeting,
                  leading: VIconButton(
                    icon: VIcons.menu,
                    label: l.actionExpandMenu,
                    onPressed: _noop,
                  ),
                ),
                SliverList.builder(
                  itemCount: 8,
                  itemBuilder: (_, i) => VSkeleton.row(),
                ),
              ],
            ),
          ),
          _screen(
            VSize.sideSheet,
            480,
            CustomScrollView(
              slivers: [
                VFlexibleHeader(
                  artwork: VArtwork(
                    itemId: sampleCollections.first.$1,
                    size: VSize.headerArt,
                    playing: true,
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
                  fab: VFab(
                    icon: VIcons.play,
                    label: l.actionPlay,
                    onPressed: _noop,
                  ),
                ),
                SliverList.builder(
                  itemCount: sampleTracks.length,
                  itemBuilder: (_, i) => VTrackRow(
                    track: sampleTracks[i],
                    number: i + 1,
                    playing: i == 1,
                    onTap: _noop,
                    onPlayNext: _noop,
                    quick: _quick(l),
                    groups: _groups(l),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ],
    );
  }
}

/// Réglages › Apparence: a live compact player on top, then rounded groups whose
/// choices are connected button groups (spec UI §6.7).
class _SettingsSection extends StatefulWidget {
  const _SettingsSection();

  @override
  State<_SettingsSection> createState() => _SettingsSectionState();
}

enum _Theme { system, light, dark }

enum _Color { nowPlaying, system, preset }

class _SettingsSectionState extends State<_SettingsSection> {
  _Color _color = _Color.nowPlaying;
  _Theme _theme = _Theme.system;
  PlayerStyle _style = PlayerStyle.disc;
  bool _black = false, _normalize = true, _radio = true;
  double _volume = 0.6;

  @override
  Widget build(BuildContext context) {
    // The playing sample track: rebuilt when it changes.
    _GalleryTrack.watch(context);
    final l = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: VBreakpoints.medium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.settingsAppearance,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: VSpace.s16),
          VNowPlaying(
            position: _fixedPosition,
            data: _data(),
            size: PlayerSize.compact,
            style: _style,
            view: PlayerView.player,
            onView: (_) {},
            actions: _actions,
            lyrics: _lyrics,
            queue: _queue,
          ),
          const SizedBox(height: VSpace.s24),
          VListGroup(
            title: l.settingsColor,
            children: [
              VListRow(
                below: VChoiceGroup<_Color>(
                  choices: [
                    (_Color.nowPlaying, l.colorSourceNowPlaying),
                    (_Color.system, l.themeSystem),
                    (_Color.preset, l.colorSourcePresets),
                  ],
                  value: _color,
                  onChanged: (c) => setState(() => _color = c),
                ),
              ),
              VListRow(
                title: l.themePureBlack,
                trailing: VSwitch(
                  value: _black,
                  label: l.themePureBlack,
                  onChanged: (v) => setState(() => _black = v),
                ),
                onTap: () => setState(() => _black = !_black),
              ),
            ],
          ),
          const SizedBox(height: VSpace.s16),
          VListGroup(
            title: l.settingsPlayerStyle,
            children: [
              VListRow(
                below: VChoiceGroup<PlayerStyle>(
                  choices: [
                    (PlayerStyle.disc, l.playerStyleDisc),
                    (PlayerStyle.wave, l.playerStyleWave),
                  ],
                  value: _style,
                  onChanged: (s) => setState(() => _style = s),
                ),
              ),
            ],
          ),
          const SizedBox(height: VSpace.s16),
          VListGroup(
            title: l.settingsTheme,
            children: [
              VListRow(
                below: VChoiceGroup<_Theme>(
                  choices: [
                    (_Theme.system, l.themeSystem),
                    (_Theme.light, l.themeLight),
                    (_Theme.dark, l.themeDark),
                  ],
                  value: _theme,
                  onChanged: (t) => setState(() => _theme = t),
                ),
              ),
            ],
          ),
          const SizedBox(height: VSpace.s16),
          VListGroup(
            title: l.settingsPlayback,
            children: [
              VListRow(
                title: l.settingsEndRadio,
                trailing: VSwitch(
                  value: _radio,
                  label: l.settingsEndRadio,
                  onChanged: (v) => setState(() => _radio = v),
                ),
              ),
              VListRow(
                title: l.settingsNormalize,
                trailing: VSwitch(
                  value: _normalize,
                  label: l.settingsNormalize,
                  onChanged: (v) => setState(() => _normalize = v),
                ),
              ),
              VListRow(
                title: l.volumeLabel,
                below: VVolume(
                  value: _volume,
                  onChanged: (v) => setState(() => _volume = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Loading indicators, progress, pull to refresh, skeletons, empty and offline states,
/// badges.
class _StatesSection extends StatelessWidget {
  const _StatesSection();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _wrap([
          const VLoading(),
          const VLoading(contained: true),
          const VCircularProgress(value: 0.62),
          const VDownloadIcon(state: null),
          const VDownloadIcon(state: DownloadStateView.queued),
          const VDownloadIcon(state: DownloadStateView.running, progress: 0.6),
          const VDownloadIcon(state: DownloadStateView.done),
          VBadge(
            count: 2,
            label: l.downloading,
            child: const VSymbol(VIcons.download),
          ),
          VBadge(label: l.navLibrary, child: const VSymbol(VIcons.library)),
          const VOfflineChip(),
        ]),
        const SizedBox(height: VSpace.s16),
        SizedBox(
          width: VSize.heroCard,
          child: Column(
            children: [
              VWaveProgress(progress: 0.35, playing: true, onSeek: (_) {}),
              const VWaveProgress(progress: 0.7, playing: false, onSeek: null),
            ],
          ),
        ),
        const SizedBox(height: VSpace.s16),
        _wrap([
          _screen(
            VSize.sideSheet,
            VSize.sideSheet,
            VRefresh(
              onRefresh: () async {},
              child: ListView(
                children: [
                  for (final t in sampleTracks)
                    VTrackRow(
                      track: t,
                      playing: false,
                      onTap: _noop,
                      onPlayNext: _noop,
                      quick: const [],
                      groups: const [],
                    ),
                ],
              ),
            ),
          ),
          _screen(VSize.sideSheet, VSize.sideSheet, _filler(5)),
          _screen(
            VSize.sideSheet,
            VSize.sideSheet,
            Center(
              child: VEmptyState(icon: VIcons.favorite, message: l.emptyLikes),
            ),
          ),
        ]),
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
      _screen(
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
      _screen(
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

class _ListStatesSection extends StatelessWidget {
  const _ListStatesSection();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget list(Future<List<String>> Function() load) => _screen(
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
