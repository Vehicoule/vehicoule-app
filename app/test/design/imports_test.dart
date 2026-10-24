// Imports and reuse guards (spec UI §3, §5): material_ui replaces material.dart,
// material_3_expressive stays behind design/, and no screen rebuilds one of the six bricks.
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

final materialImport = RegExp(
  r'''import\s+['"]package:flutter/material\.dart['"]''',
);
final m3eImport = RegExp(r'''import\s+['"]package:material_3_expressive/''');

/// Own artwork, wave, ring or progress painters, and the stock controls the bricks wrap.
final ownBrick = RegExp(
  r'class\s+\w*(Artwork|Art|Cover|Wave|Ring|Disc|Progress|Equalizer)\w*\s+extends\s+CustomPainter'
  r'|\b(Slider|RangeSlider|CircularProgressIndicator|LinearProgressIndicator|RefreshProgressIndicator'
  r'|SegmentedButton|MenuAnchor|PopupMenuButton|DropdownMenu|ToggleButtons)\s*[<(]'
  r'|\bshowMenu\s*[<(]|\bM3E\w+|\bVArtworkPicture\b',
);

void main() {
  test('no material.dart import, material_3_expressive only in design/', () {
    expect(
      offending([
        ('sample', "import 'package:flutter/material.dart';"),
      ], materialImport),
      hasLength(1),
    );
    expect(
      offending([
        (
          'sample',
          "import 'package:material_3_expressive/material_3_expressive.dart';",
        ),
      ], m3eImport),
      hasLength(1),
    );
    final lib = [
      for (final s in sources('lib'))
        if (!s.$1.startsWith('lib/bridge/')) s,
    ];
    expect(lib, isNotEmpty);
    expect(offending(lib, materialImport), isEmpty);
    expect(offending(outsideDesign(), m3eImport), isEmpty);
  });

  test('no feature or shell file defines its own artwork, controls, progress, selector, track row or menu', () {
    for (final bad in [
      'class CoverPainter extends CustomPainter {',
      'class _WaveRing extends CustomPainter {',
      'Slider(value: v, onChanged: f)',
      'const LinearProgressIndicator()',
      'SegmentedButton<int>(segments: s)',
      'MenuAnchor(menuChildren: m)',
      'PopupMenuButton<int>(itemBuilder: b)',
      'M3EButtonGroup(actions: a)',
      'VArtworkPicture(itemId: id, size: 44)',
    ]) {
      expect(offending([('sample', bad)], ownBrick), hasLength(1), reason: bad);
    }
    expect(offending([('sample', 'VTrackRow(track: t)')], ownBrick), isEmpty);
    expect(offending(screens(), ownBrick), isEmpty);
  });
}
