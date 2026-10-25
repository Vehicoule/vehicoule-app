import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../bridge/catalog.dart';
import '../../l10n/app_localizations.dart';
import '../haptics.dart';
import '../motion.dart';
import '../symbols.dart';
import '../tokens.dart';
import 'artwork.dart';
import 'controls.dart';
import 'focus_ring.dart';
import 'menu.dart';
import 'now_playing.dart' show vTime;
import 'snack.dart';

/// The one track row (spec UI §5.1): search, album, playlist, queue, history, likes,
/// downloads. 56 high, 16 margin, a 44 artwork (radius 12, round for an artist).
///
/// - [number] (album page) or [leading] (the Top 50 rank) replaces the artwork, same
///   geometry;
/// - playing: the title in `primary` and an equalizer ("now playing");
/// - [offline]: 38 % opacity, and a tap explains instead of playing;
/// - swipe right = [onPlayNext] over a tonal background; swipe left = [onRemove] when the
///   list allows it; long press, right click or ⋮ = [showVMenu];
/// - [wide]: the desktop table (album and duration columns, ▶ and ⋮ on hover): a click is
///   [onTap] (select), a double click [onDoubleTap] (play);
/// - [handleIndex]: a drag handle for a `ReorderableList` (the queue).
///
/// [playing] overrides [NowPlayingScope].
class VTrackRow extends StatefulWidget {
  const VTrackRow({
    super.key,
    required this.track,
    this.number,
    this.leading,
    this.playing,
    this.offline = false,
    this.selected = false,
    this.wide = false,
    this.handleIndex,
    required this.onTap,
    this.onDoubleTap,
    required this.onPlayNext,
    this.onRemove,
    required this.quick,
    required this.groups,
    this.debugSwipe = 0,
  });

  final TrackView track;
  final int? number;
  final Widget? leading;
  final bool? playing;
  final bool offline, selected, wide;
  final int? handleIndex;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback onPlayNext;
  final VoidCallback? onRemove;
  final List<VAction> quick;
  final List<List<VAction>> groups;

  /// Where the row starts, slid open: only for the design gallery's "swiped" state.
  final double debugSwipe;

  @override
  State<VTrackRow> createState() => _VTrackRowState();
}

