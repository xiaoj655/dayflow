import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/data/local_store.dart';
import 'package:life_assistant/main.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/pages/app_pages.dart';
import 'package:life_assistant/platform/rotary_input.dart';
import 'package:life_assistant/platform/touch_haptics.dart';
import 'package:life_assistant/widgets/wear_controls.dart';

import 'fakes.dart';

Future<AppController> configure(
  WidgetTester tester, {
  double diameter = 240,
  bool round = true,
  double textScale = 1,
  FakeRepository? repository,
  FakeFocusEngine? engine,
  MemoryStore? store,
  DateTime Function()? clock,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = round
      ? Size.square(diameter)
      : const Size(390, 844);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final app = AppController(
    repository: repository ?? FakeRepository(),
    store: store ?? MemoryStore(),
    engine: engine ?? FakeFocusEngine(),
    clock: clock ?? () => DateTime.utc(2026, 11, 9, 2),
  );
  await app.initialize();
  await app.refresh();
  await tester.pumpWidget(MyApp(controller: app, isRound: round));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
  return app;
}

Future<void> rotary(WidgetTester tester, double delta) async {
  tester.binding.channelBuffers.push(
    RotaryInput.channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall('scroll', delta)),
    (_) {},
  );
  await tester.pump();
}

ScrollController listController(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView).last).controller!;
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    70,
    scrollable: find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
}

class DelayedPermissionsFocusEngine extends FakeFocusEngine {
  final permission = Completer<void>();
  int permissionRequests = 0;
  int startRequests = 0;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (method == 'permissions') {
      permissionRequests++;
      await permission.future;
    }
    if (method == 'start') startRequests++;
    return super.call(method, arguments);
  }
}

class DelayedCommandFocusEngine extends FakeFocusEngine {
  DelayedCommandFocusEngine(this.delayedMethod);

  final String delayedMethod;
  final response = Completer<void>();
  final calls = <String>[];
  bool delayNext = false;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    calls.add(method);
    if (method == delayedMethod && delayNext) {
      delayNext = false;
      await response.future;
    }
    return super.call(method, arguments);
  }
}

class DelayedTaskMutationRepository extends FakeRepository {
  DelayedTaskMutationRepository(this.method);

  final String method;
  final response = Completer<void>();
  int calls = 0;

  Future<void> waitFor(String operation) async {
    if (operation != method) return;
    calls++;
    await response.future;
  }

  @override
  Future<void> saveTask(TaskDraft draft, {DailyTask? existing}) async {
    await waitFor('save');
    await super.saveTask(draft, existing: existing);
  }

  @override
  Future<void> archiveTask(DailyTask task) async {
    await waitFor('archive');
    await super.archiveTask(task);
  }

  @override
  Future<void> addToToday(DailyTask task, String today) async {
    await waitFor('add');
    await super.addToToday(task, today);
  }
}

class DelayedTaskStore extends MemoryStore {
  final response = Completer<void>();
  bool block = false;

  @override
  Future<void> write(String key, String value) async {
    if (block) await response.future;
    await super.write(key, value);
  }
}

