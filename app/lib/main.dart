import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'bridge/api/app.dart' show initApp, start;
import 'bridge/api/settings.dart';
import 'bridge/api/system.dart' show checkUpdates;
import 'bridge/frb_generated.dart';
import 'debug/dev_feed.dart';
import 'debug/fake_api.dart';
import 'design/design.dart';
import 'now_playing_model.dart';
import 'platform/downloads_service.dart';
import 'platform/errors.dart';
import 'platform/links.dart';
import 'platform/lock_screen.dart';
import 'platform/network.dart';
import 'platform/paths.dart';
import 'platform/player.dart';
import 'router.dart';
import 'shell_desktop/title_bar.dart';
import 'theme_controller.dart';

/// Debug only: `--dart-define=VEHICOULE_FAKE=true` runs on the simulated core.
const _fake = kDebugMode && bool.fromEnvironment('VEHICOULE_FAKE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 1. The core, the error hooks, the links hub (before any route listens), the system
  //    media session, the window.
  if (_fake) {
    RustLib.initMock(api: FakeApi());
  } else {
    await RustLib.init();
  }
  installErrorHooks();
  startLinks();
  await initApp(cfg: await appConfig());
  final player = PlayerAdapter(MediaKitBackend())..start();
  await initLockScreen(player);
  if (hasTitleBar) await WindowKeeper.setUp();
  vRegisterFontLicenses();

  // 2. Every subscription, before the core starts.
  final network = Network()..start();
  DownloadsService().start();
  final theme = ThemeController();
  await theme.load();
  theme.start();
  final playback = NowPlayingModel(player)..start();
  await _keepVolume(player);

  // 3. The core: the queue comes back and downloads resume on streams already heard.
  await start();
  if (kDebugMode) unawaited(startDevFeed(player));

  // 4. The app.
  runApp(
    VehicouleApp(
      player: player,
      theme: theme,
      online: network.online,
      playback: playback,
      splash: hasTitleBar,
    ),
  );

  // 5. Never in the way: an update shows through Notice.updateAvailable only.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => checkUpdates(force: false).ignore(),
  );
}

/// The volume: read from `ui.volume`, written back after each change settles.
Future<void> _keepVolume(PlayerAdapter player) async {
  const key = 'ui.volume';
  final saved = double.tryParse(await uiPref(key: key) ?? '');
  if (saved != null) await player.setVolume(saved);
  Timer? save;
  player.volume.addListener(() {
    save?.cancel();
    save = Timer(
      VDurations.debounce,
      () => setUiPref(key: key, value: '${player.volume.value}').ignore(),
    );
  });
}
