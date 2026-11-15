import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../models/task.dart';
import 'task_steps.dart';

/// Inline task details shown on the active focus page without navigation.
class FocusTaskPanel extends StatelessWidget {
  const FocusTaskPanel({super.key, required this.task, this.onStepChanged});

  final DailyTask task;
  final StepChange? onStepChanged;

  bool _hasText(String? value) => value?.trim().isNotEmpty == true;

  Widget _section(String label, String value, {String? keySuffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            key: keySuffix == null ? null : ValueKey('focus-panel-$keySuffix'),
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections() {
    final sections = <Widget>[];
    if (task.steps.isNotEmpty) {
      sections.add(TaskSteps(task: task, onChanged: onStepChanged));
    }
    if (_hasText(task.startAction)) {
      sections.add(
        _section('启动动作', task.startAction!, keySuffix: 'start-action'),
      );
    }
    if (_hasText(task.minimumGoal)) {
      sections.add(
        _section('最低目标', task.minimumGoal!, keySuffix: 'minimum-goal'),
      );
    }
    if (_hasText(task.completionStandard)) {
      sections.add(
        _section(
          '完成标准',
          task.completionStandard!,
          keySuffix: 'completion-standard',
        ),
      );
    }
    if (_hasText(task.taskValue)) {
      sections.add(_section('任务价值', task.taskValue!, keySuffix: 'task-value'));
    }
    if (_hasText(task.content)) {
      sections.add(_section('任务内容', task.content, keySuffix: 'content'));
    }
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    if (sections.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.overlay,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: sections,
        ),
      ),
    );
  }
}