class _VTrackRowState extends State<VTrackRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dx = AnimationController.unbounded(
    vsync: this,
    value: widget.debugSwipe,
  );
  bool _hover = false, _focus = false, _armed = false;

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  double get _threshold =>
      ((context.size?.width ?? 400) * 0.25).clamp(0.0, VSize.swipe);

  void _drag(DragUpdateDetails d) {
    final max = (context.size?.width ?? 400) * 0.4;
    final next = (_dx.value + d.delta.dx).clamp(
      widget.onRemove == null ? 0.0 : -max,
      max,
    );
    _dx.value = next;
    final armed = next.abs() >= _threshold;
    if (armed != _armed) {
      _armed = armed;
      if (armed) VHaptics.selection();
    }
  }

  void _release(DragEndDetails _) {
    if (_dx.value >= _threshold) widget.onPlayNext();
    if (_dx.value <= -_threshold) widget.onRemove?.call();
    _armed = false;
    if (reduceMotion(context)) {
      _dx.value = 0;
    } else {
      _dx.animateWith(SpringSimulation(VSprings.spatial, _dx.value, 0, 0));
    }
  }

  /// The menu next to its trigger: [at] is ⋮'s rect or the pointer (a zero-size rect);
  /// otherwise (long press, keyboard) beside the row. The row itself lifts in place.
  void _menu([Rect? at]) {
    final box = context.findRenderObject()! as RenderBox;
    final row = box.localToGlobal(Offset.zero) & box.size;
    showVMenu(
      context,
      anchor: at ?? row,
      quick: widget.quick,
      groups: widget.groups,
      origin: IgnorePointer(child: _content(context, lifted: true)),
      originRect: row,
    );
  }

  void _tap() {
    if (widget.offline) {
      showVSnack(context, AppLocalizations.of(context).offlineTrack);
    } else {
      widget.onTap();
    }
  }

  bool get _playing =>
      widget.playing ?? NowPlayingScope.isPlaying(context, widget.track.id);

  Widget _leading(BuildContext context, ThemeData theme) {
    final showPlay = widget.wide && (_hover || _focus) && !_playing;
    final custom = widget.leading;
    final number = widget.number;
    if (custom == null && number == null) {
      return VArtwork(
        itemId: widget.track.id,
        size: VSize.trackArt,
        kind: ArtKind.item,
        playing: _playing,
        selected: widget.selected,
      );
    }
    return SizedBox.square(
      dimension: VSize.trackArt,
      child: Center(
        child: _playing
            ? const VEqualizer(size: VSize.trackArt / 2)
            : showPlay
            ? VSymbol(
                VIcons.play,
                filled: true,
                color: theme.colorScheme.primary,
              )
            : custom ??
                  Text(
                    '$number',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
      ),
    );
  }

  Widget _content(BuildContext context, {bool lifted = false}) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = widget.track;
    final artists = t.artists.map((a) => a.name).join(', ');
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final showMore = !widget.wide || _hover || _focus || lifted;
    final more = Builder(
      builder: (b) => VIconButton(
        icon: VIcons.more,
        label: l.actionMore,
        onPressed: () {
          final box = b.findRenderObject()! as RenderBox;
          _menu(box.localToGlobal(Offset.zero) & box.size);
        },
      ),
    );
    // 56 at rest; taller when the text is (up to 200 %, spec UI §8).
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: VSize.trackRow),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: VSpace.s16,
          end: VSpace.s4,
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: _leading(context, theme)),
            const SizedBox(width: VSpace.s16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _playing ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      if (t.explicit) ...[
                        VSymbol(
                          VIcons.explicit,
                          size: VSize.iconSmall,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: VSpace.s4),
                      ],
                      if (t.downloaded) ...[
                        VSymbol(
                          VIcons.downloadDone,
                          size: VSize.iconSmall,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: VSpace.s4),
                      ],
                      Flexible(
                        child: ExcludeSemantics(
                          child: Text(
                            artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.wide) ...[
              const SizedBox(width: VSpace.s16),
              SizedBox(
                width: VSize.albumColumn,
                child: Text(
                  t.album?.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ),
              SizedBox(
                width: VSize.durationColumn,
                child: Text(
                  t.durationMs == null ? '' : vTime(t.durationMs!),
                  textAlign: TextAlign.end,
                  style: muted,
                ),
              ),
              const SizedBox(width: VSpace.s8),
            ],
            // What plays: the cookie on the artwork, the equalizer here (the
            // shape-language mockup); a numbered row has it in place of its number.
            if (_playing && widget.number == null && widget.leading == null)
              const Padding(
                padding: EdgeInsetsDirectional.only(start: VSpace.s8),
                child: VEqualizer(size: VSize.icon),
              ),
            Visibility.maintain(visible: showMore, child: more),
            if (widget.handleIndex != null)
              ReorderableDragStartListener(
                index: widget.handleIndex!,
                child: Semantics(
                  label: l.actionReorder,
                  child: SizedBox.square(
                    dimension: VSize.menuTarget,
                    child: Center(
                      child: VSymbol(
                        VIcons.dragHandle,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter) {
      (widget.wide ? widget.onDoubleTap ?? _tap : _tap)();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.contextMenu ||
        (k == LogicalKeyboardKey.f10 &&
            HardwareKeyboard.instance.isShiftPressed)) {
      _menu(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = widget.track;
    // One node per row: what it is and its state; ⋮ and the handle stay separate. The
    // swipes have their equivalents as actions (spec UI §8).
    final row = Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      label: [
        t.title,
        t.artists.map((a) => a.name).join(', '),
        if (_playing) l.nowPlaying,
        if (t.explicit) l.explicitLabel,
        if (t.downloaded) l.downloaded,
        if (widget.offline) l.offlineChip,
      ].join(', '),
      onTap: _tap,
      onLongPress: () => _menu(),
      customSemanticsActions: {
        CustomSemanticsAction(label: l.actionPlayNext): widget.onPlayNext,
        if (widget.onRemove != null)
          CustomSemanticsAction(label: l.actionRemove): widget.onRemove!,
      },
      child: Opacity(
        opacity: widget.offline ? 0.38 : 1,
        child: _content(context),
      ),
    );
    return VFocusRing(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VRadius.small),
      ),
      child: Focus(
        onKeyEvent: _key,
        onFocusChange: (f) => setState(() => _focus = f),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _tap,
            onDoubleTap: widget.wide && !widget.offline
                ? widget.onDoubleTap
                : null,
            onLongPress: () => _menu(),
            onSecondaryTapUp: (d) => _menu(
              Rect.fromLTWH(d.globalPosition.dx, d.globalPosition.dy, 0, 0),
            ),
            onHorizontalDragUpdate: _drag,
            onHorizontalDragEnd: _release,
            child: AnimatedBuilder(
              animation: _dx,
              builder: (context, child) => Stack(
                children: [
                  if (_dx.value != 0)
                    Positioned.fill(
                      child: ColoredBox(
                        color: scheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: VSpace.s24,
                          ),
                          child: Row(
                            children: [
                              // Icons only: the row slides less than a label's width. The labels are
                              // the semantic actions above.
                              if (_dx.value > 0)
                                VSymbol(
                                  VIcons.playNext,
                                  color: scheme.onSecondaryContainer,
                                ),
                              const Spacer(),
                              if (_dx.value < 0)
                                VSymbol(
                                  VIcons.delete,
                                  color: scheme.onSecondaryContainer,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Transform.translate(
                    offset: Offset(_dx.value, 0),
                    child: ColoredBox(
                      color: widget.selected
                          ? scheme.secondaryContainer
                          : scheme.surface.withValues(
                              alpha: _dx.value == 0 ? 0 : 1,
                            ),
                      child: child,
                    ),
                  ),
                ],
              ),
              child: row,
            ),
          ),
        ),
      ),
    );
  }
}
