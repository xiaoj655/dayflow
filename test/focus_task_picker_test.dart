import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/app_colors.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/data/local_store.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/widgets/focus_task_picker.dart';
import 'package:life_assistant/widgets/screen_viewport.dart';

import 'fakes.dart';
import 'widget_test.dart' show reveal;

class _CountingStore extends MemoryStore {
  int writes = 0;

  @override
  Future<void> write(String key, String value) async {
    writes++;
    await super.write(key, value);
  }
}

DailyTask _task(
  String id, {
  String space = 'life',
  bool waiting = false,
  String? completedAt,
}) => DailyTask(
  id: id,
  templateId: id,
  date: '2026-11-11',
  title: id,
  content: '任务内容',
  space: space,
  waiting: waiting,
  completedAt: completedAt,
);

Future<({AppController app, FakeRepository repository, _CountingStore store})>
_mount(
  WidgetTester tester, {
  double diameter = 240,
  double textScale = 1,
  bool pendingOnly = true,
  String? initialSpace,
  String? selectedTaskId,
  ValueChanged<DailyTask>? onSelected,
  List<DailyTask>? tasks,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size.square(diameter);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final repository = FakeRepository();
  final store = _CountingStore();
  repository.days['2026-11-11'] =
      tasks ??
      [
        _task('生活待办'),
        _task('生活已完成', completedAt: '2026-11-11 01:00:00'),
        _task('工作等待', space: 'work', waiting: true),
        _task('工作推进', space: 'work'),
        _task('工作本周完成', space: 'work', completedAt: '2026-11-10 01:00:00'),
        _task('工作上周完成', space: 'work', completedAt: '2026-11-08 15:59:59'),
      ];
  final app = AppController(
    repository: repository,
    store: store,
    engine: FakeFocusEngine(),
    clock: () => DateTime.utc(2026, 11, 11, 2),
  );
  await app.initialize();
  await app.refresh();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
      ),
      home: ScreenShape(
        isRound: true,
        child: FocusTaskPicker(
          controller: app,
          isRound: true,
          initialSpace: initialSpace,
          pendingOnly: pendingOnly,
          selectedTaskId: selectedTaskId,
          onSelected: onSelected ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
  return (app: app, repository: repository, store: store);
}

Finder _entry(String id) => find.byKey(ValueKey('focus-picker-task-$id'));
Finder _space(String value) =>
    find.byKey(ValueKey('focus-picker-space-$value'));

Future<void> _switch(WidgetTester tester, String value) async {
  await reveal(tester, _space(value));
  await tester.tap(_space(value));
  await tester.pumpAndSettle();
}

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets('Choose another space at $diameter dp without changing home', (
      tester,
    ) async {
      DailyTask? selected;
      final setup = await _mount(
        tester,
        diameter: diameter,
        onSelected: (task) => selected = task,
      );
      final originalDate = setup.app.date;
      final originalWrites = setup.store.writes;
      await _switch(tester, 'work');
      expect(setup.app.space, 'life');
      expect(setup.app.date, originalDate);
      expect(setup.store.writes, originalWrites);
      expect(find.text('本周任务池'), findsOneWidget);
      await reveal(tester, _entry('工作推进'));
      await tester.tap(_entry('工作推进'));
      await tester.pumpAndSettle();
      expect(selected?.id, '工作推进');
      expect(selected?.space, 'work');
      expect(setup.app.space, 'life');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Free focus belongs to the browsed space', (tester) async {
    DailyTask? selected;
    final setup = await _mount(tester, onSelected: (task) => selected = task);
    await _switch(tester, 'work');
    final free = find.byKey(const ValueKey('focus-picker-free'));
    await reveal(tester, free);
    await tester.tap(free);
    await tester.pumpAndSettle();
    expect(selected?.id, '');
    expect(selected?.space, 'work');
    expect(selected?.date, setup.app.date);
    expect(setup.app.space, 'life');
  });

  testWidgets('Pending mode hides completed tasks in both spaces', (
    tester,
  ) async {
    await _mount(tester);
    await reveal(tester, _entry('生活待办'));
    expect(_entry('生活已完成'), findsNothing);
    await _switch(tester, 'work');
    await reveal(tester, _entry('工作等待'));
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(_entry('工作本周完成'), findsNothing);
    expect(_entry('工作上周完成'), findsNothing);
    expect(_entry('工作等待'), findsOneWidget);
  });

  testWidgets('Work ready tasks precede waiting and current-week completion', (
    tester,
  ) async {
    await _mount(tester, initialSpace: 'work', pendingOnly: false);
    Future<double> absoluteTop(String id) async {
      await reveal(tester, _entry(id));
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      return tester.getTopLeft(_entry(id)).dy + scroll.offset;
    }

    final readyY = await absoluteTop('工作推进');
    final waitingY = await absoluteTop('工作等待');
    expect(find.text('等待中'), findsOneWidget);
    final completedY = await absoluteTop('工作本周完成');
    expect(readyY, lessThan(waitingY));
    expect(waitingY, lessThan(completedY));
    expect(find.text('本周已完成'), findsOneWidget);
    expect(_entry('工作上周完成'), findsNothing);
  });

  testWidgets('Initial space follows associated task rather than home', (
    tester,
  ) async {
    final setup = await _mount(
      tester,
      initialSpace: 'work',
      selectedTaskId: '工作推进',
    );
    expect(setup.app.space, 'life');
    expect(find.text('本周任务池'), findsOneWidget);
    await reveal(tester, _entry('工作推进'));
    final entry = tester.widget<InkWell>(_entry('工作推进'));
    expect(entry.onTap, isNotNull);
    expect(
      find.descendant(
        of: _entry('工作推进'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Offline completion refreshes choices without losing local space',
    (tester) async {
      final setup = await _mount(tester, initialSpace: 'work');
      setup.repository.fail = true;
      final task = setup.app.tasks.singleWhere((task) => task.id == '工作推进');
      await setup.app.setCompleted(task, true);
      await setup.app.refresh();
      await tester.pumpAndSettle();
      expect(setup.app.offline, isTrue);
      expect(setup.app.space, 'life');
      expect(find.text('本周任务池'), findsOneWidget);
      expect(_entry('工作推进'), findsNothing);
      await reveal(tester, _entry('工作等待'));
      expect(_entry('工作等待'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Life shows selected date and can switch back from empty work', (
    tester,
  ) async {
    final setup = await _mount(tester, tasks: [_task('生活待办')]);
    expect(find.text(setup.app.date), findsOneWidget);
    await _switch(tester, 'work');
    await reveal(tester, find.text('暂无待办，也可以自由专注'));
    expect(find.text('暂无待办，也可以自由专注'), findsOneWidget);
    await _switch(tester, 'life');
    await reveal(tester, _entry('生活待办'));
    expect(_entry('生活待办'), findsOneWidget);
    expect(setup.app.space, 'life');
  });

  testWidgets('Large text remains selectable on a 192 dp round screen', (
    tester,
  ) async {
    DailyTask? selected;
    await _mount(
      tester,
      diameter: 192,
      textScale: 1.6,
      onSelected: (task) => selected = task,
    );
    await reveal(tester, _entry('生活待办'));
    await tester.tap(_entry('生活待办'));
    await tester.pumpAndSettle();
    expect(selected?.id, '生活待办');
    expect(tester.takeException(), isNull);
  });
}
