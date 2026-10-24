import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/design/design.dart';

void main() {
  test('pastelSeed caps chroma at 48', () {
    for (var h = 0; h < 360; h += 15) {
      final loud = Color(Hct.from(h.toDouble(), 120, 50).toInt());
      final p = Hct.fromInt(pastelSeed(loud).toARGB32());
      expect(p.chroma, lessThanOrEqualTo(48.5), reason: 'hue $h');
      expect(
        p.hue,
        closeTo(Hct.fromInt(loud.toARGB32()).hue, 3),
        reason: 'hue $h kept',
      );
    }
    const soft = Color(0xFF6F8F72);
    expect(pastelSeed(soft), soft);
  });

  testWidgets('seedFromArtwork caches by path', (tester) async {
    final path = File('assets/gallery/art_1.png').absolute.path;
    await tester.runAsync(() async {
      final before = debugQuantizations;
      final a = await seedFromArtwork(path);
      final b = await seedFromArtwork(path);
      expect(a, isNotNull);
      expect(b, a);
      expect(debugQuantizations - before, 1);
      expect(Hct.fromInt(a!.toARGB32()).chroma, lessThanOrEqualTo(48.5));
    });
  });

  testWidgets('seedFromArtwork gives null for a missing file', (tester) async {
    await tester.runAsync(() async {
      expect(await seedFromArtwork('/nope/missing.png'), isNull);
    });
  });
}
