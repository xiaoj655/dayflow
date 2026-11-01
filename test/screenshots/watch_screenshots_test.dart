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
import 'package:life_assistant/pages/app_pages.dart';

import '../fakes.dart';

void main() {
  testWidgets(
    'Capture the watch documentation from real pages and synthetic data',
    (tester) async {
      // Widget tests otherwise use Ahem rectangles. Use a pinned CJK font for
      // all text, including the clock's standalone TextPainter.
      await tester.runAsync(() async {
        final font = await File(const String.fromEnvironment('SCREENSHOT_FONT'))
            .readAsBytes();
        for (final family in ['Roboto', 'Ahem']) {
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.sublistView(font)))).load();
        }
      });
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size.square(480);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final now = DateTime.utc(2026, 11, 1, 2, 8);
      final engine = FakeFocusEngine()..now = now;
      final controller = AppController(
        repository: FakeRepository(),
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
        expect(find.text('街头观察'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.label == '当前时间 10:08',
          ),
          findsOneWidget,
        );
        await capture('tasks');
        await open(TaskDatePage(controller: controller, isRound: true));
        await capture('calendar');
        await back();

        final task = controller.tasks.first;
        await open(
          TaskDetailPage(controller: controller, task: task, isRound: true),
        );
        expect(find.text('先观察一个路口'), findsOneWidget);
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

        await controller.start(task, 25);
        await open(FocusPage(controller: controller, isRound: true));
        expect(find.text('25:00'), findsOneWidget);
        await capture('focus-running');

        engine.elapse(const Duration(minutes: 25));
        await controller.refreshFocus();
        await tester.pumpAndSettle();
        expect(find.text('本次专注完成'), findsOneWidget);
        await capture('focus-finished');
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
    skip: !const bool.fromEnvironment('GENERATE_SCREENSHOTS'),
  );
}
