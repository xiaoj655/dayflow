import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/data/local_store.dart';
import 'package:life_assistant/models/task.dart';

import 'fakes.dart';

DailyTask _task(String date, {String space = 'life'}) => DailyTask(
  id: 'steps:$date',
  templateId: 'steps',
  date: date,
  title: '修复登录',
  content: '分步验证并修复问题。',
  space: space,
  steps: const [
    TaskStep(id: 'reproduce', title: '复现问题'),
    TaskStep(id: 'fix', title: '修改代码'),
    TaskStep(id: 'verify', title: '验证修复'),
  ],
);

AppController _app(
  FakeRepository repository,
  MemoryStore store,
  FakeFocusEngine engine,
) => AppController(
  repository: repository,
  store: store,
  engine: engine,
  clock: () => engine.now,
);

class _HeldStepRepository extends FakeRepository {
  final uploading = Completer<void>();
  final release = Completer<void>();
  final writes = <bool>[];

  @override
  Future<void> setStepCompleted(
    String taskId,
    String stepId,
    bool completed,
  ) async {
    writes.add(completed);
    if (!uploading.isCompleted) {
      uploading.complete();
      await release.future;
    }
    await super.setStepCompleted(taskId, stepId, completed);
  }
}

void main() {
  test('SQL JSON and cache round trips preserve independent step progress', () {
    final task = _task('2026-11-15');
    final fromSql = DailyTask.fromJson({
      ...task.toJson(),
      'steps': jsonEncode(task.steps.map((step) => step.toJson()).toList()),
      'step_progress': jsonEncode({'reproduce': true, 'verify': true}),
    });
    expect(fromSql.completedStepCount, 2);
    expect(fromSql.currentStep!.id, 'fix');
    expect(fromSql.completed, isFalse);
    final cached = DailyTask.fromJson(
      jsonDecode(jsonEncode(fromSql.toJson())) as Map<String, dynamic>,
    );
    final marked = cached.withCompletion('2026-11-15 10:00:00');
    expect(marked.completedStepCount, 2);
    expect(marked.withWaiting(true).currentStep!.id, 'fix');
    expect(marked.withCompletion(null).completedStepCount, 2);
    expect(marked.withStepCompletion('fix', true).currentStep, isNull);
  });

  test('Legacy and malformed step data leaves the task usable', () {
    final data = _task('2026-11-15').toJson();
    expect(DailyTask.fromJson({...data, 'steps': null}).steps, isEmpty);
    expect(DailyTask.fromJson({...data, 'steps': 'broken'}).steps, isEmpty);
    final recovered = DailyTask.fromJson({
      ...data,
      'steps': [
        {'id': 'good', 'title': '可执行步骤'},
        {'id': 'good', 'title': '重复ID'},
        {'id': 9, 'title': '损坏'},
        null,
      ],
      'step_progress': 'broken',
    });
    expect(recovered.steps.single.title, '可执行步骤');
    expect(recovered.currentStep!.completed, isFalse);
  });

  test(
    'Offline progress survives restart without altering active focus',
    () async {
      final engine = FakeFocusEngine();
      final date = dayKey(chinaNow(engine.now));
      final task = _task(date);
      final repository = FakeRepository()..days[date] = [task];
      final store = MemoryStore();
      final app = _app(repository, store, engine);
      await app.initialize();
      await app.refresh();
      await app.start(task, 25);
      final sessionId = app.focus!.id;
      repository.fail = true;
      await app.setStepCompleted(task, 'reproduce', true);
      await app.refresh();
      expect(app.tasks.single.currentStep!.id, 'fix');
      expect(app.focus!.id, sessionId);
      expect(app.focus!.running, isTrue);
      expect(app.tasks.single.completed, isFalse);
      app.dispose();

      final restored = _app(repository, store, engine);
      await restored.initialize();
      expect(restored.tasks.single.completedStepCount, 1);
      expect(restored.focus!.id, sessionId);
      repository.fail = false;
      await restored.refresh();
      expect(repository.days[date]!.single.completedStepCount, 1);
      await restored.setStepCompleted(
        restored.tasks.single,
        'reproduce',
        false,
      );
      await restored.refresh();
      expect(repository.days[date]!.single.completedStepCount, 0);
      expect(restored.focus!.running, isTrue);
      restored.dispose();
    },
  );

  test(
    'Undo during an upload remains queued and wins over the old response',
    () async {
      final engine = FakeFocusEngine();
      final date = dayKey(chinaNow(engine.now));
      final task = _task(date);
      final repository = _HeldStepRepository()..days[date] = [task];
      final app = _app(repository, MemoryStore(), engine);
      await app.initialize();
      await app.refresh();
      await app.setStepCompleted(task, 'reproduce', true);
      await repository.uploading.future;
      await app.setStepCompleted(task, 'reproduce', false);
      expect(app.tasks.single.completedStepCount, 0);
      repository.release.complete();
      await app.refresh();
      expect(repository.writes, [true, false]);
      expect(repository.days[date]!.single.completedStepCount, 0);
      expect(app.tasks.single.completedStepCount, 0);
      app.dispose();
    },
  );

  test(
    'A step changed during fetch survives its stale response and uploads',
    () async {
      final engine = FakeFocusEngine();
      final date = dayKey(chinaNow(engine.now));
      final task = _task(date);
      final repository = DelayedRepository()..days[date] = [task];
      final app = _app(repository, MemoryStore(), engine);
      await app.initialize();
      await app.refresh();
      repository.block = true;
      final refreshing = app.refresh();
      await Future<void>.delayed(Duration.zero);
      await app.setStepCompleted(task, 'reproduce', true);
      repository.block = false;
      repository.requests[date]!.complete([task]);
      await refreshing;
      expect(app.tasks.single.completedStepCount, 1);
      expect(repository.days[date]!.single.completedStepCount, 1);
      app.dispose();
    },
  );

  test('Work progress is shared across cached dates and restart', () async {
    final engine = FakeFocusEngine();
    final date = dayKey(chinaNow(engine.now));
    final tomorrow = dayKey(chinaNow(engine.now).add(const Duration(days: 1)));
    final task = _task(date, space: 'work');
    final repository = FakeRepository()
      ..days[date] = [task]
      ..days[tomorrow] = [task];
    final store = MemoryStore();
    final app = _app(repository, store, engine);
    await app.initialize();
    await app.refresh();
    await app.selectDate(DateTime.parse(tomorrow));
    repository.fail = true;
    await app.setStepCompleted(task, 'reproduce', true);
    await app.refresh();
    await app.selectDate(DateTime.parse(date));
    expect(app.tasks.single.currentStep!.id, 'fix');
    final snapshot = jsonDecode(store.values['life_assistant.v1']!) as Map;
    for (final key in [date, tomorrow, 'work']) {
      final rows = snapshot['days'][key] as List;
      expect((rows.single as Map)['step_progress']['reproduce'], isTrue);
    }
    app.dispose();
    engine.elapse(const Duration(days: 1));
    final restored = _app(repository, store, engine);
    await restored.initialize();
    expect(restored.tasks.single.id, task.id);
    expect(restored.tasks.single.currentStep!.id, 'fix');
    repository.fail = false;
    await restored.refresh();
    expect(repository.days[tomorrow]!.single.completedStepCount, 1);
    restored.dispose();
  });

  test('Recurring life occurrences keep progress separate', () async {
    final engine = FakeFocusEngine();
    final date = dayKey(chinaNow(engine.now));
    final tomorrow = dayKey(chinaNow(engine.now).add(const Duration(days: 1)));
    final task = _task(date);
    final repository = FakeRepository()
      ..days[date] = [task]
      ..days[tomorrow] = [_task(tomorrow)];
    final app = _app(repository, MemoryStore(), engine);
    await app.initialize();
    await app.refresh();
    await app.setStepCompleted(task, 'reproduce', true);
    await app.refresh();
    await app.selectDate(DateTime.parse(tomorrow));
    expect(app.tasks.single.completedStepCount, 0);
    await app.selectDate(DateTime.parse(date));
    expect(app.tasks.single.completedStepCount, 1);
    app.dispose();
  });

  test(
    'An old detail keeps its cached steps after the home date changes',
    () async {
      final engine = FakeFocusEngine();
      final date = dayKey(chinaNow(engine.now));
      final tomorrow = dayKey(
        chinaNow(engine.now).add(const Duration(days: 1)),
      );
      final task = _task(date);
      final repository = FakeRepository()
        ..days[date] = [task]
        ..days[tomorrow] = [];
      final store = MemoryStore();
      final app = _app(repository, store, engine);
      await app.initialize();
      await app.refresh();
      await app.selectDate(DateTime.parse(tomorrow));
      repository.fail = true;
      await app.setStepCompleted(task, 'reproduce', true);
      await app.refresh();
      expect(app.tasks, isEmpty);
      expect(app.taskById(task.id)!.currentStep!.id, 'fix');
      app.dispose();
      final restored = _app(repository, store, engine);
      await restored.initialize();
      expect(restored.taskById(task.id)!.completedStepCount, 1);
      repository.fail = false;
      await restored.refresh();
      expect(repository.days[date]!.single.completedStepCount, 1);
      restored.dispose();
    },
  );

  test(
    'Adding to today preserves source steps and never resets an existing copy',
    () async {
      final engine = FakeFocusEngine();
      final today = dayKey(chinaNow(engine.now));
      final yesterday = dayKey(
        chinaNow(engine.now).subtract(const Duration(days: 1)),
      );
      final source = _task(yesterday).withStepCompletion('reproduce', true);
      final repository = FakeRepository()
        ..days[yesterday] = [source]
        ..days[today] = [];
      final app = _app(repository, MemoryStore(), engine);
      await app.initialize();
      await app.refresh();
      await app.addToToday(source);
      expect(app.tasks.single.completedStepCount, 1);
      expect(app.tasks.single.carriedFromDate, yesterday);
      await app.setStepCompleted(app.tasks.single, 'fix', true);
      await app.refresh();
      await app.addToToday(source);
      expect(app.tasks.single.completedStepCount, 2);
      expect(repository.days[yesterday]!.single.completedStepCount, 1);
      app.dispose();
    },
  );

  test(
    'Damaged queued steps do not discard a valid step or completion',
    () async {
      final engine = FakeFocusEngine();
      final date = dayKey(chinaNow(engine.now));
      final task = _task(date);
      final store = MemoryStore();
      store.values['life_assistant.v1'] = jsonEncode({
        'days': {
          date: [task.toJson()],
        },
        'steps': {
          'broken': [],
          jsonEncode([task.id, 'reproduce']): {
            'taskId': task.id,
            'stepId': 'reproduce',
            'completed': true,
          },
        },
        'completion': {
          task.id: {
            'completedAt': sqlTime(engine.now),
            'changedAt': sqlTime(engine.now),
          },
        },
      });
      final repository = FakeRepository()..days[date] = [task];
      final app = _app(repository, store, engine);
      await app.initialize();
      expect(app.tasks.single.completedStepCount, 1);
      expect(app.tasks.single.completed, isTrue);
      await app.refresh();
      expect(repository.days[date]!.single.completedStepCount, 1);
      expect(repository.days[date]!.single.completed, isTrue);
      app.dispose();
    },
  );
}
