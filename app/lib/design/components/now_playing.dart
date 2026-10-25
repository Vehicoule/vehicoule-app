import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../bridge/catalog.dart';
import '../../bridge/downloads.dart';
import '../../bridge/queue.dart';
import '../color.dart';
import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../motion.dart';
import '../symbols.dart';
import '../theme.dart';
import '../tokens.dart';
import 'artwork.dart';
import 'controls.dart';
import 'loading.dart';
import 'menu.dart';
import 'view_selector.dart';
import 'wave_artwork.dart';
import 'wave_progress.dart';

export 'view_selector.dart' show PlayerView;

enum PlayerSize { compact, medium, large }

enum PlayerStyle { disc, wave }

/// "3:26", or "1:02:03" past an hour.
String vTime(int ms) {
  final s = (ms / 1000).floor();
  final h = s ~/ 3600,
      m = s ~/ 60 % 60,
      sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// The player's slow state. The position is separate ([VNowPlaying.position]): it ticks
/// many times a second and only the ring, the wave edge and the times follow it.
class NowPlayingData {
  const NowPlayingData({
    required this.track,
    required this.sourceTitle,
    required this.playing,
    required this.loading,
    required this.durationMs,
    required this.liked,
    required this.download,
    this.downloadProgress,
    required this.shuffle,
    required this.repeat,
    this.sleepLeft,
    this.sleepEndOfTrack = false,
    this.coverTop,
  });

  final TrackView track;

  /// What the queue plays from ("Playing from …").
  final String sourceTitle;
  final bool playing, loading;
  final int durationMs;
  final bool liked;
  final DownloadStateView? download;
  final double? downloadProgress;
  final bool shuffle;
  final Repeat repeat;

  /// A sleep timer is running: the moon and the time left show in the header.
  final Duration? sleepLeft;
  final bool sleepEndOfTrack;

  /// The artwork's top band (`coverTopFromArtwork`, with the seed): the Vague's header
  /// picks its content colour from it. Null: unknown, the header gets a scrim.
  final VCoverTop? coverTop;

  double progressAt(int positionMs) =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);
}

class NowPlayingActions {
  const NowPlayingActions({
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    required this.onLike,
    required this.onAddToPlaylist,
    required this.onDownload,
    required this.onShuffle,
    required this.onRepeat,
    this.onOutput,
    this.onMenu,
    this.onCollapse,
    this.onOpen,
    this.onStop,
  });

  final VoidCallback onPlayPause, onNext, onPrevious;

  /// To a position in milliseconds (once per gesture: on release, a tap or a key).
  final ValueChanged<int> onSeek;
  final VoidCallback onLike, onAddToPlaylist, onDownload, onShuffle, onRepeat;
  final VoidCallback? onOutput;

  /// ⋮, with the button's global rect to anchor `showVMenu`.
  final ValueChanged<Rect>? onMenu;

  /// ⌄ (mobile) or fold the pane (desktop).
  final VoidCallback? onCollapse;

  /// The mini player's ↑ or tap: open the full player.
  final VoidCallback? onOpen;

  /// The mini player's ↓: stop and hide (the shell shows "Lecture arrêtée — Annuler").
  final VoidCallback? onStop;
}

/// The one player (spec UI §5.5), presentation only. Its blocks, always in this order:
/// header (the size toggle last, top right) · artwork · times · title with like /
/// playlist / download · controls · the bottom row (volume or output, the view menu).
///
/// - [PlayerSize.compact]: the mini player (spec UI §5.3): an M3E floating toolbar
///   (artwork with its ring, title, artists, like, a menu) and the ⏯ FAB beside it, with
///   its gestures; the desktop strip with [axis] vertical (spec UI §4.2);
/// - medium (desktop pane) and large (phone full screen): one column, centred in the
///   height it gets; [wide] puts the artwork left of the blocks (landscape);
/// - [immersive] (desktop, large): artwork left, lyrics or queue right, controls below;
///   Esc calls [onImmersive].
///
/// In the lyrics and queue views the big artwork flies into the compact header, which is
/// the mini player's own toolbar (a 150 ms fade with "reduce motion"). [position] (ms) is
/// listened to by the ring, the wave edge and the times only.
class VNowPlaying extends StatefulWidget {
  const VNowPlaying({
    super.key,
    required this.data,
    required this.position,
    required this.size,
    required this.style,
    required this.view,
    required this.onView,
    required this.actions,
    required this.lyrics,
    required this.queue,
    this.onImmersive,
    this.volume,
    this.axis = Axis.horizontal,
    this.wide = false,
    this.immersive = false,
    this.artworkVisible = true,
    this.onArtworkRect,
  });

  final NowPlayingData data;
  final ValueListenable<int> position;
  final PlayerSize size;
  final PlayerStyle style;
  final PlayerView view;
  final ValueChanged<PlayerView> onView;
  final NowPlayingActions actions;
  final WidgetBuilder lyrics, queue;

