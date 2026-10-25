// The ring's played part (spec UI §5.5): from 12 o'clock clockwise to the progress,
// nothing of the played colour anywhere else (user report: a played dash just left of
// 12 o'clock), and one continuous ring: no hole, no overlap where played meets rest.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart' show M3ETheme;
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
  testWidgets('circular indicators are continuous, linear ones keep their gap', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: vTheme(brightness: Brightness.light, seed: VPresets.seeds.first),
        builder: vAppBuilder,
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final t = M3ETheme.of(ctx).progressIndicatorTheme;
    expect(t.circular.gapSize, 0);
    expect(t.linear.gapSize, greaterThan(0));
  });

  for (final shape in [ArtShape.circle, ArtShape.cookie]) {
    for (final p in [0.0, 0.01, 0.5, 0.99, 1.0]) {
      test('$shape at $p: played only on its clockwise arc', () async {
        final px = await _paint(p, shape);
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
        // A butt end: the played colour stops at its arc, give or take a pixel.
        final edge = 1.5 / (_size / 2) * 180 / math.pi;
        for (final a in played) {
          final inside = a <= p * 360 + edge || a >= 360 - edge;
          expect(inside, isTrue, reason: 'played pixel at $a° for p = $p');
        }
        // Continuous: every degree of the ring is painted, once.
        final painted = List.filled(360, 0);
        for (final a in [...played, ...track]) {
          painted[a.floor() % 360]++;
        }
        for (var d = 0; d < 360; d++) {
          expect(painted[d], greaterThan(0), reason: 'a hole at $d° for p = $p');
        }
        if (p > 0 && p < 1) {
          // Where they meet (the head, 12 o'clock), no pixel mixes the two colours.
          var mixed = 0;
          for (var y = 0; y < _size; y++) {
            for (var x = 0; x < _size; x++) {
              final i = (y * _size.toInt() + x) * 4;
              final r = px.getUint8(i), b = px.getUint8(i + 2);
              if (r > 80 && b > 80) mixed++;
            }
          }
          expect(mixed, lessThanOrEqualTo(2 * _stroke), reason: 'an overlap');
        }
      });
    }
  }
}
