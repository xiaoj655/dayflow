import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/pages/app_pages.dart';
import 'package:life_assistant/widgets/focus_task_brief.dart';

import 'fakes.dart';
import 'widget_test.dart' show configure, reveal, rotary;

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets(
      'Read task context without losing duration or active focus at $diameter',
      (tester) async {
        const date = '2026-11-09';
        final task = DailyTask.fromJson({
          ...fixtures(date).first.toJson(),
          'title': '把今天看到的街道细节整理成三条观察笔记',
          'start_action': '先走到路口，观察行人的步速和姿态，再写下看到的具体细节。' * 3,
        });
        final repository = FakeRepository()..days[date] = [task];
        final app = await configure(
          tester,
          diameter: diameter,
          repository: repository,
        );
        await tester.tap(find.byKey(ValueKey('task-focus-${task.id}')));
        await tester.pumpAndSettle();
        await rotary(tester, 80);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('focus-task-brief')));
        await tester.pumpAndSettle();
        expect(find.byType(FocusTaskBrief), findsOneWidget);
        expect(find.text(task.title), findsOneWidget);
        expect(find.text(task.startAction!), findsOneWidget);
        await reveal(
          tester,
          find.byKey(const ValueKey('focus-brief-completion-standard')),
        );
        expect(find.text(task.completionStandard!), findsOneWidget);
        expect(app.focus, isNull);
        Navigator.of(tester.element(find.byType(FocusTaskBrief))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('focus-start-action')));
        await tester.pumpAndSettle();
        expect(find.text(task.startAction!), findsWidgets);
        await reveal(tester, find.text('返回'));
        await tester.tap(find.text('返回'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('开始专注'));
        await tester.pumpAndSettle();
        expect(app.focus!.plannedSeconds, 35 * 60);
        final id = app.focus!.id;
        await tester.tap(find.byKey(const ValueKey('active-focus-brief')));
        await tester.pumpAndSettle();
        expect(find.byType(FocusTaskBrief), findsOneWidget);
        (app.engine as FakeFocusEngine).elapse(const Duration(minutes: 1));
        await app.refreshFocus();
        await tester.pumpAndSettle();
        expect(app.focus!.running, isTrue);
        expect(app.focus!.id, id);
        expect(app.completed, isEmpty);
        Navigator.of(tester.element(find.byType(FocusTaskBrief))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(FocusPage), findsOneWidget);
        expect(find.text('34:00'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Free focus offers context after choosing a task, with selection preserved',
    (tester) async {
      final app = await configure(tester);
      await reveal(tester, find.text('开始自由专注'));
      await tester.tap(find.text('开始自由专注'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('focus-task-brief')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('focus-task-selector')));
      await tester.pumpAndSettle();
      final choice = find.byKey(
        ValueKey('focus-picker-task-${app.tasks.first.id}'),
      );
      await reveal(tester, choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('focus-task-selector')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('focus-task-brief')));
      await tester.pumpAndSettle();
      expect(find.text(app.tasks.first.title), findsOneWidget);
      Navigator.of(tester.element(find.byType(FocusTaskBrief))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(FocusSetupPage), findsOneWidget);
      expect(find.text(app.tasks.first.title), findsOneWidget);
      expect(app.focus, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
