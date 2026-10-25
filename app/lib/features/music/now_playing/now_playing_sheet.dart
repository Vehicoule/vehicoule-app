// The phone's full player (spec UI §5.5, §6.6, audit 13d): a sheet over the shell that
// the mini player opens. Its artwork flies from the mini player's disc with the sheet's
// extent (VExtentFlight, never a Hero). The lyrics are Task 6's; the queue is here.
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app_scope.dart';
import '../../../bridge/api/playback.dart' show queueOp;
import '../../../bridge/player.dart' show QueueOp;
import '../../../design/design.dart';

class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({super.key, required this.extent, required this.from});

  /// The sheet's extent, 0 (the mini player) to 1 (the player), for the shell.
  final ValueNotifier<double> extent;

  /// The mini player's disc, in global coordinates (`onArtworkRect`).
  final ValueListenable<Rect?> from;

  @override
  State<NowPlayingSheet> createState() => NowPlayingSheetState();
}

class NowPlayingSheetState extends State<NowPlayingSheet> {
  @visibleForTesting
  final controller = DraggableScrollableController();
  final _stack = GlobalKey();

  /// The player's artwork, relative to the sheet's top: the sheet moves the player
  /// without rebuilding it, so its last reported rect goes stale; this one doesn't.
  Rect? _to;
  double _height = 0;
  bool _shown = false, _landed = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(_moved);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _moved() {
    final e = controller.size;
    widget.extent.value = e;
    final shown = e > 0, landed = e >= 1;
    if (shown != _shown || landed != _landed) {
      setState(() {
        _shown = shown;
        _landed = landed;
      });
    }
  }

  Duration get _duration =>
      reduceMotion(context) ? VDurations.reduced : VDurations.medium;

  void open() =>
      controller.animateTo(1, duration: _duration, curve: VCurves.emphasized);

  void close() =>
      controller.animateTo(0, duration: _duration, curve: VCurves.emphasized);

  Rect? _local(Rect? global) {
    final box = _stack.currentContext?.findRenderObject() as RenderBox?;
    if (global == null || box == null || !box.hasSize) return null;
    return box.globalToLocal(global.topLeft) & global.size;
  }

  void _playerArt(Rect global) {
    final local = _local(global);
    if (local == null || !controller.isAttached) return;
    _to = local.translate(0, -_height * (1 - controller.size));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback;
    final width = MediaQuery.sizeOf(context).width;
    // Two columns in landscape and from the medium width (spec UI §4.3).
    final wide =
        windowClassOf(width) != WindowClass.compact ||
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return LayoutBuilder(
      builder: (context, box) {
        _height = box.maxHeight;
        final player = ListenableBuilder(
          listenable: Listenable.merge([playback, scope.theme]),
          builder: (context, _) {
            final data = playback.data(coverTop: scope.theme.coverTop);
            if (data == null) return const SizedBox.shrink();
            return VNowPlaying(
              data: data,
              position: scope.player.position,
              size: PlayerSize.large,
              style: scope.theme.playerStyle,
              view: playback.view,
              onView: (v) => playback.view = v,
              actions: playback.actions(onCollapse: close),
              lyrics: lyricsView,
              queue: queueView,
              wide: wide,
              artworkVisible: _landed,
              onArtworkRect: _playerArt,
            );
          },
        );
        // Back closes the open player first (and tells the system so: predictive back).
        return PopScope(
          canPop: !_shown,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) close();
          },
          child: Stack(
            key: _stack,
            children: [
              DraggableScrollableSheet(
                controller: controller,
                initialChildSize: 0,
                minChildSize: 0,
                maxChildSize: 1,
                snap: true,
                builder: (context, scroll) => Offstage(
                  // Laid out even closed: the flight knows where it lands.
                  offstage: !_shown,
                  child: ExcludeFocus(
                    excluding: !_shown,
                    child: CustomScrollView(
                      controller: scroll,
                      physics: const ClampingScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: SizedBox(height: _height, child: player),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder(
                valueListenable: widget.extent,
                builder: (context, e, _) {
                  final from = _local(widget.from.value), to = _to;
                  final track = playback.track;
                  if (e <= 0 || e >= 1 || from == null || to == null) {
                    return const SizedBox.shrink();
                  }
                  return VExtentFlight(
                    extent: e,
                    from: from,
                    to: to.translate(0, _height * (1 - e)),
                    builder: (context, side) => IgnorePointer(
                      child: VArtwork(
                        itemId: track?.id ?? '',
                        size: side,
                        playing: playback.playing,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Paroles: Task 6.
Widget lyricsView(BuildContext context) => const SizedBox.shrink();

/// File: what plays next, a track table (roving focus, Space selects, Delete removes).
Widget queueView(BuildContext context) => const _Queue();

class _Queue extends StatefulWidget {
  const _Queue();

  @override
  State<_Queue> createState() => _QueueState();
}

class _QueueState extends State<_Queue> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final playback = AppScope.of(context).playback;
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final upcoming = playback.queue?.upcoming ?? const [];
        return VRovingFocus(
          child: ListView(
            children: [
              for (final u in upcoming)
                VTrackRow(
                  key: ValueKey(u.entry),
                  track: u.track,
                  selected: _selected.contains(u.entry),
                  onTap: () => playback.jumpTo(u.entry),
                  onPlayNext: () => queueOp(op: QueueOp.move(entry: u.entry)),
                  onRemove: () => queueOp(op: QueueOp.remove(u.entry)),
                  onSelect: () => setState(() {
                    if (!_selected.remove(u.entry)) _selected.add(u.entry);
                  }),
                  // Task 6: the track menu.
                  quick: const [],
                  groups: const [],
                ),
            ],
          ),
        );
      },
    );
  }
}
