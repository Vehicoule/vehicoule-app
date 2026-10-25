/// The app's only durations, curves, springs and page transitions (spec UI §2.6, §5.6).
/// Screens and shells never write `Duration(` or `Curves.` (guarded by test/design).
library;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

abstract final class VDurations {
  /// Every transition becomes a fade of this length with "reduce motion".
  static const reduced = Duration(milliseconds: 150);
  static const short = M3EMotion.short4;
  static const medium = M3EMotion.medium2;
  static const long = M3EMotion.long2;

  /// The "Undo" window after a stop or a destructive action (spec UI §5.3, §5.8).
  static const undo = Duration(seconds: 5);

  /// How long a plain snackbar stays.
  static const snack = Duration(seconds: 4);

  /// The theme fades to a new seed color on a track change (spec UI §2.2).
  static const themeFade = M3EMotion.medium4;

  /// Search suggestions wait for typing to pause (spec UI §6.2).
  static const debounce = Duration(milliseconds: 150);

  /// One step of ←/→ seeking (spec UI §4.2).
  static const seekStep = Duration(seconds: 10);

  /// Delay between two shelves or cards entering.
  static const stagger = Duration(milliseconds: 40);

  /// One turn of the playing cookie (spec UI §5.5).
  static const spin = Duration(seconds: 20);
}

abstract final class VCurves {
  static const emphasized = M3EMotion.emphasized;
  static const emphasizedDecelerate = M3EMotion.emphasizedDecelerate;
  static const emphasizedAccelerate = M3EMotion.emphasizedAccelerate;
  static const standard = M3EMotion.standard;
  static const linear = M3EMotion.linear;
}

/// M3E springs, from the package tokens.
abstract final class VSprings {
  static final spatial = M3EMotion.expressiveSpatialDefault.toDescription();
  static final spatialFast = M3EMotion.expressiveSpatialFast.toDescription();
  static final effects = M3EMotion.effectsDefault.toDescription();
}

/// "Reduce motion", from the system or the app setting (which sets the same flag).
bool reduceMotion(BuildContext c) =>
    MediaQuery.maybeDisableAnimationsOf(c) ?? false;

/// [d], or zero when motion is reduced: for movement that has no fade equivalent.
Duration vMotion(BuildContext c, Duration d) =>
    reduceMotion(c) ? Duration.zero : d;

enum _Kind { containerTransform, fadeThrough }

class _VPage<T> extends Page<T> {
  const _VPage({
    required super.key,
    required this.child,
    required this.kind,
    this.heroTag,
  });

  final Widget child;
  final _Kind kind;
  final Object? heroTag;

  @override
  Route<T> createRoute(BuildContext context) => _VRoute<T>(this);
}

class _VRoute<T> extends PageRoute<T> {
  _VRoute(_VPage<T> page) : super(settings: page);

  _VPage<T> get _page => settings as _VPage<T>;

  bool get _reduced {
    final c = navigator?.context;
    return c != null && reduceMotion(c);
  }

  @override
  Duration get transitionDuration =>
      _reduced ? VDurations.reduced : VDurations.medium;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> a,
    Animation<double> s,
  ) {
    final tag = _page.heroTag;
    if (tag == null) return _page.child;
    // The flying surface is a sibling under the page, never its ancestor: the page may
    // hold cards that are Heroes themselves.
    return Stack(
      fit: StackFit.expand,
      children: [
        HeroMode(
          enabled: !reduceMotion(context),
          child: Hero(
            tag: tag,
            flightShuttleBuilder: _containerShuttle,
            child: ColoredBox(color: Theme.of(context).colorScheme.surface),
          ),
        ),
        _page.child,
      ],
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> a,
    Animation<double> s,
    Widget child,
  ) {
    if (reduceMotion(context)) return FadeTransition(opacity: a, child: child);
    // Fade through: the old page fades out in the first 35 %, the new one fades and
    // scales in after. A container transform grows the card (the Hero), then fades in.
    final incoming = CurvedAnimation(
      parent: a,
      curve: const Interval(0.35, 1, curve: VCurves.emphasizedDecelerate),
    );
    final outgoing = CurvedAnimation(
      parent: s,
      curve: const Interval(0, 0.35, curve: VCurves.emphasizedAccelerate),
    );
    final page = FadeTransition(
      opacity: incoming,
      child: FadeTransition(opacity: ReverseAnimation(outgoing), child: child),
    );
    if (_page.kind == _Kind.containerTransform) return page;
    return ScaleTransition(
      scale: Tween(begin: 0.92, end: 1.0).animate(incoming),
      child: page,
    );
  }
}

