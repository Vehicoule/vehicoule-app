import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../symbols.dart';

enum PlayerView { player, lyrics, queue }

/// Player · Lyrics · Queue: the M3E floating toolbar, whose active action widens with its
/// label (spec UI §5.5). [views] narrows the choice (the immersive view has no "player").
class VViewSelector extends StatelessWidget {
  const VViewSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.views = PlayerView.values,
  });

  final PlayerView value;
  final ValueChanged<PlayerView> onChanged;
  final List<PlayerView> views;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String label(PlayerView v) => switch (v) {
      PlayerView.player => l.viewPlayer,
      PlayerView.lyrics => l.viewLyrics,
      PlayerView.queue => l.viewQueue,
    };
    IconData icon(PlayerView v) => switch (v) {
      PlayerView.player => VIcons.musicNote,
      PlayerView.lyrics => VIcons.lyrics,
      PlayerView.queue => VIcons.queue,
    };
    return M3EToolbar.floating(
      screenOffset: 0,
      activeIndex: views.indexOf(value),
      onActiveIndexChanged: (i) {
        VHaptics.selection();
        onChanged(views[i]);
      },
      actions: [
        for (final v in views)
          M3EToolbarAction(
            icon: icon(v),
            label: label(v),
            semanticLabel: label(v),
            onPressed: () {},
          ),
      ],
    );
  }
}
