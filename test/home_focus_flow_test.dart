import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/pages/app_pages.dart';

import 'fakes.dart';
import 'widget_test.dart' show configure, reveal;

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets(
      'Home pauses, resumes and opens the same focus at $diameter dp',
      (tester) async {
        final app = await configure(tester, diameter: diameter);
        await app.start(app.tasks.first, 25);
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('home-focus-toggle'));
        await reveal(tester, toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(app.focus!.paused, isTrue);
        expect(find.byType(FocusPage), findsNothing);
        expect(find.byTooltip('继续专注'), findsOneWidget);
        final id = app.focus!.id;
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(app.focus!.running, isTrue);
        expect(app.focus!.id, id);
        expect(find.byType(TaskListPage), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('home-focus-open')));
        await tester.pumpAndSettle();
        expect(find.byType(FocusPage), findsOneWidget);
        expect(app.focus!.id, id);
        Navigator.of(tester.element(find.byType(FocusPage))).pop();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-focus-card')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Free focus stays in the first screen after all tasks finish at $diameter dp',
      (tester) async {
        final app = await configure(tester, diameter: diameter);
        for (final task in app.tasks.toList()) {
          await app.setCompleted(task, true);
        }
        await app.refresh();
        await tester.pumpAndSettle();
        expect(app.pending, isEmpty);
        final free = find.text('开始自由专注');
        expect(free.hitTestable(), findsOneWidget);
        await tester.tap(free);
        await tester.pumpAndSettle();
        expect(find.byType(FocusSetupPage), findsOneWidget);
        expect(find.text('自由专注'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Home transitions from active controls to completion summary', (
    tester,
  ) async {
    final app = await configure(tester);
    await app.start(app.tasks.first, 5);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-focus-toggle')), findsOneWidget);
    (app.engine as FakeFocusEngine).elapse(const Duration(minutes: 5));
    await app.refreshFocus();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-focus-card')), findsNothing);
    final summary = find.byKey(const ValueKey('last-focus-summary'));
    expect(summary, findsOneWidget);
    await tester.tap(summary);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('focus-finished-change-task')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
