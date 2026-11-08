import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_colors.dart';

import 'package:flutter/rendering.dart';

import '../models/task.dart';
import '../platform/rotary_input.dart';
import '../platform/touch_haptics.dart';
import 'app_clock.dart';

/// Main action whose lower edge follows the circular display.
class WearEdgeButton extends StatelessWidget {
  const WearEdgeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: FilledButton(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 42),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      onPressed: busy ? null : onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (icon != null)
            Icon(icon, size: 22),
          if (busy || icon != null) const SizedBox(width: 6),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    ),
  );
}

/// Minute-aligned updates, suspended when the route or application is hidden.
class CurvedTimeText extends StatefulWidget {
  const CurvedTimeText({super.key});
  @override
  State<CurvedTimeText> createState() => _CurvedTimeTextState();
}

class _CurvedTimeTextState extends State<CurvedTimeText>
    with WidgetsBindingObserver {
  Timer? timer;
  bool visible = true, foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    visible = TickerMode.valuesOf(context).enabled;
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (!visible || !foreground) return;
    final now = AppClock.now(context);
    timer = Timer(
      Duration(milliseconds: 60000 - now.second * 1000 - now.millisecond),
      () {
        if (mounted) {
          setState(() {});
          schedule();
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && mounted) setState(() {});
    schedule();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = chinaNow(AppClock.now(context));
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Semantics(
      label: '当前时间 $time',
      child: CustomPaint(
        painter: _TimePainter(time),
        size: const Size(double.infinity, 32),
      ),
    );
  }
}

class _TimePainter extends CustomPainter {
  _TimePainter(this.text);
  final String text;
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 11;
    final painters = text
        .split('')
        .map(
          (letter) => TextPainter(
            text: TextSpan(
              text: letter,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            textDirection: TextDirection.ltr,
          )..layout(),
        )
        .toList();
    final total = painters.fold<double>(0, (sum, p) => sum + p.width);
    var advance = -total / 2;
    for (final p in painters) {
      final angle = (advance + p.width / 2) / radius;
      canvas.save();
      canvas.translate(
        size.width / 2 + radius * math.sin(angle),
        size.width / 2 - radius * math.cos(angle),
      );
      canvas.rotate(angle);
      p.paint(canvas, Offset(-p.width / 2, -p.height / 2));
      canvas.restore();
      advance += p.width;
    }
  }

  @override
  bool shouldRepaint(_TimePainter oldDelegate) => text != oldDelegate.text;
}

/// Resolve mouse wheel input before the child Scrollable applies an instant jump.
class AnimatedWheelInput extends SingleChildRenderObjectWidget {
  const AnimatedWheelInput({
    super.key,
    required this.onScroll,
    required super.child,
  });
  final ValueChanged<double> onScroll;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _WheelPointerHandler(onScroll);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) => (renderObject as _WheelPointerHandler).onScroll = onScroll;
}

class _WheelPointerHandler extends RenderProxyBox {
  _WheelPointerHandler(this.onScroll);
  ValueChanged<double> onScroll;
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    hitTestChildren(result, position: position);
    return true;
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        (_) => onScroll(event.scrollDelta.dy),
      );
    }
  }
}

/// Nearby dates in a week-aligned calendar; tapping a day selects it directly.
class WearDatePicker extends StatefulWidget {
  const WearDatePicker({
    super.key,
    required this.initialDate,
    required this.onPicked,
  });
  final DateTime initialDate;
  final Future<void> Function(DateTime) onPicked;
  @override
  State<WearDatePicker> createState() => _WearDatePickerState();
}

class _WearDatePickerState extends State<WearDatePicker> {
  static final firstDay = DateTime(2020);
  static final lastDay = DateTime(2100, 12, 31);
  static final firstMonday = firstDay.subtract(
    Duration(days: firstDay.weekday - 1),
  );
  static final weekCount =
      (lastDay.difference(firstMonday).inDays / 7).floor() + 1;
  ScrollController? controller;
  late final StreamSubscription<double> rotary;
  late DateTime month;
  double rowHeight = 40, residual = 0;
  double? target;
  int generation = 0;
  bool touching = false, dragging = false, busy = false;
  int weekOf(DateTime date) => date.difference(firstMonday).inDays ~/ 7;
  DateTime dayAt(int week, int day) =>
      firstMonday.add(Duration(days: week * 7 + day));
  @override
  void initState() {
    super.initState();
    month = DateTime(widget.initialDate.year, widget.initialDate.month);
    rotary = RotaryInput.events.listen(scroll);
  }

