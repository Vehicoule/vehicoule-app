/// What every screen may reach without a global: the player, the theme, the network,
/// and what plays.
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'design/design.dart';
import 'now_playing_model.dart';
import 'platform/player.dart';
import 'theme_controller.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.player,
    required this.theme,
    required this.online,
    required this.playback,
    required this.miniPlayerRect,
    required super.child,
  });

  final PlayerAdapter player;
  final ThemeController theme;
  final ValueListenable<bool> online;

  /// What plays (the shells' players, [NowPlayingScope]).
  final NowPlayingModel playback;

  /// The mini player's toolbar (or the desktop strip, or pane) in global coordinates,
  /// written by the shell after each layout: what the video window docks to
  /// (addendum §5.2). Null while there is none.
  final ValueNotifier<Rect?> miniPlayerRect;

  static AppScope of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) =>
      old.player != player ||
      old.theme != theme ||
      old.online != online ||
      old.playback != playback ||
      old.miniPlayerRect != miniPlayerRect;
}

/// Under a destination's app bar: « Hors ligne · … » while offline (spec UI §6.9).
class OfflineChipSliver extends StatelessWidget {
  const OfflineChipSliver({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: AppScope.of(context).online,
    builder: (context, online, _) => SliverToBoxAdapter(
      child: online
          ? const SizedBox.shrink()
          : Padding(
              padding: EdgeInsets.symmetric(
                horizontal: VSpace.margin(
                  windowClassOf(MediaQuery.sizeOf(context).width),
                ),
                vertical: VSpace.s8,
              ),
              child: const Align(
                alignment: AlignmentDirectional.centerStart,
                child: VOfflineChip(),
              ),
            ),
    ),
  );
}

/// The layer between the shell's players (mini player, strip, pane) and what floats over
/// them (sheets, dialogs, snackbars): the floating video window lives here (addendum §5.2,
/// §11.7). Nothing is drawn in it in v1.
class VideoLayer extends StatelessWidget {
  const VideoLayer({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
