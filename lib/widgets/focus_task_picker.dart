import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../controllers/app_controller.dart';
import '../models/task.dart';
import 'screen_viewport.dart';
import 'wear_controls.dart';

/// Browses both spaces without changing the task list's selected space.
class FocusTaskPicker extends StatefulWidget {
  const FocusTaskPicker({
    super.key,
    required this.controller,
    required this.isRound,
    required this.onSelected,
    this.title = '关联任务',
    this.pendingOnly = true,
    this.initialSpace,
    this.selectedTaskId,
  });

  final AppController controller;
  final bool isRound, pendingOnly;
  final String title;
  final String? initialSpace, selectedTaskId;
  final ValueChanged<DailyTask> onSelected;

  @override
  State<FocusTaskPicker> createState() => _FocusTaskPickerState();
}

class _FocusTaskPickerState extends State<FocusTaskPicker> {
  late String space;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSpace ?? widget.controller.space;
    space = initial == 'work' ? 'work' : 'life';
  }

  Widget _header() {
    final label = Text(
      widget.title,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
    if (widget.isRound) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: label,
      );
    }
    return Row(
      children: [
        IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        Expanded(child: label),
      ],
    );
  }

  Widget _spaces() => WearSpaceSelector(
    space: space,
    keyPrefix: 'focus-picker-space',
    onSelected: (value) => setState(() => space = value),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.muted, fontSize: 11),
    ),
  );

  Widget _task(DailyTask task) {
    final selected = widget.selectedTaskId == task.id;
    final metadata = [
      if (task.estimatedMinutes != null) '约 ${task.estimatedMinutes} 分钟',
      '${widget.controller.focusCount(task)} 个番茄钟',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        child: Material(
          color: task.completed
              ? AppColors.background
              : selected
              ? AppColors.surfaceRaised
              : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(
              color: selected ? AppColors.muted : Colors.transparent,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('focus-picker-task-${task.id}'),
            onTap: () => widget.onSelected(task),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: task.completed
                                  ? AppColors.muted
                                  : AppColors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            metadata,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected || task.completed) ...[
                      const SizedBox(width: 6),
                      Icon(
                        selected
                            ? Icons.check_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 18,
                        color: AppColors.muted,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final tasks = widget.controller.visibleTasksForSpace(space);
      final pending = tasks.where((task) => !task.completed).toList();
      final completed = tasks.where((task) => task.completed).toList();
      final waiting = space == 'work'
          ? pending.where((task) => task.waiting).toList()
          : <DailyTask>[];
      final ready = space == 'work'
          ? pending.where((task) => !task.waiting).toList()
          : pending;
      final empty =
          pending.isEmpty && (widget.pendingOnly || completed.isEmpty);
      return Scaffold(
        backgroundColor: AppColors.background,
        body: ScreenViewport(
          isRound: widget.isRound,
          child: ShapeScrollView(
            key: ValueKey('focus-picker-list-$space'),
            storageKey: PageStorageKey('focus-picker-$space'),
            isRound: widget.isRound,
            showTime: false,
            topPadding: widget.isRound ? 18 : null,
            children: [
              _header(),
              const SizedBox(height: 2),
              _spaces(),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  space == 'life' ? widget.controller.date : '本周任务池',
                  key: const ValueKey('focus-picker-period'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('focus-picker-free'),
                onPressed: () => widget.onSelected(
                  DailyTask(
                    id: '',
                    templateId: '',
                    date: widget.controller.date,
                    title: '自由专注',
                    content: '',
                    space: space,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.text,
                  textStyle: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 12,
                  ),
                ),
                icon: Icon(
                  widget.selectedTaskId == '' &&
                          space ==
                              (widget.initialSpace ?? widget.controller.space)
                      ? Icons.check_rounded
                      : Icons.timer_outlined,
                  size: 16,
                ),
                label: Text(widget.pendingOnly ? '自由专注' : '不关联任务'),
              ),
              if (empty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  child: Text(
                    widget.pendingOnly ? '暂无待办，也可以自由专注' : '暂无任务，也可以自由专注',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              for (final task in ready) _task(task),
              if (waiting.isNotEmpty) _label('等待中'),
              for (final task in waiting) _task(task),
              if (!widget.pendingOnly && completed.isNotEmpty) ...[
                _label(space == 'work' ? '本周已完成' : '已完成'),
                for (final task in completed) _task(task),
              ],
            ],
          ),
        ),
      );
    },
  );
}