  /// ⤢ in the header (enter), or leave the immersive view (its ⌄ and Esc).
  final VoidCallback? onImmersive;
  final Widget? volume;
  final Axis axis;
  final bool wide, immersive;

  /// False while a sheet's flight ([VExtentFlight]) draws this player's artwork: the
  /// player keeps its place but doesn't paint it.
  final bool artworkVisible;

  /// Where the artwork is, in global coordinates, after each layout: the big artwork in
  /// the player, the disc in the mini player. The two ends of the mini player → player
  /// flight (spec UI §5.6).
  final ValueChanged<Rect>? onArtworkRect;

  static const headerKey = ValueKey('np.header'),
      artworkKey = ValueKey('np.artwork'),
      titleKey = ValueKey('np.title'),
      actionsKey = ValueKey('np.actions'),
      progressKey = ValueKey('np.progress'),
      controlsKey = ValueKey('np.controls'),
      selectorKey = ValueKey('np.selector'),
      scrimKey = ValueKey('np.scrim'),
      compactKey = ValueKey('np.compact'),
      compactArtKey = ValueKey('np.compact.art');

  @override
  State<VNowPlaying> createState() => _VNowPlayingState();
}

class _VNowPlayingState extends State<VNowPlaying>
    with SingleTickerProviderStateMixin {
  /// 0 = the player view, 1 = lyrics or queue (the artwork in the compact header).
  late final AnimationController _side = AnimationController(
    vsync: this,
    value: widget.view == PlayerView.player ? 0 : 1,
  );

  /// The lyrics or queue last shown: it stays built while it fades out on the way back
  /// to the player.
  late PlayerView _lastSide = widget.view == PlayerView.player
      ? PlayerView.lyrics
      : widget.view;

  NowPlayingData get data => widget.data;
  NowPlayingActions get actions => widget.actions;

  /// The compact header's artwork slot and the side view holding it: the flight lands on
  /// the slot as laid out, whatever the toolbar's padding and the text size.
  final _slotKey = GlobalKey(), _sideKey = GlobalKey();

  /// The artwork as painted (big, mini or strip), for [VNowPlaying.onArtworkRect].
  final _artKey = GlobalKey();
  Rect? _reported;

  /// The header's height, measured: in the Vague style the artwork runs under it and
  /// the lyrics/queue view starts below it.
  final _headerKey = GlobalKey();
  double _headerHeight = VSize.playerHeader;

  void _report() {
    final box = _artKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.attached && box.hasSize) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect != _reported) {
        _reported = rect;
        widget.onArtworkRect?.call(rect);
      }
    }
    final header = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (header != null &&
        header.hasSize &&
        header.size.height != _headerHeight) {
      setState(() => _headerHeight = header.size.height);
    }
  }

  @override
  void didUpdateWidget(VNowPlaying old) {
    super.didUpdateWidget(old);
    if (widget.view != PlayerView.player) _lastSide = widget.view;
    final target = widget.view == PlayerView.player ? 0.0 : 1.0;
    if (target != _side.value) {
      _side.animateTo(
        target,
        duration: reduceMotion(context)
            ? VDurations.reduced
            : VDurations.medium,
        curve: VCurves.emphasized,
      );
    }
  }

  @override
  void dispose() {
    _side.dispose();
    super.dispose();
  }

  double _scrimHeight(BuildContext context) =>
      MediaQuery.paddingOf(context).top + VSize.headerScrimHeight;

  /// Dark, from the scheme's scrim role, for a busy cover top (spec UI §6.6): darkest at
  /// the very top, then a cosine ease to nothing, with no flat band and no edge.
  LinearGradient _scrim(BuildContext context) {
    final scrim = Theme.of(context).colorScheme.scrim;
    const steps = 10;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        for (var i = 0; i <= steps; i++)
          scrim.withValues(
            alpha: VSize.headerScrim * (1 + math.cos(math.pi * i / steps)) / 2,
          ),
      ],
      stops: [for (var i = 0; i <= steps; i++) i / steps],
    );
  }

  /// Hides the artwork while a flight draws it.
  Widget _visible(Widget child) => Opacity(
    opacity: widget.artworkVisible ? 1 : 0,
    child: KeyedSubtree(key: _artKey, child: child),
  );

  bool get _bleed =>
      widget.style == PlayerStyle.wave && !widget.wide && !widget.immersive;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report();
    });
    if (widget.size == PlayerSize.compact) {
      return widget.axis == Axis.vertical ? _strip(context) : _mini(context);
    }
    // A plain surface, no gradient (spec UI §6.6, user ruling).
    return ColoredBox(
      color: vScreenSurface(Theme.of(context).colorScheme),
      // The Vague's cover runs under the status bar: no top inset for the column, the
      // header takes it instead.
      child: SafeArea(
        top: !_bleed,
        child: widget.immersive ? _immersive(context) : _column(context),
      ),
    );
  }

  Widget _column(BuildContext context) {
    final onCover = vOnCoverFor(data.coverTop);
    return Column(
      children: [
        // The Vague runs full bleed under the header (lecteur-v3, style C).
        if (_bleed)
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _body(context)),
                // Under the header, a scrim only when the cover's top is too busy for
                // plain content (text 4.5:1, icons 3:1).
                if (onCover == VOnCover.scrim)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: _scrimHeight(context),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: VNowPlaying.scrimKey,
                        decoration: BoxDecoration(gradient: _scrim(context)),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: KeyedSubtree(
                    key: _headerKey,
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.paddingOf(context).top,
                      ),
                      // Content straight on the cover: dark on a light top, light on
                      // a dark or scrimmed one; the status-bar icons follow.
                      child: AnnotatedRegion<SystemUiOverlayStyle>(
                        value: onCover == VOnCover.dark
                            ? SystemUiOverlayStyle.dark
                            : SystemUiOverlayStyle.light,
                        child: vOnCover(
                          context,
                          onCover == VOnCover.dark
                              ? vOnCoverDark
                              : vOnCoverLight,
                          Builder(builder: _header),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          _header(context),
          Expanded(child: _body(context)),
        ],
        _bottomRow(context, VViewSelector.order, widget.view),
      ],
    );
  }

  /// The volume (desktop) or the audio output (phone) at the start, the view menu at the
  /// end (spec UI §5.5, item 5): the volume takes the room left, 240 at most.
  Widget _bottomRow(
    BuildContext context,
    List<PlayerView> views,
    PlayerView value,
  ) {
    final Widget? start = widget.volume != null
        ? ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: VSize.volumeMax),
            child: widget.volume,
          )
        : actions.onOutput != null && !_outputInHeader
        ? VIconButton(
            icon: VIcons.devices,
            label: AppLocalizations.of(context).actionOutput,
            onPressed: actions.onOutput,
          )
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VSpace.s16,
        VSpace.s8,
        VSpace.s16,
        VSpace.s16,
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: start,
            ),
          ),
          const SizedBox(width: VSpace.s16),
          VViewSelector(
            key: VNowPlaying.selectorKey,
            value: value,
            views: views,
            onChanged: widget.onView,
          ),
        ],
      ),
    );
  }

  /// The output sits in the header on desktop (the pane, the immersive view); on a
  /// phone it takes the volume's place in the bottom row.
  bool get _outputInHeader =>
      widget.size == PlayerSize.medium || widget.immersive;

  double get _seekStep => data.durationMs <= 0
      ? 0.05
      : (VDurations.seekStep.inMilliseconds / data.durationMs).clamp(0.0, 1.0);

  void _seek(double p) => actions.onSeek((p * data.durationMs).round());

  bool get _disc => widget.style == PlayerStyle.disc;

  /// The player view and the lyrics/queue view, with one artwork flying between the big
  /// place and the compact header.
  Widget _body(BuildContext context) {
    final reduced = reduceMotion(context);
    return LayoutBuilder(
      builder: (context, box) {
        // A phone held upright has the room for large controls and wider gaps.
        final tall =
            widget.size == PlayerSize.large &&
            !widget.wide &&
            box.maxHeight >= VSize.tallPlayer;
        return AnimatedBuilder(
          animation: _side,
          builder: (context, _) =>
              _layers(context, _side.value, reduced, tall, widget.wide),
        );
      },
    );
  }

  Widget _layers(
    BuildContext context,
    double t,
    bool reduced,
    bool tall,
    bool wide,
  ) => CustomMultiChildLayout(
    delegate: _PlayerLayout(
      slotKey: _slotKey,
      sideKey: _sideKey,
      t: t,
      reduced: reduced,
      wide: wide,
      disc: _disc,
      bleed: _bleed,
      margin: tall ? VSpace.s16 : VSpace.s24,
      controlsGap: _controlsGap(tall),
      cap: widget.size == PlayerSize.large
          ? VSize.playerArtLarge
          : VSize.playerArtMedium,
    ),
    children: [
      // Keyed: the layers come and go, and the flying artwork must keep its state
      // (its turn, its wave) rather than be matched to whichever layer is next.
      if (t < 1)
        LayoutId(
          key: const ValueKey('np.layer.player'),
          id: _Part.blocks,
          child: IgnorePointer(
            ignoring: t > 0,
            child: Opacity(
              opacity: 1 - t,
              child: _blocks(context, tall: tall, wide: wide),
            ),
          ),
        ),
      if (t < 1 && !wide)
        LayoutId(
          key: const ValueKey('np.layer.controls'),
          id: _Part.controls,
          child: IgnorePointer(
            ignoring: t > 0,
            child: Opacity(
              opacity: 1 - t,
              child: _controls(tall: tall),
            ),
          ),
        ),
      if (t < 1 && !wide)
        LayoutId(
          key: const ValueKey('np.layer.times'),
          id: _Part.times,
          child: Opacity(opacity: 1 - t, child: _times(context)),
        ),
      if (t > 0)
        LayoutId(
          key: const ValueKey('np.layer.side'),
          id: _Part.side,
          child: IgnorePointer(
            key: _sideKey,
            ignoring: t < 1,
            child: Opacity(opacity: t, child: _sideView(context)),
          ),
        ),
      LayoutId(
        key: const ValueKey('np.layer.art'),
        id: _Part.art,
        child: Opacity(
          opacity: reduced ? (1 - 2 * t).abs() : 1,
          child: KeyedSubtree(
            key: VNowPlaying.artworkKey,
            child: _visible(
              LayoutBuilder(
                builder: (context, box) =>
                    _art(box.maxWidth, t, height: box.maxHeight),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  /// The flying artwork at [side] for the flight's progress [t] (0 = big, 1 = in the
  /// compact header). The compact header keeps the disc in both styles (spec UI §5.5):
  /// in the Wave style the wave fades into the disc over the middle of the flight.
  Widget _art(
    double side,
    double t, {
    double? height,
  }) => ValueListenableBuilder(
    valueListenable: widget.position,
    builder: (context, ms, _) {
      final p = data.progressAt(ms);
      Widget disc() => VArtwork(
        itemId: data.track.id,
        size: math.min(side, height ?? side),
        playing: data.playing,
        progress: p,
        onSeek: _seek,
        seekStep: _seekStep,
        semanticLabel: data.track.album?.title,
      );
      if (_disc) return disc();
      final f = ((t - 0.35) / 0.3).clamp(0.0, 1.0);
      final wave = VWaveArtwork(
        itemId: data.track.id,
        width: side,
        height: height,
        progress: p,
        playing: data.playing,
        onSeek: _seek,
        seekStep: _seekStep,
      );
      // Always the same Stack with keyed children, so the wave's phase and the disc's
      // turn survive the fade; a child is left out only while it is invisible.
      return Stack(
        alignment: Alignment.center,
        children: [
          if (f < 1)
            Opacity(key: const ValueKey('wave'), opacity: 1 - f, child: wave),
          if (f > 0)
            Opacity(key: const ValueKey('disc'), opacity: f, child: disc()),
        ],
      );
    },
  );

  /// « Lecture depuis » over the source · moon and time left · output · ⤢ · ⋮ · the size
  /// toggle, on one row (spec UI §5.5): the source ellipsizes, the actions never move.
  /// The toggle is always last, top right of the player's surface (⌄ on a phone, fold
  /// on the desktop pane, ⤡ in the immersive view).
  Widget _header(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sleep = data.sleepLeft;
    final immersive = widget.immersive;
    final pane = widget.size == PlayerSize.medium;
    final small = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget button(IconData icon, String label, VoidCallback? onPressed) =>
        VIconButton(icon: icon, label: label, onPressed: onPressed);
    final Widget? toggle = immersive
        ? (widget.onImmersive == null
              ? null
              : button(
                  VIcons.closeFullscreen,
                  l.actionExitImmersive,
                  widget.onImmersive,
                ))
        : actions.onCollapse == null
        ? null
        : button(
            pane ? VIcons.panelClose : VIcons.collapse,
            l.actionCollapse,
            actions.onCollapse,
          );
    return Padding(
      key: VNowPlaying.headerKey,
      padding: const EdgeInsetsDirectional.only(
        start: VSpace.s16,
        end: VSpace.s8,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: VSize.playerHeader),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.playingFromLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  ),
                  Text(
                    data.sourceTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: VSpace.s4),
            // A running timer: a small tonal chip before the actions.
            if (sleep != null || data.sleepEndOfTrack)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: VSpace.s4),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    // On the Vague's scrim the tonal fill goes, an outline stays.
                    shape: StadiumBorder(
                      side: theme.colorScheme.secondaryContainer.a == 0
                          ? BorderSide(color: theme.colorScheme.outlineVariant)
                          : BorderSide.none,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: VSpace.s8,
                      vertical: VSpace.s4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VSymbol(
                          VIcons.bedtime,
                          size: VSize.iconSmall,
                          filled: true,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: VSpace.s4),
                        Text(
                          data.sleepEndOfTrack
                              ? l.sleepEndOfTrack
                              : l.sleepMinutesLeft(
                                  (sleep!.inSeconds / 60).ceil(),
                                ),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (actions.onOutput != null && _outputInHeader)
              button(VIcons.devices, l.actionOutput, actions.onOutput),
            if (!immersive && widget.onImmersive != null)
              button(VIcons.fullscreen, l.actionImmersive, widget.onImmersive),
            if (actions.onMenu != null)
              Builder(
                builder: (b) => button(VIcons.more, l.actionMore, () {
                  final box = b.findRenderObject()! as RenderBox;
                  actions.onMenu!(box.localToGlobal(Offset.zero) & box.size);
                }),
              ),
            ?toggle,
          ],
        ),
      ),
    );
  }

  /// The ring's reading, centred under it as one line (Disque); the Vague keeps its two
  /// ends under the wave.
  Widget _times(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        (_disc ? theme.textTheme.labelLarge : theme.textTheme.labelMedium)
            ?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            );
    return ValueListenableBuilder(
      key: VNowPlaying.progressKey,
      valueListenable: widget.position,
      builder: (context, ms, _) => _disc
          ? Text(
              '${vTime(ms)} / ${vTime(data.durationMs)}',
              style: style,
              textAlign: TextAlign.center,
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(vTime(ms), style: style),
                Text(vTime(data.durationMs), style: style),
              ],
            ),
    );
  }

  /// The title in the rounded display face, large; the artists under it.
  Widget _title(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: VNowPlaying.titleKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data.track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.size == PlayerSize.large
              ? theme.textTheme.headlineMedium
              : theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: VSpace.s4),
        Text(
          data.track.artists.map((a) => a.name).join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  VAction _like(AppLocalizations l) =>
      VAction(l.actionLike, VIcons.favorite, () {
        VHaptics.light();
        actions.onLike();
      }, selected: data.liked);

  /// Like, add to a playlist, download: standard icon buttons trailing the title.
  Widget _actions(BuildContext context) {
    final l = AppLocalizations.of(context);
    final download = data.download;
    return Row(
      key: VNowPlaying.actionsKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        _likeButton(l),
        VIconButton(
          icon: VIcons.playlistAdd,
          label: l.actionAddToPlaylist,
          onPressed: actions.onAddToPlaylist,
        ),
        VIconButton(
          icon: VIcons.download,
          label: switch (download) {
            DownloadStateView.done => l.downloaded,
            DownloadStateView.queued ||
            DownloadStateView.running => l.downloading,
            _ => l.actionDownload,
          },
          onPressed: actions.onDownload,
          glyph: VDownloadIcon(
            state: download,
            progress: data.downloadProgress,
          ),
        ),
      ],
    );
  }

  Widget _controls({bool tall = false}) => VControls(
    key: VNowPlaying.controlsKey,
    playing: data.playing,
    loading: data.loading,
    shuffle: data.shuffle,
    repeat: data.repeat,
    tall: tall,
    onPlayPause: actions.onPlayPause,
    onNext: actions.onNext,
    onPrevious: actions.onPrevious,
    onShuffle: actions.onShuffle,
    onRepeat: actions.onRepeat,
  );

  /// The title and artists with their three buttons. Beside the artwork ([wide]), the
  /// times above and the controls under them.
  Widget _blocks(BuildContext context, {bool tall = false, bool wide = false}) {
    final row = Row(
      children: [
        Expanded(child: _title(context)),
        const SizedBox(width: VSpace.s8),
        _actions(context),
      ],
    );
    if (!wide) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _times(context)),
        const SizedBox(height: VSpace.s24),
        row,
        SizedBox(height: _controlsGap(tall)),
        _controls(tall: tall),
      ],
    );
  }

  static double _controlsGap(bool tall) => tall ? VSpace.s32 : VSpace.s24;

  /// Lyrics or queue under the compact header, whose artwork slot the flying artwork fills.
  Widget _sideView(BuildContext context) => Column(
    children: [
      if (_bleed) SizedBox(height: _headerHeight),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: VSpace.s16),
        child: _mini(context, slot: true),
      ),
      const SizedBox(height: VSpace.s8),
      Expanded(child: _sideContent(context, _lastSide)),
    ],
  );

  Widget _sideContent(BuildContext context, PlayerView v) => vSharedAxis(
    key: v,
    reverse: v == PlayerView.lyrics,
    child: (v == PlayerView.queue ? widget.queue : widget.lyrics)(context),
  );

  /// Desktop full window (spec UI §4.2, §5.5): the player's own column on the left (the
  /// artwork, the times, the title, the controls, the bottom row), lyrics or queue on
  /// the right.
  Widget _immersive(BuildContext context) {
    final side = widget.view == PlayerView.queue
        ? PlayerView.queue
        : PlayerView.lyrics;
    return CallbackShortcuts(
      bindings: {
        if (widget.onImmersive != null)
          const SingleActivator(LogicalKeyboardKey.escape): widget.onImmersive!,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        Expanded(
                          child: _layers(
                            context,
                            0,
                            reduceMotion(context),
                            false,
                            false,
                          ),
                        ),
                        _bottomRow(context, const [
                          PlayerView.lyrics,
                          PlayerView.queue,
                        ], side),
                      ],
                    ),
                  ),
                  Expanded(flex: 6, child: _sideContent(context, side)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _likeButton(AppLocalizations l) => VIconButton(
    icon: VIcons.favorite,
    label: l.actionLike,
    selected: data.liked,
    onPressed: _like(l).onSelected,
  );

  Widget _fab() => VPlayPauseFab(
    playing: data.playing,
    loading: data.loading,
    onPressed: actions.onPlayPause,
  );

  /// The mini player (spec UI §5.3): the floating toolbar (artwork with its ring, title,
  /// artists, like, the menu of its gestures) and the ⏯ FAB beside it. With [slot], it is
  /// the lyrics/queue header: the artwork's place is left for the player's flying
  /// artwork, and there are no gestures.
  Widget _mini(BuildContext context, {bool slot = false}) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final art = slot
        ? KeyedSubtree(
            key: _slotKey,
            child: const SizedBox.square(
              key: VNowPlaying.compactArtKey,
              dimension: VSize.compactArt,
            ),
          )
        : _visible(
            ValueListenableBuilder(
              valueListenable: widget.position,
              builder: (context, ms, _) => VArtwork(
                itemId: data.track.id,
                size: VSize.compactArt,
                playing: data.playing,
                progress: data.progressAt(ms),
              ),
            ),
          );
    final gestures = !slot;
    // The pill grows with the text, up to 200 % (spec UI §8): its height is the title
    // and the artists' lines plus its padding, never less than the M3E 64.
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle? style) => (TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout()).height;
    final height = math.max(
      VSize.toolbar,
      line(theme.textTheme.titleMedium) +
          line(theme.textTheme.bodyMedium) +
          2 * VSpace.s8,
    );
    final m3e = M3ETheme.of(context);
    final bar = M3ETheme(
      data: m3e.copyWith(
        toolbarTheme: m3e.toolbarTheme.copyWith(containerSize: height),
      ),
      child: M3EToolbar.floating(
        screenOffset: 0,
        padding: const EdgeInsets.all(VSpace.s4),
        semanticLabel: l.miniPlayerLabel,
        leading: art,
        title: Text(
          data.track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Text(
          data.track.artists.map((a) => a.name).join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [M3EToolbarWidget(child: _likeButton(l))],
      ),
    );
    // The FAB sits beside the pill, as the M3E toolbar's own FAB slot would put it, but
    // laid out here: that slot fixes the pill at 64 and the pill must grow with the text.
    Widget assembly(Widget pill) => Row(
      key: VNowPlaying.compactKey,
      children: [
        Expanded(child: pill),
        const SizedBox(width: VSpace.s8),
        _fab(),
      ],
    );
    if (!gestures) return assembly(bar);
    // Every gesture has its equivalent in the toolbar's menu (long press, right click)
    // and as a spoken action.
    final menu = [
      VAction(l.actionPrevious, VIcons.skipPrevious, actions.onPrevious),
      VAction(l.actionNext, VIcons.skipNext, actions.onNext),
      if (actions.onOpen case final open?)
        VAction(l.actionOpenPlayer, VIcons.expandUp, open),
      if (actions.onStop case final stop?)
        VAction(l.actionStop, VIcons.stop, stop),
    ];
    // The gestures belong to the toolbar only (spec UI §5.3), not to ⏯.
    return assembly(
      Semantics(
        customSemanticsActions: {
          for (final a in menu)
            CustomSemanticsAction(label: a.label): a.onSelected,
        },
        child: _MiniGestures(
          onNext: actions.onNext,
          onPrevious: actions.onPrevious,
          onOpen: actions.onOpen,
          onStop: actions.onStop,
          onMenu: (at) => showVMenu(
            context,
            anchor: at,
            quick: const [],
            groups: [menu.sublist(0, 2), menu.sublist(2)],
          ),
          child: bar,
        ),
      ),
    );
  }

  /// The collapsed desktop pane: a 76 px band, the mirror of the rail (spec UI §4.2), in
  /// three groups spread over its height: at the top the toggle that opens the pane and
  /// the disc with its ring; in the middle ⏯ (the biggest, as in the player), ⏭ and
  /// like; at the bottom the upright volume.
  Widget _strip(BuildContext context) {
    final l = AppLocalizations.of(context);
    final top = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actions.onOpen case final open?) ...[
          VIconButton(
            icon: VIcons.panelOpen,
            label: l.actionOpenPlayer,
            onPressed: open,
          ),
          const SizedBox(height: VSpace.s8),
        ],
        _visible(
          ValueListenableBuilder(
            valueListenable: widget.position,
            builder: (context, ms, _) => VArtwork(
              itemId: data.track.id,
              size: VSize.strip - VSpace.s16,
              playing: data.playing,
              progress: data.progressAt(ms),
              onSeek: _seek,
              seekStep: _seekStep,
            ),
          ),
        ),
      ],
    );
    final middle = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (data.loading)
          const SizedBox.square(
            dimension: VSize.fab,
            child: Center(child: VLoading(size: VSize.playIcon)),
          )
        else
          VIconButton(
            icon: data.playing ? VIcons.pause : VIcons.play,
            label: data.playing ? l.actionPause : l.actionPlay,
            // Not a toggle: M3E squares a selected toggle; ⏯ keeps its shape.
            style: VIconStyle.filled,
            size: VIconSize.medium,
            onPressed: () {
              VHaptics.light();
              actions.onPlayPause();
            },
          ),
        const SizedBox(height: VSpace.s8),
        VIconButton(
          icon: VIcons.skipNext,
          label: l.actionNext,
          style: VIconStyle.tonal,
          glyphFilled: true,
          onPressed: actions.onNext,
        ),
        const SizedBox(height: VSpace.s8),
        _likeButton(l),
      ],
    );
    final bottom = widget.volume == null
        ? const SizedBox.shrink()
        : SizedBox(height: VSize.stripVolume, child: widget.volume);
    return LayoutBuilder(
      builder: (context, box) {
        if (!box.hasBoundedHeight) {
          return Column(
            key: VNowPlaying.compactKey,
            mainAxisSize: MainAxisSize.min,
            children: [
              top,
              const SizedBox(height: VSpace.s24),
              middle,
              const SizedBox(height: VSpace.s24),
              bottom,
            ],
          );
        }
        // Spread over the height; scrolled below the room the three groups need.
        return SingleChildScrollView(
          child: SizedBox(
            height: math.max(box.maxHeight, VSize.stripMin),
            child: Column(
              key: VNowPlaying.compactKey,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [top, middle, bottom],
            ),
          ),
        );
      },
    );
  }
}

