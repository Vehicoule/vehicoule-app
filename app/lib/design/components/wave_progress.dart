import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../bridge/downloads.dart';
import '../../l10n/app_localizations.dart';
import '../motion.dart';
import '../symbols.dart';
import '../tokens.dart';
import 'focus_ring.dart';

/// Maps a pointer position inside the seek area to a progress in [0, 1].
typedef SeekMapping = double Function(Offset local, Size size);

double horizontalSeek(Offset local, Size size) =>
    size.width <= 0 ? 0 : (local.dx / size.width).clamp(0.0, 1.0);

/// Clockwise from the top, for a ring around the artwork.
double angularSeek(Offset local, Size size) {
  final d = local - size.center(Offset.zero);
  final a = math.atan2(d.dx, -d.dy); // 0 at the top, clockwise
  return ((a < 0 ? a + 2 * math.pi : a) / (2 * math.pi)).clamp(0.0, 1.0);
}

/// Builds the seekable's content for the progress it shows: the drag position while
/// dragging, the real progress otherwise.
typedef SeekBuilder = Widget Function(
  BuildContext context,
  double shown,
  Widget? child,
);

/// Which points belong to the slider (the ring, not the cover inside it).
typedef SeekHitArea = bool Function(Offset local, Size size);

/// The ring around a disc of this outer [Size]: within [VSize.ringHit] inside its edge.
bool ringHit(Offset local, Size size) {
  final r = size.shortestSide / 2;
  final d = (local - size.center(Offset.zero)).distance;
  return d >= r - VSize.ringHit && d <= r;
}

/// What makes the disc ring, the wave edge and the linear wave seek alike: a tap or a key
/// seeks at once; a drag previews and seeks once, on release; an accessible slider with
/// ←/→. [hit] limits where it can be grabbed. With [angular], a drag that crosses 12
/// o'clock stops at the end instead of wrapping. Without [onSeek] it only shows.
class VSeekable extends StatefulWidget {
  const VSeekable({
    super.key,
    required this.progress,
    required this.onSeek,
    required this.builder,
    this.child,
    this.mapping = horizontalSeek,
    this.hit,
    this.angular = false,
    this.step = 0.05,
    this.shape = const StadiumBorder(),
  });

  final double progress;
  final ValueChanged<double>? onSeek;
  final SeekBuilder builder;
  final Widget? child;
  final SeekMapping mapping;
  final SeekHitArea? hit;
  final bool angular;

  /// One ←/→ press, as a fraction (the player passes 10 s over the track length).
  final double step;
  final ShapeBorder shape;

  @override
  State<VSeekable> createState() => _VSeekableState();
}

class _VSeekableState extends State<VSeekable> {
  double? _drag;

  /// Where the last seek went, shown until the player's progress comes near it (or for
  /// a moment, if it never does): no snap back to the old place for one round trip.
  double? _held;
  Timer? _hold;

  double get _shown => (_drag ?? _held ?? widget.progress).clamp(0.0, 1.0);

