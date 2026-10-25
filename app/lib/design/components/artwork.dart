import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/physics.dart';

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart'
    hide CornerRounding, RoundedPolygon;

import '../../bridge/api/catalog.dart' as core;
import '../../l10n/app_localizations.dart';
import '../motion.dart';
import '../symbols.dart';
import '../tokens.dart';
import 'ring.dart';
import 'wave_progress.dart';

/// Turns an item id into a picture at [px] physical pixels. One seam: the app uses the
/// core's `artworkFile` cache; the gallery and tests provide generated artwork.
typedef ArtworkSource = Future<ImageProvider?> Function(String itemId, int px);

class ArtworkResolver extends InheritedWidget {
  const ArtworkResolver({
    super.key,
    required this.resolve,
    required super.child,
  });

  final ArtworkSource resolve;

  static Future<ImageProvider?> _core(String id, int px) async {
    final path = await core.artworkFile(id: id, size: px);
    return path == null ? null : FileImage(File(path));
  }

  static ArtworkSource of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<ArtworkResolver>()?.resolve ?? _core;

  @override
  bool updateShouldNotify(ArtworkResolver old) => old.resolve != resolve;
}

/// What is playing, for every [VArtwork] on screen: the shell provides it, so no screen
/// computes "playing" itself (spec UI §2.3).
class NowPlayingScope extends InheritedWidget {
  const NowPlayingScope({
    super.key,
    required this.trackId,
    this.contextId,
    required this.playing,
    required super.child,
  });

  final String? trackId;

  /// The album, playlist or artist the queue plays from.
  final String? contextId;
  final bool playing;

  /// Whether [itemId] (a track or its context) is playing now.
  static bool isPlaying(BuildContext c, String itemId) {
    final s = c.dependOnInheritedWidgetOfExactType<NowPlayingScope>();
    return s != null &&
        s.playing &&
        (s.trackId == itemId || s.contextId == itemId);
  }

  @override
  bool updateShouldNotify(NowPlayingScope old) =>
      old.trackId != trackId ||
      old.contextId != contextId ||
      old.playing != playing;
}

/// The meaning decides the shape (spec UI §2.3); a screen never picks one.
enum ArtKind { item, artist }

enum ArtShape { roundedSquare, cookie, circle }

/// Rounded square at rest, cookie for what's playing, circle for an artist; anything
/// selected is a cookie with a check.
ArtShape artShapeFor({
  required ArtKind kind,
  required bool playing,
  required bool selected,
}) => selected
    ? ArtShape.cookie
    : kind == ArtKind.artist
    ? ArtShape.circle
    : playing
    ? ArtShape.cookie
    : ArtShape.roundedSquare;

double _cornerFor(double size) =>
    size <= VSize.compactArt * 2 ? VRadius.small : VRadius.large;

/// A [RoundedPolygon] (normalized to the unit square) as a [ShapeBorder]: for clipping and
/// for the focus ring around a cookie.
class VPolygonBorder extends ShapeBorder {
  const VPolygonBorder(this.polygon, {this.turns = 0});

  final RoundedPolygon polygon;
  final double turns;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final m = Matrix4.identity()
      ..translateByDouble(rect.center.dx, rect.center.dy, 0, 1)
      ..rotateZ(turns * 2 * math.pi)
      ..scaleByDouble(rect.width, rect.height, 1, 1)
      ..translateByDouble(-0.5, -0.5, 0, 1);
    return polygon.toPath().transform(m.storage);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

final _cookie = M3EShapeKind.cookie12Sided.polygon;

/// The border of an artwork shape at [size]: for clipping and for the focus ring.
ShapeBorder vArtBorder(ArtShape shape, double size) => switch (shape) {
  ArtShape.circle => const CircleBorder(),
  ArtShape.cookie => VPolygonBorder(_cookie),
  ArtShape.roundedSquare => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_cornerFor(size)),
  ),
};

/// Cookie (0) → rounded square (1), with the square's corner at this size.
Morph _morphFor(double size) => vCookieMorph(_cornerFor(size) / size);

