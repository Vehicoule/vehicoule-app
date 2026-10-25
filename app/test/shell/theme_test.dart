// The theme follows what plays (spec UI §2.2): one seed per track, the fallback for a
// colourless cover, and each setting written before it is shown.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vehicoule/bridge/events.dart';
import 'package:vehicoule/bridge/frb_generated.dart';
import 'package:vehicoule/debug/fake_api.dart';
import 'package:vehicoule/debug/library.dart';
import 'package:vehicoule/design/design.dart';
import 'package:vehicoule/theme_controller.dart';

Future<String> _cover(Color fill, Color dot) async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec)
    ..drawRect(const Rect.fromLTWH(0, 0, 112, 112), Paint()..color = fill)
    ..drawCircle(const Offset(56, 56), 30, Paint()..color = dot);
  final image = await rec.endRecording().toImage(112, 112);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = await Directory.systemTemp.createTemp('cover');
  final path = '${dir.path}/cover.png';
  await File(path).writeAsBytes(png!.buffer.asUint8List());
  return path;
}

NowPlaying _now(int i, String? art) => NowPlaying(
  track: sampleTracks[i],
  artworkPath: art,
  durationMs: BigInt.from(sampleTracks[i].durationMs!),
);

void main() {
  late FakeApi api;
  setUp(() {
    api = FakeApi();
    RustLib.initMock(api: api);
  });
  tearDown(RustLib.dispose);

  test('theme seed changes once per track, not per position', () async {
    var seeds = 0;
    final theme = ThemeController(
      seedFor: (path, {required fallback}) async {
        seeds++;
        return const Color(0xFF3366AA);
      },
      coverTopFor: (_) async => null,
      systemSeedFor: () async => null,
    );
    await theme.load();
    theme.start();
    api.setNow(_now(0, '/covers/1.png'));
    await pumpEventQueue();
    final first = seeds;
    for (var i = 0; i < 3; i++) {
      api.setNow(_now(0, '/covers/1.png'));
      await pumpEventQueue();
    }
    expect(seeds, first, reason: 'the same track again: no new seed');
    api.setNow(_now(1, '/covers/2.png'));
    await pumpEventQueue();
    expect(seeds, first + 1);
    expect(
      theme.light.colorScheme.primary,
      vTheme(
        brightness: Brightness.light,
        seed: const Color(0xFF3366AA),
      ).colorScheme.primary,
    );
  });

  testWidgets(
    'a colourless cover gives the fallback seed, not the previous one',
    (tester) async {
      await tester.runAsync(() async {
        final colourful = await _cover(
          const Color(0xFF2F5D9E),
          const Color(0xFFF6D38B),
        );
        final grey = await _cover(
          const Color(0xFF808080),
          const Color(0xFF202020),
        );
        final theme = ThemeController(systemSeedFor: () async => null);
        await theme.load();
        theme.start();
        Future<void> until(bool Function() done) async {
          for (var i = 0; i < 200 && !done(); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }

        api.setNow(_now(1, colourful));
        await until(() => theme.seed != VPresets.seeds.first);
        final fromCover = theme.seed;
        expect(fromCover, isNot(VPresets.seeds.first));
        api.setNow(_now(2, grey));
        await until(() => theme.seed != fromCover);
        // No System seed in tests: the chosen preset (the first by default).
        expect(theme.seed, VPresets.seeds.first);
      });
    },
  );

  test('theme setters persist then notify', () async {
    final theme = ThemeController(systemSeedFor: () async => null);
    await theme.load();
    final seen = <String?>[];
    theme.addListener(() => seen.add(api.prefs['ui.player_style']));
    await theme.setPlayerStyle(PlayerStyle.wave);
    expect(seen, ['wave']);
    expect(theme.playerStyle, PlayerStyle.wave);
    await theme.setMode(ThemeMode.dark);
    await theme.setPureBlack(true);
    await theme.setPreset(2);
    await theme.setSource(ColorSource.preset);
    expect(api.prefs, containsPair('ui.theme', 'dark'));
    expect(api.prefs, containsPair('ui.pure_black', 'true'));
    expect(api.prefs, containsPair('ui.preset', '2'));
    expect(api.prefs, containsPair('ui.color_source', 'preset'));
    expect(theme.seed, VPresets.seeds[2]);
    expect(theme.dark.colorScheme.surface, const Color(0xFF000000));

    // Read back at the next launch.
    final again = ThemeController(systemSeedFor: () async => null);
    await again.load();
    expect(again.playerStyle, PlayerStyle.wave);
    expect(again.mode, ThemeMode.dark);
    expect(again.seed, VPresets.seeds[2]);
  });
}
