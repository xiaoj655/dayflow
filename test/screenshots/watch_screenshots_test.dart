@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/data/local_store.dart';
import 'package:life_assistant/main.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/pages/app_pages.dart';
import 'package:life_assistant/widgets/app_clock.dart';

import '../fakes.dart';
import 'demo_data.dart';

void main() {
  testWidgets(
    'Capture the watch documentation from real pages and synthetic data',
    (tester) async {
      // Theme text and custom painters use Roboto on Android. Register the
      // watch font under that family; registering Ahem does not replace the
      // test engine's built-in fallback. Icons need their own font as well.
      await tester.runAsync(() async {
        final font = await File(const String.fromEnvironment('SCREENSHOT_FONT'))
            .readAsBytes();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(ByteData.sublistView(font)))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size.square(480);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final now = DateTime.utc(2026, 11, 1, 2, 8);
      final engine = FakeFocusEngine()..now = now;
      final repository = screenshotRepository('2026-11-01');
      var working = false;
      const workChannel = MethodChannel('life_assistant/work');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        workChannel,
        (call) async => {
          'active': working,
          'water': 60,
          'eyes': 30,
          'lunchStart': 720,
          'lunchEnd': 840,
          'dinnerStart': 1080,
          'dinnerEnd': 1140,
          'autoEnd': true,
          'endMinute': 1320,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          workChannel,
          null,
        ),
      );
      final controller = AppController(
        repository: repository,
        store: MemoryStore(),
        engine: engine,
        clock: () => now,
      );
      await controller.initialize();
      await controller.refresh();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: ClipOval(child: MyApp(controller: controller, isRound: true)),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ClipOval), findsWidgets);
        // A custom button or notification style can replace the theme style
        // and silently lose its family. Fail before publishing any images.
        void checkFonts(InlineSpan span, [TextStyle? inherited]) {
          if (span is! TextSpan) return;
          final style = (inherited ?? const TextStyle()).merge(span.style);
          if (span.text?.trim().isNotEmpty == true) {
            expect(
              style.fontFamily,
              isIn(['Roboto', 'MaterialIcons']),
              reason: '$name: "${span.text}" must use a loaded screenshot font',
            );
          }
          for (final child in span.children ?? <InlineSpan>[]) {
            checkFonts(child, style);
          }
        }

        for (final paragraph
            in tester.allRenderObjects.whereType<RenderParagraph>()) {
          checkFonts(paragraph.text);
        }
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            expect(image.width, 480);
            expect(image.height, 480);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final output = Directory(
              const String.fromEnvironment('SCREENSHOT_OUTPUT'),
            );
            await output.create(recursive: true);
            await File('${output.path}/$name.png').writeAsBytes(
              bytes!.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
              flush: true,
            );
          } finally {
            image.dispose();
          }
        });
      }

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      Future<void> open(Widget page) async {
        navigator.push(MaterialPageRoute<void>(builder: (_) => page));
        await tester.pumpAndSettle();
      }

      Future<void> back() async {
        navigator.pop();
        await tester.pumpAndSettle();
      }

      try {
        expect(find.text('整理书桌'), findsOneWidget);
        expect(AppClock.now(tester.element(find.text('整理书桌'))), now);
        await capture('tasks');
        await controller.selectSpace('work');
        await capture('work-tasks');
        await open(WorkTaskHistoryPage(controller: controller, isRound: true));
        await capture('work-history');
        await back();
        await controller.selectSpace('life');
        await open(const WorkModePage());
        expect(find.text('提醒已关闭'), findsOneWidget);
        await capture('work-mode');
        await back();
        working = true;
        await open(const WorkModePage());
        expect(find.text('提醒已开启'), findsOneWidget);
        await capture('work-active');
        await tester.scrollUntilVisible(
          find.text('远眺提醒'),
          70,
          scrollable: find.byType(Scrollable).last,
        );
        await capture('work-reminders');
        await tester.scrollUntilVisible(
          find.textContaining('自动关闭时间'),
          70,
          scrollable: find.byType(Scrollable).last,
        );
        await capture('work-schedule');
        await back();
        await open(const IntervalPage(title: '喝水提醒', initial: 60));
        await capture('reminder-interval');
        await back();
        await open(
          const IntervalPage(title: '自动关闭时间', initial: 1320, timeOfDay: true),
        );
        await capture('work-end-time');
        await back();
        await open(HistoryPage(controller: controller));
        await capture('analysis');
        await back();
        await open(TaskDatePage(controller: controller, isRound: true));
        await capture('calendar');
        await back();

        final task = controller.tasks.first;
        await open(
          TaskDetailPage(controller: controller, task: task, isRound: true),
        );
        expect(find.text('先收好桌上的杂物'), findsOneWidget);
        await capture('task-detail');
        await back();

        await open(
          FocusSetupPage(
            controller: controller,
            isRound: true,
            initialTask: task,
          ),
        );
        await capture('focus-setup');
        await back();

        await open(TaskEditorPage(controller: controller, task: task));
        await capture('task-editor');
        await back();
        await open(
          FocusSetupPage(
            controller: controller,
            isRound: true,
            allowTaskSelection: true,
            initialTask: DailyTask(
              id: '',
              templateId: '',
              date: controller.date,
              title: '自由专注',
              content: '',
            ),
          ),
        );
        await capture('free-focus-setup');
        await back();
        await open(TaskPickerPage(controller: controller, isRound: true));
        await capture('task-picker');
        await back();
        await controller.start(task, 25);
        await open(FocusPage(controller: controller, isRound: true));
        expect(find.text('25:00'), findsOneWidget);
        await capture('focus-running');

        await controller.focusAction('pause');
        expect(controller.focus!.paused, isTrue);
        await capture('focus-paused');
        await controller.focusAction('resume');
        engine.elapse(const Duration(minutes: 25));
        await controller.refreshFocus();
        await tester.pumpAndSettle();
        expect(find.text('本次专注完成'), findsOneWidget);
        await capture('focus-finished');
        await back();
        await controller.focusAction('dismiss');
        await controller.start(task, 5, rest: true);
        await open(FocusPage(controller: controller, isRound: true));
        expect(controller.focus!.kind, 'rest');
        await capture('rest-running');
        engine.elapse(const Duration(minutes: 5));
        await controller.refreshFocus();
        await capture('rest-finished');
        await back();
        await controller.focusAction('dismiss');
        repository.days[controller.date] = [];
        await controller.refresh();
        expect(controller.visibleTasks, isEmpty);
        await capture('tasks-empty');
        await controller.selectDate(DateTime(2026, 11, 2));
        await open(HistoryPage(controller: controller));
        await capture('analysis-empty');
        await back();
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
    skip: !const bool.fromEnvironment('GENERATE_SCREENSHOTS'),
  );
}
