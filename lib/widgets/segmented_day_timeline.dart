import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../models/task.dart';
import '../platform/rotary_input.dart';
import '../platform/touch_haptics.dart';

/// A single proportional 24-hour track; crown selects whole sessions.
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
      if (residual.sign != delta.sign) residual = 0;
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
    return LayoutBuilder(
      builder: (context, size) => Semantics(
        label: '全天专注时间轴，00至24时',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (event) {
            final minute =
                (event.localPosition.dx / math.max(1, size.maxWidth)).clamp(
                  0,
                  1,
                ) *
                1440;
            int? best;
            double distance = double.infinity;
            for (var i = 0; i < spans.length; i++) {
              final span = spans[i];

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
            painter: _SegmentPainter(
              spans,
              widget.selected,
              Theme.of(context).textTheme.bodySmall!
                  .copyWith(fontSize: 8, color: AppColors.faint),
            ),
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
  const _SegmentPainter(this.spans, this.selected, this.labelStyle);
  final List<DayTimelineSpan> spans;
  final int selected;
  final TextStyle labelStyle;
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * .42;
    const height = 9.0;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y, size.width, height),
      const Radius.circular(5),
    );
    canvas.drawRRect(track, Paint()..color = AppColors.overlay);
    canvas.save();
    canvas.clipRRect(track);
    for (var i = 0; i < spans.length; i++) {
      final span = spans[i];
      final x = span.start / 1440 * size.width;
      final width = math.max(.8, (span.end - span.start) / 1440 * size.width);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, width, height),
          const Radius.circular(3),
        ),
        Paint()..color = span.color.withValues(alpha: i == selected ? 1 : .65),
      );
    }
    canvas.restore();
    if (selected >= 0 && selected < spans.length) {
      final span = spans[selected];
      final x = (span.start + span.end) / 2 / 1440 * size.width;
      canvas.drawCircle(Offset(x, y - 4), 2, Paint()..color = AppColors.text);
    }
    for (final hour in [0, 6, 12, 18, 24]) {
      final text = TextPainter(
        text: TextSpan(
          text: hour.toString().padLeft(2, '0'),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (hour / 24 * size.width - text.width / 2).clamp(
        0.0,
        math.max(0.0, size.width - text.width),
      );
      text.paint(canvas, Offset(x.toDouble(), y + height + 3));
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentPainter old) => true;
}