const _buckets = [64, 128, 256, 512, 1024, 2048];

/// The pixel size a picture is fetched and decoded at: the next bucket up, so a resize
/// or an animated size asks the core for a handful of files, not one per frame.
int vPictureBucket(double px) =>
    _buckets.firstWhere((b) => b >= px, orElse: () => _buckets.last);

class _MorphClipper extends CustomClipper<Path> {
  const _MorphClipper(this.morph, this.t);

  final Morph morph;
  final double t;

  @override
  Path getClip(Size size) {
    final m = Matrix4.identity()..scaleByDouble(size.width, size.height, 1, 1);
    return morph.toPath(progress: t).transform(m.storage);
  }

  @override
  bool shouldReclip(_MorphClipper old) => old.t != t || old.morph != morph;
}

/// The cookie's current turn, so the missing-cover icon and the equalizer stay upright.
class _Turn extends InheritedWidget {
  const _Turn({required this.angle, required super.child});

  final double angle;

  static double of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_Turn>()?.angle ?? 0;

  @override
  bool updateShouldNotify(_Turn old) => old.angle != angle;
}

/// Hides the missing-cover icon (the equalizer takes its place).
class _QuietCover extends InheritedWidget {
  const _QuietCover({required this.quiet, required super.child});

  final bool quiet;

  static bool of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_QuietCover>()?.quiet ?? false;

  @override
  bool updateShouldNotify(_QuietCover old) => old.quiet != quiet;
}

/// Undoes the cookie's turn for what must stay upright.
class _Upright extends StatelessWidget {
  const _Upright({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Transform.rotate(angle: -_Turn.of(context), child: child);
}

/// The one artwork: shape by meaning, the slow spin of what's playing, the wavy ring.
///
/// - item: rounded square; playing → a cookie turning once in 20 s, morphing back to the
///   square when it stops; selected → cookie + check;
/// - artist: always a circle (playing → equalizer; selected → cookie + check);
/// - [mosaic]: a user playlist without a picture, drawn from its first distinct tracks
///   (1 → full, 2 → diagonal, 3 → repeated, 0 → the missing-cover look), with the same
///   shapes;
/// - [progress] draws the wavy ring around it (flat when not playing); [onSeek] makes the
///   ring a slider (only the ring: the cover inside lets taps through).
///
/// [playing] overrides [NowPlayingScope] (the gallery and the player pass it).
class VArtwork extends StatefulWidget {
  const VArtwork({
    super.key,
    required this.itemId,
    required this.size,
    this.kind = ArtKind.item,
    this.playing,
    this.selected = false,
    this.mosaic,
    this.progress,
    this.onSeek,
    this.seekStep = 0.05,
    this.semanticLabel,
  });

  final String itemId;
  final double size;
  final ArtKind kind;
  final bool? playing;
  final bool selected;
  final List<String>? mosaic;
  final double? progress;
  final ValueChanged<double>? onSeek;
  final double seekStep;
  final String? semanticLabel;

  /// Keys of the shown shape, for tests.
  static Key shapeKey(ArtShape s) => ValueKey('art.$s');

  @override
  State<VArtwork> createState() => _VArtworkState();
}

class _VArtworkState extends State<VArtwork> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: VDurations.spin,
  );

