import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../models/task.dart';
import 'screen_viewport.dart';
import 'task_steps.dart';

/// The task context remains available without leaving the current focus flow.
class FocusTaskBrief extends StatefulWidget {
  const FocusTaskBrief({
    super.key,
    required this.task,
    required this.isRound,
    this.onStepChanged,
  });

  final DailyTask task;
  final bool isRound;
  final StepChange? onStepChanged;

  @override
  State<FocusTaskBrief> createState() => _FocusTaskBriefState();
}

class _FocusTaskBriefState extends State<FocusTaskBrief> {
  final expanded = <String>{};

  bool _hasText(String? value) => value?.trim().isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    if (!_hasText(widget.task.minimumGoal) &&
        !_hasText(widget.task.completionStandard)) {
      expanded.add('content');
    }
  }

  Widget _header() {
    const title = Text(
      '本次任务',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppColors.muted,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
    if (widget.isRound) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: title,
      );
    }
    return Row(
      children: [
        IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const Expanded(child: title),
        const SizedBox(width: 48),
      ],
    );
  }

  Widget _information(String id, String label, String value) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: id == 'start-action' ? AppColors.surfaceRaised : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: id == 'start-action'
          ? Border.all(color: AppColors.outline)
          : null,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          value,
          key: ValueKey('focus-brief-$id'),
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ],
    ),
  );

  List<Widget> _optional(String id, String label, String? value) {
    if (!_hasText(value)) return const [];
    final open = expanded.contains(id);
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton(
              key: ValueKey('focus-brief-$id-toggle'),
              style: TextButton.styleFrom(
                foregroundColor: open ? AppColors.text : AppColors.muted,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => setState(() {
                if (!expanded.add(id)) expanded.remove(id);
              }),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  const SizedBox(width: 8),
                  Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.faint,
                  ),
                ],
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  value!,
                  key: ValueKey('focus-brief-$id'),
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ScreenViewport(
        isRound: widget.isRound,
        child: ShapeScrollView(
          isRound: widget.isRound,
          showTime: false,
          topPadding: widget.isRound ? 18 : null,
          children: [
            _header(),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                task.title,
                key: const ValueKey('focus-brief-title'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (task.steps.isNotEmpty)
              TaskSteps(task: task, onChanged: widget.onStepChanged),
            if (_hasText(task.startAction))
              _information('start-action', '启动动作', task.startAction!),
            if (_hasText(task.minimumGoal))
              _information('minimum-goal', '最低目标', task.minimumGoal!),
            if (_hasText(task.completionStandard))
              _information(
                'completion-standard',
                '完成标准',
                task.completionStandard!,
              ),
            if (task.estimatedMinutes != null)
              _information('estimate', '预估时长', '${task.estimatedMinutes} 分钟'),
            ..._optional('task-value', '任务价值', task.taskValue),
            ..._optional('content', '任务内容', task.content),
            ..._optional('tutorial', '技巧与教程', task.tutorial),
          ],
        ),
      ),
    );
  }
}