/// A card's surface growing into its page while the Hero flies.
Widget _containerShuttle(
  BuildContext flight,
  Animation<double> a,
  HeroFlightDirection direction,
  BuildContext from,
  BuildContext to,
) {
  final scheme = Theme.of(to).colorScheme;
  return AnimatedBuilder(
    animation: a,
    builder: (context, _) => DecoratedBox(
      decoration: BoxDecoration(
        color: Color.lerp(scheme.surfaceContainer, scheme.surface, a.value),
        borderRadius: BorderRadius.circular(VRadius.medium * (1 - a.value)),
      ),
    ),
  );
}

/// Card or row → its page (album, artist, playlist, category). The source wraps itself
/// in [vContainerSource] with the same [heroTag].
Page<T> vContainerTransformPage<T>({
  required LocalKey key,
  required Widget child,
  required Object heroTag,
}) => _VPage<T>(
  key: key,
  child: child,
  kind: _Kind.containerTransform,
  heroTag: heroTag,
);

/// The card or row a [vContainerTransformPage] grows from.
Widget vContainerSource({required Object heroTag, required Widget child}) =>
    Hero(tag: heroTag, flightShuttleBuilder: _containerShuttle, child: child);

/// A change of destination (bottom bar, rail).
Page<T> vFadeThroughPage<T>({required LocalKey key, required Widget child}) =>
    _VPage<T>(key: key, child: child, kind: _Kind.fadeThrough);

/// Horizontal shared axis: the player's views, the first-launch steps. [key] names the
/// current child; a new key slides it in from the right, or from the left with
/// [reverse] (going back), while the old one leaves the other way.
Widget vSharedAxis({
  required Widget child,
  required Object key,
  bool reverse = false,
}) => _SharedAxis(childKey: key, reverse: reverse, child: child);

class _SharedAxis extends StatelessWidget {
  const _SharedAxis({
    required this.childKey,
    required this.reverse,
    required this.child,
  });

  final Object childKey;
  final bool reverse;
  final Widget child;

  static const _shift = 0.08;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotion(context);
    final current = ValueKey(childKey);
    final dir = reverse ? -1.0 : 1.0;
    return AnimatedSwitcher(
      duration: reduced ? VDurations.reduced : VDurations.medium,
      switchInCurve: VCurves.emphasizedDecelerate,
      switchOutCurve: VCurves.emphasizedAccelerate,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [...previous, ?current],
      ),
      transitionBuilder: (c, a) {
        if (reduced) return FadeTransition(opacity: a, child: c);
        // The incoming child comes from `dir`; the outgoing one (its animation runs
        // backwards) leaves towards `-dir`.
        final from = c.key == current ? dir : -dir;
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: Offset(from * _shift, 0),
              end: Offset.zero,
            ).animate(a),
            child: c,
          ),
        );
      },
      child: KeyedSubtree(key: current, child: child),
    );
  }
}

/// A shelf or card entering, [index] places later than the first. Nothing moves with
/// "reduce motion".
Widget vEntrance(int index, Widget child) =>
    _Entrance(index: index, child: child);

class _Entrance extends StatefulWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  // ponytail: the stagger stops growing after 8 items; later ones enter with the 8th.
  late final int _slot = widget.index.clamp(0, 8);
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: VDurations.medium + VDurations.stagger * _slot,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (_c.isDismissed) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start =
        _slot * VDurations.stagger.inMilliseconds / _c.duration!.inMilliseconds;
    final a = CurvedAnimation(
      parent: _c,
      curve: Interval(start, 1, curve: VCurves.emphasizedDecelerate),
    );
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(a),
        child: widget.child,
      ),
    );
  }
}

/// The mini player → player shared element, driven by the sheet's drag [extent] (0 = the
/// mini player, 1 = the full player), not a Hero: the artwork's rect interpolates from
/// [from] to [to] (both in the enclosing Stack's coordinates) and [builder] draws it at
/// that side. Goes in a Stack.
class VExtentFlight extends StatelessWidget {
  const VExtentFlight({
    super.key,
    required this.extent,
    required this.from,
    required this.to,
    required this.builder,
  });

  final double extent;
  final Rect from, to;
  final Widget Function(BuildContext context, double side) builder;

  @override
  Widget build(BuildContext context) {
    final rect = Rect.lerp(from, to, extent.clamp(0.0, 1.0))!;
    return Positioned.fromRect(
      rect: rect,
      child: builder(context, rect.shortestSide),
    );
  }
}