enum _Part { blocks, controls, times, side, art }

/// One column, centred in the height it gets: the artwork as large as the width allows
/// (a margin of 24, full width for the Wave) and the blocks under it; [wide] puts the
/// artwork in the left half and the blocks in the right one. The artwork flies to the
/// compact header's slot as [t] goes to 1.
class _PlayerLayout extends MultiChildLayoutDelegate {
  _PlayerLayout({
    required this.slotKey,
    required this.sideKey,
    required this.t,
    required this.reduced,
    required this.wide,
    required this.disc,
    required this.bleed,
    required this.margin,
    required this.cap,
    required this.controlsGap,
  });

  final GlobalKey slotKey, sideKey;
  final double t, cap, margin, controlsGap;
  final bool reduced, wide, disc;

  /// The Vague: the artwork at full width from the very top, under the header.
  final bool bleed;

  /// The slot as just laid out inside the side view (which sits at the origin).
  Rect _slot() {
    final slot = slotKey.currentContext?.findRenderObject() as RenderBox?;
    final side = sideKey.currentContext?.findRenderObject();
    if (slot == null || side == null || !slot.attached) {
      return const Rect.fromLTWH(
        VSpace.s16,
        0,
        VSize.compactArt,
        VSize.compactArt,
      );
    }
    return slot.localToGlobal(Offset.zero, ancestor: side) &
        const Size.square(VSize.compactArt);
  }

