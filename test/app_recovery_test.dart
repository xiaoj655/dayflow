import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/data/local_store.dart';
import 'package:life_assistant/main.dart';
import 'package:life_assistant/pages/app_pages.dart';

import 'fakes.dart';

class _FlakyEngine extends FakeFocusEngine {
  bool failNextRead = false;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? arguments,
  ]) {
    if (method == 'get' && failNextRead) {
      failNextRead = false;
      return Future.error(PlatformException(code: 'TEMPORARY'));
    }
    return super.call(method, arguments);
  }
}

class _FlakyController extends AppController {
  _FlakyController(_FlakyEngine engine)
    : super(
        repository: FakeRepository(),
        store: MemoryStore(),
        engine: engine,
        clock: () => engine.now,
      );

  bool failNextRefresh = false;
  int refreshCalls = 0;

  @override
  Future<void> refresh() {
    refreshCalls++;
    if (failNextRefresh) {
      failNextRefresh = false;
      return Future.error(StateError('Temporary refresh failure'));
    }
    return super.refresh();
  }
}

Future<void> _mount(
  WidgetTester tester,
  _FlakyController app, {
  bool initialize = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size.square(240);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
  await tester.pumpWidget(
    MyApp(controller: app, isRound: true, initializeController: initialize),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('A periodic focus read failure is contained and retried', (
    tester,
  ) async {
    final engine = _FlakyEngine();
    final app = _FlakyController(engine);
    await app.initialize();
    await app.refresh();
    await app.start(app.tasks.first, 25);
    await _mount(tester, app);
    final id = app.focus!.id;
    engine.failNextRead = true;
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    engine.elapse(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(app.focus!.id, id);
    expect(app.focus!.remainingSeconds, 25 * 60 - 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Resume refresh failures do not prevent the next refresh', (
    tester,
  ) async {
    final engine = _FlakyEngine();
    final app = _FlakyController(engine);
    await app.initialize();
    await app.refresh();
    await _mount(tester, app);
    final calls = app.refreshCalls;
    app.failNextRefresh = true;
    engine.failNextRead = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(app.refreshCalls, calls + 2);
    expect(app.tasks, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('The initial background refresh can fail and recover on resume', (
    tester,
  ) async {
    final engine = _FlakyEngine();
    final app = _FlakyController(engine)..failNextRefresh = true;
    await _mount(tester, app, initialize: true);
    expect(find.byType(TaskListPage), findsOneWidget);
    expect(app.initializing, isFalse);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(app.tasks, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
