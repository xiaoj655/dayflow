import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/pages/app_pages.dart';

import 'fakes.dart';
import 'widget_test.dart' show configure, reveal;

Future<DailyTask> addWorkTask(AppController app) async {
  final task = DailyTask(
    id: 'work-report',
    templateId: 'report',
    date: app.date,
    title: '整理项目报告',
    content: '整理本周进度',
    space: 'work',
  );
  (app.repository as FakeRepository).days[app.date] = [...app.tasks, task];
  await app.refresh();
  return task;
}

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets(
      'Choose work from free focus while home stays life at $diameter',
      (tester) async {
        final app = await configure(tester, diameter: diameter);
        final work = await addWorkTask(app);
        await tester.pumpAndSettle();
        await reveal(tester, find.text('开始自由专注'));
        await tester.tap(find.text('开始自由专注'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('focus-task-selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('focus-picker-space-work')));
        await tester.pumpAndSettle();
        expect(app.space, 'life');
        final workCard = find.byKey(ValueKey('focus-picker-task-${work.id}'));
        await reveal(tester, workCard);
        await tester.tap(workCard);
        await tester.pumpAndSettle();
        expect(find.byType(FocusSetupPage), findsOneWidget);
        expect(find.text(work.title), findsOneWidget);
        await tester.tap(find.text('开始专注'));
        await tester.pumpAndSettle();
        expect(app.focus!.taskId, work.id);
        expect(app.focus!.space, 'work');
        expect(app.space, 'life');
        Navigator.of(tester.element(find.byType(FocusPage))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(TaskListPage), findsOneWidget);
        expect(app.space, 'life');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Next task opens the finished session space and can start free life focus',
    (tester) async {
      final app = await configure(tester);
      final work = await addWorkTask(app);
      await app.start(work, 5);
      (app.engine as FakeFocusEngine).elapse(const Duration(minutes: 5));
      await app.refreshFocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('last-focus-summary')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('focus-finished-change-task')),
      );
      await tester.pumpAndSettle();
      final period = tester.widget<Text>(
        find.byKey(const ValueKey('focus-picker-period')),
      );
      expect(period.data, '本周任务池');
      await tester.tap(find.byKey(const ValueKey('focus-picker-space-life')));
      await tester.pumpAndSettle();
      final free = find.byKey(const ValueKey('focus-picker-free'));
      await reveal(tester, free);
      await tester.tap(free);
      await tester.pumpAndSettle();
      expect(find.text('自由专注'), findsOneWidget);
      await tester.tap(find.text('开始专注'));
      await tester.pumpAndSettle();
      expect(app.focus!.taskId, '');
      expect(app.focus!.space, 'life');
      expect(app.space, 'life');
      expect(tester.takeException(), isNull);
    },
  );
}
