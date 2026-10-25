import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../bridge/queue.dart';
import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../motion.dart';
import '../symbols.dart';
import '../tokens.dart';
import 'kit.dart';
import 'loading.dart';
import 'menu.dart';

enum VIconStyle { standard, filled, tonal, outlined }

/// An icon-only button with its spoken label (and tooltip on desktop). [selected] makes
/// it a toggle (the icon fills, the shape morphs).
class VIconButton extends StatelessWidget {
  const VIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected,
    this.style = VIconStyle.standard,
    this.glyphFilled,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Null: not a toggle.
  final bool? selected;
  final VIconStyle style;

  /// The glyph's FILL; by default filled when selected or in a filled button.
  final bool? glyphFilled;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onPressed != null,
    toggled: selected,
    label: label,
    onTap: onPressed,
    excludeSemantics: true,
    child: M3EIconButton(
      icon: VSymbol(
        icon,
        filled: glyphFilled ?? (selected ?? style == VIconStyle.filled),
      ),
      onPressed: onPressed,
      tooltip: label,
      variant: switch (style) {
        VIconStyle.standard => M3EIconButtonVariant.standard,
        VIconStyle.filled => M3EIconButtonVariant.filled,
        VIconStyle.tonal => M3EIconButtonVariant.tonal,
        VIconStyle.outlined => M3EIconButtonVariant.outlined,
      },
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
    final scheme = Theme.of(context).colorScheme;
    return M3EButtonGroup(
      type: M3EButtonGroupType.connected,
      style: M3EButtonStyle.tonal,
      // Selected toggles are primary, like ⏯ and the selector (the mockup).
      decoration: M3EButtonDecoration.styleFrom(
        selectedBackgroundColor: scheme.primary,
        selectedForegroundColor: scheme.onPrimary,
      ),
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

  // M3E's segments center themselves in all the height they are offered, and the menu
  // anchors under that: held to its own height, the menu opens under the chevron.
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: M3ESplitButton<int>(
      label: label,
      leadingIcon: icon,
      onPressed: onPressed,
      trailingTooltip: AppLocalizations.of(context).actionMore,
      items: [
        for (final (i, a) in items.indexed)
          M3ESplitButtonItem(value: i, child: a.label),
      ],
      onSelected: (i) => items[i].onSelected(),
    ),
  );
}

/// A collection's main action (spec UI §5.4): the split button « Lire | ▾ » or
/// « Aléatoire | ▾ » while its header shows, the FAB of the same action once the list
/// has scrolled ([collapsed], set by the screen).
class VSplitFab extends StatelessWidget {
  const VSplitFab({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.items,
    required this.collapsed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final List<VAction> items;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotion(context);
    return AnimatedSwitcher(
      duration: reduced ? VDurations.reduced : VDurations.medium,
      switchInCurve: VCurves.emphasizedDecelerate,
      switchOutCurve: VCurves.emphasizedAccelerate,
      transitionBuilder: (child, a) => reduced
          ? FadeTransition(opacity: a, child: child)
          : ScaleTransition(
              scale: a,
              alignment: Alignment.bottomRight,
              child: FadeTransition(opacity: a, child: child),
            ),
      child: collapsed
          ? VFab(
              key: const ValueKey('fab'),
              icon: icon,
              label: label,
              onPressed: onPressed,
            )
          : VSplitButton(
              key: const ValueKey('split'),
              label: label,
              icon: icon,
              onPressed: onPressed,
              items: items,
            ),
    );
  }
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

/// Shuffle · ⏮ · ⏯ · ⏭ · repeat, an M3E button group whose widths morph on press. ⏯ is
/// the one emphasized action (filled, twice as wide); it becomes the loading indicator
/// while [loading]. All five always fit the width they get.
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
    this.tall = false,
  });

  final bool playing, loading, shuffle;
  final Repeat repeat;
  final VoidCallback onPlayPause, onNext, onPrevious, onShuffle, onRepeat;

