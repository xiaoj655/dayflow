import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/app_colors.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/widgets/focus_task_brief.dart';
import 'package:life_assistant/widgets/screen_viewport.dart';

DailyTask _task({
  String title = '整理项目资料',
  String content = '汇总当前项目资料并记录下一步。',
  String? startAction,
  String? minimumGoal,
  String? completionStandard,
  String? taskValue,
  String? tutorial,
  int? estimatedMinutes,
}) => DailyTask(
  id: 'brief-task',
  templateId: 'brief-template',
  date: '2026-11-15',
  title: title,
  content: content,
  startAction: startAction,
  minimumGoal: minimumGoal,
  completionStandard: completionStandard,
  taskValue: taskValue,
  tutorial: tutorial,
  estimatedMinutes: estimatedMinutes,
);

Future<void> _mount(
  WidgetTester tester,
  DailyTask task, {
  double diameter = 240,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size.square(diameter);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
      ),
      builder: (context, child) => ScreenShape(isRound: true, child: child!),
      home: FocusTaskBrief(task: task, isRound: true),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _part(String id) => find.byKey(ValueKey('focus-brief-$id'));

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final controller = tester.widget<ListView>(find.byType(ListView)).controller!;
  controller.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    target,
    60,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: .3);
  await tester.pumpAndSettle();
}

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets(
      'Read full task action and goals by scrolling at $diameter dp',
      (tester) async {
        final task = _task(
          title: '整理项目资料并明确这一轮需要推进的事项与交付结果',
          startAction: '先打开项目文档，标记本轮需要解决的一个问题。' * 7,
          minimumGoal: '至少记录一个可以执行的小步骤，并写出还需要确认的信息。' * 3,
          completionStandard: '把结果保存到项目笔记，并确认下一步可以直接开始。' * 3,
          estimatedMinutes: 35,
        );
        await _mount(tester, task, diameter: diameter);
        final title = tester.widget<Text>(_part('title'));
        expect(title.data, task.title);
        expect(title.maxLines, isNull);
        expect(title.overflow, isNull);
        for (final part in {
          'start-action': task.startAction,
          'minimum-goal': task.minimumGoal,
          'completion-standard': task.completionStandard,
          'estimate': '35 分钟',
        }.entries) {
          await _reveal(tester, _part(part.key));
          final text = tester.widget<Text>(_part(part.key));
          expect(text.data, part.value);
          expect(text.maxLines, isNull);
          expect(text.overflow, isNull);
          expect(tester.takeException(), isNull);
        }
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(TextFormField), findsNothing);
      },
    );
  }

  testWidgets('Tasks without goal fields show their content immediately', (
    tester,
  ) async {
    final task = _task(content: '读一节书，随后写一句今天的收获。');
    await _mount(tester, task, diameter: 192);
    await _reveal(tester, _part('content'));
    expect(tester.widget<Text>(_part('content')).data, task.content);
    expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);
    expect(_part('start-action'), findsNothing);
    expect(_part('minimum-goal'), findsNothing);
    expect(_part('completion-standard'), findsNothing);
    expect(_part('estimate'), findsNothing);
    expect(_part('tutorial-toggle'), findsNothing);
    expect(_part('task-value-toggle'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Optional sections expand and collapse without changing task data',
    (tester) async {
      final task = _task(
        startAction: '先打开文档',
        minimumGoal: '写出一个下一步',
        taskValue: '减少下次开始时的犹豫',
        tutorial: '先列出已知信息，再标记需要确认的部分。',
      );
      final original = task.toJson();
      await _mount(tester, task);
      for (final entry in {
        'task-value': task.taskValue,
        'content': task.content,
        'tutorial': task.tutorial,
      }.entries) {
        final toggle = _part('${entry.key}-toggle');
        await _reveal(tester, toggle);
        expect(_part(entry.key), findsNothing);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await _reveal(tester, _part(entry.key));
        expect(tester.widget<Text>(_part(entry.key)).data, entry.value);
        await _reveal(tester, toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(_part(entry.key), findsNothing);
      }
      expect(task.toJson(), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Whitespace-only task sections are omitted', (tester) async {
    await _mount(
      tester,
      _task(
        content: '  ',
        startAction: '\n',
        minimumGoal: ' ',
        completionStandard: '\t',
        taskValue: ' ',
        tutorial: '\n ',
      ),
    );
    for (final name in [
      'start-action',
      'minimum-goal',
      'completion-standard',
      'estimate',
      'task-value-toggle',
      'content-toggle',
      'tutorial-toggle',
    ]) {
      expect(_part(name), findsNothing);
    }
    expect(find.text('本次任务'), findsOneWidget);
    expect(_part('title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Large type still scrolls through task goals at 192 dp', (
    tester,
  ) async {
    final task = _task(
      startAction: '先打开文档并选出一个问题。' * 4,
      minimumGoal: '记录一个可执行的小步骤。' * 3,
      completionStandard: '保存这一轮结果并确认下一步。' * 3,
    );
    await _mount(tester, task, diameter: 192, textScale: 2);
    await _reveal(tester, _part('completion-standard'));
    expect(
      tester.widget<Text>(_part('completion-standard')).data,
      task.completionStandard,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phone back returns to the original page', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final task = _task();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => FocusTaskBrief(task: task, isRound: false),
                ),
              ),
              child: const Text('原专注页面'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('原专注页面'));
    await tester.pumpAndSettle();
    expect(find.text('本次任务'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('原专注页面'), findsOneWidget);
    expect(find.byType(FocusTaskBrief), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