  /// 0 = cookie, 1 = rounded square.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    value: 1,
  );
  bool _first = true;

  /// Where the morph is heading (0 = cookie, 1 = rounded square).
  double _morphTarget = 1;

  bool get _playing =>
      widget.playing ?? NowPlayingScope.isPlaying(context, widget.itemId);

  ArtShape get _shape => artShapeFor(
    kind: widget.kind,
    playing: _playing,
    selected: widget.selected,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(VArtwork old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _spin.dispose();
    _morph.dispose();
    super.dispose();
  }

  void _sync() {
    final reduced = reduceMotion(context);
    final cookie = _shape == ArtShape.cookie;
    final target = cookie ? 0.0 : 1.0;
    if (reduced || _first) {
      _first = false;
      _morph.stop();
      _morph.value = _morphTarget = target;
    } else if (target != _morphTarget) {
      // A new target, even mid-spring (a double tap on ⏯): re-aim from where the shape
      // is, keeping its speed. The same target again (every position tick rebuilds)
      // leaves the running spring alone.
      _morphTarget = target;
      _morph
          .animateWith(
            SpringSimulation(
              VSprings.spatial,
              _morph.value,
              target,
              _morph.velocity,
            ),
          )
          // The spring stops within tolerance; land exactly on the shape.
          .then((_) {
            if (_morphTarget == target) _morph.value = target;
          });
    }
    final spin = cookie && _playing && !widget.selected && !reduced;
    if (spin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!spin && _spin.isAnimating) {
      _spin.stop();
    }
    // Paused, the morph back to the square brings it upright; a selected or still
    // cookie stands upright at once.
    if (!spin && (reduced || widget.selected)) _spin.value = 0;
  }

  VRingGeometry? _ring;
  (double, double, bool)? _ringFor;

  /// The ring's outline for the current morph, cached while the shape holds still.
  VRingGeometry _ringGeometry(double art, bool circle) {
    final key = (circle ? 1.0 : _morph.value, widget.size, circle);
    if (_ringFor != key || _ring == null) {
      final s = VSize.ringStroke;
      final box = Rect.fromLTWH(s / 2, s / 2, widget.size - s, widget.size - s);
      final share = (_cornerFor(art) + VSize.ringGap + s / 2) / box.width;
      _ringFor = key;
      _ring = VRingGeometry(
        circle
            ? vRingOutline(ArtShape.circle, box)
            : vUnitPath(vCookieMorph(share).toPath(progress: key.$1), box),
        box.center,
      );
    }
    return _ring!;
  }

  Widget _picture(double art) {
    final ids = widget.mosaic?.toSet().take(4).toList();
    if (ids == null) {
      return VArtworkPicture(
        itemId: widget.itemId,
        size: art,
        kind: widget.kind,
      );
    }
    if (ids.isEmpty) {
      return _Picture(image: null, kind: ArtKind.item, size: art);
    }
    if (ids.length == 1) return VArtworkPicture(itemId: ids.first, size: art);
    return Wrap(
      children: [
        // Two tracks sit on the diagonal; three repeat the first last.
        for (final i
            in ids.length == 2 ? const [0, 1, 1, 0] : const [0, 1, 2, 3])
          VArtworkPicture(itemId: ids[i % ids.length], size: art / 2),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final playing = _playing;
    final shape = _shape;
    final ring = widget.progress != null;
    final inset = ring ? VSize.ringStroke + VSize.ringGap : 0.0;
    final art = widget.size - 2 * inset;
    // The turning cookie is the playing sign on its own (spec UI §5.3, the
    // shape-language mockup); an artist keeps its circle, so it has the equalizer.
    final equalizer = playing && !ring && widget.kind == ArtKind.artist;

    // The picture, the equalizer's scrim and bars, all inside the shape.
    final inside = Stack(
      fit: StackFit.expand,
      children: [
        // Under the equalizer the missing-cover icon steps aside: one sign at a time.
        _QuietCover(quiet: equalizer, child: _picture(art)),
        if (equalizer) VEqualizer(size: art / 2, onArtwork: true),
      ],
    );

    Widget picture;
    if (shape == ArtShape.circle) {
      picture = ClipOval(child: inside);
    } else {
      final morph = _morphFor(art);
      picture = RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _morph]),
          builder: (context, child) {
            // The turn fades out as the cookie becomes a square again.
            final angle = _spin.value * 2 * math.pi * (1 - _morph.value);
            return Transform.rotate(
              angle: angle,
              child: ClipPath(
                clipper: _MorphClipper(morph, _morph.value),
                child: _Turn(angle: angle, child: child!),
              ),
            );
          },
          child: inside,
        ),
      );
    }

    picture = Stack(
      key: VArtwork.shapeKey(shape),
      alignment: Alignment.center,
      children: [
        SizedBox.square(dimension: art, child: picture),
        if (widget.selected)
          SizedBox.square(
            dimension: art,
            child: _Check(size: art),
          ),
      ],
    );

    if (ring) {
      final scheme = Theme.of(context).colorScheme;
      picture = VSeekable(
        progress: widget.progress!,
        onSeek: widget.onSeek,
        step: widget.seekStep,
        mapping: angularSeek,
        angular: true,
        hit: ringHit,
        shape: const CircleBorder(),
        child: IgnorePointer(child: picture),
        builder: (context, shown, cover) => Stack(
          alignment: Alignment.center,
          children: [
            // The outline of the artwork's own shape, a gap further out: it morphs and
            // turns with it (spec UI §5.5).
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_spin, _morph]),
                builder: (context, _) {
                  final circle = shape == ArtShape.circle;
                  return CustomPaint(
                    size: Size.square(widget.size),
                    painter: VRingPainter(
                      geometry: _ringGeometry(art, circle),
                      shape: shape,
                      turn: circle
                          ? 0
                          : _spin.value * 2 * math.pi * (1 - _morph.value),
                      progress: shown,
                      played: scheme.primary,
                      track: scheme.secondaryContainer,
                    ),
                  );
                },
              ),
            ),
            cover!,
          ],
        ),
      );
    }

    return Semantics(
      image: widget.semanticLabel != null,
      label: widget.semanticLabel,
      child: SizedBox.square(dimension: widget.size, child: picture),
    );
  }
}

