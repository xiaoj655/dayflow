import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/app_colors.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/data/local_store.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/widgets/home_focus_card.dart';

import 'fakes.dart';

class _CardEngine extends FakeFocusEngine {
  final calls = <String>[];
  Completer<void>? permission;
  Completer<void>? command;
  String? failMethod;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    calls.add(method);
    if (method == 'permissions') await permission?.future;
    if (method == 'pause' || method == 'resume') await command?.future;
    if (method == failMethod) {
      throw PlatformException(code: 'denied', message: '请允许专注计时权限');
    }
    return super.call(method, arguments);
  }
}

class _Fixture {
  _Fixture(this.controller, this.engine);
  final AppController controller;
  final _CardEngine engine;
  final navigator = GlobalKey<NavigatorState>();
  final errors = <String>[];
  int opened = 0;
}

Future<_Fixture> _pumpCard(
  WidgetTester tester, {
  double diameter = 192,
  double textScale = 1,
  bool paused = false,
  bool rest = false,
  int minutes = 25,
  String title = '整理下一轮任务和项目安排',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size.square(diameter);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final engine = _CardEngine();
  final controller = AppController(
    repository: FakeRepository(),
    store: MemoryStore(),
    engine: engine,
    clock: () => engine.now,
  );
  await controller.initialize();
  await controller.refresh();
  final task = DailyTask.fromJson({
    ...controller.pending.first.toJson(),
    'title': title,
  });
  await controller.start(task, minutes, rest: rest);
  if (paused) await controller.focusAction('pause');
  engine.calls.clear();
  final fixture = _Fixture(controller, engine);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: fixture.navigator,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: diameter - 28,
            child: HomeFocusCard(
              controller: controller,
              onOpen: () => fixture.opened++,
              onError: fixture.errors.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  return fixture;
}

Finder get _toggle => find.byKey(const ValueKey('home-focus-toggle'));
Finder get _open => find.byKey(const ValueKey('home-focus-open'));
Finder get _card => find.byKey(const ValueKey('home-focus-card'));

void main() {
  for (final diameter in [192.0, 240.0]) {
    testWidgets('Home card separates open and pause at $diameter dp', (
      tester,
    ) async {
      final fixture = await _pumpCard(tester, diameter: diameter);
      final session = fixture.controller.focus!;
      expect(find.text('25:00'), findsOneWidget);
      expect(find.byTooltip('暂停专注'), findsOneWidget);
      expect(
        tester.widget<Semantics>(_open).properties.label,
        '返回专注，${session.taskTitle}，专注中，剩余 25:00',
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.timer_outlined));
      expect(icon.color, AppColors.focus);
      for (final control in [_open, _toggle]) {
        expect(control.hitTestable(), findsOneWidget);
        final rect = tester.getRect(control);
        final center = Offset(diameter / 2, diameter / 2);
        for (final corner in [rect.topLeft, rect.bottomRight]) {
          expect((corner - center).distance, lessThan(diameter / 2));
        }
      }
      await tester.tap(_open);
      await tester.pump();
      expect(fixture.opened, 1);
      expect(fixture.engine.calls, isEmpty);
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(fixture.opened, 1);
      expect(fixture.controller.focus!.paused, isTrue);
      expect(fixture.engine.calls, ['pause']);
      expect(find.byTooltip('继续专注'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.timer_outlined)).color,
        AppColors.muted,
      );
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(fixture.controller.focus!.running, isTrue);
      expect(fixture.controller.focus!.id, session.id);
      expect(fixture.engine.calls, ['pause', 'permissions', 'get', 'resume']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Long names and large text keep countdown and pause usable', (
    tester,
  ) async {
    await _pumpCard(tester, textScale: 2, minutes: 180, title: '待推进的项目任务' * 20);
    expect(find.text('180:00'), findsOneWidget);
    expect(_toggle.hitTestable(), findsOneWidget);
    expect(_open.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pause and permission waits reject repeated taps', (
    tester,
  ) async {
    final fixture = await _pumpCard(tester);
    fixture.engine.command = Completer<void>();
    await tester.tap(_toggle);
    await tester.pump();
    await tester.tap(_toggle);
    await tester.pump();
    expect(fixture.engine.calls, ['pause']);
    expect(tester.widget<IconButton>(_toggle).onPressed, isNull);
    fixture.engine.command!.complete();
    await tester.pumpAndSettle();
    fixture.engine.command = null;
    fixture.engine.calls.clear();
    fixture.engine.permission = Completer<void>();
    await tester.tap(_toggle);
    await tester.pump();
    await tester.tap(_toggle);
    await tester.pump();
    expect(fixture.engine.calls, ['permissions']);
    fixture.engine.permission!.complete();
    await tester.pumpAndSettle();
    expect(fixture.engine.calls, ['permissions', 'get', 'resume']);
    expect(fixture.controller.focus!.running, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Disposing during permission does not resume', (tester) async {
    final fixture = await _pumpCard(tester, paused: true);
    fixture.engine.permission = Completer<void>();
    await tester.tap(_toggle);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    fixture.engine.permission!.complete();
    await tester.pumpAndSettle();
    expect(fixture.engine.calls, ['permissions']);
    expect(fixture.controller.focus!.paused, isTrue);
    expect(fixture.errors, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Leaving home during permission cancels the delayed resume', (
    tester,
  ) async {
    final fixture = await _pumpCard(tester, paused: true);
    fixture.engine.permission = Completer<void>();
    await tester.tap(_toggle);
    await tester.pump();
    fixture.navigator.currentState!.push<void>(
      MaterialPageRoute(builder: (_) => const Scaffold(body: Text('其他页面'))),
    );
    await tester.pumpAndSettle();
    fixture.engine.permission!.complete();
    await tester.pumpAndSettle();
    expect(fixture.engine.calls, ['permissions']);
    expect(fixture.controller.focus!.paused, isTrue);
    expect(fixture.errors, isEmpty);
    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(_toggle).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  for (final change in ['new-session', 'finished', 'resumed']) {
    testWidgets('Permission wait never changes a $change timer', (
      tester,
    ) async {
      final fixture = await _pumpCard(tester, paused: true);
      final id = fixture.controller.focus!.id;
      fixture.engine.permission = Completer<void>();
      await tester.tap(_toggle);
      await tester.pump();
      if (change == 'new-session') {
        fixture.engine.state!['id'] = 'another-session';
      } else if (change == 'finished') {
        fixture.engine.state!['status'] = 'finished';
      } else {
        fixture.engine.state!['status'] = 'running';
      }
      // Leave the controller stale to exercise the native refresh after access.
      expect(fixture.controller.focus!.id, id);
      expect(fixture.controller.focus!.paused, isTrue);
      fixture.engine.permission!.complete();
      await tester.pumpAndSettle();
      expect(fixture.engine.calls, ['permissions', 'get']);
      expect(fixture.errors, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Rest pauses and resumes without focus permissions', (
    tester,
  ) async {
    final fixture = await _pumpCard(tester, rest: true);
    expect(find.byTooltip('暂停休息'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.timer_outlined)).color,
      AppColors.muted,
    );
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    expect(find.byTooltip('继续休息'), findsOneWidget);
    await tester.tap(_toggle);
    await tester.pumpAndSettle();
    expect(fixture.engine.calls, ['pause', 'resume']);
    expect(fixture.controller.focus!.running, isTrue);
    expect(fixture.controller.focus!.kind, 'rest');
    expect(tester.takeException(), isNull);
  });

  for (final method in ['pause', 'permissions', 'resume']) {
    testWidgets('$method errors are presented and allow retry', (tester) async {
      final fixture = await _pumpCard(tester, paused: method != 'pause');
      fixture.engine.failMethod = method;
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(fixture.errors, ['请允许专注计时权限']);
      expect(tester.widget<IconButton>(_toggle).onPressed, isNotNull);
      fixture.engine.failMethod = null;
      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      expect(fixture.controller.focus!.running, method != 'pause');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Finished and absent timers leave no active card', (
    tester,
  ) async {
    final fixture = await _pumpCard(tester);
    fixture.engine.elapse(const Duration(minutes: 25));
    await fixture.controller.refreshFocus();
    await tester.pumpAndSettle();
    expect(_card, findsNothing);
    expect(_toggle, findsNothing);
    await fixture.controller.focusAction('dismiss');
    await tester.pumpAndSettle();
    expect(_card, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
