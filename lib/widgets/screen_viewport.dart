import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';

import 'package:flutter/rendering.dart';

import 'wear_controls.dart';

import '../platform/rotary_input.dart';
import '../platform/touch_haptics.dart';

class ScreenShape extends InheritedWidget {
  const ScreenShape({super.key, required this.isRound, required super.child});
  final bool isRound;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScreenShape>()?.isRound ??
      false;
  @override
  bool updateShouldNotify(ScreenShape oldWidget) =>
      oldWidget.isRound != isRound;
}

/// Uses the whole circular display rather than an inscribed square.
class ScreenViewport extends StatelessWidget {
  const ScreenViewport({super.key, required this.isRound, required this.child});

  final bool isRound;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isRound) {
      return LayoutBuilder(
        builder: (context, constraints) => Center(
          child: SizedBox.square(
            dimension: constraints.biggest.shortestSide,
            child: ClipOval(child: _EdgeBackGesture(child: child)),
          ),
        ),
      );
    }
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: child,
        ),
      ),
    );
  }
}

/// Continuous scrolling with subtle Wear-style edge treatment.
class ShapeScrollView extends StatefulWidget {
  const ShapeScrollView({
    super.key,
    required this.isRound,
    required this.children,
    this.storageKey,
    this.enableRotary = true,
    this.showTime = true,
    this.footerInset = 0,
    this.topPadding,
  });

  final bool isRound;
  final bool enableRotary;
  final bool showTime;
  final double footerInset;
  final double? topPadding;
  final List<Widget> children;
  final PageStorageKey<String>? storageKey;

  @override
  State<ShapeScrollView> createState() => _ShapeScrollViewState();
}

