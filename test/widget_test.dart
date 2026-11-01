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
    store: MemoryStore(),
    engine: FakeFocusEngine(),
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

void main() {
  for (final diameter in [200.0, 240.0, 360.0]) {
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
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      expect(app.lastMinutes, 30);
      expect(app.focus!.taskTitle, '街头观察');
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
  testWidgets('Phone creates a weekly task with all content preserved', (
    tester,
  ) async {
    final app = await configure(tester, round: false);
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
    await reveal(tester, find.text('一'));
    await tester.tap(find.text('一'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final saved = app.tasks.singleWhere((task) => task.title == '周末观察');
    expect(saved.content, '记录三个观察细节。');
    expect(saved.tutorial, '先描述，再归纳。');
    expect(saved.recurrence, 'weekly');
    expect(saved.weekdays, contains(1));
    expect(tester.takeException(), isNull);
  });
  for (final diameter in [200.0, 240.0, 360.0]) {
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
        await tester.tap(find.text('开始'));
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
    'Large type focus setup and running controls scroll without overflow',
    (tester) async {
      await configure(tester, diameter: 200, textScale: 2);
      await reveal(tester, find.text('街头观察'));
      await tester.tap(find.text('街头观察'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('detail-focus-top')));
      await tester.tap(find.byKey(const ValueKey('detail-focus-top')));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('开始'));
      await tester.tap(find.text('开始'));
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
      await tester.tap(find.text('开始'));
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
      expect(tester.getRect(find.byType(WearEdgeButton)).bottom, 240);
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
          find.text('${days == 1 ? '明天' : '后天'} · ${app.date.substring(5)}'),
          findsOneWidget,
        );
        expect(find.byType(TaskDatePage), findsNothing);
      }
      // A root-page swipe must also work from the left edge.
      await tester.dragFrom(const Offset(4, 120), const Offset(130, 0));
      await tester.pumpAndSettle();
      expect(app.date, dayKey(today.add(const Duration(days: 1))));
      await tester.tap(find.text('回到今天'));
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
}
