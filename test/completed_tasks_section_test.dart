import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/pages/app_pages.dart';

import 'fakes.dart';
import 'widget_test.dart' show configure, reveal;

const _sectionKey = ValueKey('completed-tasks-toggle');

Finder _completedTiles() => find.byWidgetPredicate(
  (widget) => widget is TaskTile && widget.task.completed,
);

Future<void> _toggleSection(WidgetTester tester) async {
  final header = find.byKey(_sectionKey);
  await reveal(tester, header);
  await tester.tap(header);
  await tester.pumpAndSettle();
}

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets(
      'Completed tasks collapse and can be restored at $diameter dp',
      (tester) async {
        const date = '2026-11-09';
        final tasks = fixtures(date);
        final repository = FakeRepository()
          ..days[date] = [
            tasks.first,
            tasks[1].withCompletion('2026-11-09 01:00:00'),
            tasks[2].withCompletion('2026-11-09 01:30:00'),
          ];
        final app = await configure(
          tester,
          diameter: diameter,
          repository: repository,
        );

        expect(_completedTiles(), findsNothing);
        await _toggleSection(tester);
        final restore = find.byTooltip('恢复待办阅读');
        await reveal(tester, restore);
        expect(restore.hitTestable(), findsOneWidget);
        await tester.tap(restore);
        await tester.pumpAndSettle();
        expect(app.pending.map((task) => task.title), contains('阅读'));
        expect(app.completed.single.title, '晚间回顾');
        // Let the transient undo notice clear before tapping behind it.
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        await reveal(tester, find.byKey(_sectionKey));
        expect(find.text('已完成 · 1'), findsOneWidget);
        // A task mutation rebuilds the home page without closing the section.
        expect(_completedTiles(), findsOneWidget);
        await _toggleSection(tester);
        expect(_completedTiles(), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Completing a task keeps undo available while collapsed at $diameter dp',
      (tester) async {
        final app = await configure(tester, diameter: diameter);
        await tester.tap(find.byTooltip('完成街头观察'));
        await tester.pumpAndSettle();
        expect(app.completed.single.title, '街头观察');
        expect(_completedTiles(), findsNothing);
        expect(find.text('撤销').hitTestable(), findsOneWidget);
        await tester.tap(find.text('撤销'));
        await tester.pumpAndSettle();
        expect(app.completed, isEmpty);
        expect(app.pending.first.title, '街头观察');
        expect(find.byKey(_sectionKey), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Expanded sections remember each life date and work space', (
    tester,
  ) async {
    const date = '2026-11-09';
    const tomorrow = '2026-11-10';
    const work = DailyTask(
      id: 'work:completed',
      templateId: 'work',
      date: date,
      title: '完成工作',
      content: '工作任务',
      space: 'work',
      completedAt: '2026-11-09 01:00:00',
    );
    final repository = FakeRepository()
      ..days[date] = [
        fixtures(date).first.withCompletion('2026-11-09 01:00:00'),
        work,
      ]
      ..days[tomorrow] = [
        fixtures(tomorrow).first.withCompletion('2026-11-10 01:00:00'),
        work,
      ];
    final app = await configure(tester, repository: repository);
    await _toggleSection(tester);
    expect(_completedTiles(), findsOneWidget);

    await app.selectDate(DateTime(2026, 11, 10));
    await tester.pumpAndSettle();
    expect(_completedTiles(), findsNothing);
    await app.selectDate(DateTime(2026, 11, 9));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(_sectionKey));
    expect(_completedTiles(), findsOneWidget);

    await app.selectSpace('work');
    await tester.pumpAndSettle();
    expect(_completedTiles(), findsNothing);
    await _toggleSection(tester);
    expect(find.text('本周已完成 · 1'), findsOneWidget);
    expect(_completedTiles(), findsOneWidget);
    await app.refresh();
    await tester.pumpAndSettle();
    expect(_completedTiles(), findsOneWidget);

    await app.selectSpace('life');
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(_sectionKey));
    expect(_completedTiles(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
