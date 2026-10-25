// The desktop « en lecture » pane (spec UI §4.2): the medium player in a standard side
// sheet, with the volume; folded, the 76 px strip, the rail's mirror and the desktop's
// only compact player.
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../design/design.dart';
import '../features/music/now_playing/now_playing_sheet.dart';

class NowPlayingPane extends StatelessWidget {
  const NowPlayingPane({
    super.key,
    required this.open,
    required this.onToggle,
    required this.onImmersive,
  });

  final bool open;
  final VoidCallback onToggle, onImmersive;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback;
    final player = scope.player;
    return ListenableBuilder(
      listenable: Listenable.merge([playback, scope.theme]),
      builder: (context, _) {
        final data = playback.data(coverTop: scope.theme.coverTop);
        if (data == null) return const SizedBox.shrink();
        Widget volume({bool vertical = false}) => ValueListenableBuilder(
          valueListenable: player.volume,
          builder: (context, v, _) => VVolume(
            value: v,
            vertical: vertical,
            onChanged: player.setVolume,
          ),
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VSideSheet(
              open: open,
              child: VNowPlaying(
                data: data,
                position: player.position,
                size: PlayerSize.medium,
                style: scope.theme.playerStyle,
                view: playback.view,
                onView: (v) => playback.view = v,
                actions: playback.actions(onCollapse: onToggle),
                lyrics: lyricsView,
                queue: queueView,
                onImmersive: onImmersive,
                volume: volume(),
              ),
            ),
            if (!open)
              SizedBox(
                width: VSize.strip,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: VSpace.s16),
                  child: VNowPlaying(
                    data: data,
                    position: player.position,
                    size: PlayerSize.compact,
                    style: scope.theme.playerStyle,
                    view: PlayerView.player,
                    onView: (_) {},
                    actions: playback.actions(onOpen: onToggle),
                    lyrics: lyricsView,
                    queue: queueView,
                    axis: Axis.vertical,
                    volume: SizedBox(
                      height: VSize.stripVolume,
                      child: volume(vertical: true),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