/// An item's bare picture at its display size (fetched and decoded at a bucketed
/// size × DPR), with the missing-cover look. For design components only (the wave
/// artwork, decor): screens use [VArtwork], which gives the shape its meaning (guarded in
/// test/design).
class VArtworkPicture extends StatefulWidget {
  const VArtworkPicture({
    super.key,
    required this.itemId,
    required this.size,
    this.kind = ArtKind.item,
  });

  final String itemId;
  final double size;
  final ArtKind kind;

  @override
  State<VArtworkPicture> createState() => _VArtworkPictureState();
}

class _VArtworkPictureState extends State<VArtworkPicture> {
  Future<ImageProvider?>? _image;
  (String, int, ArtworkSource)? _for;
  int _px = 0;

  @override
  Widget build(BuildContext context) {
    _px = vPictureBucket(widget.size * MediaQuery.devicePixelRatioOf(context));
    final resolve = ArtworkResolver.of(context);
    if (_for != (widget.itemId, _px, resolve)) {
      _for = (widget.itemId, _px, resolve);
      _image = resolve(widget.itemId, _px);
    }
    return SizedBox.square(
      dimension: widget.size,
      child: FutureBuilder<ImageProvider?>(
        future: _image,
        builder: (context, snap) => _Picture(
          image: snap.data == null
              ? null
              : ResizeImage(snap.data!, width: _px, allowUpscaling: false),
          kind: widget.kind,
          size: widget.size,
        ),
      ),
    );
  }
}

/// The picture, or the missing-cover look: a flat `surfaceContainerHighest` with a centred
/// note (a person for an artist) in `onSurfaceVariant`, nothing else. The icon never turns.
class _Picture extends StatelessWidget {
  const _Picture({required this.image, required this.kind, required this.size});

