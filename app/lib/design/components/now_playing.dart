import 'package:flutter/foundation.dart';
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
}

/// The one player (spec UI §5.5), presentation only. Its blocks, always in this order:
/// header · artwork · title · like/playlist/download · times · controls · view selector.
///
/// - [PlayerSize.compact]: artwork (disc, ring), title, like, ⏯ — the mini player, the
///   desktop strip ([axis] vertical, with ⏭ and [volume]) and the lyrics/queue header;
/// - medium (desktop pane) and large (full screen); [wide] puts the artwork left of the
///   blocks (landscape, immersive).
///
/// In the lyrics and queue views the big artwork shrinks into the compact header: one
/// artwork flies between the two places (a 150 ms fade with "reduce motion").
/// [position] (ms) is listened to by the ring, the wave edge and the times only.
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
    this.inlinePlayPause = true,
  });

  final NowPlayingData data;
  final ValueListenable<int> position;
  final PlayerSize size;
  final PlayerStyle style;
  final PlayerView view;
  final ValueChanged<PlayerView> onView;
  final NowPlayingActions actions;
  final WidgetBuilder lyrics, queue;
  final VoidCallback? onImmersive;
  final Widget? volume;
  final Axis axis;
  final bool wide;

  /// False when ⏯ is the separate [VPlayPauseFab] (the mobile mini player).
  final bool inlinePlayPause;

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

  NowPlayingData get data => widget.data;
  NowPlayingActions get actions => widget.actions;

  @override
  void didUpdateWidget(VNowPlaying old) {
    super.didUpdateWidget(old);
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
      return widget.axis == Axis.vertical ? _strip(context) : _compact(context);
    }
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      // The player's one gradient: a tint behind the artwork (spec UI §2.2).
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: widget.wide
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
        child: Column(
          children: [
            _header(context),
            Expanded(child: LayoutBuilder(builder: _body)),
            ?widget.volume,
            Padding(
              padding: const EdgeInsets.all(VSpace.s16),
              child: VViewSelector(
                key: VNowPlaying.selectorKey,
                value: widget.view,
                onChanged: widget.onView,
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _seekStep => data.durationMs <= 0
      ? 0.05
      : (VDurations.seekStep.inMilliseconds / data.durationMs).clamp(0.0, 1.0);

  void _seek(double p) => actions.onSeek((p * data.durationMs).round());

  /// The big artwork's side for this body: as large as the size allows, leaving room for
  /// the blocks under it (beside it when wide), and never taller than the body.
  double _artSide(BuildContext context, BoxConstraints box) {
    final maxArt = widget.size == PlayerSize.large
        ? VSize.playerArtLarge
        : VSize.playerArtMedium;
    final times = MediaQuery.textScalerOf(context).scale(VSpace.s24);
    final fits = box.maxHeight - VSpace.s8 - times;
    final room = widget.wide ? box.maxWidth / 2 : box.maxWidth;
    final tall = widget.wide ? fits : box.maxHeight - VSize.playerBlocks;
    // The Wave style is full width (spec UI §5.5); the disc keeps a margin and a cap.
    final wave = widget.style == PlayerStyle.wave;
    final cap = wave ? room : maxArt;
    final side = [
      wave ? room : room - 2 * VSpace.s24,
      tall,
      cap,
    ].reduce((a, b) => a < b ? a : b).clamp(VSize.playerArtMin, cap);
    return side.clamp(0.0, fits < 0 ? 0.0 : fits);
  }

  Widget _body(BuildContext context, BoxConstraints box) {
    final side = _artSide(context, box);
    final big = widget.wide
        ? Rect.fromLTWH((box.maxWidth / 2 - side) / 2, VSpace.s8, side, side)
        : Rect.fromLTWH((box.maxWidth - side) / 2, VSpace.s8, side, side);
    const slot = Rect.fromLTWH(
      VSpace.s16,
      0,
      VSize.compactArt,
      VSize.compactArt,
    );
    final reduced = reduceMotion(context);
    return AnimatedBuilder(
      animation: _side,
      builder: (context, _) {
        final t = _side.value;
        final rect = reduced
            ? (t < 0.5 ? big : slot)
            : Rect.lerp(big, slot, t)!;
        return Stack(
          children: [
            if (t < 1)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: t > 0,
                  child: Opacity(opacity: 1 - t, child: _player(context, side)),
                ),
              ),
            if (t > 0)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: t < 1,
                  child: Opacity(opacity: t, child: _sideView(context)),
                ),
              ),
            Positioned.fromRect(
              rect: rect,
              child: Opacity(
                opacity: reduced ? (1 - 2 * t).abs() : 1,
                child: KeyedSubtree(
                  key: VNowPlaying.artworkKey,
                  child: _art(rect.width, compact: t > 0.5),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _art(double side, {required bool compact}) => ValueListenableBuilder(
    valueListenable: widget.position,
    builder: (context, ms, _) {
      final p = data.progressAt(ms);
      // The compact header keeps the disc in both styles (spec UI §5.5).
      if (widget.style == PlayerStyle.wave && !compact) {
        return VWaveArtwork(
          itemId: data.track.id,
          width: side,
          progress: p,
          playing: data.playing,
          onSeek: _seek,
          seekStep: _seekStep,
        );
      }
      return VArtwork(
        itemId: data.track.id,
        size: side,
        playing: data.playing,
        progress: p,
        onSeek: _seek,
        seekStep: _seekStep,
        semanticLabel: data.track.album?.title,
      );
    },
  );

  Widget _header(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sleep = data.sleepLeft;
    return Padding(
      key: VNowPlaying.headerKey,
      padding: const EdgeInsets.symmetric(horizontal: VSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (actions.onCollapse != null)
                VIconButton(
                  icon: VIcons.collapse,
                  label: l.actionCollapse,
                  onPressed: actions.onCollapse,
                ),
              const Spacer(),
              if (sleep != null || data.sleepEndOfTrack) ...[
                VSymbol(
                  VIcons.bedtime,
                  size: VSize.iconSmall,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: VSpace.s4),
                Text(
                  data.sleepEndOfTrack
                      ? l.sleepEndOfTrack
                      : l.sleepMinutesLeft((sleep!.inSeconds / 60).ceil()),
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(width: VSpace.s8),
              ],
              if (actions.onOutput != null)
                VIconButton(
                  icon: VIcons.devices,
                  label: l.actionOutput,
                  onPressed: actions.onOutput,
                ),
              if (widget.onImmersive != null)
                VIconButton(
                  icon: VIcons.fullscreen,
                  label: l.actionImmersive,
                  onPressed: widget.onImmersive,
                ),
              if (actions.onMenu != null)
                Builder(
                  builder: (b) => VIconButton(
                    icon: VIcons.more,
                    label: l.actionMore,
                    onPressed: () {
                      final box = b.findRenderObject()! as RenderBox;
                      actions.onMenu!(
                        box.localToGlobal(Offset.zero) & box.size,
                      );
                    },
                  ),
                ),
            ],
          ),
          // Its own line, wrapping if it must: never cut (a narrow pane has little room
          // beside the icons).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.s8),
            child: Text(
              l.playingFrom(data.sourceTitle),
              style: theme.textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _times(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
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

  Widget _title(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: VNowPlaying.titleKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data.track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall,
        ),
        Text(
          data.track.artists.map((a) => a.name).join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
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
    return VConnectedGroup(
      key: VNowPlaying.actionsKey,
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

  /// The player view, with an empty square where the flying artwork sits.
  Widget _player(BuildContext context, double side) {
    final disc = widget.style == PlayerStyle.disc;
    final artArea = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: VSpace.s8 + side),
        if (disc) SizedBox(width: side, child: _times(context)),
      ],
    );
    final blocks = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(context),
        if (!disc) ...[const SizedBox(height: VSpace.s8), _times(context)],
        const SizedBox(height: VSpace.s16),
        Center(child: _actions(context)),
        const SizedBox(height: VSpace.s16),
        Center(child: _controls()),
      ],
    );
    const pad = EdgeInsets.symmetric(
      horizontal: VSpace.s24,
      vertical: VSpace.s8,
    );
    if (widget.wide) {
      return Row(
        children: [
          Expanded(
            child: Align(alignment: Alignment.topCenter, child: artArea),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(padding: pad, child: blocks),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        artArea,
        const SizedBox(height: VSpace.s8),
        Expanded(
          child: SingleChildScrollView(padding: pad, child: blocks),
        ),
      ],
    );
  }

  /// Lyrics or queue under the compact header, whose artwork slot the flying artwork fills.
  Widget _sideView(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: VSpace.s16),
        child: _compact(context, slot: true),
      ),
      const SizedBox(height: VSpace.s8),
      Expanded(
        child: widget.view == PlayerView.player
            ? const SizedBox.shrink()
            : vSharedAxis(
                key: widget.view,
                reverse: widget.view == PlayerView.lyrics,
                child: (widget.view == PlayerView.lyrics
                    ? widget.lyrics
                    : widget.queue)(context),
              ),
      ),
    ],
  );

  Widget _playPause(AppLocalizations l) => data.loading
      ? const SizedBox.square(
          dimension: VSize.menuTarget,
          child: Center(child: VLoading(size: VSize.playIcon)),
        )
      : VIconButton(
          icon: data.playing ? VIcons.pause : VIcons.play,
          label: data.playing ? l.actionPause : l.actionPlay,
          filled: true,
          onPressed: () {
            VHaptics.light();
            actions.onPlayPause();
          },
        );

  Widget _likeButton(AppLocalizations l) => VIconButton(
    icon: VIcons.favorite,
    label: l.actionLike,
    selected: data.liked,
    onPressed: _like(l).onSelected,
  );

  /// Artwork (disc, ring), title, like, ⏯. With [slot], the artwork's place is left empty
  /// for the player's flying artwork.
  Widget _compact(BuildContext context, {bool slot = false}) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      key: VNowPlaying.compactKey,
      children: [
        if (slot)
          const SizedBox.square(
            key: VNowPlaying.compactArtKey,
            dimension: VSize.compactArt,
          )
        else
          ValueListenableBuilder(
            valueListenable: widget.position,
            builder: (context, ms, _) => VArtwork(
              itemId: data.track.id,
              size: VSize.compactArt,
              playing: data.playing,
              progress: data.progressAt(ms),
            ),
          ),
        const SizedBox(width: VSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              Text(
                data.track.artists.map((a) => a.name).join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _likeButton(l),
        if (widget.inlinePlayPause) _playPause(l),
      ],
    );
  }

  /// The collapsed desktop pane: a 76 px column (spec UI §4.2).
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
            size: VSize.strip - VSpace.s16,
            playing: data.playing,
            progress: data.progressAt(ms),
            onSeek: _seek,
            seekStep: _seekStep,
          ),
        ),
        const SizedBox(height: VSpace.s8),
        _likeButton(l),
        _playPause(l),
        VIconButton(
          icon: VIcons.skipNext,
          label: l.actionNext,
          onPressed: actions.onNext,
        ),
        ?widget.volume,
      ],
    );
  }
}
