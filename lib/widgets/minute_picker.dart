import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/rotary_input.dart';
import '../platform/touch_haptics.dart';

/// One owner for touch, encoder target, and snapped minute selection.
class MinutePicker extends StatefulWidget {
  const MinutePicker({
    super.key,
    required this.initial,
    required this.onChanged,
    this.timeOfDay = false,
  });
  final int initial;
  final bool timeOfDay;
  final ValueChanged<int> onChanged;
  @override
  State<MinutePicker> createState() => _MinutePickerState();
}

class _MinutePickerState extends State<MinutePicker> {
  late final FixedExtentScrollController controller;
  late final StreamSubscription<double> rotary;
  late int target;
  double remainder = 0;
  bool touching = false, fromCrown = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    target = (widget.initial ~/ 5 - (widget.timeOfDay ? 0 : 1)).clamp(
      0,
      widget.timeOfDay ? 287 : 35,
    );
    controller = FixedExtentScrollController(initialItem: target);
    rotary = RotaryInput.events.listen(scroll);
  }

  void scroll(double delta) {
    if (!mounted ||
        touching ||
        ModalRoute.of(context)?.isCurrent != true ||
        !controller.hasClients) {
      return;
    }
    remainder += delta;
    final steps = (remainder / 40).truncate();
    if (steps == 0) return;
    remainder -= steps * 40;
    final next = (target + steps).clamp(0, widget.timeOfDay ? 287 : 35);
    if (next == target) return;
    target = next;
    widget.onChanged((next + (widget.timeOfDay ? 0 : 1)) * 5);
    TouchHaptics.rotaryTick();
    fromCrown = true;
    final current = ++generation;
    controller
        .animateToItem(
          next,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (mounted && generation == current) fromCrown = false;
        });
  }

  @override
  void dispose() {
    rotary.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      touching = true;
      fromCrown = false;
      generation++;
      remainder = 0;
    },
    onPointerUp: (_) => touching = false,
    onPointerCancel: (_) => touching = false,
    child: ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 42,
      diameterRatio: 1.7,
      perspective: .003,
      overAndUnderCenterOpacity: .28,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (i) {
        if (!fromCrown) {
          target = i;
          widget.onChanged((i + (widget.timeOfDay ? 0 : 1)) * 5);
          TouchHaptics.rotaryTick();
        }
      },
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: widget.timeOfDay ? 288 : 36,
        builder: (context, i) => Center(
          child: Text(
            widget.timeOfDay
                ? '${(i * 5 ~/ 60).toString().padLeft(2, '0')}:${(i * 5 % 60).toString().padLeft(2, '0')}'
                : '${(i + 1) * 5}',
            style: const TextStyle(
              fontSize: 38,
              height: 1,
              leadingDistribution: TextLeadingDistribution.even,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    ),
  );
}