  final ImageProvider? image;
  final ArtKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: _QuietCover.of(context)
          ? null
          : Center(
              child: _Upright(
                child: VSymbol(
                  kind == ArtKind.artist ? VIcons.person : VIcons.musicNote,
                  size: size / 2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
    );
    final img = image;
    if (img == null) return placeholder;
    return Image(
      image: img,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => placeholder,
      frameBuilder: (_, child, frame, sync) =>
          sync || frame != null ? child : placeholder,
    );
  }
}

/// The check of what is chosen: a small badge on the cookie's lower right edge.
class _Check extends StatelessWidget {
  const _Check({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = size * 0.36;
    return Align(
      alignment: Alignment.bottomRight,
      child: Semantics(
        label: AppLocalizations.of(context).selectedLabel,
        child: Container(
          width: badge,
          height: badge,
          decoration: ShapeDecoration(
            color: scheme.primary,
            shape: CircleBorder(
              side: BorderSide(color: scheme.surface, width: badge / 10),
            ),
          ),
          child: Center(
            child: VSymbol(
              VIcons.check,
              size: badge * 0.62,
              color: scheme.onPrimary,
              weight: 700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Three bars that bounce while playing (scale only, no layout per frame); still with
/// "reduce motion". Spoken as "now playing". [onArtwork]: drawn straight over the
/// picture, on a light scrim filling the artwork's shape; otherwise bars alone in
/// `primary` (a numbered row).
class VEqualizer extends StatefulWidget {
  const VEqualizer({super.key, required this.size, this.onArtwork = false});

  final double size;
  final bool onArtwork;

  @override
  State<VEqualizer> createState() => _VEqualizerState();
}

class _VEqualizerState extends State<VEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: VDurations.long * 2,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.size;
    final bars = RepaintBoundary(
      child: SizedBox.square(
        dimension: s,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: s / 24),
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) => Transform.scale(
                    alignment: Alignment.bottomCenter,
                    scaleY:
                        0.35 +
                        0.65 *
                            (0.5 +
                                0.5 *
                                    math.sin((_c.value + i / 3) * 2 * math.pi)),
                    child: child,
                  ),
                  child: Container(
                    width: s / 8,
                    height: s * 0.7,
                    decoration: BoxDecoration(
                      color: widget.onArtwork
                          ? scheme.onSurfaceVariant
                          : scheme.primary,
                      borderRadius: BorderRadius.circular(s / 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      label: AppLocalizations.of(context).nowPlaying,
      child: widget.onArtwork
          // The scrim is the missing-cover colour: invisible on a missing cover, a soft
          // veil on a real one; the bars read on both.
          ? ColoredBox(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
              child: Center(child: _Upright(child: bars)),
            )
          : bars,
    );
  }
}

/// Decor shapes: genre tiles, first-launch steps, empty states, never artwork.
enum VDecorShape { clover, flower, sunny, burst, pill, arch, gem, cookie }

extension on VDecorShape {
  M3EShapeKind get kind => switch (this) {
    VDecorShape.clover => M3EShapeKind.clover8Leaf,
    VDecorShape.flower => M3EShapeKind.flower,
    VDecorShape.sunny => M3EShapeKind.sunny,
    VDecorShape.burst => M3EShapeKind.softBurst,
    VDecorShape.pill => M3EShapeKind.pill,
    VDecorShape.arch => M3EShapeKind.arch,
    VDecorShape.gem => M3EShapeKind.gem,
    VDecorShape.cookie => M3EShapeKind.cookie9Sided,
  };
}

/// The same id always gets the same shape (FNV-1a, stable across runs).
VDecorShape decorFor(String id) {
  var h = 0x811c9dc5;
  for (final u in id.codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xffffffff;
  }
  return VDecorShape.values[h % VDecorShape.values.length];
}

/// A decor shape filled with an item's picture ([imageItemId]) or the secondary
/// container with [child] (an icon) at its center.
class VDecor extends StatelessWidget {
  const VDecor({
    super.key,
    required this.shape,
    required this.size,
    this.imageItemId,
    this.child,
    this.tilt = 0,
  });

  final VDecorShape shape;
  final double size;
  final String? imageItemId;
  final Widget? child;

  /// In turns.
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = imageItemId;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ClipPath(
              clipper: ShapeBorderClipper(
                shape: VPolygonBorder(shape.kind.polygon, turns: tilt),
              ),
              child: id == null
                  ? ColoredBox(color: scheme.secondaryContainer)
                  : VArtworkPicture(itemId: id, size: size, kind: ArtKind.item),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}
