import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Floating scrollbar with a frosted glass thumb. It stays hidden until the list
/// moves, follows fingers on the thumb and fades out shortly after scrolling stops.
///
/// When no controller is available the thumb still tracks the content, but the
/// drag handle is disabled; this keeps the indicator useful in nested scroll
/// views that own their controllers.
class GlassScrollbar extends StatefulWidget {
  const GlassScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thickness = 7,
    this.edgeInset = 4,
  });

  final Widget child;
  final ScrollController? controller;
  final double thickness;
  final double edgeInset;

  @override
  State<GlassScrollbar> createState() => _GlassScrollbarState();
}

class _GlassScrollbarState extends State<GlassScrollbar> {
  static const double _minThumbLength = 42;
  static const Duration _fadeDuration = Duration(milliseconds: 180);
  static const Duration _hideDelay = Duration(milliseconds: 1100);

  ScrollController? _controller;
  ScrollMetrics? _metrics;
  Timer? _hideTimer;
  bool _visible = false;
  bool _dragging = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = widget.controller ?? PrimaryScrollController.maybeOf(context);
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller;
      _controller?.addListener(_onControllerChanged);
    }
    if (_metrics == null && controller != null && controller.hasClients) {
      _metrics = controller.position;
    }
  }

  @override
  void didUpdateWidget(covariant GlassScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller) && widget.controller != null) {
      _controller?.removeListener(_onControllerChanged);
      _controller = widget.controller;
      _controller?.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    _metrics = controller.position;
    _show();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    _metrics = notification.metrics;
    _show();
    return false;
  }

  void _show() {
    _hideTimer?.cancel();
    if (!_visible) {
      setState(() => _visible = true);
    }
    if (!_dragging) {
      _hideTimer = Timer(_hideDelay, () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _handleDragStart(DragStartDetails details) {
    _hideTimer?.cancel();
    setState(() => _dragging = true);
  }

  void _handleDragUpdate(DragUpdateDetails details, double trackLength, double thumbLength) {
    final controller = _controller;
    final metrics = _metrics;
    if (controller == null || metrics == null || !controller.hasClients) return;
    final range = metrics.maxScrollExtent;
    if (range <= 0) return;
    final travel = (trackLength - thumbLength).clamp(1.0, double.infinity);
    final next = controller.offset + details.delta.dy / travel * range;
    controller.jumpTo(next.clamp(0.0, range));
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() => _dragging = false);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.black.withValues(alpha: 0.16);
    final border = dark
        ? Colors.white.withValues(alpha: 0.38)
        : Colors.black.withValues(alpha: 0.22);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_visible,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: _fadeDuration,
                curve: Curves.easeOut,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final metrics = _metrics;
                    if (metrics == null ||
                        constraints.maxHeight <= 0 ||
                        metrics.maxScrollExtent <= 0) {
                      return const SizedBox.shrink();
                    }

                    final trackLength = constraints.maxHeight - widget.edgeInset * 2;
                    final contentExtent =
                        metrics.maxScrollExtent + metrics.viewportDimension;
                    final thumbLength = (trackLength *
                            metrics.viewportDimension /
                            contentExtent)
                        .clamp(_minThumbLength, trackLength);
                    final travel = (trackLength - thumbLength).clamp(0.0, double.infinity);
                    final progress = (metrics.pixels / metrics.maxScrollExtent)
                        .clamp(0.0, 1.0);
                    final thumbTop = widget.edgeInset + travel * progress;
                    final thumbWidth = _dragging ? widget.thickness + 2 : widget.thickness;

                    return Stack(
                      children: [
                        Positioned(
                          top: thumbTop,
                          right: widget.edgeInset,
                          width: thumbWidth + 14,
                          height: thumbLength,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onVerticalDragStart: _handleDragStart,
                            onVerticalDragUpdate: (details) =>
                                _handleDragUpdate(details, trackLength, thumbLength),
                            onVerticalDragEnd: _handleDragEnd,
                            onVerticalDragCancel: _scheduleHide,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                width: thumbWidth,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.28),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: BackdropFilter(
                                    filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: fill,
                                        border: Border.all(color: border, width: 0.8),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}