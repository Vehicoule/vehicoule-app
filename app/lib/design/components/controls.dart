import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../bridge/queue.dart';
import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../motion.dart';
import '../symbols.dart';
import '../tokens.dart';
import 'loading.dart';
import 'menu.dart';

/// An icon-only button with its spoken label (and tooltip on desktop).
class VIconButton extends StatelessWidget {
  const VIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  /// A filled container (tonal), for the one prominent icon of a block.
  final bool filled;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onPressed != null,
    toggled: selected ? true : null,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: M3EIconButton(
      icon: VSymbol(icon, filled: selected),
      onPressed: onPressed,
      tooltip: label,
      variant: filled
          ? M3EIconButtonVariant.tonal
          : M3EIconButtonVariant.standard,
      isSelected: selected,
    ),
  );
}

enum VButtonStyle { filled, tonal, outlined, text }

/// A text button, in one of the M3 emphasis levels.
class VButton extends StatelessWidget {
  const VButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = VButtonStyle.filled,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final VButtonStyle style;

  @override
  Widget build(BuildContext context) => M3EButton(
    onPressed: onPressed,
    icon: icon == null ? null : VSymbol(icon!),
    label: Text(label),
    style: switch (style) {
      VButtonStyle.filled => M3EButtonStyle.filled,
      VButtonStyle.tonal => M3EButtonStyle.tonal,
      VButtonStyle.outlined => M3EButtonStyle.outlined,
      VButtonStyle.text => M3EButtonStyle.text,
    },
  );
}

/// Toggles and actions as one connected button group (the player's like / playlist /
/// download, the menu's quick row). [VAction.selected] fills the toggles.
class VConnectedGroup extends StatelessWidget {
  const VConnectedGroup({
    super.key,
    required this.actions,
    this.autofocusFirst = false,
  });

  final List<VAction> actions;

  /// The first action takes focus (a menu whose quick row is all it has).
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    final on = {
      for (final (i, a) in actions.indexed)
        if (a.selected) i,
    };
    return M3EButtonGroup(
      type: M3EButtonGroupType.connected,
      style: M3EButtonStyle.tonal,
      multiSelect: true,
      selectedIndices: on,
      onSelectedIndicesChanged: (next) {
        for (final i in next.difference(on).union(on.difference(next))) {
          actions[i].onSelected();
        }
      },
      actions: [
        for (final (i, a) in actions.indexed)
          M3EButtonGroupAction(
            autofocus: autofocusFirst && i == 0,
            icon: a.leading ?? VSymbol(a.icon),
            selectedIcon: a.leading ?? VSymbol(a.icon, filled: true),
            semanticLabel: a.label,
          ),
      ],
    );
  }
}

/// "Play | ▾": the main action and its variants (shuffle, play next, add to queue).
class VSplitButton extends StatelessWidget {
  const VSplitButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.items,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final List<VAction> items;

  @override
  Widget build(BuildContext context) => M3ESplitButton<int>(
    label: label,
    leadingIcon: icon,
    onPressed: onPressed,
    trailingTooltip: AppLocalizations.of(context).actionMore,
    items: [
      for (final (i, a) in items.indexed)
        M3ESplitButtonItem(value: i, child: a.label),
    ],
    onSelected: (i) => items[i].onSelected(),
  );
}

/// Play ↔ pause, morphing.
class VPlayPauseIcon extends StatefulWidget {
  const VPlayPauseIcon({super.key, required this.playing, this.size});

  final bool playing;
  final double? size;

  @override
  State<VPlayPauseIcon> createState() => _VPlayPauseIconState();
}

class _VPlayPauseIconState extends State<VPlayPauseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: VDurations.short,
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(VPlayPauseIcon old) {
    super.didUpdateWidget(old);
    final target = widget.playing ? 1.0 : 0.0;
    if (reduceMotion(context)) {
      _c.value = target;
    } else {
      _c.animateTo(target, curve: VCurves.emphasized);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedIcon(
    icon: AnimatedIcons.play_pause,
    progress: _c,
    size: widget.size,
  );
}

String _playLabel(
  AppLocalizations l, {
  required bool playing,
  required bool loading,
}) => loading ? l.loading : (playing ? l.actionPause : l.actionPlay);

/// Shuffle · ⏮ · ⏯ · ⏭ · repeat, an M3E button group whose widths morph on press.
/// ⏯ becomes the loading indicator while [loading].
class VControls extends StatelessWidget {
  const VControls({
    super.key,
    required this.playing,
    required this.loading,
    required this.shuffle,
    required this.repeat,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onShuffle,
    required this.onRepeat,
    this.compact = false,
  });

  final bool playing, loading, shuffle;
  final Repeat repeat;
  final VoidCallback onPlayPause, onNext, onPrevious, onShuffle, onRepeat;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final size = compact ? M3EButtonSize.sm : M3EButtonSize.md;
    final on = {if (shuffle) 0, if (playing) 2, if (repeat != Repeat.off) 4};
    final calls = [
      onShuffle,
      onPrevious,
      () {
        VHaptics.light();
        onPlayPause();
      },
      onNext,
      onRepeat,
    ];
    final play = loading
        ? const VLoading(size: VSize.playIcon)
        : VPlayPauseIcon(playing: playing);
    return M3EButtonGroup(
      size: size,
      style: M3EButtonStyle.tonal,
      multiSelect: true,
      selectedIndices: on,
      onSelectedIndicesChanged: (next) {
        for (final i in next.difference(on).union(on.difference(next))) {
          calls[i]();
        }
      },
      actions: [
        M3EButtonGroupAction(
          icon: VSymbol(VIcons.shuffle),
          semanticLabel: l.actionShuffle,
        ),
        M3EButtonGroupAction(
          icon: VSymbol(VIcons.skipPrevious, filled: true),
          semanticLabel: l.actionPrevious,
        ),
        M3EButtonGroupAction(
          icon: play,
          selectedIcon: play,
          semanticLabel: _playLabel(l, playing: playing, loading: loading),
        ),
        M3EButtonGroupAction(
          icon: VSymbol(VIcons.skipNext, filled: true),
          semanticLabel: l.actionNext,
        ),
        M3EButtonGroupAction(
          icon: VSymbol(
            repeat == Repeat.one ? VIcons.repeatOne : VIcons.repeat,
          ),
          semanticLabel: l.actionRepeat,
        ),
      ],
    );
  }
}

/// The mini player's square ⏯ FAB (spec UI §5.3): play ↔ pause, the loading indicator
/// while loading.
class VPlayPauseFab extends StatelessWidget {
  const VPlayPauseFab({
    super.key,
    required this.playing,
    required this.loading,
    required this.onPressed,
  });

  final bool playing, loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    void press() {
      VHaptics.light();
      onPressed();
    }

    return Semantics(
      button: true,
      label: _playLabel(
        AppLocalizations.of(context),
        playing: playing,
        loading: loading,
      ),
      onTap: press,
      excludeSemantics: true,
      child: M3EFab(
        size: M3EFabSize.regular,
        onPressed: press,
        icon: loading
            ? const VLoading(size: VSize.playIcon)
            : VPlayPauseIcon(playing: playing),
      ),
    );
  }
}
