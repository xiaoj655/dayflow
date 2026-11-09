import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../models/task.dart';
import '../platform/rotary_input.dart';
import '../platform/touch_haptics.dart';

/// Three six-hour rows; include the fourth only when midnight has records.
/// Both painting and hit testing use these exact, proportional session spans.
class SegmentedDayTimeline extends StatefulWidget {
  const SegmentedDayTimeline({
    super.key,
    required this.rows,
    required this.selected,
    required this.onSelected,
  });
  final List<Map<String, dynamic>> rows;
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  State<SegmentedDayTimeline> createState() => _SegmentedDayTimelineState();
}

class _SegmentedDayTimelineState extends State<SegmentedDayTimeline> {
  late final StreamSubscription<double> rotary;
  double residual = 0;
  @override
  void initState() {
    super.initState();
    rotary = RotaryInput.events.listen((delta) {
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true ||
          widget.rows.isEmpty) {
        return;
      }
      residual += delta;
      final steps = (residual / 40).truncate();
      if (steps == 0) return;
      residual -= steps * 40;
      final next = (widget.selected + steps).clamp(0, widget.rows.length - 1);
      if (next != widget.selected) {
        TouchHaptics.rotaryTick();
        widget.onSelected(next);
      }
    });
  }

  @override
  void dispose() {
    rotary.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spans = widget.rows.map(DayTimelineSpan.fromRow).toList();
    final firstHour = spans.any((span) => span.start < 360 && span.end > 0)
        ? 0
        : 6;
    final count = (24 - firstHour) ~/ 6;
    return LayoutBuilder(
      builder: (context, size) => Semantics(
        label: '全天专注时间轴，每行六小时，${firstHour == 0 ? '包含凌晨' : '凌晨无记录'}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (event) {
            final row = (event.localPosition.dy / size.maxHeight * count)
                .floor()
                .clamp(0, count - 1);
            final from = (firstHour + row * 6) * 60.0, to = from + 360;
            final minute =
                from +
                ((event.localPosition.dx - 35) /
                            math.max(1, size.maxWidth - 39))
                        .clamp(0, 1) *
                    360;
            int? best;
            double distance = double.infinity;
            for (var i = 0; i < spans.length; i++) {
              final span = spans[i];
              if (span.end <= from || span.start >= to) continue;
              final d = minute >= span.start && minute <= span.end
                  ? 0.0
                  : math.min(
                      (span.start - minute).abs(),
                      (span.end - minute).abs(),
                    );
              if (d < distance) {
                best = i;
                distance = d;
              }
            }
            if (best != null) {
              TouchHaptics.selectionClick();
              widget.onSelected(best);
            }
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: _SegmentPainter(spans, firstHour, widget.selected),
          ),
        ),
      ),
    );
  }
}

class DayTimelineSpan {
  const DayTimelineSpan(this.start, this.end, this.color);
  final double start, end;
  final Color color;
  factory DayTimelineSpan.fromRow(Map<String, dynamic> row) {
    DateTime parse(dynamic value) {
      final raw = value.toString();
      return chinaNow(DateTime.parse(raw.endsWith('Z') ? raw : '${raw}Z'));
    }

    final start = parse(row['started_at']), end = parse(row['ended_at']);
    double minutes(DateTime d) => d.hour * 60 + d.minute + d.second / 60;
    return DayTimelineSpan(
      minutes(start),
      dayKey(start) == dayKey(end) ? minutes(end) : 1440,
      row['kind'] == 'rest'
          ? AppColors.timelineRest
          : row['space'] == 'work'
          ? AppColors.timelineWork
          : AppColors.timelineLife,
    );
  }
}

class _SegmentPainter extends CustomPainter {
  const _SegmentPainter(this.spans, this.firstHour, this.selected);
  final List<DayTimelineSpan> spans;
  final int firstHour, selected;
  @override
  void paint(Canvas canvas, Size size) {
    final count = (24 - firstHour) ~/ 6, rowHeight = size.height / count;
    const left = 35.0;
    final width = math.max(1.0, size.width - left - 4);
    for (var row = 0; row < count; row++) {
      final hour = firstHour + row * 6, from = hour * 60.0, to = from + 360;
      final y = (row + .5) * rowHeight;
      final height = math.min(14.0, rowHeight * .5);
      final label = TextPainter(
        text: TextSpan(
          text:
              '${hour.toString().padLeft(2, '0')}–${(hour + 6).toString().padLeft(2, '0')}',
          style: const TextStyle(
            fontSize: 10,
            height: 1,
            color: AppColors.muted,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 33);
      label.paint(canvas, Offset(0, y - label.height / 2));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, y - height / 2, width, height),
          const Radius.circular(2),
        ),
        Paint()..color = AppColors.surface,
      );
      for (var h = 1; h < 6; h++) {
        final x = left + width * h / 6;
        canvas.drawLine(
          Offset(x, y + height / 2 + 2),
          Offset(x, y + height / 2 + 4),
          Paint()
            ..color = AppColors.faint
            ..strokeWidth = 1,
        );
      }
      for (var i = 0; i < spans.length; i++) {
        final span = spans[i];
        final a = math.max(from, span.start), b = math.min(to, span.end);
        if (b <= a) continue;
        final x = left + (a - from) / 360 * width, w = (b - a) / 360 * width;
        canvas.drawRect(
          Rect.fromLTWH(x, y - height / 2, w, height),
          Paint()..color = span.color.withValues(alpha: i == selected ? 1 : .8),
        );
        if (i == selected) {
          canvas.drawCircle(
            Offset(x + w / 2, y - height / 2 - 3),
            1.5,
            Paint()..color = AppColors.text,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentPainter old) => true;
}
