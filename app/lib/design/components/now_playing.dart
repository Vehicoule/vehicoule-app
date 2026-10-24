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

class NowPlayingData {
  const NowPlayingData({
    required this.track,
    required this.sourceTitle,
    required this.playing,
    required this.loading,
    required this.positionMs,
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
  final int positionMs, durationMs;
  final bool liked;
  final DownloadStateView? download;
  final double? downloadProgress;
  final bool shuffle;
  final Repeat repeat;

  /// A sleep timer is running: the moon and the time left show in the header.
  final Duration? sleepLeft;
  final bool sleepEndOfTrack;

  double get progress =>
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

  /// To a position in milliseconds.
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
/// In the lyrics and queue views the artwork shrinks into the compact header.
class VNowPlaying extends StatelessWidget {
  const VNowPlaying({
    super.key,
    required this.data,
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
      compactKey = ValueKey('np.compact');

  @override
  Widget build(BuildContext context) {
    if (size == PlayerSize.compact) {
      return axis == Axis.vertical ? _strip(context) : _compact(context);
    }
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      // The player's one gradient: a tint behind the artwork (spec UI §2.2).
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: wide ? const Alignment(-0.5, 0) : const Alignment(0, -0.45),
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
            Expanded(
              child: vSharedAxis(
                key: view == PlayerView.player ? PlayerView.player : 'side',
                child: view == PlayerView.player
                    ? _player(context)
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: VSpace.s16,
                            ),
                            child: _compact(context),
                          ),
                          const SizedBox(height: VSpace.s8),
                          Expanded(
                            child: vSharedAxis(
                              key: view,
                              child: (view == PlayerView.lyrics
                                  ? lyrics
                                  : queue)(context),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            ?volume,
            Padding(
              padding: const EdgeInsets.all(VSpace.s16),
              child: VViewSelector(
                key: selectorKey,
                value: view,
                onChanged: onView,
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

  Widget _header(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sleep = data.sleepLeft;
    return Padding(
      key: headerKey,
      padding: const EdgeInsets.symmetric(horizontal: VSpace.s8),
      child: Row(
        children: [
          if (actions.onCollapse != null)
            VIconButton(
              icon: VIcons.collapse,
              label: l.actionCollapse,
              onPressed: actions.onCollapse,
            ),
          const SizedBox(width: VSpace.s8),
          Expanded(
            child: Text(
              l.playingFrom(data.sourceTitle),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
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
                  : l.sleepMinutesLeft(sleep!.inMinutes + 1),
              style: theme.textTheme.labelMedium,
            ),
          ],
          if (actions.onOutput != null)
            VIconButton(
              icon: VIcons.devices,
              label: l.actionOutput,
              onPressed: actions.onOutput,
            ),
          if (onImmersive != null)
            VIconButton(
              icon: VIcons.fullscreen,
              label: l.actionImmersive,
              onPressed: onImmersive,
            ),
          if (actions.onMenu != null)
            Builder(
              builder: (b) => VIconButton(
                icon: VIcons.more,
                label: l.actionMore,
                onPressed: () {
                  final box = b.findRenderObject()! as RenderBox;
                  actions.onMenu!(box.localToGlobal(Offset.zero) & box.size);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _times(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Row(
      key: progressKey,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(vTime(data.positionMs), style: style),
        Text(vTime(data.durationMs), style: style),
      ],
    );
  }

  Widget _title(
    BuildContext context, {
    CrossAxisAlignment align = CrossAxisAlignment.start,
  }) {
    final theme = Theme.of(context);
    return Column(
      key: titleKey,
      crossAxisAlignment: align,
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
      key: actionsKey,
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

  Widget _controls({bool compact = false}) => VControls(
    key: controlsKey,
    playing: data.playing,
    loading: data.loading,
    shuffle: data.shuffle,
    repeat: data.repeat,
    onPlayPause: actions.onPlayPause,
    onNext: actions.onNext,
    onPrevious: actions.onPrevious,
    onShuffle: actions.onShuffle,
    onRepeat: actions.onRepeat,
    compact: compact,
  );

  Widget _art(double side) => style == PlayerStyle.disc
      ? VArtwork(
          itemId: data.track.id,
          size: side,
          playing: data.playing,
          progress: data.progress,
          onSeek: _seek,
          seekStep: _seekStep,
          semanticLabel: data.track.album?.title,
        )
      : VWaveArtwork(
          itemId: data.track.id,
          width: side,
          progress: data.progress,
          playing: data.playing,
          onSeek: _seek,
          seekStep: _seekStep,
        );

  Widget _player(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final maxArt = size == PlayerSize.large ? 420.0 : 300.0;
      // Room left for the title, actions, times and controls under the artwork.
      const below = 260.0;
      final room = wide ? box.maxWidth / 2 : box.maxWidth;
      final side = [
        room - 2 * VSpace.s24,
        box.maxHeight - (wide ? 0 : below),
        maxArt,
      ].reduce((a, b) => a < b ? a : b).clamp(120.0, maxArt);
      final art = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(key: artworkKey, child: _art(side)),
          if (style == PlayerStyle.disc)
            SizedBox(width: side, child: _times(context)),
        ],
      );
      final blocks = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(context),
          if (style == PlayerStyle.wave) _times(context),
          const SizedBox(height: VSpace.s16),
          Center(child: _actions(context)),
          const SizedBox(height: VSpace.s16),
          Center(child: _controls()),
        ],
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: VSpace.s24,
          vertical: VSpace.s8,
        ),
        child: wide
            ? Row(
                children: [
                  Expanded(child: Center(child: art)),
                  const SizedBox(width: VSpace.s24),
                  Expanded(child: blocks),
                ],
              )
            : Column(
                children: [
                  art,
                  const SizedBox(height: VSpace.s16),
                  blocks,
                ],
              ),
      );
    },
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

  Widget _compact(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      key: compactKey,
      children: [
        VArtwork(
          itemId: data.track.id,
          size: VSize.compactArt,
          playing: data.playing,
          progress: data.progress,
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
        if (inlinePlayPause) _playPause(l),
      ],
    );
  }

  /// The collapsed desktop pane: a 76 px column (spec UI §4.2).
  Widget _strip(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      key: compactKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        VArtwork(
          itemId: data.track.id,
          size: VSize.strip - VSpace.s16,
          playing: data.playing,
          progress: data.progress,
          onSeek: _seek,
          seekStep: _seekStep,
        ),
        const SizedBox(height: VSpace.s8),
        _likeButton(l),
        _playPause(l),
        VIconButton(
          icon: VIcons.skipNext,
          label: l.actionNext,
          onPressed: actions.onNext,
        ),
        ?volume,
      ],
    );
  }
}
