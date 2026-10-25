// The ring's played part (spec UI §5.5): from 12 o'clock clockwise to the progress,
// nothing of the played colour anywhere else, the two gaps the same (user report: a
// played dash just left of 12 o'clock).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';

const _size = 200.0, _stroke = VSize.ringStroke;
const _played = Color(0xFFFF0000), _track = Color(0xFF0000FF);

Future<ByteData> _paint(double p, ArtShape shape) async {
  const box = Rect.fromLTWH(
    _stroke / 2,
    _stroke / 2,
    _size - _stroke,
    _size - _stroke,
  );
  final painter = VRingPainter(
    geometry: VRingGeometry(vRingOutline(shape, box), box.center),
    shape: shape,
    turn: 0,
    progress: p,
    played: _played,
    track: _track,
  );
  final rec = ui.PictureRecorder();
  painter.paint(Canvas(rec), const Size.square(_size));
  final img = await rec.endRecording().toImage(_size.toInt(), _size.toInt());
  return (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
}

/// Clockwise from 12 o'clock, in degrees [0, 360).
double _angle(int x, int y) {
  final a = math.atan2(x + 0.5 - _size / 2, -(y + 0.5 - _size / 2));
  return (a < 0 ? a + 2 * math.pi : a) * 180 / math.pi;
}

void main() {
  for (final shape in [ArtShape.circle, ArtShape.cookie]) {
    for (final p in [0.0, 0.01, 0.5, 0.99, 1.0]) {
      test('$shape at $p: played only on its clockwise arc', () async {
        final px = await _paint(p, shape);
        // A round cap reaches half the stroke past each end of the arc.
        final slack = (_stroke / 2 + 1) / (_size / 2) * 180 / math.pi;
        final played = <double>[], track = <double>[];
        for (var y = 0; y < _size; y++) {
          for (var x = 0; x < _size; x++) {
            final i = (y * _size.toInt() + x) * 4;
            final r = px.getUint8(i), b = px.getUint8(i + 2);
            final a = _angle(x, y);
            if (r > 200 && b < 60) played.add(a);
            if (b > 200 && r < 60) track.add(a);
          }
        }
        for (final a in played) {
          final inside =
              a <= p * 360 + slack || a >= 360 - slack; // the start's cap
          expect(inside, isTrue, reason: 'played pixel at $a° for p = $p');
        }
        if (p > 0.005 && p < 0.9) {
          // The gaps after the played end and before 12 o'clock are equal.
          final after =
              track.where((a) => a > p * 360).reduce(math.min) - p * 360;
          final before = 360 - track.reduce(math.max);
          expect(after, closeTo(before, slack), reason: 'gaps $after / $before');
        }
      });
    }
  }
}
