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
final _squares = <double, Morph>{};

/// Cookie (0) → rounded square (1), with the square's corner at this size.
Morph _morphFor(double size) => _squares[size] ??= Morph(
  _cookie,
  RoundedPolygon.rectangle(
    width: 1,
    height: 1,
    centerX: 0.5,
    centerY: 0.5,
    rounding: CornerRounding(radius: _cornerFor(size) / size),
  ),
);

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

/// The one artwork: shape by meaning, the slow spin of what's playing, the wavy ring.
///
/// - item: rounded square; playing → a cookie turning once in 20 s, morphing back to the
///   square when it stops; selected → cookie + check;
/// - artist: always a circle (playing → equalizer; selected → cookie + check);
/// - [progress] draws the wavy ring around it (flat when not playing); [onSeek] makes the
///   ring a slider.
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
      _morph.value = target;
    } else if (_morph.value != target) {
      _morph
          .animateWith(
            SpringSimulation(VSprings.spatial, _morph.value, target, 0),
          )
          // The spring stops within tolerance; land exactly on the shape.
          .then((_) => _morph.value = target);
    }
    final spin = cookie && _playing && !widget.selected && !reduced;
    if (spin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!spin && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotion(context);
    final playing = _playing;
    final shape = _shape;
    final ring = widget.progress != null;
    final inset = ring ? VSize.ringStroke + VSize.ringGap : 0.0;
    final art = widget.size - 2 * inset;

    Widget picture = VArtworkPicture(
      itemId: widget.itemId,
      size: art,
      kind: widget.kind,
    );

    if (shape == ArtShape.circle) {
      picture = ClipOval(child: picture);
    } else {
      final morph = _morphFor(art);
      picture = AnimatedBuilder(
        animation: Listenable.merge([_spin, _morph]),
        builder: (context, child) => Transform.rotate(
          // The turn fades out as the cookie becomes a square again.
          angle: _spin.value * 2 * math.pi * (1 - _morph.value),
          child: ClipPath(
            clipper: _MorphClipper(morph, _morph.value),
            child: child,
          ),
        ),
        child: picture,
      );
    }

    picture = Stack(
      key: VArtwork.shapeKey(shape),
      alignment: Alignment.center,
      children: [
        SizedBox.square(dimension: art, child: picture),
        if (playing &&
            (widget.kind == ArtKind.artist || art <= VSize.compactArt))
          VEqualizer(size: art / 2),
        if (widget.selected) _Check(size: art),
      ],
    );

    if (ring) {
      final wave = playing && !reduced;
      final p = widget.progress!.clamp(0.0, 1.0);
      picture = Stack(
        alignment: Alignment.center,
        children: [
          VSeekable(
            progress: p,
            onSeek: widget.onSeek,
            step: widget.seekStep,
            mapping: angularSeek,
            shape: const CircleBorder(),
            child: wave
                ? M3EProgressIndicator.circularWavy(
                    value: p,
                    size: widget.size,
                    strokeWidth: VSize.ringStroke,
                  )
                : M3EProgressIndicator.circular(
                    value: p,
                    size: widget.size,
                    strokeWidth: VSize.ringStroke,
                  ),
          ),
          IgnorePointer(child: picture),
        ],
      );
    }

    return Semantics(
      image: widget.semanticLabel != null,
      label: widget.semanticLabel,
      child: SizedBox.square(dimension: widget.size, child: picture),
    );
  }
}

/// An item's bare picture at its display size (decoded at size × DPR), with a
/// placeholder. For design components only (the wave artwork, decor, mosaic): screens use
/// [VArtwork], which gives the shape its meaning (guarded in test/design).
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
    _px = (widget.size * MediaQuery.devicePixelRatioOf(context)).round();
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
      child: Center(
        child: VSymbol(
          kind == ArtKind.artist ? VIcons.person : VIcons.musicNote,
          size: size / 2,
          color: scheme.onSurfaceVariant,
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

class _Check extends StatelessWidget {
  const _Check({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: AppLocalizations.of(context).selectedLabel,
      child: Container(
        width: size * 0.45,
        height: size * 0.45,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: VSymbol(
            VIcons.check,
            size: size * 0.3,
            color: scheme.onPrimary,
            weight: 600,
          ),
        ),
      ),
    );
  }
}

/// Three bars that bounce while playing; still with "reduce motion". Spoken as "now
/// playing".
class VEqualizer extends StatefulWidget {
  const VEqualizer({super.key, required this.size});

  final double size;

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
    return Semantics(
      label: AppLocalizations.of(context).nowPlaying,
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(s / 4),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: s / 8,
                  height:
                      s *
                      (0.3 +
                          0.4 *
                              (0.5 +
                                  0.5 *
                                      math.sin(
                                        (_c.value + i / 3) * 2 * math.pi,
                                      ))),
                  margin: EdgeInsets.symmetric(horizontal: s / 24),
                  decoration: BoxDecoration(
                    color: scheme.onPrimaryContainer,
                    borderRadius: BorderRadius.circular(s / 16),
                  ),
                ),
            ],
          ),
        ),
      ),
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

/// A user playlist without a picture: its first distinct tracks in 2×2 (1 → full,
/// 2–3 → 2×2 repeating), an icon when it is empty.
class VMosaicArtwork extends StatelessWidget {
  const VMosaicArtwork({super.key, required this.itemIds, required this.size});

  final List<String> itemIds;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ids = itemIds.toSet().take(4).toList();
    if (ids.length == 1) {
      return VArtwork(itemId: ids.first, size: size, playing: false);
    }
    final scheme = Theme.of(context).colorScheme;
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_cornerFor(size)),
      child: SizedBox.square(
        dimension: size,
        child: ids.isEmpty
            ? ColoredBox(
                color: scheme.secondaryContainer,
                child: Center(
                  child: VSymbol(
                    VIcons.queue,
                    size: half,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              )
            : Wrap(
                children: [
                  // Two tracks sit on the diagonal; three repeat the first last.
                  for (final i
                      in ids.length == 2
                          ? const [0, 1, 1, 0]
                          : const [0, 1, 2, 3])
                    VArtworkPicture(
                      itemId: ids[i % ids.length],
                      size: half,
                      kind: ArtKind.item,
                    ),
                ],
              ),
      ),
    );
  }
}
