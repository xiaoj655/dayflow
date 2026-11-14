import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/pages/app_pages.dart';
import 'package:life_assistant/widgets/focus_finished_view.dart';

import 'fakes.dart';
import 'widget_test.dart' show configure, reveal;

Future<AppController> _finishTask(WidgetTester tester, double diameter) async {
  final app = await configure(tester, diameter: diameter);
  await tester.tap(find.text(app.tasks.first.title));
  await tester.pumpAndSettle();
  final start = find.byKey(const ValueKey('detail-focus-top'));
  await reveal(tester, start);
  await tester.tap(start);
  await tester.pumpAndSettle();
  await tester.tap(find.text('开始专注'));
  await tester.pumpAndSettle();
  (app.engine as FakeFocusEngine).elapse(
    Duration(seconds: app.focus!.plannedSeconds),
  );
  await app.refreshFocus();
  await app.refresh();
  await tester.pumpAndSettle();
  expect(find.byType(FocusFinishedView), findsOneWidget);
  expect(app.completed, isEmpty);
  return app;
}

void main() {
  testWidgets('Starting a task focus leaves the task list as its back target', (
    tester,
  ) async {
    final app = await configure(tester);
    final task = app.tasks.first;
    await tester.tap(find.text(task.title));
    await tester.pumpAndSettle();
    final start = find.byKey(const ValueKey('detail-focus-top'));
    await reveal(tester, start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始专注'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(FocusPage))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(TaskListPage), findsOneWidget);
    expect(find.byType(TaskDetailPage), findsNothing);
    expect(app.focus!.running, isTrue);
    expect(app.focus!.taskId, task.id);
    expect(tester.takeException(), isNull);
  });

  for (final diameter in [192.0, 240.0]) {
    testWidgets('Finish A and start B directly at $diameter dp', (
      tester,
    ) async {
      final app = await _finishTask(tester, diameter);
      final first = app.tasks.first;
      final second = app.tasks[1];
      final completion = find.byKey(
        const ValueKey('focus-finished-task-completion'),
      );
      final change = find.byKey(const ValueKey('focus-finished-change-task'));
      expect(completion.hitTestable(), findsOneWidget);
      expect(change.hitTestable(), findsOneWidget);
      await tester.tap(completion);
      await tester.pumpAndSettle();
      expect(app.completed.single.id, first.id);
      expect(app.focus!.finished, isTrue);
      await tester.tap(change);
      await tester.pumpAndSettle();
      expect(find.byType(TaskPickerPage), findsOneWidget);
      expect(find.text(first.title), findsNothing);
      await reveal(tester, find.text(second.title));
      await tester.tap(find.text(second.title));
      await tester.pumpAndSettle();
      expect(find.byType(FocusSetupPage), findsOneWidget);
      expect(find.text(second.title), findsOneWidget);
      expect(find.byKey(const ValueKey('focus-task-selector')), findsOneWidget);
      await tester.tap(find.text('开始专注'));
      await tester.pumpAndSettle();
      expect(app.focus!.running, isTrue);
      expect(app.focus!.taskId, second.id);
      expect(
        app.focusCount(app.tasks.singleWhere((task) => task.id == first.id)),
        1,
      );
      Navigator.of(tester.element(find.byType(FocusPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(TaskListPage), findsOneWidget);
      expect(find.byType(TaskDetailPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Cancel changing tasks keeps the completed round available', (
    tester,
  ) async {
    final app = await _finishTask(tester, 240);
    final id = app.focus!.id;
    await tester.tap(find.byKey(const ValueKey('focus-finished-change-task')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(TaskPickerPage))).pop();
    await tester.pumpAndSettle();
    expect(app.focus!.id, id);
    expect(app.focus!.finished, isTrue);
    expect(find.byType(FocusFinishedView), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('focus-finished-change-task')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Task completion can be undone on the focus completion page', (
    tester,
  ) async {
    final app = await _finishTask(tester, 240);
    final id = app.focus!.id;
    final completion = find.byKey(
      const ValueKey('focus-finished-task-completion'),
    );
    await tester.tap(completion);
    await tester.pumpAndSettle();
    expect(app.completed, hasLength(1));
    expect(find.byTooltip('恢复待办'), findsOneWidget);
    await tester.tap(completion);
    await tester.pumpAndSettle();
    expect(app.completed, isEmpty);
    expect(app.focus!.id, id);
    expect(app.focus!.finished, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Returning from completion goes to the task list', (
    tester,
  ) async {
    final app = await _finishTask(tester, 240);
    await tester.tap(find.byKey(const ValueKey('focus-finished-return')));
    await tester.pumpAndSettle();
    expect(app.focus, isNull);
    expect(find.byType(TaskListPage), findsOneWidget);
    expect(find.byType(TaskDetailPage), findsNothing);
    expect(find.byType(FocusPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Continuing free focus keeps task selection available', (
    tester,
  ) async {
    final app = await configure(tester);
    await reveal(tester, find.text('开始自由专注'));
    await tester.tap(find.text('开始自由专注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始专注'));
    await tester.pumpAndSettle();
    (app.engine as FakeFocusEngine).elapse(
      Duration(seconds: app.focus!.plannedSeconds),
    );
    await app.refreshFocus();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('focus-finished-task-completion')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('focus-finished-continue')));
    await tester.pumpAndSettle();
    expect(find.byType(FocusSetupPage), findsOneWidget);
    expect(find.text('自由专注'), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-task-selector')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