  @override
  void didUpdateWidget(VSeekable old) {
    super.didUpdateWidget(old);
    final held = _held;
    if (held != null && (widget.progress - held).abs() <= 0.01) _release();
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  void _release() {
    _hold?.cancel();
    _hold = null;
    _held = null;
  }

  void _seek(double p) {
    setState(() => _held = p);
    _hold?.cancel();
    _hold = Timer(VDurations.long * 2, () {
      if (mounted) setState(_release);
    });
    widget.onSeek?.call(p);
  }

  void _move(Offset local, Size size) {
    var next = widget.mapping(local, size);
    final last = _drag;
    // Across the top the angle jumps 1 ↔ 0: hold the end it came from.
    if (widget.angular && last != null && (next - last).abs() > 0.5) {
      next = last > 0.5 ? 1.0 : 0.0;
    }
    setState(() => _drag = next);
  }

  void _commit() {
    final d = _drag;
    setState(() => _drag = null);
    if (d != null) _seek(d);
  }

  @override
  Widget build(BuildContext context) {
    final seek = widget.onSeek;
    final content = widget.builder(context, _shown, widget.child);
    if (seek == null) return content;
    final l = AppLocalizations.of(context);
    final pct = NumberFormat.percentPattern(l.localeName);
    final p = _shown;
    final step = widget.step;
    // From what the slider shows (a held seek included), so it moves and announces
    // the value it seeks to.
    void by(double d) => _seek((_shown + d).clamp(0.0, 1.0));
    return Semantics(
      slider: true,
      label: l.seekLabel,
      value: pct.format(p),
      increasedValue: pct.format((p + step).clamp(0.0, 1.0)),
      decreasedValue: pct.format((p - step).clamp(0.0, 1.0)),
      onIncrease: () => by(step),
      onDecrease: () => by(-step),
      child: VFocusRing(
        shape: widget.shape,
        child: Focus(
          onKeyEvent: (_, e) {
            if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
              by(step);
            } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
              by(-step);
            } else {
              return KeyEventResult.ignored;
            }
            return KeyEventResult.handled;
          },
          child: LayoutBuilder(
            builder: (context, box) => _HitArea(
              test: widget.hit,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) =>
                    _seek(widget.mapping(d.localPosition, box.biggest)),
                onPanStart: (d) => _move(d.localPosition, box.biggest),
                onPanUpdate: (d) => _move(d.localPosition, box.biggest),
                onPanEnd: (_) => _commit(),
                onPanCancel: () => setState(() => _drag = null),
                child: ExcludeSemantics(child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets pointers through outside [test]'s area (to the cover under the ring, say).
class _HitArea extends SingleChildRenderObjectWidget {
  const _HitArea({required this.test, super.child});

  final SeekHitArea? test;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHitArea(test);

  @override
  void updateRenderObject(BuildContext context, _RenderHitArea r) =>
      r.test = test;
}

class _RenderHitArea extends RenderProxyBox {
  _RenderHitArea(this.test);

  SeekHitArea? test;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      (test?.call(position, size) ?? true) &&
      super.hitTest(result, position: position);
}

/// Linear wavy progress (downloads, first launch, the player's bar): it waves while
/// [playing], lies flat otherwise and with "reduce motion".
class VWaveProgress extends StatelessWidget {
  const VWaveProgress({
    super.key,
    required this.progress,
    required this.playing,
    required this.onSeek,
    this.step = 0.05,
  });

  final double progress;
  final bool playing;
  final ValueChanged<double>? onSeek;
  final double step;

  @override
  Widget build(BuildContext context) {
    final wave = playing && !reduceMotion(context);
    return VSeekable(
      progress: progress,
      onSeek: onSeek,
      step: step,
      builder: (context, shown, _) => SizedBox(
        height: VSize.menuTarget,
        child: Center(
          child: wave
              ? M3EProgressIndicator.linearWavy(value: shown)
              : M3EProgressIndicator.linear(value: shown),
        ),
      ),
    );
  }
}

/// The download icon that morphs: arrow → progress ring → check (spec UI §2.5).
class VDownloadIcon extends StatelessWidget {
  const VDownloadIcon({
    super.key,
    required this.state,
    this.progress,
    this.size = VSize.icon,
  });

  final DownloadStateView? state;

  /// Bytes done over total while running; null is indeterminate.
  final double? progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final reduced = reduceMotion(context);
    final (Widget icon, String label) = switch (state) {
      DownloadStateView.done => (
        VSymbol(VIcons.check, filled: true, weight: 600, size: size),
        l.downloaded,
      ),
      // The download icon inside an M3E circular progress, never a bare arc. Queued
      // has no progress yet: the ring turns, or waits at zero with reduce motion.
      DownloadStateView.queued || DownloadStateView.running => (
        Stack(
          alignment: Alignment.center,
          children: [
            M3EProgressIndicator.circular(
              value: progress ?? (reduced ? 0 : null),
              size: size,
              strokeWidth: VSize.iconStroke,
            ),
            VSymbol(VIcons.download, size: size * 0.6),
          ],
        ),
        l.downloading,
      ),
      DownloadStateView.failed ||
      null => (VSymbol(VIcons.download, size: size), l.actionDownload),
    };
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: AnimatedSwitcher(
          duration: reduced ? VDurations.reduced : VDurations.short,
          transitionBuilder: (c, a) => reduced
              ? FadeTransition(opacity: a, child: c)
              : ScaleTransition(
                  scale: a,
                  child: FadeTransition(opacity: a, child: c),
                ),
          child: SizedBox.square(
            key: ValueKey(
              state == DownloadStateView.running
                  ? DownloadStateView.queued
                  : state,
            ),
            dimension: size,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
