import 'dart:math' as math;

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

/// What makes the disc ring, the wave edge and the linear wave seek alike: dragging or
/// tapping, ←/→ on the keyboard, and an accessible slider. Without [onSeek] it only shows.
class VSeekable extends StatelessWidget {
  const VSeekable({
    super.key,
    required this.progress,
    required this.onSeek,
    required this.child,
    this.mapping = horizontalSeek,
    this.step = 0.05,
    this.shape = const StadiumBorder(),
  });

  final double progress;
  final ValueChanged<double>? onSeek;
  final Widget child;
  final SeekMapping mapping;

  /// One ←/→ press, as a fraction (the player passes 10 s over the track length).
  final double step;
  final ShapeBorder shape;

  @override
  Widget build(BuildContext context) {
    final seek = onSeek;
    if (seek == null) return child;
    final l = AppLocalizations.of(context);
    final pct = NumberFormat.percentPattern(l.localeName);
    final p = progress.clamp(0.0, 1.0);
    void by(double d) => seek((p + d).clamp(0.0, 1.0));
    return Semantics(
      slider: true,
      label: l.seekLabel,
      value: pct.format(p),
      increasedValue: pct.format((p + step).clamp(0.0, 1.0)),
      decreasedValue: pct.format((p - step).clamp(0.0, 1.0)),
      onIncrease: () => by(step),
      onDecrease: () => by(-step),
      child: VFocusRing(
        shape: shape,
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
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => seek(mapping(d.localPosition, box.biggest)),
              onPanUpdate: (d) => seek(mapping(d.localPosition, box.biggest)),
              child: ExcludeSemantics(child: child),
            ),
          ),
        ),
      ),
    );
  }
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
      child: SizedBox(
        height: VSize.menuTarget,
        child: Center(
          child: wave
              ? M3EProgressIndicator.linearWavy(value: progress)
              : M3EProgressIndicator.linear(value: progress),
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
    final (Widget icon, String label) = switch (state) {
      DownloadStateView.done => (
        VSymbol(VIcons.downloadDone, filled: true, size: size),
        l.downloaded,
      ),
      DownloadStateView.queued || DownloadStateView.running => (
        M3EProgressIndicator.circular(
          value: progress,
          size: size,
          strokeWidth: 3,
        ),
        l.downloading,
      ),
      DownloadStateView.failed ||
      null => (VSymbol(VIcons.download, size: size), l.actionDownload),
    };
    final reduced = reduceMotion(context);
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
