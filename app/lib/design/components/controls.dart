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

enum VIconStyle { standard, filled, tonal, outlined }

/// M3E icon button sizes: 40 (the default) and 56 (the desktop strip's ⏯).
enum VIconSize { small, medium }

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
    this.size = VIconSize.small,
    this.glyph,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Null: not a toggle.
  final bool? selected;
  final VIconStyle style;
  final VIconSize size;

  /// The glyph's FILL; by default filled when selected or in a filled button.
  final bool? glyphFilled;

  /// Drawn instead of [icon] (the download state, with its progress).
  final Widget? glyph;

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
      icon:
          glyph ??
          VSymbol(
            icon,
            filled: glyphFilled ?? (selected ?? style == VIconStyle.filled),
          ),
      onPressed: onPressed,
      tooltip: label,
      size: switch (size) {
        VIconSize.small => M3EIconButtonSize.sm,
        VIconSize.medium => M3EIconButtonSize.md,
      },
      // A square-ish container, like ⏯ in the player's group (the strip's ⏯).
      shape: size == VIconSize.medium
          ? M3EIconButtonShapeVariant.square
          : M3EIconButtonShapeVariant.round,
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
      // Menu entries lead with their action's icon, as M3's menus do.
      items: null,
      m3eMenuBuilder: (_) => [
        for (final (i, a) in items.indexed)
          M3EMenuSelectable(label: a.label, value: i, leading: Icon(a.icon)),
      ],
      onSelected: (i) => items[i].onSelected(),
    ),
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

/// Shuffle · ⏮ · ⏯ · ⏭ · repeat across the whole column (spec UI §5.5): a large M3E
/// button group whose widths morph on press, the player's main action and the biggest
/// thing in it. ⏯ is filled and the widest, ⏮ ⏭ tonal, shuffle and repeat toggles at the
/// ends, all at least [VSize.control] high. ⏯ becomes the loading indicator while
/// [loading].
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

  /// A phone held upright: the controls are taller.
  final bool tall;

  /// The group's width in units: ⏯ 1.5, ⏮ and ⏭ 1.25 each, the toggles 1 each (at
  /// least 48 on a 360 dp phone and in the desktop pane).
  static const _units = 6.0;

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
        final room = box.maxWidth.isFinite
            ? box.maxWidth
            : _units * VSize.controlMax;
        final unit = (room - 4 * VSpace.s8) / _units;
        final height = tall ? VSize.controlTall : VSize.control;
        final play = loading
            ? const VLoading(size: VSize.playIcon, onContainer: true)
            : VPlayPauseIcon(playing: playing, size: VSize.playIcon);
        // The toggles: their own container (M3E toggle buttons); on, they take the
        // secondary colour, never ⏯'s primary.
        final toggle = M3EButtonDecoration.styleFrom(
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundColor: scheme.onSurfaceVariant,
          selectedBackgroundColor: scheme.secondary,
          selectedForegroundColor: scheme.onSecondary,
        );
        M3EButtonGroupAction end(Widget icon, String label) =>
            M3EButtonGroupAction(
              icon: icon,
              semanticLabel: label,
              minWidth: unit,
              decoration: toggle,
            );
        M3EButtonGroupAction skip(Widget icon, String label) =>
            M3EButtonGroupAction(
              icon: icon,
              semanticLabel: label,
              minWidth: 1.25 * unit,
            );
        return M3EButtonGroup(
          size: M3EButtonSize.custom(height: height, iconSize: VSize.icon),
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
            end(VSymbol(VIcons.shuffle, filled: shuffle), l.actionShuffle),
            skip(VSymbol(VIcons.skipPrevious, filled: true), l.actionPrevious),
            M3EButtonGroupAction(
              icon: play,
              selectedIcon: play,
              minWidth: 1.5 * unit,
              semanticLabel: _playLabel(l, playing: playing, loading: loading),
              decoration: M3EButtonDecoration.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                selectedBackgroundColor: scheme.primary,
                selectedForegroundColor: scheme.onPrimary,
              ),
            ),
            skip(VSymbol(VIcons.skipNext, filled: true), l.actionNext),
            end(
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

/// The volume (spec UI §4.2, §5.5): an M3E slider with its thick track and the speaker
/// inside it, its handle inside the component; upright in the desktop strip
/// ([vertical]). The player gives it 240 dp at most, the strip 120.
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
    // M3E centres the handle on the track's end: at 0 or 100 % half of it would stick
    // out past the component (and into the pane's margin). Inset by that half.
    final half = M3ETheme.of(context).sliderTheme.handleWidth / 2;
    final inset = Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: half),
      child: slider,
    );
    // Upright: it grows from the bottom, the speaker at the bottom.
    return vertical ? RotatedBox(quarterTurns: 3, child: inset) : inset;
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
