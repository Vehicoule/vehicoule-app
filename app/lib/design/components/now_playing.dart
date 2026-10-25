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
import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../motion.dart';
import '../symbols.dart';
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
/// header · artwork · title · like/playlist/download · times · controls · view selector.
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

  static const headerKey = ValueKey('np.header'),
      artworkKey = ValueKey('np.artwork'),
      titleKey = ValueKey('np.title'),
      actionsKey = ValueKey('np.actions'),
      progressKey = ValueKey('np.progress'),
      controlsKey = ValueKey('np.controls'),
      selectorKey = ValueKey('np.selector'),
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

  @override
  Widget build(BuildContext context) {
    if (widget.size == PlayerSize.compact) {
      return widget.axis == Axis.vertical ? _strip(context) : _mini(context);
    }
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      // The player's one gradient: a tint behind the artwork (spec UI §2.2).
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: widget.wide || widget.immersive
              ? const Alignment(-0.5, 0)
              : const Alignment(0, -0.45),
          radius: 0.9,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.6),
            scheme.surface,
          ],
        ),
      ),
      child: SafeArea(
        child: widget.immersive ? _immersive(context) : _column(context),
      ),
    );
  }

  Widget _column(BuildContext context) => Column(
    children: [
      _header(context),
      Expanded(child: _body(context)),
      if (widget.volume case final volume?)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VSpace.s16),
          child: Row(
            children: [
              if (actions.onOutput case final output?)
                VIconButton(
                  icon: VIcons.speaker,
                  label: AppLocalizations.of(context).actionOutput,
                  onPressed: output,
                ),
              const SizedBox(width: VSpace.s8),
              Expanded(child: volume),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: VSpace.s8, bottom: VSpace.s16),
        child: _selector(PlayerView.values, widget.view),
      ),
    ],
  );

  Widget _selector(List<PlayerView> views, PlayerView value) => VViewSelector(
    key: VNowPlaying.selectorKey,
    value: value,
    views: views,
    onChanged: widget.onView,
  );

  double get _seekStep => data.durationMs <= 0
      ? 0.05
      : (VDurations.seekStep.inMilliseconds / data.durationMs).clamp(0.0, 1.0);

  void _seek(double p) => actions.onSeek((p * data.durationMs).round());

  bool get _disc => widget.style == PlayerStyle.disc;

  /// The player view and the lyrics/queue view, with one artwork flying between the big
  /// place and the compact header.
  Widget _body(BuildContext context) {
    final reduced = reduceMotion(context);
    return AnimatedBuilder(
      animation: _side,
      builder: (context, _) {
        final t = _side.value;
        return CustomMultiChildLayout(
          delegate: _PlayerLayout(
            slotKey: _slotKey,
            sideKey: _sideKey,
            t: t,
            reduced: reduced,
            wide: widget.wide,
            disc: _disc,
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
                  child: Opacity(opacity: 1 - t, child: _blocks(context)),
                ),
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
                  child: LayoutBuilder(
                    builder: (context, box) => _art(box.maxWidth, t),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The flying artwork at [side] for the flight's progress [t] (0 = big, 1 = in the
  /// compact header). The compact header keeps the disc in both styles (spec UI §5.5):
  /// in the Wave style the wave fades into the disc over the middle of the flight.
  Widget _art(double side, double t) => ValueListenableBuilder(
    valueListenable: widget.position,
    builder: (context, ms, _) {
      final p = data.progressAt(ms);
      Widget disc() => VArtwork(
        itemId: data.track.id,
        size: side,
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

  /// ⌄ · « Lecture depuis » over the source · moon and time left · output · ⤢ · ⋮, on one
  /// row (the mockup's header): the source ellipsizes, the actions never move. The
  /// desktop pane folds with its panel icon; the immersive view leaves with ⤡ at the end.
  /// In the pane the output sits by the volume instead.
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
        VIconButton(
          icon: icon,
          label: label,
          style: VIconStyle.tonal,
          onPressed: onPressed,
        );
    return Padding(
      key: VNowPlaying.headerKey,
      padding: const EdgeInsets.symmetric(horizontal: VSpace.s8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: VSize.playerHeader),
        child: Row(
          children: [
            if (!immersive && actions.onCollapse != null)
              button(
                pane ? VIcons.panelClose : VIcons.collapse,
                l.actionCollapse,
                actions.onCollapse,
              ),
            const SizedBox(width: VSpace.s4),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A running timer shares the label's line: the moon and the time
                  // left, so the actions keep their room.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          l.playingFromLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                      ),
                      if (sleep != null || data.sleepEndOfTrack) ...[
                        const SizedBox(width: VSpace.s8),
                        VSymbol(
                          VIcons.bedtime,
                          size: VSize.iconSmall,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: VSpace.s4),
                        Text(
                          data.sleepEndOfTrack
                              ? l.sleepEndOfTrack
                              : l.sleepMinutesLeft(
                                  (sleep!.inSeconds / 60).ceil(),
                                ),
                          style: small?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    data.sourceTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: VSpace.s4),
            if (actions.onOutput != null && !(pane && widget.volume != null))
              button(VIcons.devices, l.actionOutput, actions.onOutput),
            if (widget.onImmersive != null)
              immersive
                  ? button(
                      VIcons.closeFullscreen,
                      l.actionExitImmersive,
                      widget.onImmersive,
                    )
                  : button(
                      VIcons.fullscreen,
                      l.actionImmersive,
                      widget.onImmersive,
                    ),
            if (actions.onMenu != null)
              Builder(
                builder: (b) => button(VIcons.more, l.actionMore, () {
                  final box = b.findRenderObject()! as RenderBox;
                  actions.onMenu!(box.localToGlobal(Offset.zero) & box.size);
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _times(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ValueListenableBuilder(
      key: VNowPlaying.progressKey,
      valueListenable: widget.position,
      builder: (context, ms, _) => Row(
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

  Widget _actions(BuildContext context) {
    final l = AppLocalizations.of(context);
    final group = VConnectedGroup(
      actions: [
        _like(l),
        VAction(
          l.actionAddToPlaylist,
          VIcons.playlistAdd,
          actions.onAddToPlaylist,
        ),
        VAction(
          l.actionDownload,
          VIcons.download,
          actions.onDownload,
          leading: VDownloadIcon(
            state: data.download,
            progress: data.downloadProgress,
          ),
        ),
      ],
    );
    // A compact group, centred (the mockup), not stretched across the player.
    return Center(
      key: VNowPlaying.actionsKey,
      child: SizedBox(width: 3 * VSize.controlMax, child: group),
    );
  }

  Widget _controls() => VControls(
    key: VNowPlaying.controlsKey,
    playing: data.playing,
    loading: data.loading,
    shuffle: data.shuffle,
    repeat: data.repeat,
    onPlayPause: actions.onPlayPause,
    onNext: actions.onNext,
    onPrevious: actions.onPrevious,
    onShuffle: actions.onShuffle,
    onRepeat: actions.onRepeat,
  );

  /// Everything under the artwork: the times under the ring (Disc) or under the title
  /// (Wave), the connected group, the controls.
  Widget _blocks(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_disc) ...[_times(context), const SizedBox(height: VSpace.s16)],
      _title(context),
      if (!_disc) ...[const SizedBox(height: VSpace.s12), _times(context)],
      const SizedBox(height: VSpace.s16),
      _actions(context),
      const SizedBox(height: VSpace.s24),
      _controls(),
    ],
  );

  /// Lyrics or queue under the compact header, whose artwork slot the flying artwork fills.
  Widget _sideView(BuildContext context) => Column(
    children: [
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

  /// Desktop full window: the artwork and title on the left, lyrics or queue on the
  /// right, the controls along the bottom (spec UI §4.2).
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: VSpace.s32,
                        vertical: VSpace.s16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final s = box.biggest.shortestSide;
                                return Center(
                                  child: SizedBox.square(
                                    key: VNowPlaying.artworkKey,
                                    dimension: s,
                                    child: _art(s, 0),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: VSpace.s16),
                          _title(context),
                          const SizedBox(height: VSpace.s8),
                          _times(context),
                        ],
                      ),
                    ),
                  ),
                  Expanded(flex: 6, child: _sideContent(context, side)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                VSpace.s24,
                VSpace.s8,
                VSpace.s24,
                VSpace.s16,
              ),
              child: LayoutBuilder(
                builder: (context, box) {
                  final controls = SizedBox(
                    width: 6 * VSize.controlMax + 4 * VSpace.s8,
                    child: _controls(),
                  );
                  final selector = _selector(const [
                    PlayerView.lyrics,
                    PlayerView.queue,
                  ], side);
                  // Wide: one row; narrower, the controls above the group and
                  // the selector.
                  if (box.maxWidth >= VSize.immersiveRow) {
                    return Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: _actions(context),
                          ),
                        ),
                        const SizedBox(width: VSpace.s16),
                        controls,
                        const SizedBox(width: VSpace.s16),
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: selector,
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      controls,
                      const SizedBox(height: VSpace.s16),
                      Row(
                        children: [_actions(context), const Spacer(), selector],
                      ),
                    ],
                  );
                },
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
        : ValueListenableBuilder(
            valueListenable: widget.position,
            builder: (context, ms, _) => VArtwork(
              itemId: data.track.id,
              size: VSize.compactArt,
              playing: data.playing,
              progress: data.progressAt(ms),
            ),
          );
    final gestures = !slot;
    // The pill keeps its M3E height: very large text is capped inside it.
    final bar = MediaQuery.withClampedTextScaling(
      maxScaleFactor: VSize.toolbarTextScale,
      child: M3EToolbar.floating(
        key: VNowPlaying.compactKey,
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
        floatingActionButton: _fab(),
        fabExpandsToolbar: false,
      ),
    );
    if (!gestures) return bar;
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
    return Semantics(
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
    );
  }

  /// The collapsed desktop pane: a 76 px band, the mirror of the rail (spec UI §4.2):
  /// the disc with its ring, like, ⏯, ⏭ and the volume.
  Widget _strip(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      key: VNowPlaying.compactKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder(
          valueListenable: widget.position,
          builder: (context, ms, _) => VArtwork(
            itemId: data.track.id,
            size: VSize.strip - VSpace.s8,
            playing: data.playing,
            progress: data.progressAt(ms),
            onSeek: _seek,
            seekStep: _seekStep,
          ),
        ),
        const SizedBox(height: VSpace.s8),
        _likeButton(l),
        const SizedBox(height: VSpace.s4),
        if (data.loading)
          const SizedBox.square(
            dimension: VSize.menuTarget,
            child: Center(child: VLoading(size: VSize.playIcon)),
          )
        else
          VIconButton(
            icon: data.playing ? VIcons.pause : VIcons.play,
            label: data.playing ? l.actionPause : l.actionPlay,
            selected: true,
            style: VIconStyle.filled,
            onPressed: () {
              VHaptics.light();
              actions.onPlayPause();
            },
          ),
        const SizedBox(height: VSpace.s4),
        VIconButton(
          icon: VIcons.skipNext,
          label: l.actionNext,
          onPressed: actions.onNext,
        ),
        if (widget.volume case final volume?) ...[
          const SizedBox(height: VSpace.s8),
          volume,
        ],
        if (actions.onOpen case final open?) ...[
          const SizedBox(height: VSpace.s8),
          VIconButton(
            icon: VIcons.panelOpen,
            label: l.actionOpenPlayer,
            onPressed: open,
          ),
        ],
      ],
    );
  }
}

enum _Part { blocks, side, art }

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
    required this.cap,
  });

  final GlobalKey slotKey, sideKey;
  final double t, cap;
  final bool reduced, wide, disc;

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
    final gap = disc ? VSpace.s8 : VSpace.s16;
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
      final w = size.width - 2 * m;
      var blocksH = 0.0;
      if (hasChild(_Part.blocks)) {
        blocksH = layoutChild(
          _Part.blocks,
          BoxConstraints(minWidth: w, maxWidth: w, maxHeight: size.height),
        ).height;
      }
      final room = size.height - blocksH - gap - 2 * VSpace.s8;
      final side = [
        disc ? w : size.width,
        room,
        disc ? cap : size.width,
      ].reduce(math.min).clamp(0.0, double.infinity);
      final top = ((size.height - side - gap - blocksH) / 2).clamp(
        0.0,
        double.infinity,
      );
      big = Rect.fromLTWH((size.width - side) / 2, top, side, side);
      if (hasChild(_Part.blocks)) {
        positionChild(_Part.blocks, Offset(m, top + side + gap));
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
