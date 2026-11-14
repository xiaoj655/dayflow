import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/pages/app_pages.dart';
import 'package:life_assistant/widgets/focus_finished_view.dart';

import 'fakes.dart';
import 'widget_test.dart' show configure, reveal;

Finder _finished(String name) => find.byKey(ValueKey('focus-finished-$name'));

Future<AppController> _openSession(
  WidgetTester tester, {
  double diameter = 240,
  FakeFocusEngine? engine,
  FakeRepository? repository,
  bool rest = false,
}) async {
  final app = await configure(
    tester,
    diameter: diameter,
    engine: engine,
    repository: repository,
  );
  await app.start(app.tasks.first, rest ? 5 : 25, rest: rest);
  await tester.pumpAndSettle();
  final open = find.byKey(const ValueKey('home-focus-open'));
  await reveal(tester, open);
  await tester.tap(open);
  await tester.pumpAndSettle();
  expect(find.byType(FocusPage), findsOneWidget);
  return app;
}

Future<void> _confirmEarlyFinish(
  WidgetTester tester, {
  bool rest = false,
}) async {
  await tester.tap(find.byTooltip(rest ? '结束休息' : '提前结束'));
  await tester.pumpAndSettle();
  expect(find.text(rest ? '结束本次休息？' : '结束本次专注？'), findsOneWidget);
  final confirm = find.text(rest ? '结束休息' : '结束专注');
  await reveal(tester, confirm);
  await tester.tap(confirm);
  await tester.pumpAndSettle();
  expect(find.byType(FocusFinishedView), findsOneWidget);
}