  @override
  void performLayout(Size size) {
    const m = VSpace.s24;
    Rect big;
    if (wide) {
      final half = size.width / 2;
      var blocksH = 0.0;
      if (hasChild(_Part.blocks)) {
        final w = half - 2 * m;
        blocksH = layoutChild(
          _Part.blocks,
          BoxConstraints(minWidth: w, maxWidth: w, maxHeight: size.height),
        ).height;
        positionChild(
          _Part.blocks,
          Offset(half + m, ((size.height - blocksH) / 2).clamp(0, size.height)),
        );
      }
      final side = [
        half - 2 * m,
        size.height - 2 * VSpace.s8,
        cap,
      ].reduce(math.min).clamp(0.0, double.infinity);
      big = Rect.fromLTWH(
        (half - side) / 2,
        (size.height - side) / 2,
        side,
        side,
      );
    } else {
      // The column's edge: the M3 phone margin, so the controls keep 48 dp targets
      // on a 360 dp phone and in the pane.
      const edge = VSpace.s16;
      final w = size.width - 2 * edge;
      final loose = BoxConstraints(
        minWidth: w,
        maxWidth: w,
        maxHeight: size.height,
      );
      // Title row, then the controls group, both the column's width.
      final titleH = hasChild(_Part.blocks)
          ? layoutChild(_Part.blocks, loose).height
          : 0.0;
      final controlsH = hasChild(_Part.controls)
          ? layoutChild(_Part.controls, loose).height
          : 0.0;
      // The times: one centred line (Disque), or the wave's two ends.
      var times = Size.zero;
      if (hasChild(_Part.times)) {
        times = layoutChild(
          _Part.times,
          disc
              ? BoxConstraints(maxWidth: w)
              : BoxConstraints(minWidth: w, maxWidth: w),
        );
      }
      // A token gap under the header (the ring never touches it), the times just
      // under the artwork, then the title and the controls.
      final above = bleed ? 0.0 : VSpace.s16;
      final under = VSpace.s8 + times.height + VSpace.s24;
      final below = titleH + (controlsH > 0 ? controlsGap + controlsH : 0);
      final fixed = above + under + below + VSpace.s8;
      final side = [
        bleed ? size.width : size.width - 2 * margin,
        size.height - fixed,
        bleed ? size.width : cap,
      ].reduce(math.min).clamp(0.0, double.infinity);
      // The Vague may grow taller than wide (up to 1.15×, the cover cropped) to take
      // the room that would otherwise sit between the wave and the title.
      var height = side;
      if (bleed) {
        final spare = size.height - side - fixed - VSpace.s16;
        height = side + spare.clamp(0.0, side * (VSize.waveTallest - 1));
      }
      // The room left: the column is centred in it (Disque); the Vague, pinned to the
      // top, shares it between its gaps. No dead band.
      final slack = math.max(0.0, size.height - fixed - height);
      final top = above + (bleed ? 0.0 : slack / 2);
      final share = bleed ? slack / 3 : 0.0;
      big = Rect.fromLTWH((size.width - side) / 2, top, side, height);
      final timesY = big.bottom + VSpace.s8;
      if (hasChild(_Part.times)) {
        positionChild(
          _Part.times,
          Offset(disc ? (size.width - times.width) / 2 : edge, timesY),
        );
      }
      final y = timesY + times.height + VSpace.s24 + share;
      if (hasChild(_Part.blocks)) {
        positionChild(_Part.blocks, Offset(edge, y));
      }
      if (hasChild(_Part.controls)) {
        positionChild(
          _Part.controls,
          Offset(edge, y + titleH + controlsGap + share),
        );
      }
    }
    if (hasChild(_Part.side)) {
      layoutChild(_Part.side, BoxConstraints.tight(size));
      positionChild(_Part.side, Offset.zero);
    }
    final slot = t > 0 ? _slot() : big;
    final rect = reduced ? (t < 0.5 ? big : slot) : Rect.lerp(big, slot, t)!;
    layoutChild(_Part.art, BoxConstraints.tight(rect.size));
    positionChild(_Part.art, rect.topLeft);
  }

