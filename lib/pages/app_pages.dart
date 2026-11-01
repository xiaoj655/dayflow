import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../models/task.dart';
import '../platform/rotary_input.dart';
import '../platform/touch_haptics.dart';
import '../widgets/screen_viewport.dart';
import '../widgets/wear_controls.dart';

// sRGB conversion of oklch(71.2% 0.194 13.428).
const accent = Color(0xFFFF637E);
const surface = Color(0xFF1C1C1E);
const muted = Color(0xFF98989D);

Route<T> appRoute<T>(BuildContext context, {required WidgetBuilder builder}) =>
    ScreenShape.of(context)
    ? WearPageRoute<T>(builder: builder)
    : MaterialPageRoute<T>(builder: builder);

Future<T?> appDialog<T>(
  BuildContext context, {
  String? title,
  String? message,
  required List<Widget> Function(BuildContext dialog) actions,
}) {
  if (!ScreenShape.of(context)) {
    return showDialog<T>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: title == null ? null : Text(title),
        content: message == null ? null : Text(message),
        scrollable: true,
        actions: actions(dialog),
      ),
    );
  }
  return Navigator.push<T>(
    context,
    WearPageRoute<T>(
      builder: (dialog) => Scaffold(
        body: ScreenViewport(
          isRound: true,
          child: ShapeScrollView(
            isRound: true,
            showTime: false,
            children: [
              if (title != null)
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Text(message, textAlign: TextAlign.center),
                ),
              const SizedBox(height: 12),
              ...actions(dialog),
            ],
          ),
        ),
      ),
    ),
  );
}

void showNotice(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  final round = ScreenShape.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        action: action,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: round
            ? EdgeInsets.fromLTRB(
                32,
                0,
                32,
                MediaQuery.sizeOf(context).shortestSide * .20,
              )
            : null,
        shape: const StadiumBorder(),
      ),
    );
}

Future<void> explainError(BuildContext context, String text) async {
  if (!text.contains('权限') && !text.contains('设置') && !text.contains('授权')) {
    showNotice(context, text);
    return;
  }
  await appDialog<void>(
    context,
    title: '需要系统授权',
    message: text,
    actions: (dialog) => [
      FilledButton(
        onPressed: () => Navigator.pop(dialog),
        child: const Text('知道了'),
      ),
    ],
  );
}

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.isRound,
    required this.children,
    this.storageKey,
    this.enableRotary = true,
    this.showTime = true,
    this.bottomAction,
    this.topPadding,
  });
  final double? topPadding;
  final bool showTime;
  final Widget? bottomAction;
  final bool enableRotary;
  final bool isRound;
  final List<Widget> children;
  final PageStorageKey<String>? storageKey;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ScreenViewport(
      isRound: isRound,
      child: Stack(
        children: [
          ShapeScrollView(
            isRound: isRound,
            storageKey: storageKey,
            enableRotary: enableRotary,
            showTime: showTime,
            footerInset: bottomAction == null ? 0 : 64,
            topPadding: topPadding,
            children: children,
          ),
          if (bottomAction != null)
            Positioned(
              left: isRound ? 0 : 16,
              right: isRound ? 0 : 16,
              bottom: isRound ? 0 : 16,
              child: bottomAction!,
            ),
        ],
      ),
    ),
  );
}

Widget backHeader(BuildContext context, String label) {
  if (ScreenShape.of(context)) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: muted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
  return Row(
    children: [
      IconButton(
        tooltip: '返回',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      ),
    ],
  );
}

class TaskListPage extends StatefulWidget {
  const TaskListPage({
    super.key,
    required this.controller,
    required this.isRound,
  });
  final AppController controller;
  final bool isRound;

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  AppController get controller => widget.controller;
  bool get isRound => widget.isRound;
  double _swipeDistance = 0;

