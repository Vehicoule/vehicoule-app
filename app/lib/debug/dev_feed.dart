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

/// True when a feed was given (and added, or already there).
Future<bool> addDevFeed() async {
  const url = String.fromEnvironment('VEHICOULE_DEV_FEED');
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

/// Adds the feed and skips the first launch (Task 7 builds it); then, in the
/// background, refreshes the feed and plays `VEHICOULE_DEV_PLAY`'s tracks if given.
Future<void> startDevFeed(PlayerAdapter player) async {
  if (!await addDevFeed()) return;
  await finishOnboarding(telemetry: false);
  unawaited(_play(player));
}

Future<void> _play(PlayerAdapter player) async {
  try {
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