  /// Large controls (a phone held upright): 72 high, the mockup's proportions.
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
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
    return LayoutBuilder(
      builder: (context, box) {
        // Six units (⏯ takes two) and four gaps.
        final room = box.maxWidth.isFinite
            ? box.maxWidth
            : 6 * VSize.controlMax;
        final unit = ((room - 4 * VSpace.s8) / 6).clamp(
          VSize.menuTarget * 0.75,
          VSize.controlMax,
        );
        final big = unit >= VSize.menuTarget;
        final play = loading
            ? VLoading(size: big ? VSize.playIcon : VSize.icon)
            : VPlayPauseIcon(
                playing: playing,
                size: tall && big
                    ? VSize.playIcon + VSpace.s8
                    : big
                    ? VSize.playIcon
                    : VSize.icon,
              );
        M3EButtonGroupAction side(Widget icon, String label) =>
            M3EButtonGroupAction(
              icon: icon,
              semanticLabel: label,
              minWidth: unit,
            );
        // Shuffle and repeat are M3 standard icon toggles: no container, the icon in
        // onSurfaceVariant, in primary with a filled glyph when on. ⏯ alone is the
        // filled primary, so it dominates.
        final clear = scheme.surface.withValues(alpha: 0);
        final quiet = M3EButtonDecoration.styleFrom(
          backgroundColor: clear,
          selectedBackgroundColor: clear,
          foregroundColor: scheme.onSurfaceVariant,
          selectedForegroundColor: scheme.primary,
        );
        M3EButtonGroupAction toggle(Widget icon, String label) =>
            M3EButtonGroupAction(
              icon: icon,
              semanticLabel: label,
              minWidth: unit,
              decoration: quiet,
            );
        return M3EButtonGroup(
          size: tall && big
              ? M3EButtonSize.custom(
                  height: VSize.controlTall,
                  iconSize: VSize.playIcon - VSpace.s4,
                )
              : big
              ? M3EButtonSize.md
              : M3EButtonSize.sm,
          style: M3EButtonStyle.tonal,
          spacing: VSpace.s8,
          multiSelect: true,
          selectedIndices: on,
          onSelectedIndicesChanged: (next) {
            for (final i in next.difference(on).union(on.difference(next))) {
              calls[i]();
            }
          },
          actions: [
            toggle(VSymbol(VIcons.shuffle, filled: shuffle), l.actionShuffle),
            side(VSymbol(VIcons.skipPrevious, filled: true), l.actionPrevious),
            M3EButtonGroupAction(
              icon: play,
              selectedIcon: play,
              minWidth: 2 * unit,
              semanticLabel: _playLabel(l, playing: playing, loading: loading),
              decoration: M3EButtonDecoration.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                selectedBackgroundColor: scheme.primary,
                selectedForegroundColor: scheme.onPrimary,
              ),
            ),
            side(VSymbol(VIcons.skipNext, filled: true), l.actionNext),
            toggle(
              VSymbol(
                repeat == Repeat.one ? VIcons.repeatOne : VIcons.repeat,
                filled: repeat != Repeat.off,
              ),
              l.actionRepeat,
            ),
          ],
        );
      },
    );
  }
}

/// The mini player's rounded-square ⏯ FAB (spec UI §5.3): play ↔ pause morphing, and the
/// M3E loading indicator inside the same container while loading.
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
        color: M3EFabColor.primary,
        onPressed: press,
        icon: loading
            ? const VLoading(size: VSize.playIcon, onContainer: true)
            : VPlayPauseIcon(playing: playing),
      ),
    );
  }
}

/// The volume (spec UI §4.2): an M3E slider with the speaker inside its track; upright
/// in the desktop strip ([vertical]).
class VVolume extends StatelessWidget {
  const VVolume({
    super.key,
    required this.value,
    required this.onChanged,
    this.vertical = false,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final slider = M3ESlider(
      value: value,
      onChanged: onChanged,
      size: vSliderSize(VSize.volumeTrack),
      semanticLabel: AppLocalizations.of(context).volumeLabel,
      // Upright whichever way the slider runs.
      icon: RotatedBox(
        quarterTurns: vertical ? 1 : 0,
        child: const VSymbol(VIcons.volume, filled: true),
      ),
      iconPosition: M3ESliderIconPosition.start,
    );
    return vertical ? RotatedBox(quarterTurns: 3, child: slider) : slider;
  }
}

/// A plain M3E slider with its spoken label (a sheet's extent in the gallery, settings).
class VSlider extends StatelessWidget {
  const VSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => M3ESlider(
    value: value,
    onChanged: onChanged,
    size: vSliderSize(VSize.sliderTrack),
    semanticLabel: label,
  );
}

/// The M3E slider size whose track is [track] (a token of [VSize]).
M3ESliderSize vSliderSize(double track) =>
    M3ESliderSize.values.firstWhere((s) => s.trackHeight == track);