  void _endDaySwipe(DragEndDetails details) {
    if (ModalRoute.of(context)?.isCurrent != true || controller.initializing) {
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final longSwipe = _swipeDistance.abs() >= (width * .18).clamp(32, 72);
    final fastSwipe =
        _swipeDistance.abs() >= 12 &&
        velocity.abs() >= 450 &&
        velocity.sign == _swipeDistance.sign;
    if (!longSwipe && !fastSwipe) return;
    final date = DateTime.parse(controller.date);
    final days = _swipeDistance < 0 ? 1 : -1;
    unawaited(
      controller.selectDate(DateTime(date.year, date.month, date.day + days)),
    );
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.push(context, appRoute<void>(context, builder: (_) => page));
  void _focus(BuildContext context) {
    final session = controller.focus;
    if (session != null) {
      _open(context, FocusPage(controller: controller, isRound: isRound));
    } else if (controller.tasks.isNotEmpty) {
      _open(
        context,
        FocusSetupPage(
          controller: controller,
          isRound: isRound,
          initialTask: controller.pending.firstOrNull ?? controller.tasks.first,
          allowTaskSelection: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragStart: (_) => _swipeDistance = 0,
    onHorizontalDragUpdate: (details) => _swipeDistance += details.delta.dx,
    onHorizontalDragEnd: _endDaySwipe,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final dateLabel = taskDateLabel(controller.date, controller.today);
        return AppPage(
          isRound: isRound,
          topPadding: isRound
              ? MediaQuery.sizeOf(context).shortestSide * .12
              : null,
          storageKey: PageStorageKey('daily-tasks-${controller.date}'),
          children: [
            Center(
              child: TextButton.icon(
                key: const ValueKey('task-date-selector'),
                style: TextButton.styleFrom(
                  foregroundColor: isRound ? muted : Colors.white,
                  minimumSize: isRound ? const Size(48, 28) : null,
                  padding: isRound
                      ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
                      : null,
                  tapTargetSize: isRound
                      ? MaterialTapTargetSize.shrinkWrap
                      : null,
                ),
                icon: Icon(
                  Icons.calendar_today_rounded,
                  size: isRound ? 12 : 16,
                ),
                label: Text(
                  dateLabel == controller.date.substring(5)
                      ? controller.date
                      : '$dateLabel · ${controller.date.substring(5)}',
                  style: TextStyle(
                    fontSize: isRound ? 12 : 16,
                    fontWeight: isRound ? FontWeight.w500 : FontWeight.w600,
                  ),
                ),
                onPressed: () async {
                  if (isRound) {
                    _open(
                      context,
                      TaskDatePage(controller: controller, isRound: true),
                    );
                  } else {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.parse(controller.date),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) await controller.selectDate(date);
                  }
                },
              ),
            ),
            if (controller.date != controller.today)
              Center(
                child: TextButton(
                  onPressed: () =>
                      controller.selectDate(DateTime.parse(controller.today)),
                  child: const Text('回到今天'),
                ),
              ),
            if (!isRound)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        _open(context, TaskEditorPage(controller: controller)),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('添加任务'),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _open(context, HistoryPage(controller: controller)),
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('专注记录'),
                  ),
                ],
              ),
            SizedBox(height: isRound ? 6 : 12),
            if (controller.focus != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    backgroundColor: accent.withValues(alpha: .16),
                    foregroundColor: accent,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => _focus(context),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          controller.focus!.finished
                              ? '本次专注已结束'
                              : controller.focus!.taskTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        controller.focus!.finished
                            ? '查看'
                            : timerText(controller.focus!.remainingSeconds),
                      ),
                    ],
                  ),
                ),
              ),
            if ((controller.initializing || controller.loading) &&
                controller.tasks.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (!controller.initializing &&
                !controller.loading &&
                controller.tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    controller.offline
                        ? '暂时无法同步'
                        : '${taskDateLabel(controller.date, controller.today)}没有任务',
                    style: const TextStyle(color: muted),
                  ),
                ),
              ),
            for (final task in controller.pending)
              TaskTile(
                task: task,
                onToggle: () async {
                  await controller.toggle(task);
                  TouchHaptics.selectionClick();
                  if (context.mounted) {
                    showNotice(
                      context,
                      task.completed ? '已恢复待办' : '已完成',
                      action: SnackBarAction(
                        label: '撤销',
                        onPressed: () {
                          final current = controller.tasks
                              .where((item) => item.id == task.id)
                              .firstOrNull;
                          if (current != null &&
                              current.completed != task.completed) {
                            controller.toggle(current);
                          }
                        },
                      ),
                    );
                  }
                },
                onTap: () => _open(
                  context,
                  TaskDetailPage(
                    controller: controller,
                    task: task,
                    isRound: isRound,
                  ),
                ),
              ),
            if (controller.completed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 0, 10),
                child: Text(
                  '已完成 · ${controller.completed.length}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            for (final task in controller.completed)
              TaskTile(
                task: task,
                onToggle: () async {
                  await controller.toggle(task);
                  TouchHaptics.selectionClick();
                  if (context.mounted) {
                    showNotice(
                      context,
                      task.completed ? '已恢复待办' : '已完成',
                      action: SnackBarAction(
                        label: '撤销',
                        onPressed: () {
                          final current = controller.tasks
                              .where((item) => item.id == task.id)
                              .firstOrNull;
                          if (current != null &&
                              current.completed != task.completed) {
                            controller.toggle(current);
                          }
                        },
                      ),
                    );
                  }
                },
                onTap: () => _open(
                  context,
                  TaskDetailPage(
                    controller: controller,
                    task: task,
                    isRound: isRound,
                  ),
                ),
              ),
            if (controller.focus == null && controller.tasks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Tooltip(
                  message: '专注',
                  child: FilledButton.tonalIcon(
                    onPressed: () => _focus(context),
                    icon: const Icon(Icons.timer_outlined, size: 20),
                    label: const Text('选择任务专注'),
                  ),
                ),
              ),
            if (controller.offline)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    const Text(
                      '离线 · 更改会在联网后同步',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    TextButton.icon(
                      onPressed: controller.loading ? null : controller.refresh,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('重新同步'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

String taskDateLabel(String date, String today) {
  final delta = DateTime.parse(date).difference(DateTime.parse(today)).inDays;
  return switch (delta) {
    0 => '今天',
    -1 => '昨天',
    1 => '明天',
    2 => '后天',
    _ => date.substring(5),
  };
}

class TaskDatePage extends StatefulWidget {
  const TaskDatePage({
    super.key,
    required this.controller,
    required this.isRound,
  });
  final AppController controller;
  final bool isRound;
  @override
  State<TaskDatePage> createState() => _TaskDatePageState();
}

class _TaskDatePageState extends State<TaskDatePage> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ScreenViewport(
      isRound: widget.isRound,
      child: WearDatePicker(
        initialDate: DateTime.parse(widget.controller.date),
        onPicked: (date) async {
          unawaited(widget.controller.selectDate(date));
          if (context.mounted) Navigator.pop(context);
        },
      ),
    ),
  );
}

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onTap,
    this.onToggle,
  });
  final DailyTask task;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (task.estimatedMinutes != null) '约 ${task.estimatedMinutes} 分钟',
      if (task.carriedFromDate != null)
        '来自 ${task.carriedFromDate!.substring(5)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: task.completed ? const Color(0xFF151518) : surface,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 4, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: task.completed ? muted : Colors.white,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              subtitle,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (onToggle != null)
              IconButton(
                tooltip: task.completed
                    ? '恢复待办${task.title}'
                    : '完成${task.title}',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onToggle,
                icon: Icon(
                  task.completed
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: task.completed ? muted : accent,
                  size: 24,
                ),
              ),
            if (onToggle == null)
              IconButton(
                onPressed: onTap,
                tooltip: '查看${task.title}',
                icon: const Icon(Icons.chevron_right_rounded, color: muted),
              ),
          ],
        ),
      ),
    );
  }
}

