import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/pages/app_pages.dart';
import 'package:life_assistant/widgets/focus_task_brief.dart';
import 'package:life_assistant/widgets/focus_task_panel.dart';

import 'fakes.dart';
import 'widget_test.dart' show configure, reveal, rotary;

DailyTask steppedTask({bool longTitle = false}) => DailyTask(
  id: 'steps:2026-11-09',
  templateId: 'steps',
  date: '2026-11-09',
  title: '修复登录问题',
  content: '排查登录失败并验证修复。',
  startAction: '先打开日志',
  steps: [
    TaskStep(
      id: 'reproduce',
      title: longTitle ? '打开日志并复现登录失败，记下出现问题的条件。' * 8 : '复现问题',
    ),
    const TaskStep(id: 'fix', title: '修改代码'),
    const TaskStep(id: 'verify', title: '验证修复'),
  ],
);

Future<void> toggleStep(WidgetTester tester, String id) async {
  final button = find.byKey(ValueKey('task-step-toggle-$id')).last;
  await Scrollable.ensureVisible(tester.element(button), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets(
      'Steps advance and undo across setup and running focus at $diameter dp',
      (tester) async {
        final task = steppedTask();
        final repository = FakeRepository()..days[task.date] = [task];
        final app = await configure(
          tester,
          diameter: diameter,
          repository: repository,
        );
        expect(find.text('0/3 步'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('task-focus-${task.id}')));
        await tester.pumpAndSettle();
        expect(find.text('复现问题'), findsOneWidget);
        await rotary(tester, 80);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('current-task-step-title')));
        await tester.pumpAndSettle();
        expect(find.byType(FocusTaskBrief), findsOneWidget);
        await toggleStep(tester, 'reproduce');
        expect(app.tasks.single.completedStepCount, 1);
        expect(app.tasks.single.completed, isFalse);
        Navigator.of(tester.element(find.byType(FocusTaskBrief))).pop();
        await tester.pumpAndSettle();
        expect(find.text('修改代码'), findsOneWidget);
        await tester.tap(find.text('开始专注'));
        await tester.pumpAndSettle();
        final session = app.focus!;
        expect(session.plannedSeconds, 35 * 60);
        final stepBounds = tester.getRect(
          find.byKey(const ValueKey('current-task-step')),
        );
        final timerBounds = tester.getRect(
          find.byKey(const ValueKey('active-focus-countdown')),
        );
        final statusBounds = tester.getRect(
          find.byKey(const ValueKey('active-focus-status')),
        );
        expect(stepBounds.bottom, lessThanOrEqualTo(timerBounds.top));
        expect(timerBounds.bottom, lessThanOrEqualTo(statusBounds.top));
        final controls = tester.getRect(
          find.byKey(const ValueKey('active-focus-controls')),
        );
        expect(statusBounds.bottom, lessThanOrEqualTo(controls.top));
        expect(
          find.byKey(const ValueKey('task-step-toggle-fix')).hitTestable(),
          findsOneWidget,
        );
        await toggleStep(tester, 'fix');
        expect(find.text('验证修复'), findsOneWidget);
        expect(app.tasks.single.completedStepCount, 2);
        expect(app.focus!.id, session.id);
        expect(app.focus!.running, isTrue);
        (app.engine as FakeFocusEngine).elapse(const Duration(minutes: 1));
        await app.refreshFocus();
        await tester.pumpAndSettle();
        expect(find.text('34:00'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('current-task-step-title')));
        await tester.pumpAndSettle();
        expect(find.byType(FocusTaskPanel), findsOneWidget);
        await toggleStep(tester, 'fix');
        expect(app.tasks.single.currentStep!.id, 'fix');
        expect(app.focus!.id, session.id);
        expect(app.focus!.remainingSeconds, 34 * 60);
        expect(app.tasks.single.completed, isFalse);
        await tester.tap(find.byKey(const ValueKey('active-focus-brief')));
        await tester.pumpAndSettle();
        expect(find.byType(FocusTaskPanel), findsNothing);
        expect(find.text('修改代码'), findsOneWidget);
        Navigator.of(tester.element(find.byType(FocusPage))).pop();
        await tester.pumpAndSettle();
        expect(find.text('1/3 步'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Finishing all steps keeps the task and focus active', (
    tester,
  ) async {
    final task = steppedTask();
    final repository = FakeRepository()..days[task.date] = [task];
    final app = await configure(tester, repository: repository);
    await app.start(app.tasks.single, 25);
    await tester.pumpWidget(
      MaterialApp(home: FocusPage(controller: app, isRound: true)),
    );
    await tester.pumpAndSettle();
    final sessionId = app.focus!.id;
    for (final id in ['reproduce', 'fix', 'verify']) {
      await toggleStep(tester, id);
    }
    expect(find.text('步骤已完成'), findsOneWidget);
    expect(app.tasks.single.currentStep, isNull);
    expect(app.tasks.single.completed, isFalse);
    expect(app.focus!.id, sessionId);
    expect(app.focus!.running, isTrue);
    await tester.tap(find.text('步骤已完成'));
    await tester.pumpAndSettle();
    await toggleStep(tester, 'verify');
    expect(app.tasks.single.currentStep!.id, 'verify');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Long steps remain readable and reversible with large watch type',
    (tester) async {
      final task = steppedTask(longTitle: true);
      final repository = FakeRepository()..days[task.date] = [task];
      final app = await configure(
        tester,
        diameter: 192,
        textScale: 2,
        repository: repository,
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TaskDetailPage(controller: app, task: task, isRound: true),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('task-step-reproduce')));
      final title = tester.widget<Text>(find.text(task.steps.first.title));
      expect(title.maxLines, isNull);
      expect(title.overflow, isNull);
      await toggleStep(tester, 'reproduce');
      expect(app.tasks.single.currentStep!.id, 'fix');
      await toggleStep(tester, 'reproduce');
      expect(app.tasks.single.currentStep!.id, 'reproduce');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Large type can advance steps while the timer stays running', (
    tester,
  ) async {
    final task = steppedTask();
    final repository = FakeRepository()..days[task.date] = [task];
    final app = await configure(
      tester,
      diameter: 192,
      textScale: 2,
      repository: repository,
    );
    await app.start(app.tasks.single, 25);
    await tester.pumpWidget(
      MaterialApp(home: FocusPage(controller: app, isRound: true)),
    );
    await tester.pumpAndSettle();
    final id = app.focus!.id;
    await toggleStep(tester, 'reproduce');
    expect(app.tasks.single.currentStep!.id, 'fix');
    expect(app.focus!.id, id);
    expect(app.focus!.running, isTrue);
    expect(tester.takeException(), isNull);
  });
}
