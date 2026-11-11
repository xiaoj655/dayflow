import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/app_colors.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/pages/app_pages.dart';

import 'fakes.dart';
import 'widget_test.dart' show configure;

const workChannel = MethodChannel('life_assistant/work');

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets(
      'Daily and weekly progress use the visible pool at $diameter dp',
      (tester) async {
        var now = DateTime.utc(2026, 11, 9, 2);
        const date = '2026-11-09';
        DailyTask work(
          String id, {
          String? completedAt,
          bool waiting = false,
        }) => DailyTask(
          id: id,
          templateId: id,
          date: '2026-11-01',
          title: id,
          content: '工作任务',
          space: 'work',
          completedAt: completedAt,
          waiting: waiting,
        );
        final repository = FakeRepository();
        final workPool = [
          work('跨周待办'),
          work('等待回复', waiting: true),
          work('本周完成', completedAt: '2026-11-09 01:00:00'),
          work('上周完成', completedAt: '2026-11-08 01:00:00'),
        ];
        repository.days[date] = [...fixtures(date), ...workPool];
        final app = await configure(
          tester,
          diameter: diameter,
          repository: repository,
          clock: () => now,
        );
        Finder getProgress() => find.byType(LinearProgressIndicator);
        expect(find.text('今日任务'), findsOneWidget);
        expect(tester.widget<LinearProgressIndicator>(getProgress()).value, 0);
        await tester.tap(find.byTooltip('完成街头观察'));
        await tester.pumpAndSettle();
        final progress = tester.widget<LinearProgressIndicator>(getProgress());
        expect(progress.value, closeTo(1 / 3, .001));
        expect(progress.color, AppColors.taskProgress);
        await tester.tap(find.text('撤销'));
        await tester.pumpAndSettle();
        expect(tester.widget<LinearProgressIndicator>(getProgress()).value, 0);

        await app.selectSpace('work');
        await tester.pumpAndSettle();
        expect(find.text('本周任务'), findsOneWidget);
        expect(
          app.visibleTasks.map((t) => t.title),
          containsAll(['跨周待办', '等待回复']),
        );
        expect(app.visibleTasks, hasLength(3));
        expect(
          tester.widget<LinearProgressIndicator>(getProgress()).value,
          closeTo(1 / 3, .001),
        );
        await app.toggle(app.tasks.singleWhere((t) => t.title == '等待回复'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<LinearProgressIndicator>(getProgress()).value,
          closeTo(2 / 3, .001),
        );
        now = now.add(const Duration(days: 7));
        // The real repository returns the persistent work pool on every date.
        repository.days[app.today] = [
          ...fixtures(app.today),
          ...repository.days[date]!.where((task) => task.space == 'work'),
        ];
        await app.selectDate(DateTime.parse(app.today));
        await tester.pumpAndSettle();
        expect(app.visibleTasks.single.title, '跨周待办');
        expect(tester.widget<LinearProgressIndicator>(getProgress()).value, 0);

        repository.days['2026-11-10'] = [];
        await app.selectSpace('life');
        await app.selectDate(DateTime(2026, 11, 10));
        await tester.pumpAndSettle();
        expect(find.text('11月10日'), findsOneWidget);
        expect(find.text('暂无任务'), findsOneWidget);
        expect(find.text('0 / 0'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Bell toggles, undoes and opens settings at $diameter dp', (
      tester,
    ) async {
      var active = false;
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        workChannel,
        (call) async {
          calls.add(call.method);
          if (call.method == 'start') active = true;
          if (call.method == 'stop') active = false;
          return {'active': active, 'water': 60, 'eyes': 30};
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          workChannel,
          null,
        ),
      );
      final app = await configure(tester, diameter: diameter);
      await app.selectSpace('work');
      await tester.pumpAndSettle();
      expect(calls, ['get']);
      await tester.tap(find.byTooltip('开启工作提醒'));
      await tester.pumpAndSettle();
      expect(calls, ['get', 'get', 'permissions', 'start']);
      expect(find.byTooltip('关闭工作提醒'), findsOneWidget);
      expect(find.byType(WorkModePage), findsNothing);
      expect(find.text('工作提醒已开启'), findsOneWidget);
      expect(app.focus, isNull);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkModePage), findsOneWidget);
      expect(find.text('工作提醒'), findsOneWidget);
      expect(find.text('提醒已开启'), findsOneWidget);
      expect(find.textContaining('已工作'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '关闭提醒'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(WorkModePage))).pop();
      await tester.pumpAndSettle();
      expect(find.byTooltip('开启工作提醒'), findsOneWidget);
      await tester.longPress(find.byTooltip('开启工作提醒'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkModePage), findsOneWidget);
      expect(active, isFalse);
      Navigator.of(tester.element(find.byType(WorkModePage))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('开启工作提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭工作提醒'));
      await tester.pumpAndSettle();
      expect(active, isFalse);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(active, isTrue);
      expect(find.byTooltip('关闭工作提醒'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Repeated taps wait for permission and failure leaves reminders off',
    (tester) async {
      final permission = Completer<Map<String, dynamic>>();
      var startCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        workChannel,
        (call) async {
          if (call.method == 'permissions') return permission.future;
          if (call.method == 'start') startCalls++;
          return {'active': false};
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          workChannel,
          null,
        ),
      );
      final app = await configure(tester);
      await app.selectSpace('work');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('work-reminder-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('work-reminder-toggle')));
      await tester.pump();
      expect(startCalls, 0);
      permission.completeError(
        PlatformException(code: 'PERMISSION_REQUIRED', message: '请先允许通知权限'),
      );
      await tester.pumpAndSettle();
      expect(find.text('需要系统授权'), findsOneWidget);
      expect(startCalls, 0);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('开启工作提醒'), findsOneWidget);
      expect(find.text('工作提醒已开启'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Bell refreshes on automatic close and reads state before toggling',
    (tester) async {
      var active = true;
      final end = DateTime.now()
          .add(const Duration(seconds: 2))
          .millisecondsSinceEpoch;
      final commands = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        workChannel,
        (call) async {
          commands.add(call.method);
          if (call.method == 'start') active = true;
          if (call.method == 'stop') active = false;
          return {'active': active, 'end': end, 'autoEnd': true};
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          workChannel,
          null,
        ),
      );
      final app = await configure(tester);
      await app.selectSpace('work');
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭工作提醒'), findsOneWidget);
      await tester.longPress(find.byTooltip('关闭工作提醒'));
      await tester.pumpAndSettle();
      expect(find.text('提醒已开启'), findsOneWidget);
      active = false;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('提醒已关闭'), findsOneWidget);
      Navigator.of(tester.element(find.byType(WorkModePage))).pop();
      await tester.pumpAndSettle();
      expect(find.byTooltip('开启工作提醒'), findsOneWidget);
      // Simulate state changing outside this page after the last snapshot.
      active = true;
      await tester.tap(find.byTooltip('开启工作提醒'));
      await tester.pumpAndSettle();
      expect(commands.last, 'stop');
      expect(active, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