Widget readableAction(BuildContext context, String value, Widget child) =>
    Semantics(
      button: true,
      label: '查看完整启动动作',
      child: InkWell(
        onTap: () => appDialog<void>(
          context,
          title: '启动动作',
          message: value,
          actions: (dialog) => [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('返回'),
            ),
          ],
        ),
        child: child,
      ),
    );

Widget taskInformation(String label, String? value) {
  if (value?.trim().isNotEmpty != true) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label, style: const TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 6),
        ],
        Text(value!, style: const TextStyle(fontSize: 15, height: 1.45)),
      ],
    ),
  );
}

class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage({
    super.key,
    required this.controller,
    required this.task,
    required this.isRound,
  });
  final AppController controller;
  final DailyTask task;
  final bool isRound;
  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  final expanded = <String>{};
  bool adding = false;
  @override
  void initState() {
    super.initState();
    if (widget.task.minimumGoal?.trim().isNotEmpty != true &&
        widget.task.completionStandard?.trim().isNotEmpty != true) {
      expanded.add('任务内容');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final task =
          widget.controller.tasks
              .where((task) => task.id == widget.task.id)
              .firstOrNull ??
          widget.task;
      Widget focusButton(String position) => KeyedSubtree(
        key: ValueKey('detail-focus-$position'),
        child: FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            appRoute<void>(
              context,
              builder: (_) => widget.controller.focus != null
                  ? FocusPage(
                      controller: widget.controller,
                      isRound: widget.isRound,
                    )
                  : FocusSetupPage(
                      controller: widget.controller,
                      isRound: widget.isRound,
                      initialTask: task,
                    ),
            ),
          ),
          label: Text(widget.controller.focus != null ? '返回专注' : '开始专注'),
          icon: const Icon(Icons.play_arrow_rounded),
        ),
      );
      return AppPage(
        isRound: widget.isRound,
        children: [
          backHeader(context, '任务'),
          const SizedBox(height: 8),
          Text(
            task.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          focusButton('top'),
          if (!task.completed && task.date != widget.controller.today) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('add-task-to-today'),
              onPressed: adding
                  ? null
                  : () async {
                      setState(() => adding = true);
                      try {
                        await widget.controller.addToToday(task);
                        if (context.mounted) {
                          Navigator.popUntil(context, (route) => route.isFirst);
                        }
                      } on FormatException catch (error) {
                        if (context.mounted) {
                          await explainError(context, error.message);
                        }
                      } catch (_) {
                        if (context.mounted) {
                          await explainError(context, '暂时无法加入今天，请联网后重试');
                        }
                      } finally {
                        if (mounted) setState(() => adding = false);
                      }
                    },
              icon: const Icon(Icons.today_rounded, size: 18),
              label: Text(adding ? '正在加入' : '加入今天'),
            ),
          ],
          const SizedBox(height: 20),
          taskInformation('启动动作', task.startAction),
          taskInformation('最低目标', task.minimumGoal),
          taskInformation('完成标准', task.completionStandard),
          if (task.estimatedMinutes != null)
            taskInformation('预估时长', '${task.estimatedMinutes} 分钟'),
          for (final section in [
            ('任务价值', task.taskValue),
            ('任务内容', task.content),
            ('技巧与教程', task.tutorial),
          ])
            if (section.$2?.trim().isNotEmpty == true) ...[
              TextButton(
                onPressed: () => setState(() {
                  if (!expanded.add(section.$1)) expanded.remove(section.$1);
                }),
                child: Row(
                  children: [
                    Expanded(child: Text(section.$1)),
                    Icon(
                      expanded.contains(section.$1)
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                    ),
                  ],
                ),
              ),
              if (expanded.contains(section.$1))
                taskInformation('', section.$2),
            ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () async {
              await widget.controller.toggle(task);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(task.completed ? '恢复待办' : '标记完成'),
          ),
          if (!widget.isRound) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                appRoute<void>(
                  context,
                  builder: (_) =>
                      TaskEditorPage(controller: widget.controller, task: task),
                ),
              ),
              child: const Text('编辑任务'),
            ),
          ],
          const SizedBox(height: 12),
          focusButton('bottom'),
        ],
      );
    },
  );
}

