import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../models/task.dart';

typedef StepChange = Future<void> Function(TaskStep step, bool completed);

/// A task's execution progress is independent of its timer and completion.
class TaskSteps extends StatelessWidget {
  const TaskSteps({super.key, required this.task, this.onChanged});

  final DailyTask task;
  final StepChange? onChanged;

  @override
  Widget build(BuildContext context) {
    if (task.steps.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            task.currentStep == null
                ? '步骤已完成 · ${task.steps.length}/${task.steps.length}'
                : '任务步骤 · ${task.completedStepCount}/${task.steps.length}',
            key: const ValueKey('task-steps-progress'),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
        for (final step in task.steps)
          Padding(
            key: ValueKey('task-step-${step.id}'),
            padding: const EdgeInsets.only(bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 10, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StepToggle(step: step, onChanged: onChanged),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(
                          step.title,
                          style: TextStyle(
                            color: step.completed
                                ? AppColors.muted
                                : AppColors.text,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Shows only the next unfinished step where watch space is limited.
class CurrentTaskStep extends StatelessWidget {
  const CurrentTaskStep({
    super.key,
    required this.task,
    required this.onOpen,
    this.onChanged,
  });

  final DailyTask task;
  final VoidCallback? onOpen;
  final StepChange? onChanged;

  @override
  Widget build(BuildContext context) {
    if (task.steps.isEmpty) return const SizedBox.shrink();
    final step = task.currentStep;
    if (step == null) {
      return TextButton(
        key: const ValueKey('current-task-step'),
        onPressed: onOpen,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.muted,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(vertical: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('步骤已完成', style: TextStyle(fontSize: 11, height: 1.2)),
      );
    }
    return Row(
      key: const ValueKey('current-task-step'),
      children: [
        if (onChanged != null)
          _StepToggle(key: ValueKey(step.id), step: step, onChanged: onChanged),
        Expanded(
          child: TextButton(
            onPressed: onOpen,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.text,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '第 ${task.steps.indexOf(step) + 1}/${task.steps.length} 步',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 9,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.title,
                  key: const ValueKey('current-task-step-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, height: 1.15),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepToggle extends StatefulWidget {
  const _StepToggle({super.key, required this.step, required this.onChanged});

  final TaskStep step;
  final StepChange? onChanged;

  @override
  State<_StepToggle> createState() => _StepToggleState();
}

class _StepToggleState extends State<_StepToggle> {
  bool saving = false;

  Future<void> change() async {
    if (saving || widget.onChanged == null) return;
    setState(() => saving = true);
    try {
      await widget.onChanged!(widget.step, !widget.step.completed);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('步骤暂时无法保存，请重试'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: ValueKey('task-step-toggle-${widget.step.id}'),
    tooltip: '${widget.step.completed ? '撤销步骤' : '完成步骤'}：${widget.step.title}',
    onPressed: saving || widget.onChanged == null ? null : change,
    style: IconButton.styleFrom(
      foregroundColor: AppColors.muted,
      disabledForegroundColor: AppColors.faint,
      minimumSize: const Size(32, 32),
      padding: const EdgeInsets.all(5),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: Icon(
      widget.step.completed
          ? Icons.check_circle_rounded
          : Icons.radio_button_unchecked_rounded,
      size: 22,
    ),
  );
}
