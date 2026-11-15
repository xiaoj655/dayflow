import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/app_colors.dart';
import 'package:life_assistant/widgets/focus_finished_view.dart';
import 'package:life_assistant/widgets/screen_viewport.dart';

void _noop() {}

Future<void> _pumpFinished(
  WidgetTester tester, {
  double diameter = 192,
  double textScale = 1,
  bool isRound = true,
  bool busy = false,
  bool isRest = false,
  bool taskCompleted = false,
  bool interrupted = false,
  int? actualSeconds,
  String taskTitle = '整理项目需求与下一步计划',
  VoidCallback onContinue = _noop,
  VoidCallback onChangeTask = _noop,
  VoidCallback onReturn = _noop,
  VoidCallback? onRest,
  VoidCallback? onTaskCompletion,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = isRound
      ? Size.square(diameter)
      : const Size(390, 844);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => ScreenShape(isRound: isRound, child: child!),
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(primary: AppColors.primary),
      ),
      home: FocusFinishedView(
        isRound: isRound,
        taskTitle: taskTitle,
        minutes: 25,
        isRest: isRest,
        busy: busy,
        taskCompleted: taskCompleted,
        interrupted: interrupted,
        actualSeconds: actualSeconds,
        onContinue: onContinue,
        onChangeTask: onChangeTask,
        onReturn: onReturn,
        onRest: onRest,
        onTaskCompletion: onTaskCompletion,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _control(String name) => find.byKey(ValueKey('focus-finished-$name'));

void _expectInsideCircle(WidgetTester tester, Finder finder, double diameter) {
  final rect = tester.getRect(finder);
  final center = Offset(diameter / 2, diameter / 2);
  for (final corner in [
    rect.topLeft,
    rect.topRight,
    rect.bottomLeft,
    rect.bottomRight,
  ]) {
    expect(
      (corner - center).distance,
      lessThanOrEqualTo(diameter / 2),
      reason: '$finder must fit inside the round viewport',
    );
  }
}

void main() {
  for (final diameter in [192.0, 240.0]) {
    for (final seconds in [0, 179, 180, 10799]) {
      testWidgets(
        'Early finish shows $seconds seconds safely at $diameter dp',
        (tester) async {
          await _pumpFinished(
            tester,
            diameter: diameter,
            interrupted: true,
            actualSeconds: seconds,
            onRest: _noop,
            onTaskCompletion: _noop,
          );
          expect(find.text('提前结束'), findsOneWidget);
          final duration = tester.widget<Text>(_control('minutes')).data!;
          expect(duration, contains('${seconds ~/ 60}分${seconds % 60}秒'));
          expect(duration.contains('未记录'), seconds < 180);
          _expectInsideCircle(tester, _control('minutes'), diameter);
          for (final name in [
            'task-completion',
            'continue',
            'rest',
            'change-task',
          ]) {
            expect(_control(name).hitTestable(), findsOneWidget);
            _expectInsideCircle(tester, _control(name), diameter);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('All next-round actions fit on the first $diameter dp screen', (
      tester,
    ) async {
      final calls = <String>[];
      await _pumpFinished(
        tester,
        diameter: diameter,
        onContinue: () => calls.add('continue'),
        onChangeTask: () => calls.add('change-task'),
        onReturn: () => calls.add('return'),
        onRest: () => calls.add('rest'),
        onTaskCompletion: () => calls.add('task-completion'),
      );
      expect(find.text('专注完成'), findsOneWidget);
      expect(find.text('25 分钟'), findsOneWidget);
      expect(find.byType(Scrollable), findsNothing);
      for (final name in ['title', 'task', 'minutes']) {
        _expectInsideCircle(tester, _control(name), diameter);
      }
      for (final name in [
        'return',
        'task-completion',
        'continue',
        'rest',
        'change-task',
      ]) {
        final finder = _control(name);
        expect(finder.hitTestable(), findsOneWidget);
        _expectInsideCircle(tester, finder, diameter);
        await tester.tap(finder);
        await tester.pump();
      }
      expect(calls, [
        'return',
        'task-completion',
        'continue',
        'rest',
        'change-task',
      ]);
      final primary = tester.widget<FilledButton>(_control('continue'));
      expect(primary.style!.backgroundColor!.resolve({}), AppColors.primary);
      expect(primary.style!.foregroundColor!.resolve({}), AppColors.onPrimary);
      final changeTask = tester.widget<FilledButton>(_control('change-task'));
      expect(changeTask.style!.backgroundColor!.resolve({}), AppColors.surface);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Busy disables every action including completion and return', (
    tester,
  ) async {
    var calls = 0;
    void tapped() => calls++;
    await _pumpFinished(
      tester,
      busy: true,
      onContinue: tapped,
      onChangeTask: tapped,
      onReturn: tapped,
      onRest: tapped,
      onTaskCompletion: tapped,
    );
    for (final button in tester.widgetList<ButtonStyleButton>(
      find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    )) {
      expect(button.onPressed, isNull);
    }
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      expect(button.onPressed, isNull);
    }
    for (final name in [
      'return',
      'task-completion',
      'continue',
      'rest',
      'change-task',
    ]) {
      await tester.tap(_control(name));
    }
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Free focus has no task completion control', (tester) async {
    await _pumpFinished(tester, taskTitle: '自由专注', onRest: _noop);
    expect(_control('task-completion'), findsNothing);
    expect(find.text('自由专注'), findsOneWidget);
    expect(_control('change-task').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Completed task remains available to undo', (tester) async {
    var calls = 0;
    await _pumpFinished(
      tester,
      taskCompleted: true,
      onTaskCompletion: () => calls++,
    );
    expect(find.byTooltip('恢复待办'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(tester.widget<Text>(_control('task')).style!.color, AppColors.muted);
    await tester.tap(_control('task-completion'));
    expect(calls, 1);
  });

  testWidgets('Rest completion omits another rest action', (tester) async {
    await _pumpFinished(tester, isRest: true, onRest: _noop);
    expect(find.text('休息结束'), findsOneWidget);
    expect(_control('rest'), findsNothing);
    expect(_control('continue').hitTestable(), findsOneWidget);
    expect(_control('change-task').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Large text scrolls every action into a safe full button', (
    tester,
  ) async {
    final calls = <String>[];
    await _pumpFinished(
      tester,
      textScale: 2,
      interrupted: true,
      actualSeconds: 179,
      onContinue: () => calls.add('continue'),
      onChangeTask: () => calls.add('change-task'),
      onRest: () => calls.add('rest'),
      onTaskCompletion: () => calls.add('task-completion'),
    );
    expect(find.byType(ShapeScrollView), findsOneWidget);
    await tester.scrollUntilVisible(
      _control('minutes'),
      50,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('2分59秒 · 未记录'), findsOneWidget);
    for (final name in ['continue', 'rest', 'change-task']) {
      await tester.scrollUntilVisible(
        _control(name),
        50,
        scrollable: find.byType(Scrollable),
      );
      await Scrollable.ensureVisible(
        tester.element(_control(name)),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      expect(_control(name).hitTestable(), findsOneWidget);
      _expectInsideCircle(tester, _control(name), 192);
      await tester.tap(_control(name));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(calls, ['continue', 'rest', 'change-task']);
  });

  testWidgets('Phone layout stays centered without overflow', (tester) async {
    await _pumpFinished(tester, isRound: false, onRest: _noop);
    final primary = tester.getCenter(_control('continue'));
    expect(primary.dx, closeTo(195, .01));
    expect(_control('return').hitTestable(), findsOneWidget);
    expect(_control('change-task').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
