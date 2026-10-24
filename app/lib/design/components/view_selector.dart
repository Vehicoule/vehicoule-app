import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../motion.dart';
import '../symbols.dart';
import '../tokens.dart';

enum PlayerView { player, lyrics, queue }

/// Player · Lyrics · Queue: a floating segmented toolbar; the active view widens with its
/// label (spec UI §5.5).
class VViewSelector extends StatelessWidget {
  const VViewSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PlayerView value;
  final ValueChanged<PlayerView> onChanged;

  static Key segmentKey(PlayerView v) => ValueKey('selector.$v');

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // AnimatedSize can't run at zero duration: with reduce motion the width just changes.
    Widget sized(Key key, Widget child) => reduceMotion(context)
        ? KeyedSubtree(key: key, child: child)
        : AnimatedSize(
            key: key,
            duration: VDurations.short,
            curve: VCurves.emphasized,
            child: child,
          );
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.all(VSpace.s8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (v, icon, label) in [
              (PlayerView.player, VIcons.musicNote, l.viewPlayer),
              (PlayerView.lyrics, VIcons.lyrics, l.viewLyrics),
              (PlayerView.queue, VIcons.queue, l.viewQueue),
            ])
              sized(
                segmentKey(v),
                Semantics(
                  selected: v == value,
                  child: M3EButton(
                    style: v == value
                        ? M3EButtonStyle.filled
                        : M3EButtonStyle.text,
                    icon: VSymbol(icon, filled: v == value),
                    label: v == value ? Text(label) : null,
                    semanticLabel: label,
                    onPressed: () {
                      if (v == value) return;
                      VHaptics.selection();
                      onChanged(v);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
