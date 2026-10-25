import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../tokens.dart';
import 'artwork.dart';
import 'wave_progress.dart';

/// The "Wave" player style (spec UI §5.5): the artwork at full width, its bottom edge a
/// wave that ripples while playing and lies flat in pause. The played part of the edge is
/// drawn in `primary`: the edge is the progress, and dragging along it seeks.
class VWaveArtwork extends StatefulWidget {
  const VWaveArtwork({
    super.key,
    required this.itemId,
    required this.width,
    required this.progress,
    required this.playing,
    required this.onSeek,
    this.seekStep = 0.05,
    this.height,
  });

  final String itemId;
  final double width;

  /// Taller than wide on a tall screen (up to 1.15×, the player decides): the cover is
  /// cropped to fill it. Null: square.
  final double? height;
  final double progress;
  final bool playing;
  final ValueChanged<double> onSeek;
  final double seekStep;

  @override
  State<VWaveArtwork> createState() => _VWaveArtworkState();
}

class _VWaveArtworkState extends State<VWaveArtwork>
    with TickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: VDurations.long * 4,
  );
  late final AnimationController _amp = AnimationController(
    vsync: this,
    duration: VDurations.medium,
    value: widget.playing ? 1 : 0,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(VWaveArtwork old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduced = reduceMotion(context);
    final target = widget.playing ? 1.0 : 0.0;
    if (reduced) {
      _amp.value = target;
      _phase.stop();
      return;
    }
    _amp.animateTo(target, curve: VCurves.emphasized);
    if (widget.playing && !_phase.isAnimating) {
      _phase.repeat();
    } else if (!widget.playing) {
      _phase.stop();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    _amp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = widget.width, h = widget.height ?? widget.width;
    final cover = math.max(w, h);
    // Only the bottom band (the edge) is grabbed; a drag shows where it will land.
    return SizedBox(
      width: w,
      height: h,
      child: VSeekable(
        progress: widget.progress,
        onSeek: widget.onSeek,
        step: widget.seekStep,
        hit: (local, size) => local.dy >= size.height - VSize.menuTarget,
        shape: const RoundedRectangleBorder(),
        child: ClipRect(
          child: OverflowBox(
            maxWidth: cover,
            maxHeight: cover,
            child: VArtworkPicture(itemId: widget.itemId, size: cover),
          ),
        ),
        builder: (context, shown, picture) => RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_phase, _amp]),
            builder: (context, child) {
              final wave = _Wave(phase: _phase.value, amplitude: _amp.value);
              return CustomPaint(
                foregroundPainter: _EdgePainter(
                  wave: wave,
                  progress: shown,
                  played: scheme.primary,
                  rest: scheme.secondary.withValues(alpha: 0.45),
                ),
                child: ClipPath(clipper: _WaveClipper(wave), child: child),
              );
            },
            child: picture,
          ),
        ),
      ),
    );
  }
}

class _Wave {
  const _Wave({required this.phase, required this.amplitude});

  final double phase, amplitude;

  /// The edge's y at [x], for a box of [size].
  double y(double x, Size size) =>
      size.height -
      VSize.waveCrop / 2 -
      amplitude *
          VSize.waveAmplitude *
          math.sin((x / VSize.waveLength + phase) * 2 * math.pi);

  Path edge(Size size, double from, double to) {
    final p = Path()..moveTo(from, y(from, size));
    for (var x = from; x <= to; x += 2) {
      p.lineTo(x, y(x, size));
    }
    return p..lineTo(to, y(to, size));
  }
}

class _WaveClipper extends CustomClipper<Path> {
  const _WaveClipper(this.wave);

  final _Wave wave;

  @override
  Path getClip(Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0);
    for (var x = size.width; x >= 0; x -= 2) {
      p.lineTo(x, wave.y(x, size));
    }
    return p..close();
  }

  @override
  bool shouldReclip(_WaveClipper old) =>
      old.wave.phase != wave.phase || old.wave.amplitude != wave.amplitude;
}

class _EdgePainter extends CustomPainter {
  const _EdgePainter({
    required this.wave,
    required this.progress,
    required this.played,
    required this.rest,
  });

  final _Wave wave;
  final double progress;
  final Color played, rest;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = VSize.ringStroke
      ..strokeCap = StrokeCap.round;
    final at = size.width * progress;
    canvas.drawPath(wave.edge(size, at, size.width), stroke..color = rest);
    canvas.drawPath(wave.edge(size, 0, at), stroke..color = played);
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.wave.phase != wave.phase ||
      old.wave.amplitude != wave.amplitude ||
      old.progress != progress ||
      old.played != played ||
      old.rest != rest;
}
