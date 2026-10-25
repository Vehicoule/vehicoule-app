import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../symbols.dart';
import '../tokens.dart';

enum PlayerView { player, lyrics, queue }

/// Paroles · Lecteur · File, centred at the bottom of the player (spec UI §5.5, item 7):
/// an M3E connected button group, Lecteur in the middle. The active button is filled,
/// with its icon and label; the others show their icon only. [views] narrows the choice
/// (the immersive view has no « Lecteur »).
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

  /// Left to right: the shared axis follows this order.
  static const order = [PlayerView.lyrics, PlayerView.player, PlayerView.queue];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
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
    // A connected group given a width shares it equally; given none (a Row), each
    // button takes its own: the active one, with its label, is wider.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        M3EButtonGroup(
          type: M3EButtonGroupType.connected,
          style: M3EButtonStyle.tonal,
          size: M3EButtonSize.md,
          selectionRequired: true,
          selectedIndex: views.indexOf(value),
          onSelectedIndexChanged: (i) {
            if (i == null || views[i] == value) return;
            VHaptics.selection();
            onChanged(views[i]);
          },
          decoration: M3EButtonDecoration.styleFrom(
            selectedBackgroundColor: scheme.primary,
            selectedForegroundColor: scheme.onPrimary,
          ),
          actions: [
            for (final v in views)
              M3EButtonGroupAction(
                minWidth: VSize.selectorSegment,
                icon: VSymbol(icon(v), filled: v == value),
                selectedLabel: Text(label(v)),
                semanticLabel: label(v),
              ),
          ],
        ),
      ],
    );
  }
}
