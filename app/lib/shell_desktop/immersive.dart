// The immersive view (spec UI §4.2): the large player over the whole window, the artwork
// at the left, Paroles or File at the right, the controls below. ⤢, ⌘⇧F; Esc leaves.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../app_scope.dart';
import '../design/design.dart';
import '../features/music/now_playing/now_playing_sheet.dart';
import 'title_bar.dart' show hasTitleBar;

class ImmersivePlayer extends StatefulWidget {
  const ImmersivePlayer({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  State<ImmersivePlayer> createState() => _ImmersivePlayerState();
}

class _ImmersivePlayerState extends State<ImmersivePlayer> {
  /// Takes the keyboard focus from the shell, so Esc reaches the player's own shortcut.
  final _focus = FocusNode(debugLabel: 'immersive');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final playback = scope.playback;
    return ColoredBox(
      color: vScreenSurface(Theme.of(context).colorScheme),
      child: Column(
        children: [
          // The window still moves by its top, under the system's buttons.
          if (hasTitleBar)
            const SizedBox(
              height: VSize.titleBar,
              child: DragToMoveArea(child: SizedBox.expand()),
            ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([playback, scope.theme]),
              builder: (context, _) {
                final data = playback.data(coverTop: scope.theme.coverTop);
                if (data == null) return const SizedBox.shrink();
                return CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape):
                        widget.onExit,
                  },
                  child: Focus(
                    focusNode: _focus,
                    child: VNowPlaying(
                      data: data,
                      position: scope.player.position,
                      size: PlayerSize.large,
                      style: scope.theme.playerStyle,
                      // No « Lecteur » here: the artwork is always shown.
                      view: playback.view == PlayerView.player
                          ? PlayerView.lyrics
                          : playback.view,
                      onView: (v) => playback.view = v,
                      actions: playback.actions(),
                      lyrics: lyricsView,
                      queue: queueView,
                      onImmersive: widget.onExit,
                      immersive: true,
                      wide: true,
                      volume: ValueListenableBuilder(
                        valueListenable: scope.player.volume,
                        builder: (context, v, _) => VVolume(
                          value: v,
                          onChanged: scope.player.setVolume,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
