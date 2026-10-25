import 'dart:math' as math;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart'
    hide CornerRounding, RoundedPolygon;

import '../tokens.dart';
import 'artwork.dart' show ArtShape;

final _cookie = M3EShapeKind.cookie12Sided.polygon;

/// A unit rounded square whose corner is [share] of its side.
RoundedPolygon vRoundedSquare(double share) => RoundedPolygon.rectangle(
  width: 1,
  height: 1,
  centerX: 0.5,
  centerY: 0.5,
  rounding: CornerRounding(radius: share),
);

// A morph only depends on the corner's share of the side: a few dozen at most.
final _morphs = <int, Morph>{};

/// Cookie (progress 0) → rounded square whose corner is [share] of its side (1).
Morph vCookieMorph(double share) {
  final key = (share * 100).round().clamp(1, 50);
  return _morphs[key] ??= Morph(_cookie, vRoundedSquare(key / 100));
}

/// A path drawn in the unit square, stretched over [box].
Path vUnitPath(Path p, Rect box) => p.transform(
  (Matrix4.identity()
        ..translateByDouble(box.left, box.top, 0, 1)
        ..scaleByDouble(box.width, box.height, 1, 1))
      .storage,
);

/// An artwork shape's outline filling [box] (the ring around a picture is its own shape,
/// drawn a gap further out). The rounded square's corner follows the artwork's at rest.
Path vRingOutline(ArtShape shape, Rect box, {double corner = 0.14}) =>
    switch (shape) {
      ArtShape.circle => Path()..addOval(box),
      ArtShape.cookie => vUnitPath(_cookie.toPath(), box),
      ArtShape.roundedSquare => vUnitPath(vRoundedSquare(corner).toPath(), box),
    };

/// The progress ring's geometry (spec UI §5.5, Disque): the outline of the artwork's
/// shape, sampled evenly and ordered by the clockwise angle from 12 o'clock. The shape
/// may turn (the playing cookie); progress still starts at the top of the screen and
/// runs clockwise.
class VRingGeometry {
  VRingGeometry(Path outline, this.center) {
    final metric = outline.computeMetrics().first;
    final n = math.max(180, (metric.length / 2).ceil());
    var pts = [
      for (var i = 0; i < n; i++)
        metric.getTangentForOffset(metric.length * i / n)!.position,
    ];
    // Screen coordinates (y down): a positive area is clockwise.
    var area = 0.0;
    for (var i = 0; i < n; i++) {
      final a = pts[i], b = pts[(i + 1) % n];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    if (area < 0) pts = pts.reversed.toList();
    final angles = [for (final p in pts) _angle(p)];
    var start = 0;
    for (var i = 1; i < n; i++) {
      if (angles[i] < angles[start]) start = i;
    }
    points = [for (var i = 0; i < n; i++) pts[(start + i) % n]];
    this.angles = [for (var i = 0; i < n; i++) angles[(start + i) % n]];
    step = metric.length / n;
  }

  final Offset center;
  late final List<Offset> points;

  /// Clockwise from 12 o'clock, in [0, 2π), increasing (the shapes are star-shaped).
  late final List<double> angles;

  /// The length between two samples.
  late final double step;

  double _angle(Offset p) {
    final a = math.atan2(p.dx - center.dx, -(p.dy - center.dy));
    return a < 0 ? a + 2 * math.pi : a;
  }

  /// The first sample at the screen's top once the shape has turned by [turn] radians.
  int _top(double turn) {
    final local = (-turn) % (2 * math.pi);
    var lo = 0, hi = angles.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (angles[mid] < local) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo % angles.length;
  }

  Offset _turned(Offset p, double turn) {
    final d = p - center;
    final c = math.cos(turn), s = math.sin(turn);
    return center + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  /// How many samples the played part covers.
  int _count(double progress, int top) {
    if (progress <= 0) return 0;
    if (progress >= 1) return points.length;
    final sweep = progress * 2 * math.pi;
    final from = angles[top];
    var k = 0;
    while (k < points.length &&
        (angles[(top + k) % points.length] - from) % (2 * math.pi) <= sweep) {
      k++;
    }
    return k;
  }

  /// The played part, on screen: from the top, clockwise, to [progress].
  List<Offset> played(double progress, {required double turn}) {
    final top = _top(turn);
    final n = _count(progress, top);
    return [
      for (var k = 0; k < n; k++)
        _turned(points[(top + k) % points.length], turn),
      // A full ring closes on itself.
      if (n == points.length) _turned(points[top], turn),
    ];
  }

  /// The rest of the track, on screen: from where the played part ends, clockwise,
  /// back to 12 o'clock. The two meet end to end: one continuous ring.
  List<Offset> rest(double progress, {required double turn}) {
    final top = _top(turn);
    final played = _count(progress, top);
    final n = points.length;
    if (played >= n) return const [];
    // Starts on the played part's last sample, so no hole between them.
    final from = played == 0 ? 0 : played - 1;
    return [
      for (var k = from; k < n; k++) _turned(points[(top + k) % n], turn),
      _turned(points[top], turn),
    ];
  }
}

/// Paints the ring (spec UI §5.5): the played part in `primary`, the rest in the track
/// colour, one continuous line. Butt ends: the played colour stops exactly at the
/// progress, and starts exactly at 12 o'clock.
class VRingPainter extends CustomPainter {
  const VRingPainter({
    required this.geometry,
    required this.shape,
    required this.turn,
    required this.progress,
    required this.played,
    required this.track,
    this.stroke = VSize.ringStroke,
  });

  final double stroke;

  final VRingGeometry geometry;

  /// The shape the ring is heading to (for tests and semantics of the drawing).
  final ArtShape shape;
  final double turn, progress;
  final Color played, track;

  static Path _line(List<Offset> pts) =>
      pts.isEmpty ? Path() : (Path()..addPolygon(pts, false));

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      _line(geometry.rest(progress, turn: turn)),
      pen..color = track,
    );
    canvas.drawPath(
      _line(geometry.played(progress, turn: turn)),
      pen..color = played,
    );
    // No stop indicator: that is the linear bar's (a played dot at the track's end
    // read, on a closed ring, as progress before 12 o'clock).
  }

  @override
  bool shouldRepaint(VRingPainter old) =>
      old.geometry != geometry ||
      old.turn != turn ||
      old.progress != progress ||
      old.played != played ||
      old.track != track ||
      old.stroke != stroke;
}
