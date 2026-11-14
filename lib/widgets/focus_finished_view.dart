import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';
import 'screen_viewport.dart';

/// Keeps the next task and the current task's completion within easy reach.
class FocusFinishedView extends StatelessWidget {
  const FocusFinishedView({
    super.key,
    required this.isRound,
    required this.taskTitle,
    required this.minutes,
    required this.isRest,
    required this.busy,
    required this.onContinue,
    required this.onChangeTask,
    required this.onReturn,
    this.onRest,
    this.onTaskCompletion,
    this.taskCompleted = false,
    this.interrupted = false,
    this.actualSeconds,
  });

  final bool isRound, isRest, busy, taskCompleted;
  final bool interrupted;
  final int? actualSeconds;
  final String taskTitle;
  final int minutes;
  final VoidCallback onContinue, onChangeTask, onReturn;
  final VoidCallback? onRest, onTaskCompletion;

  Widget _header() => Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        key: const ValueKey('focus-finished-return'),
        tooltip: '返回任务',
        onPressed: busy ? null : onReturn,
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(24, 24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: AppColors.muted,
        ),
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
      ),
      const SizedBox(width: 3),
      Flexible(
        child: Text(
          isRest ? '休息结束' : (interrupted ? '提前结束' : '专注完成'),
          key: const ValueKey('focus-finished-title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            height: 1.1,
          ),
        ),
      ),
    ],
  );

  Widget _task({required bool largeText}) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (onTaskCompletion != null) ...[
        IconButton(
          key: const ValueKey('focus-finished-task-completion'),
          tooltip: taskCompleted ? '恢复待办' : '标记任务完成',
          isSelected: taskCompleted,
          onPressed: busy ? null : onTaskCompletion,
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size(largeText ? 36 : 32, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(
            taskCompleted
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 26,
            color: AppColors.muted,
          ),
        ),
        const SizedBox(width: 4),
      ],
      Flexible(
        child: Text(
          taskTitle,
          key: const ValueKey('focus-finished-task'),
          textAlign: onTaskCompletion == null
              ? TextAlign.center
              : TextAlign.start,
          maxLines: largeText ? null : 2,
          overflow: largeText ? null : TextOverflow.ellipsis,
          style: TextStyle(
            color: taskCompleted ? AppColors.muted : AppColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ),
    ],
  );

  Widget _minutes() {
    final seconds = actualSeconds ?? minutes * 60;
    final duration = '${seconds ~/ 60}分${seconds % 60}秒';
    final label = interrupted
        ? (!isRest && seconds < 180 ? '$duration · 未记录' : '实际 $duration')
        : '$minutes 分钟';
    return Text(
      label,
      key: const ValueKey('focus-finished-minutes'),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppColors.muted,
        fontSize: interrupted ? 13 : 15,
        height: 1.1,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _secondaryButton({required bool rest, required bool largeText}) =>
      FilledButton.tonal(
        key: ValueKey(rest ? 'focus-finished-rest' : 'focus-finished-continue'),
        onPressed: busy ? null : (rest ? onRest : onContinue),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.text,
          disabledBackgroundColor: AppColors.surface,
          disabledForegroundColor: AppColors.faint,
          minimumSize: Size.zero,
          padding: EdgeInsets.symmetric(
            horizontal: 6,
            vertical: largeText ? 10 : 0,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            height: 1,
          ),
        ),
        child: Text(rest ? '休息一下' : '继续专注', textAlign: TextAlign.center),
      );

  Widget _changeTask({required bool largeText}) => FilledButton(
    key: const ValueKey('focus-finished-change-task'),
    onPressed: busy ? null : onChangeTask,
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.background,
      disabledBackgroundColor: AppColors.overlay,
      disabledForegroundColor: AppColors.faint,
      minimumSize: Size.zero,
      padding: EdgeInsets.symmetric(
        horizontal: 6,
        vertical: largeText ? 12 : 0,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const StadiumBorder(),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.1,
      ),
    ),
    child: const Text('换个任务', textAlign: TextAlign.center),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: ScreenViewport(
      isRound: isRound,
      child: LayoutBuilder(
        builder: (context, box) {
          final side = math.min(box.biggest.shortestSide, 360.0);
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 16;
          final canRest = !isRest && onRest != null;
          if (largeText) {
            Widget centered(Widget child, {double width = .66}) => Center(
              child: SizedBox(width: side * width, child: child),
            );
            return ShapeScrollView(
              isRound: isRound,
              showTime: false,
              topPadding: side * .16,
              children: [
                centered(_header()),
                const SizedBox(height: 10),
                centered(_task(largeText: true), width: .72),
                const SizedBox(height: 6),
                centered(_minutes()),
                const SizedBox(height: 12),
                centered(_secondaryButton(rest: false, largeText: true)),
                if (canRest) ...[
                  const SizedBox(height: 8),
                  centered(_secondaryButton(rest: true, largeText: true)),
                ],
                const SizedBox(height: 10),
                centered(_changeTask(largeText: true)),
              ],
            );
          }
          final scale = side / 192;
          return Center(
            child: SizedBox.square(
              dimension: side,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  side * .14,
                  side * .085,
                  side * .14,
                  side * .12,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 24 * scale,
                      child: Center(child: _header()),
                    ),
                    SizedBox(height: 2 * scale),
                    SizedBox(
                      height: 36 * scale,
                      child: _task(largeText: false),
                    ),
                    SizedBox(
                      height: 18 * scale,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _minutes(),
                        ),
                      ),
                    ),
                    SizedBox(height: 4 * scale),
                    SizedBox(
                      height: 30 * scale,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _secondaryButton(
                              rest: false,
                              largeText: false,
                            ),
                          ),
                          if (canRest) ...[
                            SizedBox(width: 6 * scale),
                            Expanded(
                              child: _secondaryButton(
                                rest: true,
                                largeText: false,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: 4 * scale),
                    SizedBox(
                      width: side * .60,
                      height: 34 * scale,
                      child: _changeTask(largeText: false),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
