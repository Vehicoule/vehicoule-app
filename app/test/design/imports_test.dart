// Imports and reuse guards (spec UI §3, §5): material_ui replaces material.dart,
// material_3_expressive stays behind design/, and no screen rebuilds one of the six bricks.
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

final materialImport = RegExp(
  r'''import\s+['"]package:flutter/material\.dart['"]''',
);
final m3eImport = RegExp(r'''import\s+['"]package:material_3_expressive/''');

/// Own artwork, wave, ring or progress painters, and the stock controls the bricks wrap.
/// Own painters (any name), pictures, rows, sheets, dialogs, menus and play/pause, and the
/// stock controls the bricks wrap: outside design/, every one of these re-creates a brick.
final ownBrick = RegExp(
  r'\bextends\s+CustomPainter\b'
  r'|\b(Slider|RangeSlider|CircularProgressIndicator|LinearProgressIndicator|RefreshProgressIndicator'
  r'|SegmentedButton|MenuAnchor|PopupMenuButton|DropdownMenu|ToggleButtons|ListTile|AnimatedIcon'
  r'|Image|Image\.file|Image\.network|FileImage|artworkFile)\s*[<(]'
  r'|\b(showMenu|showModalBottomSheet|showDialog|showGeneralDialog)\b|\bM3E\w+|\bVArtworkPicture\b',
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
      // Any painter, whatever its name: artwork, waves and rings live in design/.
      'class _P extends CustomPainter {',
      // Own artwork: pictures and the core's artwork cache go through VArtwork.
      'ClipRRect(child: Image.file(File(path)))',
      'Image(image: provider)',
      'FileImage(File(path))',
      'final p = await artworkFile(id: id, size: 44);',
      // Own rows, sheets, dialogs, menus and play/pause.
      'ListTile(title: Text(t.title))',
      'showModalBottomSheet(context: c, builder: b)',
      'showDialog<void>(context: c, builder: b)',
      'showMenu(context: c, position: p, items: i)',
      'AnimatedIcon(icon: AnimatedIcons.play_pause, progress: a)',
      'class _Row extends StatelessWidget {}\nWidget build(c) => ListTile(\n  title: x,\n);',
    ]) {
      expect(offending([('sample', bad)], ownBrick), hasLength(1), reason: bad);
    }
    expect(offending([('sample', 'VTrackRow(track: t)')], ownBrick), isEmpty);
    expect(
      offending([
        ('sample', 'VArtwork(itemId: id, size: VSize.trackArt)'),
      ], ownBrick),
      isEmpty,
    );
    expect(offending(outsideDesign(), ownBrick), isEmpty);
  });
}