Future<void> openTaskEditor(WidgetTester tester) async {
  await tester.tap(find.text('街头观察'));
  await tester.pumpAndSettle();
  await reveal(tester, find.text('编辑任务'));
  await tester.tap(find.text('编辑任务'));
  await tester.pumpAndSettle();
}

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets(
      'Compact home exposes the first task and left completion at $diameter dp',
      (tester) async {
        final repo = FakeRepository();
        const date = '2026-11-09';
        repo.days[date] = [
          ...fixtures(date),
          const DailyTask(
            id: 'work',
            templateId: 'work',
            date: date,
            title: '设计系统审查',
            content: '确认设计',
            space: 'work',
          ),
        ];
        for (var i = 0; i < 2; i++) {
          repo.sessions['tomato-$i'] = {
            'id': 'tomato-$i',
            'task_day_id': 'observe:$date',
            'kind': 'focus',
            'status': 'completed',
            'actual_seconds': 1500,
          };
        }
        final app = await configure(
          tester,
          diameter: diameter,
          repository: repo,
        );
        for (final space in ['life', 'work']) {
          await app.selectSpace(space);
          await tester.pumpAndSettle();
          final title = space == 'life' ? '街头观察' : '设计系统审查';
          final tile = find.ancestor(
            of: find.text(title),
            matching: find.byType(TaskTile),
          );
          final toggle = find.byTooltip('完成$title');
          final counter = find
              .descendant(of: tile, matching: find.byType(Semantics))
              .evaluate()
              .map((element) => element.widget as Semantics)
              .singleWhere(
                (widget) => widget.properties.label?.startsWith('已完成') == true,
              );
          expect(counter.properties.label, '已完成${space == 'life' ? 2 : 0}个番茄钟');
          expect(toggle.hitTestable(), findsOneWidget);
          expect(
            tester.getCenter(toggle).dx,
            lessThan(tester.getCenter(find.text(title)).dx),
          );
          expect(tester.getBottomRight(tile).dy, lessThan(diameter - 12));
          expect(listController(tester).offset, 0);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(app.completed.single.title, title);
          await tester.tap(find.text('撤销'));
          await tester.pumpAndSettle();
          expect(app.completed, isEmpty);
          expect(tester.takeException(), isNull);
        }
        final bell = find.byKey(const ValueKey('work-reminder-toggle'));
        await tester.longPress(bell);
        await tester.pumpAndSettle();
        expect(find.text('开启提醒'), findsOneWidget);
      },
    );
    testWidgets('Single timeline selects sessions with crown at $diameter dp', (
      tester,
    ) async {
      final repo = FakeRepository();
      for (var i = 0; i < 2; i++) {
        repo.sessions['session-$i'] = {
          'id': 'session-$i',
          'space': i == 0 ? 'work' : 'life',
          'kind': 'focus',
          'task_title': '专注记录$i',
          'actual_seconds': 900,
          'started_at': '2026-11-09 0${i + 1}:00:00',
          'ended_at': '2026-11-09 0${i + 1}:30:00',
        };
      }
      final app = await configure(tester, diameter: diameter, repository: repo);
      Navigator.of(tester.element(find.byType(TaskListPage))).push(
        MaterialPageRoute<void>(builder: (_) => HistoryPage(controller: app)),
      );
      await tester.pumpAndSettle();
      expect(find.text('工作 · 专注记录0'), findsOneWidget);
      await rotary(tester, 40);
      await tester.pumpAndSettle();
      expect(find.text('生活 · 专注记录1'), findsOneWidget);
      await rotary(tester, 400);
      expect(find.text('生活 · 专注记录1'), findsOneWidget);
      await rotary(tester, -40);
      expect(find.text('工作 · 专注记录0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'Reminder cards fit and retain disabled interval at $diameter dp',
      (tester) async {
        const channel = MethodChannel('life_assistant/work');
        final state = <String, dynamic>{
          'active': false,
          'water': 0,
          'eyes': 30,
          'waterInterval': 45,
        };
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'configure') {
              state.addAll(Map<String, dynamic>.from(call.arguments as Map));
            }
            return state;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await configure(tester, diameter: diameter);
        Navigator.of(
          tester.element(find.byType(TaskListPage)),
        ).push(MaterialPageRoute<void>(builder: (_) => const WorkModePage()));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('喝水提醒'));
        expect(find.text('每 45 分钟'), findsOneWidget);
        final interval = tester.widget<TextButton>(
          find.ancestor(
            of: find.text('每 45 分钟'),
            matching: find.byType(TextButton),
          ),
        );
        expect(interval.onPressed, isNull);
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        expect(state['water'], 45);
        await reveal(tester, find.text('远眺提醒'));
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final diameter in [192.0, 200.0, 240.0, 360.0]) {
    testWidgets(
      'Round ${diameter}dp fills circle and scales edge cards without changing list geometry',
      (tester) async {
        await configure(tester, diameter: diameter);
        expect(tester.getSize(find.byType(ClipOval)), Size.square(diameter));
        final tile = find.ancestor(
          of: find.text('街头观察'),
          matching: find.byType(TaskTile),
        );
        final width = tester.getSize(tile).width;
        expect(width, greaterThan(diameter * .8));
        final centralScale = tester
            .renderObject<RenderBox>(tile)
            .getTransformTo(null)
            .storage[0];
        listController(tester).jumpTo(120);
        await tester.pumpAndSettle();
        expect(tester.getSize(tile).width, width);
        final edgeScale = tester
            .renderObject<RenderBox>(tile)
            .getTransformTo(null)
            .storage[0];
        expect(edgeScale, lessThan(centralScale));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Optional tutorial, completion sinks and undo restores task order',
    (tester) async {
      final app = await configure(tester);
      await tester.tap(find.text('街头观察'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('技巧与教程'));
      await tester.tap(find.text('技巧与教程'));
      await tester.pumpAndSettle();
      expect(find.textContaining('每轮只观察'), findsOneWidget);
      await reveal(tester, find.text('标记完成'));
      await tester.tap(find.text('标记完成'));
      await tester.pumpAndSettle();
      expect(app.completed.single.title, '街头观察');
      final delegate =
          tester.widget<ListView>(find.byType(ListView)).childrenDelegate
              as SliverChildListDelegate;
      final order = delegate.children
          .expand(
            (item) =>
                item is SingleChildRenderObjectWidget ? [item.child] : [item],
          )
          .whereType<TaskTile>()
          .map((tile) => tile.task.title)
          .toList();
      expect(order, ['阅读', '晚间回顾', '街头观察']);
      await reveal(tester, find.text('街头观察'));
      await tester.tap(find.text('街头观察'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('恢复待办'));
      await tester.tap(find.text('恢复待办'));
      await tester.pumpAndSettle();
      expect(app.pending.first.title, '街头观察');
    },
  );
  testWidgets(
    'Crown is continuous, bounded and does not cancel a live finger drag',
    (tester) async {
      await configure(tester);
      for (var i = 0; i < 20; i++) {
        await rotary(tester, 2);
      }
      expect(listController(tester).offset, 40);
      await rotary(tester, -1000);
      expect(listController(tester).offset, 0);
      await tester.tap(find.text('街头观察'));
      await tester.pumpAndSettle();
      final controller = listController(tester);
      final gesture = await tester.startGesture(const Offset(120, 145));
      await gesture.moveBy(const Offset(0, -35));
      await tester.pump(const Duration(milliseconds: 16));
      final first = controller.offset;
      for (var i = 0; i < 3; i++) {
        await rotary(tester, .01);
        await gesture.moveBy(const Offset(0, -25));
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.offset, greaterThan(first + 20 * (i + 1)));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Crown changes focus by five-minute steps and default changes only on start',
    (tester) async {
      final app = await configure(tester);
      await reveal(tester, find.byTooltip('专注'));
      await tester.tap(find.byTooltip('专注'));
      await tester.pumpAndSettle();
      await rotary(tester, 40);
      await tester.pumpAndSettle();
      expect(app.lastMinutes, 25);
      await tester.tap(find.text('开始专注'));
      await tester.pumpAndSettle();
      expect(app.lastMinutes, 30);
      expect(app.focus!.taskTitle, '自由专注');
      expect(find.text('30:00'), findsOneWidget);
      await tester.tap(find.byTooltip('暂停'));
      await tester.pumpAndSettle();
      expect(find.text('已暂停'), findsOneWidget);
      expect(app.completed, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Large type and long tutorials scroll without overflow', (
    tester,
  ) async {
    await configure(tester, textScale: 2);
    await reveal(tester, find.text('街头观察'));
    await tester.tap(find.text('街头观察'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('技巧与教程'));
    await tester.tap(find.text('技巧与教程'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('标记完成'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('Phone provides required fields and optional tutorial editor', (
    tester,
  ) async {
    await configure(tester, round: false);
    await tester.tap(find.text('添加任务'));
    await tester.pumpAndSettle();
    expect(find.text('任务标题'), findsOneWidget);
    expect(find.text('任务内容'), findsOneWidget);
    expect(find.text('技巧或教程（可选）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final date in [
    DateTime.utc(2026, 11, 1, 4),
    DateTime.utc(2026, 11, 2, 4),
  ]) {
    testWidgets(
      'Phone creates a weekly task with all content preserved (weekday ${date.weekday})',
      (tester) async {
        final app = await configure(tester, round: false, clock: () => date);
        await tester.tap(find.text('添加任务'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(EditableText).at(0), '周末观察');
        await tester.enterText(find.byType(EditableText).at(1), '记录三个观察细节。');
        await tester.enterText(find.byType(EditableText).at(2), '先描述，再归纳。');
        await reveal(tester, find.text('不重复'));
        await tester.tap(find.text('不重复'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('每周').last);
        await tester.pumpAndSettle();
        final monday = find.widgetWithText(FilterChip, '一');
        final defaultDay = find.widgetWithText(
          FilterChip,
          ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1],
        );
        expect(tester.widget<FilterChip>(defaultDay).selected, isTrue);
        await reveal(tester, monday);
        if (!tester.widget<FilterChip>(monday).selected) {
          expect(monday.hitTestable(), findsOneWidget);
          await tester.tap(monday);
          await tester.pumpAndSettle();
        }
        expect(tester.widget<FilterChip>(monday).selected, isTrue);
        await reveal(tester, find.text('保存'));
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        final saved = app.tasks.singleWhere((task) => task.title == '周末观察');
        expect(saved.content, '记录三个观察细节。');
        expect(saved.tutorial, '先描述，再归纳。');
        expect(saved.recurrence, 'weekly');
        expect(
          saved.weekdays,
          orderedEquals(({1, date.weekday}.toList()..sort())),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final diameter in [192.0, 200.0, 240.0, 360.0]) {
    testWidgets(
      'Task focus at ${diameter}dp hides selector and retains task/action',
      (tester) async {
        final app = await configure(tester, diameter: diameter);
        await tester.tap(find.text('街头观察'));
        await tester.pumpAndSettle();
        await reveal(tester, find.byKey(const ValueKey('detail-focus-top')));
        await tester.tap(find.byKey(const ValueKey('detail-focus-top')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('focus-task-selector')), findsNothing);
        expect(find.byKey(const ValueKey('focus-task-title')), findsOneWidget);
        expect(find.text('先观察一个路口'), findsOneWidget);
        await tester.tap(find.text('开始专注'));
        await tester.pumpAndSettle();
        expect(app.focus!.startAction, '先观察一个路口');
        expect(find.byKey(const ValueKey('active-focus-task')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('active-focus-start-action')),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byTooltip('暂停')).shortestSide,
          greaterThanOrEqualTo(48),
        );
        final bounds = tester.getRect(find.byType(ClipOval));
        for (final tooltip in ['暂停', '提前结束']) {
          final rect = tester.getRect(find.byTooltip(tooltip));
          for (final corner in [
            rect.topLeft,
            rect.topRight,
            rect.bottomLeft,
            rect.bottomRight,
          ]) {
            expect(
              (corner - bounds.center).distance,
              lessThanOrEqualTo(diameter / 2),
            );
          }
        }
        final timer = tester.getRect(
          find.byKey(const ValueKey('active-focus-countdown')),
        );
        final status = tester.getRect(
          find.byKey(const ValueKey('active-focus-status')),
        );
        expect(timer.bottom, lessThanOrEqualTo(status.top));
        expect(
          status.bottom,
          lessThanOrEqualTo(tester.getRect(find.byTooltip('暂停')).top),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final kind in ['focus', 'rest']) {
    for (final position in ['top', 'bottom']) {
      testWidgets(
        'Task $position starts the selected task after $kind finishes without dismissal',
        (tester) async {
          final app = await configure(tester);
          final engine = app.engine as FakeFocusEngine;
          final first = app.tasks.first;
          final second = app.tasks[1];
          await tester.tap(find.text(first.title));
          await tester.pumpAndSettle();
          await reveal(tester, find.byKey(const ValueKey('detail-focus-top')));
          await tester.tap(find.byKey(const ValueKey('detail-focus-top')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('开始专注'));
          await tester.pumpAndSettle();
          final completedId = app.focus!.id;
          engine.elapse(Duration(seconds: app.focus!.plannedSeconds));
          await app.refreshFocus();
          await app.refresh();
          await tester.pumpAndSettle();
          if (kind == 'rest') {
            await app.start(first, 5, rest: true);
            engine.elapse(const Duration(minutes: 5));
            await app.refreshFocus();
            await app.refresh();
            await tester.pumpAndSettle();
          }
          expect(app.focus!.finished, isTrue);
          expect(app.focus!.kind, kind);
          Navigator.of(tester.element(find.byType(FocusPage)))
              .popUntil((route) => route.isFirst);
          await tester.pumpAndSettle();
          expect(app.focus!.finished, isTrue);
          await reveal(tester, find.text(second.title));
          await tester.tap(find.text(second.title));
          await tester.pumpAndSettle();
          final entry = find.byKey(ValueKey('detail-focus-$position'));
          await reveal(tester, entry);
          expect(
            find.descendant(of: entry, matching: find.text('开始专注')),
            findsOneWidget,
          );
          await tester.tap(entry);
          await tester.pumpAndSettle();
          expect(find.byType(FocusSetupPage), findsOneWidget);
          expect(find.byType(FocusPage), findsNothing);
          expect(
            find.byKey(const ValueKey('focus-task-selector')),
            findsNothing,
          );
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('focus-task-title')))
                .data,
            second.title,
          );
          await tester.tap(find.text('开始专注'));
          await tester.pumpAndSettle();
          expect(app.focus!.running, isTrue);
          expect(app.focus!.taskId, second.id);
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('active-focus-task')))
                .data,
            second.title,
          );
          expect(
            (app.repository as FakeRepository).sessions[completedId]?['taskId'],
            first.id,
          );
          expect(
            app.focusCount(
              app.tasks.singleWhere((task) => task.id == first.id),
            ),
            1,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final paused in [false, true]) {
    final position = paused ? 'bottom' : 'top';
    testWidgets(
      'Task $position returns to the existing ${paused ? 'paused' : 'running'} focus',
      (tester) async {
        final app = await configure(tester);
        final first = app.tasks.first;
        final second = app.tasks[1];
        await app.start(first, 25);
        if (paused) await app.focusAction('pause');
        await tester.pumpAndSettle();
        final sessionId = app.focus!.id;
        await reveal(tester, find.text(second.title));
        await tester.tap(find.text(second.title));
        await tester.pumpAndSettle();
        final entry = find.byKey(ValueKey('detail-focus-$position'));
        await reveal(tester, entry);
        expect(
          find.descendant(of: entry, matching: find.text('返回专注')),
          findsOneWidget,
        );
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(FocusPage), findsOneWidget);
        expect(find.byType(FocusSetupPage), findsNothing);
        expect(app.focus!.id, sessionId);
        expect(app.focus!.taskId, first.id);
        expect(app.focus!.paused, paused);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('active-focus-task')))
              .data,
          first.title,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final kind in ['focus', 'rest']) {
    testWidgets(
      'Finished $kind preserves completion details and permits a new free focus',
      (tester) async {
        final app = await configure(tester);
        final engine = app.engine as FakeFocusEngine;
        final first = app.tasks.first;
        await app.start(first, 5, rest: kind == 'rest');
        engine.elapse(const Duration(minutes: 5));
        await app.refreshFocus();
        await tester.pumpAndSettle();
        expect(app.focus!.finished, isTrue);
        await tester.tap(find.text('本次专注已结束'));
        await tester.pumpAndSettle();
        expect(find.byType(FocusPage), findsOneWidget);
        expect(find.text(kind == 'rest' ? '休息结束' : '本次专注完成'), findsOneWidget);
        expect(find.text(first.title), findsOneWidget);
        Navigator.of(tester.element(find.byType(FocusPage))).pop();
        await tester.pumpAndSettle();
        await reveal(tester, find.text('开始自由专注'));
        await tester.tap(find.text('开始自由专注'));
        await tester.pumpAndSettle();
        expect(find.byType(FocusSetupPage), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('focus-task-title')))
              .data,
          '自由专注',
        );
        final selector = find.byKey(const ValueKey('focus-task-selector'));
        expect(selector, findsOneWidget);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await reveal(tester, find.text('阅读'));
        await tester.tap(find.text('阅读'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('focus-task-title')))
              .data,
          '阅读',
        );
        await tester.tap(find.text('开始专注'));
        await tester.pumpAndSettle();
        expect(app.focus!.running, isTrue);
        expect(app.focus!.taskTitle, '阅读');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Repeated start waits for permissions once and starts one focus',
    (tester) async {
      final engine = DelayedPermissionsFocusEngine();
      final app = await configure(tester, engine: engine);
      await reveal(tester, find.text('开始自由专注'));
      await tester.tap(find.text('开始自由专注'));
      await tester.pumpAndSettle();
      final start = find.widgetWithText(FilledButton, '开始专注');
      await tester.tap(start);
      await tester.tap(start);
      await tester.pump();
      expect(engine.permissionRequests, 1);
      expect(engine.startRequests, 0);
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      engine.permission.complete();
      await tester.pumpAndSettle();
      expect(engine.startRequests, 1);
      expect(app.focus!.running, isTrue);
      expect(find.byType(FocusPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Leaving setup while permissions are pending cancels the start', (
    tester,
  ) async {
    final engine = DelayedPermissionsFocusEngine();
    final app = await configure(tester, engine: engine);
    await reveal(tester, find.text('开始自由专注'));
    await tester.tap(find.text('开始自由专注'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始专注'));
    await tester.pump();
    expect(engine.permissionRequests, 1);
    Navigator.of(tester.element(find.byType(FocusSetupPage))).pop();
    // Resolve during the exit animation, while the old page is still mounted.
    engine.permission.complete();
    await tester.pumpAndSettle();
    expect(engine.startRequests, 0);
    expect(app.focus, isNull);
    expect(app.lastMinutes, 25);
    expect(find.byType(TaskListPage), findsOneWidget);
    expect(find.byType(FocusPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final action in ['继续专注', '休息一下', '返回任务']) {
    testWidgets('Repeated completion action $action executes once', (
      tester,
    ) async {
      final method = action == '休息一下' ? 'start' : 'dismiss';
      final engine = DelayedCommandFocusEngine(method);
      final app = await configure(tester, engine: engine);
      await app.start(app.tasks.first, 5);
      engine.elapse(const Duration(minutes: 5));
      await app.refreshFocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('本次专注已结束'));
      await tester.pumpAndSettle();
      final button = find.text(action);
      await reveal(tester, button);
      engine.calls.clear();
      engine.delayNext = true;
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(engine.calls.where((call) => call == method), hasLength(1));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '继续专注'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '休息一下'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '返回任务'))
            .onPressed,
        isNull,
      );
      engine.response.complete();
      await tester.pumpAndSettle();
      expect(engine.calls.where((call) => call == method), hasLength(1));
      if (action == '继续专注') {
        expect(find.byType(FocusSetupPage), findsOneWidget);
        Navigator.of(tester.element(find.byType(FocusSetupPage))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(TaskListPage), findsOneWidget);
        expect(find.byType(FocusSetupPage), findsNothing);
      } else if (action == '休息一下') {
        expect(app.focus!.kind, 'rest');
        expect(app.focus!.running, isTrue);
        expect(find.byType(FocusPage), findsOneWidget);
      } else {
        expect(app.focus, isNull);
        expect(find.byType(TaskListPage), findsOneWidget);
        expect(find.byType(FocusPage), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('A failed completion action unlocks the controls for retry', (
    tester,
  ) async {
    final engine = DelayedCommandFocusEngine('start');
    final app = await configure(tester, engine: engine);
    await app.start(app.tasks.first, 5);
    engine.elapse(const Duration(minutes: 5));
    await app.refreshFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('本次专注已结束'));
    await tester.pumpAndSettle();
    final rest = find.widgetWithText(OutlinedButton, '休息一下');
    await reveal(tester, rest);
    engine.delayNext = true;
    await tester.tap(rest);
    engine.response.completeError(
      PlatformException(code: 'TEST', message: '请重试'),
    );
    await tester.pumpAndSettle();
    expect(app.focus!.finished, isTrue);
    expect(tester.widget<OutlinedButton>(rest).onPressed, isNotNull);
    await tester.tap(rest);
    await tester.pumpAndSettle();
    expect(app.focus!.kind, 'rest');
    expect(app.focus!.running, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Leaving focus during resume permissions keeps the timer paused',
    (tester) async {
      final engine = DelayedCommandFocusEngine('permissions');
      final app = await configure(tester, engine: engine);
      final task = app.tasks.first;
      await app.start(task, 25);
      await app.focusAction('pause');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, task.title));
      await tester.pumpAndSettle();
      engine.delayNext = true;
      await tester.tap(find.byTooltip('继续'));
      await tester.tap(find.byTooltip('继续'));
      await tester.pump();
      expect(engine.calls.where((call) => call == 'permissions'), hasLength(1));
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('继续'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('提前结束'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      Navigator.of(tester.element(find.byType(FocusPage))).pop();
      engine.response.complete();
      await tester.pumpAndSettle();
      expect(engine.calls, isNot(contains('resume')));
      expect(app.focus!.paused, isTrue);
      expect(find.byType(TaskListPage), findsOneWidget);
      expect(find.byType(FocusPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('A delayed completion action keeps a subsequently opened page', (
    tester,
  ) async {
    final engine = DelayedCommandFocusEngine('dismiss');
    final app = await configure(tester, engine: engine);
    await app.start(app.tasks.first, 5);
    engine.elapse(const Duration(minutes: 5));
    await app.refreshFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('本次专注已结束'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('返回任务'));
    engine.delayNext = true;
    await tester.tap(find.text('返回任务'));
    await tester.pump();
    final focusContext = tester.element(find.byType(FocusPage));
    Navigator.of(focusContext).push(
      appRoute<void>(
        focusContext,
        builder: (_) =>
            TaskDetailPage(controller: app, task: app.tasks[1], isRound: true),
      ),
    );
    await tester.pumpAndSettle();
    engine.response.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailPage), findsOneWidget);
    expect(find.text(app.tasks[1].title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Global focus can change tasks and drops absent startup action', (
    tester,
  ) async {
    await configure(tester);
    await reveal(tester, find.byTooltip('专注'));
    await tester.tap(find.byTooltip('专注'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus-task-selector')));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('阅读'));
    await tester.tap(find.text('阅读'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('focus-task-title')), findsOneWidget);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.byKey(const ValueKey('focus-start-action')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Large type focus setup fits and running controls scroll without overflow',
    (tester) async {
      await configure(tester, diameter: 200, textScale: 2);
      await reveal(tester, find.text('街头观察'));
      await tester.tap(find.text('街头观察'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('detail-focus-top')));
      await tester.tap(find.byKey(const ValueKey('detail-focus-top')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始专注'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byTooltip('暂停'));
      await tester.tap(find.byTooltip('暂停'));
      await tester.pumpAndSettle();
      expect(find.text('已暂停'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Phone saves all task detail fields independently', (
    tester,
  ) async {
    final app = await configure(tester, round: false);
    await tester.tap(find.text('添加任务'));
    await tester.pumpAndSettle();
    final values = ['读书', '阅读并记录', '', '拓宽知识', '读一节', '写一句收获', '先翻开书', '17'];
    for (var index = 0; index < values.length; index++) {
      final field = find.byType(TextFormField).at(index);
      await Scrollable.ensureVisible(tester.element(field), alignment: .5);
      await tester.pumpAndSettle();
      await tester.enterText(field, values[index]);
    }
    tester.testTextInput.hide();
    await reveal(tester, find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final task = app.tasks.singleWhere((task) => task.title == '读书');
    expect(task.taskValue, '拓宽知识');
    expect(task.minimumGoal, '读一节');
    expect(task.completionStandard, '写一句收获');
    expect(task.startAction, '先翻开书');
    expect(task.estimatedMinutes, 17);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Repeated task save writes once and locks every editor field', (
    tester,
  ) async {
    final repository = DelayedTaskMutationRepository('save');
    await configure(tester, round: false, repository: repository);
    await openTaskEditor(tester);
    await reveal(tester, find.text('不重复'));
    await tester.tap(find.text('不重复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('每周').last);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(repository.calls, 1);
    expect(
      tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .every((field) => field.enabled == false),
      isTrue,
    );
    expect(
      tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .every((field) => field.onChanged == null),
      isTrue,
    );
    expect(
      tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .every((chip) => chip.onSelected == null),
      isTrue,
    );
    final date = find.widgetWithText(ListTile, '日期');
    expect(tester.widget<ListTile>(date).onTap, isNull);
    expect(tester.widget<ListTile>(date).enabled, isFalse);
    repository.response.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditorPage), findsNothing);
    expect(find.byType(TaskDetailPage), findsOneWidget);
    expect(repository.calls, 1);
    expect(tester.takeException(), isNull);
  });
  for (final operation in ['save', 'archive']) {
    testWidgets('Delayed task $operation keeps a subsequently opened page', (
      tester,
    ) async {
      final repository = DelayedTaskMutationRepository(operation);
      await configure(tester, round: false, repository: repository);
      await openTaskEditor(tester);
      final action = find.text(operation == 'save' ? '保存' : '停止安排');
      await reveal(tester, action);
      await tester.tap(action);
      if (operation == 'archive') {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.widgetWithText(FilledButton, '停止安排'));
      }
      await tester.pump();
      final editor = tester.element(find.byType(TaskEditorPage));
      Navigator.of(editor).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('后打开的页面')),
        ),
      );
      await tester.pumpAndSettle();
      repository.response.complete();
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(find.text('后打开的页面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Leaving add-to-today preserves a subsequently selected date', (
    tester,
  ) async {
    final repository = DelayedTaskMutationRepository('add');
    final app = await configure(tester, repository: repository);
    await app.selectDate(
      DateTime.parse(app.today).subtract(const Duration(days: 1)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('街头观察'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('加入今天'));
    await tester.tap(find.text('加入今天'));
    await tester.tap(find.text('加入今天'));
    await tester.pump();
    expect(repository.calls, 1);
    Navigator.of(tester.element(find.byType(TaskDetailPage))).pop();
    await tester.pumpAndSettle();
    final next = DateTime.parse(app.today).add(const Duration(days: 2));
    await app.selectDate(next);
    await tester.pumpAndSettle();
    repository.response.complete();
    await tester.pumpAndSettle();
    expect(app.date, dayKey(next));
    expect(find.byType(TaskListPage), findsOneWidget);
    expect(repository.days[app.today]!.first.carriedFromDate, isNotNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Delayed task completion keeps a subsequently opened page', (
    tester,
  ) async {
    final store = DelayedTaskStore();
    final app = await configure(tester, store: store);
    await tester.tap(find.text('街头观察'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('标记完成'));
    store.block = true;
    await tester.tap(find.text('标记完成'));
    await tester.pump();
    final detail = tester.element(find.byType(TaskDetailPage));
    Navigator.of(detail).push(
      appRoute<void>(
        detail,
        builder: (_) => const Scaffold(body: Text('后打开的页面')),
      ),
    );
    await tester.pumpAndSettle();
    store.response.complete();
    await tester.pumpAndSettle();
    expect(app.completed.single.title, '街头观察');
    expect(find.text('后打开的页面'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final completed in [false, true]) {
    testWidgets('Undo restores $completed completion after switching dates', (
      tester,
    ) async {
      const date = '2026-11-09';
      final repository = FakeRepository();
      repository.days[date] = fixtures(date);
      if (completed) {
        repository.days[date]![0] = repository.days[date]!.first.withCompletion(
          '2026-11-09 01:00:00.000',
        );
      }
      final original = repository.days[date]!.first;
      final app = await configure(tester, repository: repository);
      final toggle = find.byTooltip('${completed ? '恢复待办' : '完成'}街头观察');
      await reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final next = DateTime.parse(date).add(const Duration(days: 1));
      await app.selectDate(next);
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(app.date, dayKey(next));
      expect(repository.days[date]!.first.completedAt, original.completedAt);
      await app.selectDate(DateTime.parse(date));
      await tester.pumpAndSettle();
      expect(app.tasks.first.completedAt, original.completedAt);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Swipe from left edge returns to tasks without resizing cards', (
    tester,
  ) async {
    await configure(tester);
    await tester.tap(find.text('街头观察'));
    await tester.pumpAndSettle();
    await tester.dragFrom(const Offset(4, 120), const Offset(130, 0));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailPage), findsNothing);
    expect(find.byType(TaskListPage), findsOneWidget);
  });
  testWidgets(
    'Watch browses yesterday and tomorrow and carries an unfinished task to today',
    (tester) async {
      final app = await configure(tester);
      final today = DateTime.parse(app.today);
      await tester.tap(find.byKey(const ValueKey('task-date-selector')));
      await tester.pumpAndSettle();
      final yesterday = today.subtract(const Duration(days: 1));
      // The calendar starts at the selected week, so Monday's yesterday
      // needs one backward crown step to reveal the preceding Sunday.
      if (today.weekday == DateTime.monday) {
        await rotary(tester, -40);
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.byKey(ValueKey('calendar-day-${dayKey(yesterday)}')),
      );
      await tester.pumpAndSettle();
      expect(app.date, dayKey(today.subtract(const Duration(days: 1))));
      await reveal(tester, find.text('街头观察'));
      await tester.tap(find.text('街头观察'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('加入今天'));
      await tester.tap(find.text('加入今天'));
      await tester.pumpAndSettle();
      expect(app.date, app.today);
      expect(
        app.tasks.where((task) => task.templateId == 'observe'),
        hasLength(1),
      );
      await reveal(tester, find.byKey(const ValueKey('task-date-selector')));
      await tester.tap(find.byKey(const ValueKey('task-date-selector')));
      await tester.pumpAndSettle();
      final tomorrow = today.add(const Duration(days: 1));
      await tester.tap(
        find.byKey(ValueKey('calendar-day-${dayKey(tomorrow)}')),
      );
      await tester.pumpAndSettle();
      expect(app.date, dayKey(today.add(const Duration(days: 1))));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Crown and physical mouse wheel animate and preserve rapid focus steps',
    (tester) async {
      final app = await configure(tester);
      await reveal(tester, find.byTooltip('专注'));
      await tester.tap(find.byTooltip('专注'));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<ListWheelScrollView>(find.byType(ListWheelScrollView))
          .controller!;
      final initial = controller.offset;
      await rotary(tester, 40);
      expect(controller.offset, initial);
      await tester.pump(const Duration(milliseconds: 60));
      expect(controller.offset, greaterThan(initial));
      expect(controller.offset, lessThan(initial + 40));
      await tester.pumpAndSettle();
      expect(controller.offset, initial + 40);
      await rotary(tester, 40);
      await rotary(tester, 40);
      await rotary(tester, 40);
      await tester.pumpAndSettle();
      expect(controller.offset, initial + 160);
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(ListWheelScrollView)),
          kind: PointerDeviceKind.mouse,
          scrollDelta: const Offset(0, -40),
        ),
      );
      await tester.pump();
      final before = controller.offset;
      await tester.pump(const Duration(milliseconds: 60));
      expect(controller.offset, lessThan(before));
      expect(controller.offset, greaterThan(initial + 120));
      await tester.pumpAndSettle();
      expect(controller.offset, initial + 120);
      expect(app.lastMinutes, 25);
      await tester.tap(find.text('开始专注'));
      await tester.pumpAndSettle();
      expect(app.lastMinutes, 40);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Calendar selects nearby leap-day dates with one tap and crown scrolls weeks',
    (tester) async {
      await configure(tester, diameter: 200, textScale: 2);
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WearDatePicker(
              initialDate: DateTime(2024, 2, 29),
              onPicked: (date) async {
                picked = date;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListWheelScrollView), findsNothing);
      await tester.tap(find.byKey(const ValueKey('calendar-day-2024-03-01')));
      await tester.pumpAndSettle();
      expect(picked, DateTime(2024, 3, 1));
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('calendar-weeks')),
      );
      final initial = list.controller!.offset;
      await rotary(tester, 40);
      await rotary(tester, 40);
      await rotary(tester, 40);
      await tester.pumpAndSettle();
      expect(list.controller!.offset, greaterThan(initial));
      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, greaterThan(initial + 100));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Detail focus actions scroll with content and the bottom action opens focus',
    (tester) async {
      await configure(tester);
      await tester.tap(find.text('街头观察'));
      await tester.pumpAndSettle();
      expect(find.byType(WearEdgeButton), findsNothing);
      final top = find.byKey(const ValueKey('detail-focus-top'));
      final bottom = find.byKey(const ValueKey('detail-focus-bottom'));
      final before = tester.getTopLeft(top).dy;
      listController(tester).jumpTo(50);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(top).dy, lessThan(before));
      await reveal(tester, bottom);
      await tester.tap(bottom);
      await tester.pumpAndSettle();
      expect(find.byType(FocusSetupPage), findsOneWidget);
      expect(find.byType(WearEdgeButton), findsNothing);
      final start = tester.getRect(find.widgetWithText(FilledButton, '开始专注'));
      final circle = tester.getRect(find.byType(ClipOval));
      for (final corner in [
        start.topLeft,
        start.topRight,
        start.bottomLeft,
        start.bottomRight,
      ]) {
        expect(
          (corner - circle.center).distance,
          lessThanOrEqualTo(circle.width / 2),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final round in [true, false]) {
    testWidgets('Day swipes browse tomorrow and the day after (round=$round)', (
      tester,
    ) async {
      final app = await configure(tester, round: round);
      final today = DateTime.parse(app.today);
      for (final days in [1, 2]) {
        await tester.dragFrom(const Offset(175, 120), const Offset(-125, 0));
        await tester.pumpAndSettle();
        expect(app.date, dayKey(today.add(Duration(days: days))));
        expect(app.tasks.every((task) => task.date == app.date), isTrue);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('task-date-selector')),
            matching: find.text(
              '${today.add(Duration(days: days)).month}月${today.add(Duration(days: days)).day}日',
            ),
          ),
          findsOneWidget,
        );
        expect(find.byType(TaskDatePage), findsNothing);
      }
      // A root-page swipe must also work from the left edge.
      await tester.dragFrom(const Offset(4, 120), const Offset(130, 0));
      await tester.pumpAndSettle();
      expect(app.date, dayKey(today.add(const Duration(days: 1))));
      await tester.tap(find.byTooltip('回到今天'));
      await tester.pumpAndSettle();
      expect(app.date, app.today);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Vertical, short and cancelled drags keep the selected day', (
    tester,
  ) async {
    final app = await configure(tester);
    final date = app.date;
    await tester.dragFrom(const Offset(120, 170), const Offset(8, -90));
    await tester.pumpAndSettle();
    expect(listController(tester).offset, greaterThan(0));
    expect(app.date, date);
    final short = await tester.startGesture(const Offset(150, 120));
    await short.moveBy(const Offset(-25, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await short.up();
    await tester.pumpAndSettle();
    expect(app.date, date);
    final cancelled = await tester.startGesture(const Offset(175, 120));
    await cancelled.moveBy(const Offset(-100, 0));
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(app.date, date);
    expect(app.completed, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Day swipes cross leap days, months and years', (tester) async {
    final app = await configure(tester);
    for (final dates in [
      ['2024-02-28', '2024-02-29', '2024-03-01'],
      ['2026-12-30', '2026-12-31', '2027-01-01'],
    ]) {
      await app.selectDate(DateTime.parse(dates.first));
      await tester.pumpAndSettle();
      for (final date in dates.skip(1)) {
        await tester.dragFrom(const Offset(175, 120), const Offset(-125, 0));
        await tester.pumpAndSettle();
        expect(app.date, date);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Rapid swipes stay responsive while loading and reject stale tasks',
    (tester) async {
      final repository = DelayedRepository();
      final app = await configure(tester, repository: repository);
      repository.block = true;
      final today = DateTime.parse(app.today);
      final dates = [
        for (var days = 1; days <= 3; days++)
          dayKey(today.add(Duration(days: days))),
      ];
      for (final date in dates) {
        await tester.dragFrom(const Offset(175, 120), const Offset(-125, 0));
        await tester.pump();
        expect(app.date, date);
        expect(app.loading, isTrue);
        expect(app.tasks, isEmpty);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
      expect(repository.requests.keys, [dates.first]);
      repository.requests[dates.first]!.complete(fixtures(dates.first));
      await tester.pump();
      expect(repository.requests.keys, [dates.first, dates.last]);
      expect(app.date, dates.last);
      expect(app.tasks, isEmpty);
      expect(find.text('街头观察'), findsNothing);
      repository.requests[dates.last]!.complete([]);
      await tester.pumpAndSettle();
      expect(app.loading, isFalse);
      expect(app.tasks, isEmpty);
      // An empty day's whole list remains swipeable.
      repository.block = false;
      await tester.dragFrom(const Offset(175, 120), const Offset(-125, 0));
      await tester.pumpAndSettle();
      expect(app.date, dayKey(today.add(const Duration(days: 4))));
      expect(app.tasks.every((task) => task.date == app.date), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Calendar closes immediately while an uncached date loads', (
    tester,
  ) async {
    final repository = DelayedRepository();
    final app = await configure(tester, repository: repository);
    repository.block = true;
    await tester.tap(find.byKey(const ValueKey('task-date-selector')));
    await tester.pumpAndSettle();
    final next = DateTime.parse(app.today).add(const Duration(days: 1));
    final key = dayKey(next);
    await tester.tap(find.byKey(ValueKey('calendar-day-$key')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TaskDatePage), findsNothing);
    expect(app.date, key);
    expect(app.loading, isTrue);
    expect(app.tasks, isEmpty);
    repository.requests[key]!.complete(fixtures(key));
    await tester.pumpAndSettle();
    expect(find.text('街头观察'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home swipes still work after returning from a loading calendar',
    (tester) async {
      final repository = DelayedRepository();
      final app = await configure(tester, repository: repository);
      repository.block = true;
      final tomorrow = dayKey(
        DateTime.parse(app.today).add(const Duration(days: 1)),
      );
      await tester.tap(find.byKey(const ValueKey('task-date-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('calendar-day-$tomorrow')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.dragFrom(const Offset(4, 120), const Offset(130, 0));
      await tester.pump();
      expect(app.date, app.today);
      expect(app.tasks.every((task) => task.date == app.today), isTrue);
      repository.requests[tomorrow]!.complete(fixtures(tomorrow));
      await tester.pump();
      repository.requests[app.today]!.complete(fixtures(app.today));
      await tester.pumpAndSettle();
      expect(app.date, app.today);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('First frame renders before local restoration has finished', (
    tester,
  ) async {
    await configure(tester);
    final store = DelayedStore();
    final app = AppController(
      repository: FakeRepository(),
      store: store,
      engine: FakeFocusEngine(),
    );
    await tester.pumpWidget(
      MyApp(
        key: UniqueKey(),
        controller: app,
        isRound: true,
        initializeController: true,
      ),
    );
    expect(find.byType(TaskListPage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(app.initializing, isTrue);
    store.restored.complete(
      jsonEncode({
        'days': {
          app.today: fixtures(app.today).map((task) => task.toJson()).toList(),
        },
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('街头观察'), findsOneWidget);
    expect(app.initializing, isFalse);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets(
    'Edge swipe follows the finger and cancellation restores the page',
    (tester) async {
      await configure(tester);
      await tester.tap(find.text('街头观察'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(4, 120));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(35, 0));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byType(TaskDetailPage)).dx,
        greaterThan(10),
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(TaskDetailPage)).dx, closeTo(0, .1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'List checkbox completes immediately and snackbar undo restores order',
    (tester) async {
      final ticks = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        TouchHaptics.channel,
        (call) async {
          ticks.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          TouchHaptics.channel,
          null,
        ),
      );
      final app = await configure(tester);
      await tester.tap(find.byTooltip('完成街头观察'));
      await tester.pumpAndSettle();
      expect(ticks.map((call) => call.method), ['selection']);
      expect(app.completed.single.title, '街头观察');
      expect(find.byType(TaskDetailPage), findsNothing);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(app.pending.first.title, '街头观察');
      expect(app.completed, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Completion notice with undo disappears after three seconds', (
    tester,
  ) async {
    await configure(tester);
    await tester.tap(find.byTooltip('完成街头观察'));
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