class _ShapeScrollViewState extends State<ShapeScrollView>
    with SingleTickerProviderStateMixin {
  final _controller = ScrollController();
  late final StreamSubscription<double> _rotarySubscription;
  final Set<int> _touchPointers = {};
  bool _touchScrolling = false;
  late final AnimationController _indicator;
  Timer? _hideIndicator;

  void _scrolled() {
    _indicator.value = 1;
    _hideIndicator?.cancel();
    _hideIndicator = Timer(const Duration(milliseconds: 750), () {
      if (mounted) _indicator.reverse();
    });
  }

  @override
  void initState() {
    super.initState();
    _indicator = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _controller.addListener(_scrolled);
    _rotarySubscription = RotaryInput.events.listen(_onRotary);
  }

  void _onRotary(double delta) {
    // Covered routes retain their scroll position and never respond to the crown.
    if (!mounted ||
        !widget.enableRotary ||
        ModalRoute.of(context)?.isCurrent != true ||
        _controller.positions.length != 1 ||
        _touchPointers.isNotEmpty ||
        _touchScrolling) {
      return;
    }
    // Use Flutter's incremental wheel path. animateTo starts a driven activity
    // that cancels a live drag and ignores subsequent pointer movement.
    final before = _controller.offset;
    _controller.position.pointerScroll(delta);
    if (_controller.offset != before) {
      TouchHaptics.rotaryScroll(delta, source: _controller);
    }
  }

  @override
  void dispose() {
    _hideIndicator?.cancel();
    _indicator.dispose();
    _rotarySubscription.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) => _touchPointers.add(event.pointer),
          onPointerUp: (event) => _touchPointers.remove(event.pointer),
          onPointerCancel: (event) => _touchPointers.remove(event.pointer),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _touchScrolling = true;
              } else if (notification is ScrollEndNotification) {
                _touchScrolling = false;
              }
              return false;
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                ListView(
                  key: widget.storageKey,
                  controller: _controller,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: widget.isRound
                      ? EdgeInsets.fromLTRB(
                          14,
                          widget.topPadding ??
                              constraints.maxHeight *
                                  (widget.showTime ? .16 : .12),
                          14,
                          widget.footerInset + constraints.maxHeight * .36,
                        )
                      : const EdgeInsets.all(16),
                  children: widget.isRound
                      ? [
                          for (final child in widget.children)
                            _EdgeItem(scroll: _controller, child: child),
                        ]
                      : widget.children,
                ),
                if (widget.isRound && widget.showTime)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _controller,
                        child: const CurvedTimeText(),
                        builder: (context, child) => Opacity(
                          opacity: _controller.positions.length == 1
                              ? (1 - _controller.offset / 32).clamp(0.0, 1.0)
                              : 1,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                if (widget.isRound)
                  IgnorePointer(
                    child: FadeTransition(
                      opacity: _indicator,
                      child: CustomPaint(
                        painter: _ScrollArcPainter(_controller),
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

class _ScrollArcPainter extends CustomPainter {
  _ScrollArcPainter(this.controller) : super(repaint: controller);

  final ScrollController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (controller.positions.length != 1 ||
        !controller.position.hasContentDimensions) {
      return;
    }
    final position = controller.position;
    if (position.maxScrollExtent <= 0) return;
    final track = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - 3,
    );
    const sweep =
        math.pi * 3 / 20; // Compact 27-degree arc, centered on the right.
    const start = -sweep / 2;
    final thumb =
        (position.viewportDimension /
                (position.viewportDimension + position.maxScrollExtent))
            .clamp(0.18, 0.65) *
        0.70;
    final progress = (position.pixels / position.maxScrollExtent).clamp(
      0.0,
      1.0,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.9
      ..strokeCap = StrokeCap.round
      ..color = AppColors.surface;
    canvas.drawArc(track, start, sweep, false, paint);
    paint.color = AppColors.muted;
    canvas.drawArc(
      track,
      start + sweep * (1 - thumb) * progress,
      sweep * thumb,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ScrollArcPainter oldDelegate) =>
      oldDelegate.controller != controller;
}

/// A route whose transition also follows an edge swipe interactively.
class WearPageRoute<T> extends PageRouteBuilder<T> {
  WearPageRoute({required WidgetBuilder builder})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            SlideTransition(
              position: Tween(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
      );
  void beginSwipe() {
    controller?.stop();
    navigator?.didStartUserGesture();
  }

  void updateSwipe(double fraction) {
    controller?.value = (1 - fraction).clamp(0.0, 1.0);
  }

  void endSwipe(bool dismiss) {
    if (dismiss) {
      navigator?.pop();
    } else {
      controller?.animateTo(
        1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
    navigator?.didStopUserGesture();
  }
}

class _EdgeBackGesture extends StatefulWidget {
  const _EdgeBackGesture({required this.child});
  final Widget child;
  @override
  State<_EdgeBackGesture> createState() => _EdgeBackGestureState();
}

class _EdgeBackGestureState extends State<_EdgeBackGesture>
    with SingleTickerProviderStateMixin {
  late final AnimationController fallback = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  double distance = 0;
  bool tracking = false, eligible = false;
  WearPageRoute<dynamic>? route;
  void finish(bool dismiss) {
    if (!tracking) return;
    tracking = false;
    if (route != null) {
      route!.endSwipe(dismiss);
    } else if (dismiss) {
      Navigator.of(context).maybePop();
    } else {
      fallback.reverse();
    }
  }

  @override
  void dispose() {
    fallback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The root page has no back action; leave horizontal drags to its content.
    if (ModalRoute.of(context)?.isFirst == true ||
        !Navigator.of(context).canPop()) {
      return widget.child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragDown: (details) =>
          eligible = details.localPosition.dx <= 28,
      onHorizontalDragStart: (details) {
        tracking = eligible && Navigator.of(context).canPop();
        distance = 0;
        final current = ModalRoute.of(context);
        route = current is WearPageRoute ? current : null;
        if (tracking) route?.beginSwipe();
      },
      onHorizontalDragUpdate: (details) {
        if (!tracking) return;
        distance = math.max(0, distance + details.delta.dx);
        final fraction = distance / MediaQuery.sizeOf(context).shortestSide;
        if (route != null) {
          route!.updateSwipe(fraction);
        } else {
          fallback.value = fraction.clamp(0.0, 1.0);
        }
      },
      onHorizontalDragEnd: (details) => finish(
        distance > MediaQuery.sizeOf(context).shortestSide * .3 ||
            details.velocity.pixelsPerSecond.dx > 700,
      ),
      onHorizontalDragCancel: () => finish(false),
      child: AnimatedBuilder(
        animation: fallback,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(
            fallback.value * MediaQuery.sizeOf(context).shortestSide,
            0,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Paint-only edge scaling preserves list geometry and continuous drag physics.
class _EdgeItem extends SingleChildRenderObjectWidget {
  const _EdgeItem({required this.scroll, required super.child});
  final ScrollController scroll;
  @override
  RenderObject createRenderObject(BuildContext context) => _EdgeItemBox(scroll);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _EdgeItemBox renderObject,
  ) => renderObject.scroll = scroll;
}

class _EdgeItemBox extends RenderProxyBox {
  _EdgeItemBox(this._scroll);
  ScrollController _scroll;
  set scroll(ScrollController value) {
    if (_scroll == value) return;
    if (attached) _scroll.removeListener(markNeedsPaint);
    _scroll = value;
    if (attached) _scroll.addListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scroll.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _scroll.removeListener(markNeedsPaint);
    super.detach();
  }

  double get factor {
    final ancestor = RenderAbstractViewport.maybeOf(this);
    if (ancestor == null || ancestor is! RenderBox || !hasSize) return 1;
    final viewport = ancestor as RenderBox;
    if (size.height > viewport.size.height * .65) return 1;
    final center = localToGlobal(
      size.center(Offset.zero),
      ancestor: viewport,
    ).dy;
    final edge =
        ((center - viewport.size.height / 2).abs() /
                    (viewport.size.height / 2) -
                .45)
            .clamp(0.0, .55) /
        .55;
    return 1 - edge * .12;
  }

  Matrix4 get transform {
    final scale = factor;
    return Matrix4.identity()
      ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final scale = factor;
    context.pushOpacity(offset, ((1 - (1 - scale) * 3.2) * 255).round(), (
      context,
      offset,
    ) {
      context.pushTransform(needsCompositing, offset, transform, super.paint);
    });
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(this.transform);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: transform,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );
}
