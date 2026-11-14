import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/data/local_store.dart';
import 'package:life_assistant/main.dart';
import 'package:life_assistant/pages/app_pages.dart';

import 'fakes.dart';

Future<AppController> _home(
  WidgetTester tester,
  double diameter, {
  FakeFocusEngine? engine,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size.square(diameter);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final focusEngine = engine ?? FakeFocusEngine();
  final controller = AppController(
    repository: FakeRepository(),
    store: MemoryStore(),
    engine: focusEngine,
    clock: () => focusEngine.now,
  );
  await controller.initialize();
  await controller.refresh();
  await tester.pumpWidget(MyApp(controller: controller, isRound: true));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  return controller;
}

Future<void> _backFrom(WidgetTester tester, Type page) async {
  Navigator.of(tester.element(find.byType(page))).pop();
  await tester.pumpAndSettle();
}

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets(
      'Home title and count open details, play opens task setup at $diameter',
      (tester) async {
        final engine = FakeFocusEngine();
        final controller = await _home(tester, diameter, engine: engine);
        final task = controller.pending.first;
        final tile = find.byWidgetPredicate(
          (widget) => widget is TaskTile && widget.task.id == task.id,
        );
        final play = find.byKey(ValueKey('task-focus-${task.id}'));
        final title = find.descendant(
          of: tile,
          matching: find.text(task.title),
        );
        expect(play.hitTestable(), findsOneWidget);
        expect(find.byTooltip('完成${task.title}').hitTestable(), findsOneWidget);
        expect(tester.getSize(play), const Size(40, 40));
        await tester.tap(title);
        await tester.pumpAndSettle();
        expect(find.byType(TaskDetailPage), findsOneWidget);
        await _backFrom(tester, TaskDetailPage);

        final count = find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == '已完成0个番茄钟',
          ),
        );
        await tester.tap(find.descendant(of: count, matching: find.text('0')));
        await tester.pumpAndSettle();
        expect(find.byType(TaskDetailPage), findsOneWidget);
        await _backFrom(tester, TaskDetailPage);

        await tester.tap(play);
        await tester.pumpAndSettle();
        final setup = tester.widget<FocusSetupPage>(
          find.byType(FocusSetupPage),
        );
        expect(setup.initialTask.id, task.id);
        expect(setup.allowTaskSelection, isFalse);
        expect(find.byType(TaskDetailPage), findsNothing);
        expect(engine.state, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'An active focus offers return only for its task and preserves the session',
    (tester) async {
      final engine = FakeFocusEngine();
      final controller = await _home(tester, 240, engine: engine);
      final task = controller.pending.first;
      final next = controller.pending[1];
      await controller.start(task, 25);
      await tester.pumpAndSettle();
      final sessionId = controller.focus!.id;
      expect(find.byKey(ValueKey('task-focus-${next.id}')), findsNothing);
      final returning = find.byTooltip('返回专注：${task.title}');
      await Scrollable.ensureVisible(tester.element(returning), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(returning);
      await tester.pumpAndSettle();
      expect(find.byType(FocusPage), findsOneWidget);
      expect(find.byType(FocusSetupPage), findsNothing);
      expect(engine.state!['id'], sessionId);
      expect(controller.focus!.taskId, task.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'After finishing, the first task play stays usable at 192 and the summary opens results',
    (tester) async {
      final engine = FakeFocusEngine();
      final controller = await _home(tester, 192, engine: engine);
      final first = controller.pending.first;
      await controller.start(first, 5);
      engine.elapse(const Duration(minutes: 5));
      await controller.refreshFocus();
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(controller.focus!.finished, isTrue);
      final play = find.byKey(ValueKey('task-focus-${first.id}'));
      expect(play.hitTestable(), findsOneWidget);
      final playRect = tester.getRect(play);
      expect(
        (playRect.center - const Offset(96, 96)).distance + playRect.width / 2,
        lessThanOrEqualTo(96),
      );
      expect(
        find.byKey(ValueKey('task-focus-${controller.pending[1].id}')),
        findsOneWidget,
      );
      final summary = find.byKey(const ValueKey('last-focus-summary'));
      expect(tester.getSize(summary).height, lessThanOrEqualTo(28));
      await tester.tap(summary);
      await tester.pumpAndSettle();
      expect(find.byType(FocusPage), findsOneWidget);
      expect(find.text(first.title), findsOneWidget);
      await _backFrom(tester, FocusPage);
      await tester.tap(play);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FocusSetupPage>(find.byType(FocusSetupPage))
            .initialTask
            .id,
        first.id,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
