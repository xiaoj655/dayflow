import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/controllers/app_controller.dart';
import 'package:life_assistant/data/local_store.dart';
import 'package:life_assistant/models/task.dart';

import 'fakes.dart';

class _FailFetchAfterUploadRepository extends FakeRepository {
  bool failFetch = false;

  @override
  Future<List<DailyTask>> fetchDay(String date) {
    if (failFetch) throw StateError('fetch offline after successful upload');
    return super.fetchDay(date);
  }
}

void main() {
  test('Spaces isolate tasks and completion and survive reopening', () async {
    final store = MemoryStore();
    final repo = FakeRepository();
    final engine = FakeFocusEngine();
    final app = AppController(repository: repo, store: store, engine: engine);
    await app.initialize();
    await app.refresh();
    final work = DailyTask(
      id: 'work',
      templateId: 'work',
      date: app.date,
      title: '工作',
      content: '内容',
      space: 'work',
    );
    app.tasks = [...app.tasks, work];
    expect(app.pending.any((t) => t.id == 'work'), false);
    await app.selectSpace('work');
    expect(app.pending.single.id, 'work');
    await app.toggle(work);
    expect(app.completed.single.space, 'work');
    await app.selectSpace('life');
    expect(app.completed, isEmpty);
    final restored = AppController(
      repository: repo,
      store: store,
      engine: engine,
    );
    await restored.initialize();
    expect(restored.space, 'life');
    await restored.selectSpace('work');
    expect(restored.completed.single.id, 'work');
    app.dispose();
    restored.dispose();
  });

  test('Work pool crosses weeks, preserves waiting offline and keeps completion history', () async {
    final repo = FakeRepository(),
        store = MemoryStore(),
        engine = FakeFocusEngine();
    var now = DateTime.utc(2026, 11, 15, 15, 59);
    AppController create() => AppController(
      repository: repo,
      store: store,
      engine: engine,
      clock: () => now,
    );
    final app = create();
    await app.initialize();
    final task = DailyTask(
      id: 'persistent',
      templateId: 'persistent',
      date: '2026-10-01',
      title: '跨周工作',
      content: '推进',
      space: 'work',
    );
    app.tasks = [task];
    repo.fail = true;
    await app.selectSpace('work');
    await app.toggleWaiting(task);
    await app.refresh();
    final restored = create();
    await restored.initialize();
    expect(restored.pending.single.waiting, true);
    await restored.toggle(restored.pending.single);
    await restored.refresh();
    expect(restored.completed.single.id, task.id);
    now = now.add(const Duration(minutes: 2)); // Monday 00:01 Shanghai.
    expect(restored.completed, isEmpty);
    expect(restored.workHistory.single.id, task.id);
    await restored.toggle(restored.workHistory.single);
    await restored.refresh();
    expect(restored.pending.single.id, task.id);
    expect(restored.pending.single.waiting, true);
    await restored.selectDate(DateTime(2026, 10, 20));
    expect(restored.pending.single.id, task.id);
    app.dispose();
    restored.dispose();
  });

  test('Shanghai date crosses UTC day boundary correctly', () {
    expect(dayKey(chinaNow(DateTime.utc(2026, 10, 24, 17))), '2026-10-25');
  });
  test('Offline completion survives restart, syncs, and does not complete tomorrow', () async {
    final repo = FakeRepository(),
        store = MemoryStore(),
        engine = FakeFocusEngine();
    AppController create() => AppController(
      repository: repo,
      store: store,
      engine: engine,
      clock: () => engine.now,
    );
    final first = create();
    await first.initialize();
    await first.refresh();
    repo.fail = true;
    await first.toggle(first.tasks.first);
    await first.refresh();
    expect(first.completed.single.title, '街头观察');
    first.dispose();
    final second = create();
    await second.initialize();
    expect(second.completed.single.title, '街头观察');
    repo.fail = false;
    await second.refresh();
    expect(repo.days[second.date]!.first.completed, isTrue);
    await second.selectDate(DateTime(2026, 10, 25));
    expect(second.completed, isEmpty);
    second.dispose();
  });
  test('Focus remembers started duration, pause survives elapsed time, rest keeps default', () async {
    final repo = FakeRepository(), engine = FakeFocusEngine();
    final app = AppController(
      repository: repo,
      store: MemoryStore(),
      engine: engine,
    );
    await app.initialize();
    await app.refresh();
    await app.start(app.tasks.first, 35);
    expect(app.lastMinutes, 35);
    engine.elapse(const Duration(minutes: 2));
    await app.refreshFocus();
    expect(app.focus!.remainingSeconds, 33 * 60);
    await app.focusAction('pause');
    engine.elapse(const Duration(hours: 1));
    await app.refreshFocus();
    expect(app.focus!.remainingSeconds, 33 * 60);
    await app.focusAction('resume');
    engine.elapse(const Duration(minutes: 33));
    await app.refreshFocus();
    await app.refresh();
    expect(app.focus!.finished, isTrue);
    expect(app.completed, isEmpty);
    expect(repo.sessions.values.single['actualSeconds'], 35 * 60);
    await app.start(app.tasks.first, 5, rest: true);
    expect(app.lastMinutes, 35);
    app.dispose();
  });
  test('Offline focus records are durable and uploaded exactly once', () async {
    final repo = FakeRepository(),
        store = MemoryStore(),
        engine = FakeFocusEngine();
    AppController create() =>
        AppController(repository: repo, store: store, engine: engine);
    var app = create();
    await app.initialize();
    await app.refresh();
    await app.start(app.tasks.first, 5);
    repo.fail = true;
    engine.elapse(const Duration(minutes: 5));
    await app.refreshFocus();
    await app.refresh();
    expect(engine.records, isEmpty);
    expect(repo.sessions, isEmpty);
    expect(app.focusCount(app.tasks.first), 1);
    app.dispose();
    app = create();
    await app.initialize();
    expect(app.focusCount(app.tasks.first), 1);
    repo.fail = false;
    await app.refresh();
    await app.refresh();
    expect(repo.sessions.length, 1);
    expect(repo.sessions.values.single['status'], 'completed');
    expect(app.focusCount(app.tasks.first), 1);
    await app.toggle(app.tasks.first);
    await app.refresh();
    expect(app.focusCount(app.tasks.first), 1);
    await app.selectDate(DateTime.parse(app.date).add(const Duration(days: 1)));
    expect(app.focusCount(app.tasks.first), 0);
    app.dispose();
  });
  test('Pomodoro counts survive a failed fetch after upload and exclude rest and interruptions', () async {
    final repo = _FailFetchAfterUploadRepository();
    final store = MemoryStore();
    final engine = FakeFocusEngine();
    AppController create() =>
        AppController(repository: repo, store: store, engine: engine);
    var app = create();
    await app.initialize();
    await app.refresh();
    final task = app.tasks.first;
    await app.start(task, 5);
    engine.elapse(const Duration(minutes: 5));
    repo.failFetch = true;
    await app.refreshFocus();
    await app.refresh();
    expect(repo.sessions.length, 1);
    expect(app.focusCount(app.tasks.first), 1);
    app.dispose();
    app = create();
    await app.initialize();
    expect(app.focusCount(app.tasks.first), 1);
    repo.failFetch = false;
    await app.refresh();
    expect(app.focusCount(app.tasks.first), 1);
    await app.start(task, 5, rest: true);
    engine.elapse(const Duration(minutes: 5));
    await app.refreshFocus();
    await app.refresh();
    await app.start(task, 5);
    engine.elapse(const Duration(minutes: 3));
    await app.focusAction('stop');
    await app.refresh();
    expect(repo.sessions.length, 3);
    expect(app.focusCount(app.tasks.first), 1);
    app.dispose();
  });
  test('Short focus is acknowledged but never cached or uploaded', () async {
    final repo = FakeRepository();
    final engine = FakeFocusEngine();
    final store = MemoryStore();
    final app = AppController(repository: repo, store: store, engine: engine);
    await app.initialize();
    await app.refresh();
    await app.start(app.tasks.first, 5);
    engine.elapse(const Duration(seconds: 179));
    await app.focusAction('pause');
    engine.elapse(const Duration(hours: 1));
    await app.focusAction('stop');
    await app.refresh();
    expect(app.focus, isNull);
    expect(engine.records, isEmpty);
    expect(repo.sessions, isEmpty);
    final saved = jsonDecode(store.values['life_assistant.v1']!) as Map;
    expect(saved['sessions'], isEmpty);
    expect(saved['history'], isEmpty);
    app.dispose();
  });

  test(
    'Restore and history filter short focus but keep the boundary and rest',
    () async {
      final repo = FakeRepository();
      final store = MemoryStore();
      final rows = <String, Map<String, dynamic>>{
        for (final seconds in [0, 179, 180, 181])
          '$seconds': {
            'id': '$seconds',
            'kind': 'focus',
            'actualSeconds': seconds,
            'startedAt': 0,
            'endedAt': 3600000,
          },
        'rest': {'id': 'rest', 'kind': 'rest', 'actualSeconds': 10},
      };
      Map<String, dynamic> historyRow(Map<String, dynamic> row) => {
        'id': row['id'],
        'kind': row['kind'],
        'actual_seconds': row['actualSeconds'].toString(),
        'started_at': '2026-11-08 00:00:00',
      };
      store.values['life_assistant.v1'] = jsonEncode({
        'sessions': rows,
        'history': rows.map((id, row) => MapEntry(id, historyRow(row))),
      });
      final app = AppController(
        repository: repo,
        store: store,
        engine: FakeFocusEngine(),
      );
      await app.initialize();
      await app.refresh();
      expect(repo.sessions.keys, unorderedEquals(['180', '181', 'rest']));
      // Simulate short records that already exist in the database.
      repo.sessions.addAll(
        rows.map((id, row) => MapEntry(id, historyRow(row))),
      );
      expect(
        (await app.history()).map((row) => row['id']),
        unorderedEquals(['180', '181', 'rest']),
      );
      repo.fail = true;
      expect(
        (await app.history()).map((row) => row['id']),
        unorderedEquals(['180', '181', 'rest']),
      );
      app.dispose();
    },
  );

  test('Durations and required task fields are validated', () async {
    final app = AppController(
      repository: FakeRepository(),
      store: MemoryStore(),
      engine: FakeFocusEngine(),
    );
    await app.initialize();
    await app.refresh();
    await expectLater(app.start(app.tasks.first, 7), throwsFormatException);
    expect(
      () => const TaskDraft(
        title: '',
        content: 'x',
        date: '2026-10-24',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const TaskDraft(
        title: 'x',
        content: 'x',
        date: '2026-10-24',
        recurrence: 'weekly',
      ).validate(),
      throwsFormatException,
    );
    app.dispose();
  });
  test(
    'Task details survive cache restore, completion and focus snapshots',
    () async {
      final repository = FakeRepository();
      final store = MemoryStore();
      final engine = FakeFocusEngine();
      final app = AppController(
        repository: repository,
        store: store,
        engine: engine,
      );
      await app.initialize();
      await app.refresh();
      final task = app.tasks.first;
      repository.fail = true;
      await app.toggle(task);
      await app.refresh();
      final restored = AppController(
        repository: repository,
        store: store,
        engine: engine,
      );
      await restored.initialize();
      final copy = restored.tasks.first;
      expect(copy.completed, isTrue);
      expect(copy.taskValue, task.taskValue);
      expect(copy.minimumGoal, task.minimumGoal);
      expect(copy.completionStandard, task.completionStandard);
      expect(copy.startAction, task.startAction);
      expect(copy.estimatedMinutes, 15);
      await restored.start(copy, 25);
      expect(restored.focus!.startAction, task.startAction);
      expect(
        restored.lastMinutes,
        25,
      ); // Estimate does not overwrite remembered focus duration.
      app.dispose();
      restored.dispose();
    },
  );
  test(
    'Estimated duration is optional and independent of five-minute focus steps',
    () {
      TaskDraft(
        title: '阅读',
        content: '读一节',
        date: '2026-10-24',
        estimatedMinutes: 17,
      ).validate();
      for (final minutes in [0, -1, 1441]) {
        expect(
          () => TaskDraft(
            title: '阅读',
            content: '读一节',
            date: '2026-10-24',
            estimatedMinutes: minutes,
          ).validate(),
          throwsFormatException,
        );
      }
    },
  );
  test('Carry a past unfinished snapshot to today without moving or duplicating it', () async {
    final repository = FakeRepository();
    final app = AppController(
      repository: repository,
      store: MemoryStore(),
      engine: FakeFocusEngine(),
    );
    await app.initialize();
    final yesterday = dayKey(
      DateTime.parse(app.today).subtract(const Duration(days: 1)),
    );
    final source = DailyTask(
      id: 'haircut:$yesterday',
      templateId: 'haircut',
      date: yesterday,
      title: '理发',
      content: '修剪头发',
      taskValue: '整洁',
      minimumGoal: '剪短',
      completionStandard: '完成修剪',
      startAction: '先联系理发店',
      estimatedMinutes: 30,
    );
    repository.days[yesterday] = [source];
    await app.selectDate(DateTime.parse(yesterday));
    await app.addToToday(source);
    expect(app.date, app.today);
    var copy = app.tasks.singleWhere((task) => task.templateId == 'haircut');
    expect(copy.carriedFromDate, yesterday);
    expect(copy.startAction, '先联系理发店');
    expect(copy.taskValue, '整洁');
    expect(copy.estimatedMinutes, 30);
    expect(repository.days[yesterday]!.single.id, source.id);
    expect(repository.days[yesterday]!.single.completed, isFalse);
    await app.addToToday(source);
    expect(
      app.tasks.where((task) => task.templateId == 'haircut'),
      hasLength(1),
    );
    await app.toggle(copy);
    await app.refresh();
    await app.addToToday(source);
    copy = app.tasks.singleWhere((task) => task.templateId == 'haircut');
    expect(copy.completed, isTrue);
    await expectLater(app.addToToday(copy), throwsFormatException);
    app.dispose();
  });
  test('Rapid date changes finish on the last requested date', () async {
    final app = AppController(
      repository: FakeRepository(),
      store: MemoryStore(),
      engine: FakeFocusEngine(),
    );
    await app.initialize();
    await app.refresh();
    final today = DateTime.parse(app.today);
    await Future.wait([
      app.selectDate(today.subtract(const Duration(days: 1))),
      app.selectDate(today.add(const Duration(days: 1))),
    ]);
    expect(app.date, dayKey(today.add(const Duration(days: 1))));
    expect(app.tasks.every((task) => task.date == app.date), isTrue);
    app.dispose();
  });
  test('Date switches use cache immediately, skip intermediate requests and reject stale results', () async {
    final repository = DelayedRepository();
    final store = MemoryStore();
    final app = AppController(
      repository: repository,
      store: store,
      engine: FakeFocusEngine(),
    );
    final a = app.today;
    final b = dayKey(DateTime.parse(a).add(const Duration(days: 1)));
    final c = dayKey(DateTime.parse(a).add(const Duration(days: 2)));
    store.values['life_assistant.v1'] = jsonEncode({
      'days': {
        for (final day in [a, b, c])
          day: fixtures(day).map((task) => task.toJson()).toList(),
      },
    });
    await app.initialize();
    repository.block = true;
    final first = app.refresh();
    final second = app.selectDate(DateTime.parse(b));
    expect(app.date, b);
    expect(app.tasks.every((task) => task.date == b), isTrue);
    final third = app.selectDate(DateTime.parse(c));
    expect(app.date, c);
    expect(app.tasks.every((task) => task.date == c), isTrue);
    repository.requests[a]!.complete(fixtures(a));
    await Future<void>.delayed(Duration.zero);
    expect(repository.requests.containsKey(b), isFalse);
    expect(repository.requests.containsKey(c), isTrue);
    expect(app.tasks.every((task) => task.date == c), isTrue);
    repository.requests[c]!.complete([]);
    await Future.wait([first, second, third]);
    expect(app.tasks, isEmpty);
    final saved = jsonDecode(store.values['life_assistant.v1']!) as Map;
    expect((saved['days'] as Map)[a], hasLength(3));
    expect((saved['days'] as Map)[c], isEmpty);
    app.dispose();
  });
}
