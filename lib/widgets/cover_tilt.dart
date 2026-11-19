import 'package:flutter/material.dart';

/// Tilts a cover while a pointer is down and restores it on release. The raw
/// Listener leaves scrolling and the card's own tap untouched.
class CoverTilt extends StatefulWidget {
  const CoverTilt({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.foil = false,
    this.enabled = true,
    this.maxTilt = 0.10,
  });

  final Widget child;
  final double borderRadius;

  /// Permanent iridescent sheen for covers rated 9+.
  final bool foil;
  final bool enabled;
  final double maxTilt;

  @override
  State<CoverTilt> createState() => _CoverTiltState();
}

class _CoverTiltState extends State<CoverTilt> with SingleTickerProviderStateMixin {
  late final AnimationController _release;
  double _rotX = 0;
  double _rotY = 0;
  double _shine = 0;
  double _startRotX = 0;
  double _startRotY = 0;
  double _startShine = 0;
  Size _size = Size.zero;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _release = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _release.addListener(() {
      final t = Curves.easeOutCubic.transform(_release.value);
      setState(() {
        _rotX = _startRotX * (1 - t);
        _rotY = _startRotY * (1 - t);
        _shine = _startShine * (1 - t);
      });
    });
  }

  @override
  void dispose() {
    _release.dispose();
    super.dispose();
  }

  void _updateTilt(Offset local) {
    if (_size.width <= 0 || _size.height <= 0) return;
    final nx = ((local.dx / _size.width) * 2 - 1).clamp(-1.0, 1.0);
    final ny = ((local.dy / _size.height) * 2 - 1).clamp(-1.0, 1.0);
    setState(() {
      _rotY = nx * widget.maxTilt;
      _rotX = -ny * widget.maxTilt;
      _shine = nx;
    });
  }

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _release.stop();
    _pressed = true;
    _updateTilt(event.localPosition);
  }

  void _onMove(PointerMoveEvent event) {
    if (!_pressed) return;
    _updateTilt(event.localPosition);
  }

  void _onUp(PointerEvent event) {
    if (!_pressed) return;
    _pressed = false;
    _startRotX = _rotX;
    _startRotY = _rotY;
    _startShine = _shine;
    _release.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final scale = _pressed ? 1.012 : 1.0;
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          ..rotateX(_rotX)
          ..rotateY(_rotY)
          ..scaleByDouble(scale, scale, 1, 1);

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          child: Transform(
            alignment: Alignment.center,
            transform: matrix,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                widget.child,
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (widget.foil)
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0x1A7CF7FF),
                                    Color(0x1AFF7AD9),
                                    Color(0x1AFFE86A),
                                    Color(0x1A7B8CFF),
                                  ],
                                ),
                              ),
                            ),
                          if (_pressed)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment(-1 + _shine * 1.8, -1),
                                  end: Alignment(1 + _shine * 1.8, 1),
                                  colors: const [
                                    Color(0x00FFFFFF),
                                    Color(0x33FFFFFF),
                                    Color(0x00FFFFFF),
                                  ],
                                  stops: const [0.2, 0.5, 0.8],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}