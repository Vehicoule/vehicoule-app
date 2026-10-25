import 'package:material_ui/material_ui.dart';

/// The keyboard focus ring (spec UI §4.4): a 3 px `secondary` stroke, 2 px away, that
/// follows [shape] (pill, card, cookie). It shows while anything inside has focus (or
/// [node], when the focusable element is around the ringed one, like a card around its
/// artwork), and only in keyboard mode: never after a click or a touch.
class VFocusRing extends StatefulWidget {
  const VFocusRing({
    super.key,
    required this.child,
    this.shape = const StadiumBorder(),
    this.node,
  });

  final Widget child;
  final ShapeBorder shape;
  final FocusNode? node;

  static const width = 3.0, gap = 2.0;

  @override
  State<VFocusRing> createState() => _VFocusRingState();
}

class _VFocusRingState extends State<VFocusRing> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onMode);
    widget.node?.addListener(_onNode);
  }

  @override
  void didUpdateWidget(VFocusRing old) {
    super.didUpdateWidget(old);
    if (old.node != widget.node) {
      old.node?.removeListener(_onNode);
      widget.node?.addListener(_onNode);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onMode);
    widget.node?.removeListener(_onNode);
    super.dispose();
  }

  void _onMode(FocusHighlightMode _) => setState(() {});

  void _onNode() => setState(() => _focused = widget.node!.hasFocus);

  @override
  Widget build(BuildContext context) {
    final show =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final paint = CustomPaint(
      foregroundPainter: show
          ? VFocusRingPainter(
              widget.shape,
              Theme.of(context).colorScheme.secondary,
            )
          : null,
      child: widget.child,
    );
    if (widget.node != null) return paint;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: paint,
    );
  }
}

class VFocusRingPainter extends CustomPainter {
  const VFocusRingPainter(this.shape, this.color);

  final ShapeBorder shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).inflate(
      VFocusRing.gap + VFocusRing.width / 2,
    );
    canvas.drawPath(
      shape.getOuterPath(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = VFocusRing.width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(VFocusRingPainter old) =>
      old.shape != shape || old.color != color;
}