String _durationLabel(WidgetTester tester) =>
    tester.widget<Text>(_finished('minutes')).data!;

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets(
      'Early finish can complete, undo and start another task at $diameter dp',
      (tester) async {
        final repo = FakeRepository();
        final app = await _openSession(
          tester,
          diameter: diameter,
          repository: repo,
        );
        final task = app.tasks.first;
        final next = app.tasks[1];
        final sessionId = app.focus!.id;
        (app.engine as FakeFocusEngine).elapse(
          const Duration(minutes: 7, seconds: 30),
        );
        await _confirmEarlyFinish(tester);
        await app.refresh();
        await tester.pumpAndSettle();

        expect(find.text('提前结束'), findsOneWidget);
        expect(_durationLabel(tester), contains('7分30秒'));
        expect(app.focus!.id, sessionId);
        expect(app.focus!.finished, isTrue);
        expect(app.completed, isEmpty);
        expect(app.focusCount(app.tasks.first), 0);
        expect(repo.sessions.values.single['actualSeconds'], 450);
        expect(repo.sessions.values.single['status'], 'interrupted');
        for (final name in [
          'task-completion',
          'continue',
          'rest',
          'change-task',
        ]) {
          expect(_finished(name).hitTestable(), findsOneWidget);
        }

        await tester.tap(_finished('task-completion'));
        await tester.pumpAndSettle();
        expect(app.completed.single.id, task.id);
        await tester.tap(_finished('task-completion'));
        await tester.pumpAndSettle();
        expect(app.completed, isEmpty);
        await tester.tap(_finished('task-completion'));
        await tester.pumpAndSettle();
        await tester.tap(_finished('change-task'));
        await tester.pumpAndSettle();
        expect(find.byType(TaskPickerPage), findsOneWidget);
        expect(find.text(task.title), findsNothing);
        await reveal(tester, find.text(next.title));
        await tester.tap(find.text(next.title));
        await tester.pumpAndSettle();
        expect(find.byType(FocusSetupPage), findsOneWidget);
        await tester.tap(find.text('开始专注'));
        await tester.pumpAndSettle();
        expect(app.focus!.running, isTrue);
        expect(app.focus!.taskId, next.id);
        expect(app.focus!.id, isNot(sessionId));
        expect(repo.sessions, hasLength(1));
        expect(
          app.focusCount(app.tasks.singleWhere((t) => t.id == task.id)),
          0,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Ending paused focus excludes the entire pause from actual time',
    (tester) async {
      final repo = FakeRepository();
      final app = await _openSession(tester, repository: repo);
      final engine = app.engine as FakeFocusEngine;
      engine.elapse(const Duration(minutes: 4, seconds: 15));
      await app.focusAction('pause');
      engine.elapse(const Duration(hours: 1));
      await app.refreshFocus();
      await tester.pumpAndSettle();
      await _confirmEarlyFinish(tester);
      await app.refresh();
      expect(_durationLabel(tester), contains('4分15秒'));
      expect(repo.sessions.values.single['actualSeconds'], 255);
      expect(app.focusCount(app.tasks.first), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A short early finish stays actionable without recording focus', (
    tester,
  ) async {
    final repo = FakeRepository();
    final app = await _openSession(tester, diameter: 192, repository: repo);
    (app.engine as FakeFocusEngine).elapse(
      const Duration(minutes: 2, seconds: 59),
    );
    await _confirmEarlyFinish(tester);
    await app.refresh();
    expect(_durationLabel(tester), contains('未记录'));
    expect(await app.history(), isEmpty);
    expect(repo.sessions, isEmpty);
    expect(app.focusCount(app.tasks.first), 0);
    await tester.tap(_finished('rest'));
    await tester.pumpAndSettle();
    expect(app.focus!.kind, 'rest');
    expect(app.focus!.running, isTrue);
    expect(app.lastMinutes, 25);
    expect(app.completed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Early rest ending uses rest wording and continues the same task',
    (tester) async {
      final repo = FakeRepository();
      final app = await _openSession(
        tester,
        diameter: 192,
        repository: repo,
        rest: true,
      );
      final task = app.tasks.first;
      (app.engine as FakeFocusEngine).elapse(const Duration(seconds: 40));
      await _confirmEarlyFinish(tester, rest: true);
      await app.refresh();
      expect(find.text('休息结束'), findsOneWidget);
      expect(_durationLabel(tester), contains('40秒'));
      expect(_durationLabel(tester), isNot(contains('未记录')));
      expect(_finished('rest'), findsNothing);
      final record = repo.sessions.values.single;
      expect(record['kind'], 'rest');
      expect(record['actualSeconds'], 40);
      expect(record['status'], 'interrupted');
      await tester.tap(_finished('continue'));
      await tester.pumpAndSettle();
      expect(find.byType(FocusSetupPage), findsOneWidget);
      expect(find.text(task.title), findsOneWidget);
      await tester.tap(find.text('开始专注'));
      await tester.pumpAndSettle();
      expect(app.focus!.running, isTrue);
      expect(app.focus!.kind, 'focus');
      expect(app.focus!.taskId, task.id);
      expect(app.focus!.plannedSeconds, 25 * 60);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cancel ending and cancel changing tasks both keep the session', (
    tester,
  ) async {
    final app = await _openSession(tester);
    final id = app.focus!.id;
    (app.engine as FakeFocusEngine).elapse(const Duration(minutes: 3));
    await tester.tap(find.byTooltip('提前结束'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('继续专注'));
    await tester.tap(find.text('继续专注'));
    await tester.pumpAndSettle();
    expect(app.focus!.id, id);
    expect(app.focus!.running, isTrue);
    expect(find.byType(FocusFinishedView), findsNothing);
    expect(await app.history(), isEmpty);

    await _confirmEarlyFinish(tester);
    await tester.tap(_finished('change-task'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(TaskPickerPage))).pop();
    await tester.pumpAndSettle();
    expect(app.focus!.id, id);
    expect(app.focus!.finished, isTrue);
    expect(find.text('提前结束'), findsOneWidget);
    expect(_finished('change-task').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('An old end confirmation cannot finish a replacement session', (
    tester,
  ) async {
    final app = await _openSession(tester);
    await tester.tap(find.byTooltip('提前结束'));
    await tester.pumpAndSettle();
    await app.focusAction('stop');
    await app.start(app.tasks[1], 15);
    final replacement = app.focus!.id;
    await tester.pumpAndSettle();
    final confirm = find.text('结束专注');
    await reveal(tester, confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(app.focus!.id, replacement);
    expect(app.focus!.running, isTrue);
    expect(find.byType(FocusFinishedView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