  @override
  bool shouldRelayout(_PlayerLayout old) =>
      old.t != t ||
      old.reduced != reduced ||
      old.wide != wide ||
      old.disc != disc ||
      old.bleed != bleed ||
      old.margin != margin ||
      old.controlsGap != controlsGap ||
      old.cap != cap;
}

/// The mini player's gestures (spec UI §5.3): the toolbar follows the finger and springs
/// back; ← next, → previous, ↑ (or a tap) opens the player, ↓ stops.
class _MiniGestures extends StatefulWidget {
  const _MiniGestures({
    required this.child,
    required this.onNext,
    required this.onPrevious,
    required this.onOpen,
    required this.onStop,
    required this.onMenu,
  });

  final Widget child;
  final VoidCallback onNext, onPrevious;
  final VoidCallback? onOpen, onStop;

  /// Opens the toolbar's menu at a global rect (a point for the pointer).
  final ValueChanged<Rect> onMenu;

  @override
  State<_MiniGestures> createState() => _MiniGesturesState();
}

class _MiniGesturesState extends State<_MiniGestures>
    with TickerProviderStateMixin {
  late final _x = AnimationController.unbounded(vsync: this);
  late final _y = AnimationController.unbounded(vsync: this);
  Axis? _axis;
  bool _armed = false;

  static const _threshold = VSize.swipe;

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    _axis ??= d.delta.dx.abs() >= d.delta.dy.abs()
        ? Axis.horizontal
        : Axis.vertical;
    final c = _axis == Axis.horizontal ? _x : _y;
    c.value += _axis == Axis.horizontal ? d.delta.dx : d.delta.dy;
    final armed = c.value.abs() >= _threshold;
    if (armed != _armed) {
      _armed = armed;
      if (armed) VHaptics.selection();
    }
  }

  void _end(DragEndDetails _) {
    final x = _x.value, y = _y.value;
    if (_axis == Axis.horizontal) {
      if (x <= -_threshold) widget.onNext();
      if (x >= _threshold) widget.onPrevious();
    } else if (_axis == Axis.vertical) {
      if (y <= -_threshold) widget.onOpen?.call();
      if (y >= _threshold && widget.onStop != null) {
        VHaptics.medium();
        widget.onStop!();
      }
    }
    _axis = null;
    _armed = false;
    for (final c in [_x, _y]) {
      if (reduceMotion(context)) {
        c.value = 0;
      } else {
        c.animateWith(SpringSimulation(VSprings.spatial, c.value, 0, 0));
      }
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: widget.onOpen,
    onLongPressStart: (d) => widget.onMenu(
      Rect.fromLTWH(d.globalPosition.dx, d.globalPosition.dy, 0, 0),
    ),
    onSecondaryTapUp: (d) => widget.onMenu(
      Rect.fromLTWH(d.globalPosition.dx, d.globalPosition.dy, 0, 0),
    ),
    onPanUpdate: _update,
    onPanEnd: _end,
    child: AnimatedBuilder(
      animation: Listenable.merge([_x, _y]),
      builder: (context, child) => Transform.translate(
        // Up and down only hint at the gesture; sideways it follows the finger.
        offset: Offset(_x.value, _y.value * 0.5),
        child: child,
      ),
      child: widget.child,
    ),
  );
}
