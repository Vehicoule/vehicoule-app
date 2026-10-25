// The mini player (spec UI §5.3): the compact player; its toolbar, ⏯, gestures, haptics
// and menu are design/'s. The shell gives it what plays and its actions.
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../design/design.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.extent,
    required this.onArtworkRect,
    required this.onOpen,
  });

  /// The player sheet's extent: the disc hides while the sheet's flight draws it.
  final ValueListenable<double> extent;
  final ValueChanged<Rect> onArtworkRect;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback;
    return ListenableBuilder(
      listenable: Listenable.merge([playback, scope.theme, extent]),
      builder: (context, _) {
        final data = playback.data(coverTop: scope.theme.coverTop);
        if (data == null) return const SizedBox.shrink();
        return VNowPlaying(
          data: data,
          position: scope.player.position,
          size: PlayerSize.compact,
          style: scope.theme.playerStyle,
          view: PlayerView.player,
          onView: (_) {},
          actions: playback.actions(
            onOpen: onOpen,
            onStop: () => playback.stop(context),
          ),
          lyrics: _none,
          queue: _none,
          artworkVisible: extent.value == 0,
          onArtworkRect: onArtworkRect,
        );
      },
    );
  }

  static Widget _none(BuildContext _) => const SizedBox.shrink();
}
