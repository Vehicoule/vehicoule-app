import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../symbols.dart';

enum PlayerView { player, lyrics, queue }

/// Paroles · Lecteur · File (spec UI §5.5, item 5): an M3E FAB menu at the end of the
/// player's bottom row. Its icon is the current view's; it opens upwards on the views,
/// the current one checked. [views] narrows the choice (the immersive view has no
/// « Lecteur »).
class VViewSelector extends StatelessWidget {
  const VViewSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.views = order,
  });

  final PlayerView value;
  final ValueChanged<PlayerView> onChanged;
  final List<PlayerView> views;

  /// Top to bottom in the open menu (File nearest the FAB); the shared axis follows it.
  static const order = [PlayerView.lyrics, PlayerView.player, PlayerView.queue];

  static IconData iconOf(PlayerView v) => switch (v) {
    PlayerView.player => VIcons.musicNote,
    PlayerView.lyrics => VIcons.lyrics,
    PlayerView.queue => VIcons.queue,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String label(PlayerView v) => switch (v) {
      PlayerView.player => l.viewPlayer,
      PlayerView.lyrics => l.viewLyrics,
      PlayerView.queue => l.viewQueue,
    };
    return Semantics(
      label: l.viewMenu(label(value)),
      child: M3EFabMenu(
        // Keyed by the view: the closed FAB shows the new view's icon at once.
        key: ValueKey(value),
        icon: VSymbol(iconOf(value), filled: true),
        closeIcon: const VSymbol(VIcons.close),
        size: M3EFabSize.regular,
        color: M3EFabColor.secondary,
        items: [
          for (final v in views)
            M3EFabMenuItem(
              icon: VSymbol(v == value ? VIcons.check : iconOf(v)),
              label: label(v),
              onPressed: () {
                if (v == value) return;
                VHaptics.selection();
                onChanged(v);
              },
            ),
        ],
      ),
    );
  }
}