class FocusSetupPage extends StatefulWidget {
  const FocusSetupPage({
    super.key,
    required this.controller,
    required this.isRound,
    required this.initialTask,
    this.allowTaskSelection = false,
  });
  final AppController controller;
  final bool isRound;
  final DailyTask initialTask;
  final bool allowTaskSelection;
  @override
  State<FocusSetupPage> createState() => _FocusSetupPageState();
}

class _FocusSetupPageState extends State<FocusSetupPage> {
  late DailyTask task;
  late int minutes;
  late FixedExtentScrollController wheel;
  late StreamSubscription<double> rotary;
  double residual = 0;
  int? rotaryTarget;
  int rotaryGeneration = 0;
  bool busy = false, touching = false;
  @override
  void initState() {
    super.initState();
    task = widget.initialTask;
    minutes = widget.controller.lastMinutes;
    wheel = FixedExtentScrollController(initialItem: minutes ~/ 5 - 1);
    rotary = RotaryInput.events.listen(animateWheel);
  }

  void animateWheel(double delta) {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        touching ||
        !wheel.hasClients) {
      return;
    }
    residual += delta;
    final steps = (residual / 40).truncate();
    if (steps == 0) return;
    residual -= steps * 40;
    final before = rotaryTarget ?? (minutes ~/ 5 - 1);
    final index = (before + steps).clamp(0, 35);
    if (index == before) return;
    TouchHaptics.rotaryScroll(steps * 40, source: wheel);
    rotaryTarget = index;
    final generation = ++rotaryGeneration;
    unawaited(
      wheel
          .animateToItem(
            index,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted && generation == rotaryGeneration) rotaryTarget = null;
          }),
    );
  }

  @override
  void dispose() {
    rotary.cancel();
    wheel.dispose();
    super.dispose();
  }

  Future<void> start() async {
    final selectedMinutes = ((rotaryTarget ?? (minutes ~/ 5 - 1)) + 1) * 5;
    setState(() => busy = true);
    try {
      await widget.controller.engine.call('permissions');
      await widget.controller.start(task, selectedMinutes);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        appRoute<void>(
          context,
          builder: (_) =>
              FocusPage(controller: widget.controller, isRound: widget.isRound),
        ),
      );
    } on PlatformException catch (error) {
      if (mounted) await explainError(context, error.message ?? '暂时无法开始专注');
    } catch (_) {
      if (mounted) await explainError(context, '暂时无法开始专注');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final taskHeading = Text(
      task.title,
      key: const ValueKey('focus-task-title'),
      textAlign: TextAlign.center,
      maxLines: MediaQuery.sizeOf(context).shortestSide < 220 ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
    final choose = widget.allowTaskSelection
        ? TextButton.icon(
            key: const ValueKey('focus-task-selector'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () async {
              final selected = await Navigator.push<DailyTask>(
                context,
                appRoute<DailyTask>(
                  context,
                  builder: (_) => TaskPickerPage(
                    controller: widget.controller,
                    isRound: widget.isRound,
                  ),
                ),
              );
              if (selected != null && mounted) setState(() => task = selected);
            },
            label: taskHeading,
            icon: const Icon(Icons.expand_more_rounded, size: 18),
          )
        : taskHeading;
    final action = task.startAction?.trim();
    final hasAction = action?.isNotEmpty == true;
    final picker = Listener(
      onPointerDown: (_) {
        touching = true;
        rotaryTarget = null;
        rotaryGeneration++;
        residual = 0;
      },
      onPointerUp: (_) => touching = false,
      onPointerCancel: (_) => touching = false,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          AnimatedWheelInput(
            onScroll: animateWheel,
            child: ListWheelScrollView.useDelegate(
              controller: wheel,
              itemExtent: 40,
              diameterRatio: 2.2,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: (index) {
                if (minutes != (index + 1) * 5) {
                  if (rotaryTarget == null) {
                    TouchHaptics.selectionClick();
                  }
                }
                setState(() => minutes = (index + 1) * 5);
              },
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: 36,
                builder: (context, index) => Center(
                  child: Text(
                    '${(index + 1) * 5} 分钟',
                    style: const TextStyle(
                      fontSize: 24,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final button = WearEdgeButton(
      label: '开始',
      icon: Icons.play_arrow_rounded,
      onPressed: start,
      busy: busy,
    );
    final actionText = Text(
      action ?? '',
      key: const ValueKey('focus-start-action'),
      textAlign: TextAlign.center,
      style: const TextStyle(color: muted, fontSize: 12, height: 1.3),
    );
    if (MediaQuery.textScalerOf(context).scale(14) > 19) {
      return AppPage(
        isRound: widget.isRound,
        enableRotary: false,
        showTime: false,
        bottomAction: button,
        children: [
          choose,
          if (hasAction)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: actionText,
            ),
          SizedBox(height: 128, child: picker),
        ],
      );
    }
    return Scaffold(
      body: ScreenViewport(
        isRound: widget.isRound,
        child: LayoutBuilder(
          builder: (context, size) => Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.isRound ? size.maxWidth * .16 : 24,
                    widget.isRound ? size.maxHeight * .13 : 24,
                    widget.isRound ? size.maxWidth * .16 : 24,
                    widget.isRound ? 60 : 24,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      choose,
                      if (hasAction)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: readableAction(
                            context,
                            action!,
                            Text(
                              action,
                              key: const ValueKey('focus-start-action'),
                              maxLines:
                                  MediaQuery.sizeOf(context).shortestSide < 220
                                  ? 1
                                  : 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: picker,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (!widget.isRound)
                        SizedBox(width: double.infinity, child: button),
                    ],
                  ),
                ),
              ),
              if (widget.isRound)
                Positioned(left: 0, right: 0, bottom: 0, child: button),
            ],
          ),
        ),
      ),
    );
  }
}

class TaskPickerPage extends StatelessWidget {
  const TaskPickerPage({
    super.key,
    required this.controller,
    required this.isRound,
  });
  final AppController controller;
  final bool isRound;
  @override
  Widget build(BuildContext context) => AppPage(
    isRound: isRound,
    children: [
      backHeader(context, '选择任务'),
      const SizedBox(height: 8),
      for (final task in [...controller.pending, ...controller.completed])
        TaskTile(task: task, onTap: () => Navigator.pop(context, task)),
    ],
  );
}

String timerText(int seconds) =>
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

class FocusPage extends StatelessWidget {
  const FocusPage({super.key, required this.controller, required this.isRound});
  final AppController controller;
  final bool isRound;

  Future<bool> _action(BuildContext context, String method) async {
    try {
      if (method == 'resume' && controller.focus?.kind == 'focus') {
        await controller.engine.call('permissions');
      }
      await controller.focusAction(method);
      return true;
    } on PlatformException catch (error) {
      if (context.mounted) {
        await explainError(context, error.message ?? '操作未完成');
      }
    } catch (_) {
      if (context.mounted) {
        await explainError(context, '操作未完成，请重试');
      }
    }
    return false;
  }

  DailyTask _task() {
    final focus = controller.focus!;
    return controller.tasks
            .where((task) => task.id == focus.taskId)
            .firstOrNull ??
        DailyTask(
          id: focus.taskId,
          templateId: '',
          date: '',
          title: focus.taskTitle,
          content: '',
          startAction: focus.startAction,
        );
  }

  Widget _controls(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton.filledTonal(
        tooltip: '提前结束',
        style: IconButton.styleFrom(fixedSize: const Size(48, 48)),
        icon: const Icon(Icons.stop_rounded, size: 24),
        onPressed: () async {
          final stop = await appDialog<bool>(
            context,
            title: '结束本次专注？',
            actions: (dialog) => [
              FilledButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('继续专注'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('结束专注'),
              ),
            ],
          );
          if (stop == true && context.mounted) {
            final stopped = await _action(context, 'stop');
            if (stopped && context.mounted) Navigator.pop(context);
          }
        },
      ),
      const SizedBox(width: 16),
      IconButton.filled(
        tooltip: controller.focus!.paused ? '继续' : '暂停',
        style: IconButton.styleFrom(fixedSize: const Size(48, 48)),
        onPressed: () =>
            _action(context, controller.focus!.paused ? 'resume' : 'pause'),
        icon: Icon(
          controller.focus!.paused
              ? Icons.play_arrow_rounded
              : Icons.pause_rounded,
          size: 26,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final focus = controller.focus;
      if (focus == null) {
        return AppPage(
          isRound: isRound,
          children: [
            backHeader(context, '专注'),
            const Center(child: Text('没有进行中的专注')),
          ],
        );
      }
      if (focus.finished) {
        return AppPage(
          isRound: isRound,
          bottomAction: WearEdgeButton(
            onPressed: () async {
              final task = _task();
              if (!await _action(context, 'dismiss')) return;
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  appRoute<void>(
                    context,
                    builder: (_) => FocusSetupPage(
                      controller: controller,
                      isRound: isRound,
                      initialTask: task,
                    ),
                  ),
                );
              }
            },
            label: '继续专注',
            icon: Icons.play_arrow_rounded,
          ),
          children: [
            const SizedBox(height: 8),
            const Icon(
              Icons.check_circle_outline_rounded,
              color: accent,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              focus.kind == 'rest' ? '休息结束' : '本次专注完成',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              focus.taskTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 14),
            ),
            Text(
              '${focus.plannedSeconds ~/ 60} 分钟',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            if (focus.kind != 'rest')
              OutlinedButton(
                onPressed: () async {
                  try {
                    await controller.start(_task(), 5, rest: true);
                  } catch (_) {
                    if (context.mounted) {
                      await explainError(context, '暂时无法开始休息');
                    }
                  }
                },
                child: const Text('休息一下'),
              ),
            TextButton(
              onPressed: () async {
                if (await _action(context, 'dismiss') && context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('返回任务'),
            ),
          ],
        );
      }
      final title = Text(
        focus.taskTitle,
        key: const ValueKey('active-focus-task'),
        maxLines: MediaQuery.sizeOf(context).shortestSide < 220 ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      );
      final action = focus.kind == 'focus' ? focus.startAction?.trim() : null;
      final hasAction = action?.isNotEmpty == true;
      final statusText = Text(
        focus.paused
            ? '已暂停'
            : focus.kind == 'rest'
            ? '休息中'
            : '专注中',
        key: const ValueKey('active-focus-status'),
        style: const TextStyle(color: accent, fontSize: 12, height: 1),
      );
      final status = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          statusText,
          if (controller.dndEnabled)
            const Padding(
              padding: EdgeInsets.only(left: 5),
              child: Tooltip(
                message: '勿扰已开启',
                child: Icon(
                  Icons.do_not_disturb_on_rounded,
                  color: muted,
                  size: 12,
                ),
              ),
            ),
        ],
      );
      if (MediaQuery.textScalerOf(context).scale(14) > 19) {
        return AppPage(
          isRound: isRound,
          children: [
            title,
            if (hasAction)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  action!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted),
                ),
              ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                timerText(focus.remainingSeconds),
                style: const TextStyle(
                  fontSize: 48,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Center(child: status),
            const SizedBox(height: 12),
            _controls(context),
          ],
        );
      }
      return Scaffold(
        body: ScreenViewport(
          isRound: isRound,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = math
                  .min(constraints.maxWidth, constraints.maxHeight)
                  .clamp(0.0, 400.0);
              return Center(
                child: SizedBox.square(
                  dimension: side,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _TimerRing(
                              focus.remainingMillis /
                                  (focus.plannedSeconds * 1000),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: side * .12,
                        left: side * .17,
                        right: side * .17,
                        child: title,
                      ),
                      if (hasAction)
                        Positioned(
                          top: side * .29,
                          left: side * .18,
                          right: side * .18,
                          child: readableAction(
                            context,
                            action!,
                            Text(
                              action,
                              key: const ValueKey('active-focus-start-action'),
                              maxLines:
                                  MediaQuery.sizeOf(context).shortestSide < 220
                                  ? 1
                                  : 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: side * (side < 220 ? .42 : .43),
                        left: side * .12,
                        right: side * .12,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            timerText(focus.remainingSeconds),
                            key: const ValueKey('active-focus-countdown'),
                            style: TextStyle(
                              fontSize: side * (side < 220 ? .18 : .20),
                              height: 1,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: side * (side < 220 ? .61 : .65),
                        left: 0,
                        right: 0,
                        child: Center(child: status),
                      ),
                      Positioned(
                        top: math.min(side * .73, side - 66),
                        left: 0,
                        right: 0,
                        child: _controls(context),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

class _TimerRing extends CustomPainter {
  _TimerRing(this.fraction);
  final double fraction;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - 10,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = surface;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
    paint
      ..color = accent
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0, 1),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_TimerRing oldDelegate) =>
      oldDelegate.fraction != fraction;
}

class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({super.key, required this.controller, this.task});
  final AppController controller;
  final DailyTask? task;
  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title,
      content,
      tutorial,
      taskValue,
      minimumGoal,
      completionStandard,
      startAction,
      estimate;
  late String date, recurrence;
  late final String templateId;
  final Set<int> weekdays = {};
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final task = widget.task;
    templateId = task?.templateId ?? newId();
    title = TextEditingController(text: task?.title);
    content = TextEditingController(text: task?.content);
    tutorial = TextEditingController(text: task?.tutorial);
    taskValue = TextEditingController(text: task?.taskValue);
    minimumGoal = TextEditingController(text: task?.minimumGoal);
    completionStandard = TextEditingController(text: task?.completionStandard);
    startAction = TextEditingController(text: task?.startAction);
    estimate = TextEditingController(text: task?.estimatedMinutes?.toString());
    date = task?.scheduleDate ?? task?.date ?? widget.controller.date;
    recurrence = task?.recurrence ?? 'once';
    weekdays.addAll(
      task?.weekdays.isNotEmpty == true
          ? task!.weekdays
          : [DateTime.parse(date).weekday],
    );
  }

  @override
  void dispose() {
    title.dispose();
    content.dispose();
    tutorial.dispose();
    taskValue.dispose();
    minimumGoal.dispose();
    completionStandard.dispose();
    startAction.dispose();
    estimate.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (recurrence == 'weekly' && weekdays.isEmpty) {
      await explainError(context, '请选择重复的星期');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.controller.saveTask(
        TaskDraft(
          id: templateId,
          title: title.text,
          content: content.text,
          tutorial: tutorial.text,
          taskValue: taskValue.text,
          minimumGoal: minimumGoal.text,
          completionStandard: completionStandard.text,
          startAction: startAction.text,
          estimatedMinutes: int.tryParse(estimate.text.trim()),
          date: date,
          recurrence: recurrence,
          weekdays: weekdays.toList()..sort(),
          sortOrder: widget.task?.sortOrder ?? widget.controller.tasks.length,
        ),
        existing: widget.task,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) await explainError(context, '暂时无法保存，请检查网络后重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    isRound: false,
    children: [
      backHeader(context, widget.task == null ? '添加任务' : '编辑任务'),
      Form(
        key: form,
        child: Column(
          children: [
            TextFormField(
              controller: title,
              maxLength: 200,
              decoration: const InputDecoration(labelText: '任务标题'),
              validator: (value) =>
                  value?.trim().isEmpty != false ? '请填写标题' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: content,
              minLines: 4,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: '任务内容',
                alignLabelWithHint: true,
              ),
              validator: (value) =>
                  value?.trim().isEmpty != false ? '请填写任务内容' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: tutorial,
              minLines: 3,
              maxLines: null,
              decoration: const InputDecoration(
                labelText: '技巧或教程（可选）',
                alignLabelWithHint: true,
              ),
            ),
            for (final field in [
              (taskValue, '任务价值', '为什么要做这件事'),
              (minimumGoal, '最低目标', '至少做到什么'),
              (completionStandard, '完成标准', '怎样才算达到目标'),
              (startAction, '启动动作', '例如：先读一节'),
            ]) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: field.$1,
                minLines: 2,
                maxLines: null,
                decoration: InputDecoration(
                  labelText: field.$2,
                  hintText: field.$3,
                  alignLabelWithHint: true,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: estimate,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '预估时长',
                suffixText: '分钟',
              ),
              validator: (value) {
                if (value?.trim().isEmpty != false) return null;
                final minutes = int.tryParse(value!.trim());
                return minutes == null || minutes < 1 || minutes > 1440
                    ? '请输入 1–1440 分钟'
                    : null;
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('日期'),
        trailing: Text(date),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.parse(date),
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (picked != null) setState(() => date = dayKey(picked));
        },
      ),
      DropdownButtonFormField<String>(
        initialValue: recurrence,
        decoration: const InputDecoration(labelText: '重复'),
        items: const [
          DropdownMenuItem(value: 'once', child: Text('不重复')),
          DropdownMenuItem(value: 'daily', child: Text('每天')),
          DropdownMenuItem(value: 'weekly', child: Text('每周')),
        ],
        onChanged: (value) => setState(() => recurrence = value!),
      ),
      if (recurrence == 'weekly')
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Wrap(
            spacing: 6,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(['一', '二', '三', '四', '五', '六', '日'][day - 1]),
                  selected: weekdays.contains(day),
                  onSelected: (value) => setState(() {
                    if (value) {
                      weekdays.add(day);
                    } else {
                      weekdays.remove(day);
                    }
                  }),
                ),
            ],
          ),
        ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: busy ? null : save,
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('保存'),
      ),
      if (widget.task != null)
        TextButton(
          onPressed: busy
              ? null
              : () async {
                  final confirmed = await appDialog<bool>(
                    context,
                    title: '停止安排这项任务？',
                    message: '已完成和专注记录会保留。',
                    actions: (dialog) => [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('停止安排'),
                      ),
                    ],
                  );
                  if (confirmed != true) return;
                  setState(() => busy = true);
                  try {
                    await widget.controller.archive(widget.task!);
                    if (context.mounted) {
                      Navigator.popUntil(context, (route) => route.isFirst);
                    }
                  } catch (_) {
                    if (context.mounted) {
                      await explainError(context, '暂时无法保存，请重试');
                    }
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: const Text('停止安排', style: TextStyle(color: Colors.redAccent)),
        ),
    ],
  );
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<Map<String, dynamic>>> history;
  @override
  void initState() {
    super.initState();
    history = widget.controller.repository.history();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: history,
    builder: (context, snapshot) => AppPage(
      isRound: false,
      children: [
        backHeader(context, '专注记录'),
        if (snapshot.connectionState != ConnectionState.done)
          const Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (snapshot.hasError)
          Center(
            child: TextButton(
              onPressed: () => setState(
                () => history = widget.controller.repository.history(),
              ),
              child: const Text('重新加载'),
            ),
          ),
        if (snapshot.hasData && snapshot.data!.isEmpty)
          const Center(
            child: Text('还没有专注记录', style: TextStyle(color: muted)),
          ),
        for (final row in snapshot.data ?? <Map<String, dynamic>>[])
          ListTile(
            title: Text(row['task_title'].toString()),
            subtitle: Text(
              '${row['kind'] == 'rest' ? '休息' : '专注'} · ${row['status'] == 'completed' ? '完成' : '提前结束'} · ${_historyTime(row['started_at'].toString())}',
            ),
            trailing: Text(
              '${(int.parse(row['actual_seconds'].toString()) / 60).floor()} 分钟',
            ),
          ),
      ],
    ),
  );
}

String _historyTime(String raw) {
  final time = chinaNow(DateTime.parse('${raw}Z'));
  return '${dayKey(time)} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
