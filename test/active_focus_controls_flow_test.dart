import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/app_colors.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/pages/app_pages.dart';
import 'package:life_assistant/widgets/active_focus_controls.dart';

import 'fakes.dart';
import 'widget_test.dart' show configure;

Finder _active(String name) => find.byKey(ValueKey('active-focus-$name'));

Future<AppController> _openTimer(
  WidgetTester tester, {
  required double diameter,
  required double textScale,
  bool steps = false,
  bool rest = false,
}) async {
  const date = '2026-11-09';
  final task = DailyTask(
    id: 'sync:$date',
    templateId: 'sync',
    date: date,
    title: '修复登录失败并验证跨设备同步',
    content: '排查登录失败并验证修复。',
    startAction: '打开日志，复现登录失败并记下出现问题的条件。',
    steps: steps
        ? const [
            TaskStep(id: 'reproduce', title: '打开日志并复现登录失败，记下出现问题的条件'),
            TaskStep(id: 'fix', title: '修改代码'),
          ]
        : const [],
  );
  final engine = FakeFocusEngine()..now = DateTime.utc(2026, 11, 9, 2);
  final app = await configure(
    tester,
    diameter: diameter,
    textScale: textScale,
    repository: FakeRepository()..days[date] = [task],
    engine: engine,
    clock: () => engine.now,
  );
  await app.start(app.tasks.single, rest ? 5 : 25, rest: rest);
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => FocusPage(controller: app, isRound: true),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

void _expectTimerLayout(
  WidgetTester tester,
  double diameter, {
  bool steps = false,
}) {
  final countdown = tester.getRect(_active('countdown'));
  final status = tester.getRect(_active('status'));
  final controls = tester.getRect(_active('controls'));
  expect(countdown.bottom, lessThanOrEqualTo(status.top));
  expect(status.bottom, lessThanOrEqualTo(controls.top));
  if (steps) {
    final title = tester.getRect(_active('task'));
    final current = tester.getRect(
      find.byKey(const ValueKey('current-task-step')),
    );
    expect(title.bottom, lessThanOrEqualTo(current.top));
    expect(current.bottom, lessThanOrEqualTo(countdown.top));
  }
  final center = Offset(diameter / 2, diameter / 2);
  for (final name in ['stop', 'toggle']) {
    final control = _active(name);
    expect(control.hitTestable(), findsOneWidget);
    final bounds = tester.getRect(control);
    expect(bounds.width, greaterThanOrEqualTo(40));
    expect(bounds.height, greaterThanOrEqualTo(40));
    for (final corner in [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomLeft,
      bounds.bottomRight,
    ]) {
      expect((corner - center).distance, lessThan(diameter / 2));
    }
  }
}

void _expectToggleColors(WidgetTester tester, {required bool primary}) {
  final style = tester.widget<FilledButton>(_active('toggle')).style!;
  expect(
    style.backgroundColor!.resolve({}),
    primary ? AppColors.primary : AppColors.overlay,
  );
  expect(
    style.foregroundColor!.resolve({}),
    primary ? AppColors.background : AppColors.text,
  );
}

Future<void> _tapToggleEdge(WidgetTester tester) async {
  await tester.tapAt(
    tester.getRect(_active('toggle')).centerRight - const Offset(4, 0),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final diameter in [192.0, 220.0, 240.0]) {
    for (final textScale in [1.0, 1.1]) {
      for (final steps in [false, true]) {
        testWidgets(
          'Timer controls remain safe with steps=$steps at $diameter dp, scale $textScale',
          (tester) async {
            final app = await _openTimer(
              tester,
              diameter: diameter,
              textScale: textScale,
              steps: steps,
            );
            final original = app.focus!;
            expect(find.byType(ActiveFocusControls), findsOneWidget);
            _expectTimerLayout(tester, diameter, steps: steps);
            _expectToggleColors(tester, primary: true);
            expect(find.byTooltip('暂停'), findsOneWidget);

            await _tapToggleEdge(tester);
            expect(app.focus!.paused, isTrue);
            expect(app.focus!.id, original.id);
            expect(app.focus!.taskId, original.taskId);
            expect(app.focus!.remainingMillis, original.remainingMillis);
            expect(find.byTooltip('继续'), findsOneWidget);
            _expectToggleColors(tester, primary: false);
            _expectTimerLayout(tester, diameter, steps: steps);

            await _tapToggleEdge(tester);
            expect(app.focus!.running, isTrue);
            expect(app.focus!.id, original.id);
            expect(app.focus!.plannedSeconds, original.plannedSeconds);
            expect(app.focus!.remainingMillis, original.remainingMillis);
            _expectToggleColors(tester, primary: true);
            _expectTimerLayout(tester, diameter, steps: steps);
            expect(app.tasks.single.completedStepCount, 0);
            expect(app.tasks.single.completed, isFalse);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      'Rest controls stay neutral and resume the same rest at $diameter dp',
      (tester) async {
        final app = await _openTimer(
          tester,
          diameter: diameter,
          textScale: 1.1,
          steps: true,
          rest: true,
        );
        final original = app.focus!;
        expect(find.byKey(const ValueKey('current-task-step')), findsNothing);
        expect(find.byTooltip('结束休息'), findsOneWidget);
        expect(find.text('休息中'), findsOneWidget);
        _expectTimerLayout(tester, diameter);
        _expectToggleColors(tester, primary: false);
        await _tapToggleEdge(tester);
        expect(app.focus!.paused, isTrue);
        expect(find.text('已暂停'), findsOneWidget);
        _expectToggleColors(tester, primary: false);
        await _tapToggleEdge(tester);
        expect(app.focus!.running, isTrue);
        expect(app.focus!.kind, 'rest');
        expect(app.focus!.id, original.id);
        expect(app.focus!.remainingMillis, original.remainingMillis);
        expect(find.text('休息中'), findsOneWidget);
        _expectToggleColors(tester, primary: false);
        _expectTimerLayout(tester, diameter);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
