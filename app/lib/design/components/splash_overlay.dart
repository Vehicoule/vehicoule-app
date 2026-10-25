import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../color.dart';
import '../motion.dart';
import '../tokens.dart';

/// The splash on macOS, Windows and Linux (spec UI §6.10), over the first frame: the
/// Mochi lands and bounces once (squash, then stretch), the note comes out, then the app
/// fades in. Android 12+ plays the same sequence in the system splash
/// (res/drawable/splash_mochi.xml); there, and on iOS, this is just [child].
///
/// No text, no spinner. With "reduce motion": the still icon, then the fade.
/// Layers: assets/brand/, written by branding/icon/export.sh from the user's Mochi.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.child});

  final Widget child;

  @visibleForTesting
  static const overlayKey = ValueKey('splash');

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

/// Fractions of [VDurations.splash] (900 ms): the fall ends at 300 ms, the squash at
/// 380, the stretch at 500, the settle at 600; the note comes out from 450 to 700, then
/// the fade.
const _fall = 300 / 900, _note = 450 / 900, _noteEnd = 700 / 900;

TweenSequence<double> _bounce(double squash, double stretch) => TweenSequence([
  TweenSequenceItem(tween: ConstantTween(1), weight: 300),
  TweenSequenceItem(
    tween: Tween(
      begin: 1.0,
      end: squash,
    ).chain(CurveTween(curve: VCurves.emphasizedDecelerate)),
    weight: 80,
  ),
  TweenSequenceItem(
    tween: Tween(
      begin: squash,
      end: stretch,
    ).chain(CurveTween(curve: VCurves.standard)),
    weight: 120,
  ),
  TweenSequenceItem(
    tween: Tween(
      begin: stretch,
      end: 1.0,
    ).chain(CurveTween(curve: VCurves.standard)),
    weight: 100,
  ),
  TweenSequenceItem(tween: ConstantTween(1), weight: 300),
]);

final _scaleX = _bounce(1.1, 0.96), _scaleY = _bounce(0.86, 1.06);

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this);
  var _shown = switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };
  bool? _reduced;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_shown || _reduced != null) return;
    final reduced = _reduced = reduceMotion(context);
    _c.duration = reduced ? VDurations.splashFade : VDurations.splash;
    _c.forward().whenCompleteOrCancel(() {
      if (mounted) setState(() => _shown = false);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    alignment: Alignment.center,
    children: [
      widget.child,
      if (_shown)
        Positioned.fill(
          child: IgnorePointer(
            child: KeyedSubtree(
              key: SplashOverlay.overlayKey,
              child: _splash(),
            ),
          ),
        ),
    ],
  );

  Widget _splash() {
    final reduced = _reduced ?? false;
    final fadeFrom = reduced
        ? 0.0
        : 1 -
              VDurations.splashFade.inMilliseconds /
                  VDurations.splash.inMilliseconds;
    final fade = ReverseAnimation(
      CurvedAnimation(
        parent: _c,
        curve: Interval(fadeFrom, 1, curve: VCurves.standard),
      ),
    );
    return FadeTransition(
      opacity: fade,
      child: ColoredBox(
        color: VBrand.background,
        child: Center(
          child: SizedBox.square(
            dimension: VSize.splashIcon,
            child: reduced
                ? Stack(
                    children: [
                      _layer('shadow'),
                      _layer('mochi'),
                      _layer('note'),
                    ],
                  )
                : AnimatedBuilder(
                    animation: _c,
                    builder: (_, _) => _bouncing(),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _bouncing() {
    final t = _c.value;
    double part(double from, double to, Curve curve) =>
        curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));
    final fall = part(0, _fall, VCurves.emphasizedAccelerate);
    final note = part(_note, _noteEnd, VCurves.emphasizedDecelerate);
    const size = VSize.splashIcon;
    return Stack(
      children: [
        Opacity(
          opacity: 0.3 + 0.7 * fall,
          child: Transform.scale(
            scale: 0.6 + 0.4 * fall,
            // The shadow's centre (256, 396) on the 512 canvas.
            alignment: const Alignment(0, 396 / 256 - 1),
            child: _layer('shadow'),
          ),
        ),
        Transform.translate(
          offset: Offset(0, -0.25 * size * (1 - fall)),
          child: Transform(
            // Squashed against the ground: the Mochi's base, (256, 400).
            alignment: const Alignment(0, 400 / 256 - 1),
            transform: Matrix4.diagonal3Values(
              _scaleX.transform(t),
              _scaleY.transform(t),
              1,
            ),
            child: _layer('mochi'),
          ),
        ),
        Opacity(
          opacity: note,
          child: Transform.translate(
            offset: Offset(0, 0.06 * size * (1 - note)),
            child: Transform.scale(
              scale: 0.4 + 0.6 * note,
              // From the headphones: the note's foot, (400, 144).
              alignment: const Alignment(400 / 256 - 1, 144 / 256 - 1),
              child: _layer('note'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _layer(String name) => Image.asset(
    'assets/brand/splash_$name.png',
    width: VSize.splashIcon,
    height: VSize.splashIcon,
    excludeFromSemantics: true,
    gaplessPlayback: true,
  );
}