  void updateMonth() {
    if (!mounted || controller?.hasClients != true) return;
    final week = (controller!.offset / rowHeight).round();
    final date = dayAt(week.clamp(0, weekCount - 1), 3);
    if (date.year != month.year || date.month != month.month) {
      setState(() => month = DateTime(date.year, date.month));
    }
  }

  void scroll(double delta) {
    if (!mounted ||
        busy ||
        touching ||
        dragging ||
        ModalRoute.of(context)?.isCurrent != true ||
        controller?.hasClients != true) {
      return;
    }
    residual += delta;
    final steps = (residual / 40).truncate();
    if (steps == 0) return;
    residual -= steps * 40;
    final before = target ?? controller!.offset;
    final next = (before + steps * rowHeight).clamp(
      0.0,
      controller!.position.maxScrollExtent,
    );
    if (next == before) return;
    TouchHaptics.rotaryScroll(steps * 40, source: controller!);
    moveTo(next);
  }

  void moveTo(double offset) {
    if (busy || controller?.hasClients != true) return;
    target = offset.clamp(0.0, controller!.position.maxScrollExtent);
    final token = ++generation;
    unawaited(
      controller!
          .animateTo(
            target!,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted && generation == token) target = null;
          }),
    );
  }

  void moveMonth(int delta) {
    final date = DateTime(month.year, month.month + delta, 15);
    moveTo(weekOf(date) * rowHeight);
  }

  Future<void> pick(DateTime date) async {
    if (busy) return;
    TouchHaptics.selectionClick();
    setState(() => busy = true);
    try {
      await widget.onPicked(date);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    rotary.cancel();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final top = size.maxHeight * .12, bottom = size.maxHeight * .14;
      rowHeight = (size.maxHeight - top - bottom - 54) / 2;
      controller ??= ScrollController(
        initialScrollOffset:
            math.max(0, weekOf(widget.initialDate)) * rowHeight,
      )..addListener(updateMonth);
      final today = dayKey(chinaNow(AppClock.now(context)));
      final selected = dayKey(widget.initialDate);
      final primary = Theme.of(context).colorScheme.primary;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          size.maxWidth * .10,
          top,
          size.maxWidth * .10,
          bottom,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  IconButton(
                    tooltip: '上个月',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 36,
                    ),
                    onPressed: busy ? null : () => moveMonth(-1),
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${month.year}年${month.month}月',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '下个月',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 36,
                    ),
                    onPressed: busy ? null : () => moveMonth(1),
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 18,
              child: Row(
                children: [
                  for (final day in ['一', '二', '三', '四', '五', '六', '日'])
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            day,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Listener(
                onPointerDown: (_) {
                  touching = true;
                  generation++;
                  target = null;
                  residual = 0;
                },
                onPointerUp: (_) => touching = false,
                onPointerCancel: (_) => touching = false,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notice) {
                    if (notice is ScrollStartNotification &&
                        notice.dragDetails != null) {
                      dragging = true;
                    }
                    if (notice is ScrollEndNotification) dragging = false;
                    return false;
                  },
                  child: ListView.builder(
                    key: const ValueKey('calendar-weeks'),
                    controller: controller,
                    padding: EdgeInsets.zero,
                    itemExtent: rowHeight,
                    itemCount: weekCount,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    itemBuilder: (context, week) => Row(
                      children: List.generate(7, (column) {
                        final date = dayAt(week, column), key = dayKey(date);
                        final active = key == selected, isToday = key == today;
                        final allowed =
                            !date.isBefore(firstDay) && !date.isAfter(lastDay);
                        return Expanded(
                          child: Semantics(
                            label: '$key${isToday ? ' 今天' : ''}',
                            button: true,
                            selected: active,
                            child: SizedBox(
                              height: rowHeight,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  key: ValueKey('calendar-day-$key'),
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: !busy && allowed
                                      ? () => pick(date)
                                      : null,
                                  child: Center(
                                    child: Container(
                                      width: math.min(
                                        rowHeight - 4,
                                        size.maxWidth * .8 / 7,
                                      ),
                                      height: math.min(
                                        rowHeight - 4,
                                        size.maxWidth * .8 / 7,
                                      ),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: active
                                            ? primary
                                            : Colors.transparent,
                                        border: isToday && !active
                                            ? Border.all(color: primary)
                                            : null,
                                      ),
                                      child: Text(
                                        '${date.day}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: active || isToday
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          color: active
                                              ? AppColors.background
                                              : !allowed ||
                                                    date.month != month.month
                                              ? AppColors.muted
                                              : AppColors.text,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
