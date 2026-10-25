/// Debug builds only: a local source feed, for checks that need sources before the
/// screens exist (the gallery's covers, a real download).
///
/// - `--dart-define=VEHICOULE_DEV_FEED=url` and `--dart-define=VEHICOULE_DEV_FEED_KEY=key`
///   add it (debug cores accept http) and skip the first launch;
/// - `--dart-define=VEHICOULE_DEV_PLAY=query` then plays the tracks found.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/api/app.dart' show finishOnboarding;
import '../bridge/api/catalog.dart' show search;
import '../bridge/api/playback.dart' show play;
import '../bridge/api/plugins.dart' show addFeed, refreshFeeds;
import '../platform/player.dart';

const _url = String.fromEnvironment('VEHICOULE_DEV_FEED');

/// True when a feed was given (and added, or already there).
Future<bool> addDevFeed({String url = _url}) async {
  if (url.isEmpty) return false;
  try {
    await addFeed(
      url: url,
      publicKey: const String.fromEnvironment('VEHICOULE_DEV_FEED_KEY'),
    );
  } on Object catch (e) {
    debugPrint('dev feed: $e');
  }
  return true;
}

/// Skips the first launch (Task 7 builds it); then, in the background, adds the feed,
/// refreshes it and plays `VEHICOULE_DEV_PLAY`'s tracks if given.
///
/// The feed's first install takes seconds (the plugins are fetched and compiled): the
/// app must not wait for it. Android freezes a cached process (Android 14's freezer),
/// so an app sent to the background during that install would show nothing until it
/// came back to the foreground.
Future<void> startDevFeed(PlayerAdapter player, {String url = _url}) async {
  if (url.isEmpty) return;
  await finishOnboarding(telemetry: false);
  unawaited(_play(player, url));
}

Future<void> _play(PlayerAdapter player, String url) async {
  try {
    await addDevFeed(url: url);
    await refreshFeeds();
    const query = String.fromEnvironment('VEHICOULE_DEV_PLAY');
    if (query.isEmpty) return;
    final found = await search(query: query);
    if (found.tracks.isEmpty) return;
    player.markTap();
    await play(items: [for (final t in found.tracks) t.id], start: 0);
  } on Object catch (e) {
    debugPrint('dev feed: $e');
  }
}
