import 'dart:async';
import 'dart:math' as math;

import 'package:life_assistant/data/task_repository.dart';
import 'package:life_assistant/data/local_store.dart';
import 'package:life_assistant/models/task.dart';
import 'package:life_assistant/platform/focus_engine.dart';

List<DailyTask> fixtures(String date) => [
  DailyTask(
    id: 'observe:$date',
    templateId: 'observe',
    date: date,
    title: '街头观察',
    content: '散步时选一个维度观察：步速、姿态或穿搭。用三条简短描述记录今天的发现。',
    tutorial: '每轮只观察一个维度。\n先描述细节，再区分自己的猜测。\n结束后记录新发现。',
    sortOrder: 0,
    taskValue: '提升观察能力',
    minimumGoal: '记录一个细节',
    completionStandard: '保存一条观察笔记',
    startAction: '先观察一个路口',
    estimatedMinutes: 15,
  ),
  DailyTask(
    id: 'read:$date',
    templateId: 'read',
    date: date,
    title: '阅读',
    content: '阅读一节，写下收获。',
    recurrence: 'daily',
    sortOrder: 1,
  ),
  DailyTask(
    id: 'review:$date',
    templateId: 'review',
    date: date,
    title: '晚间回顾',
    content: '回想今天的收获，安排明天的一件事。',
    recurrence: 'daily',
    sortOrder: 2,
  ),
];

class FakeRepository implements TaskRepository {
  final Map<String, List<DailyTask>> days = {};
  final Map<String, Map<String, dynamic>> sessions = {};
  bool fail = false;
  void _check() {
    if (fail) throw StateError('offline');
  }

  @override
  Future<List<DailyTask>> fetchDay(String date) async {
    _check();
    return days
        .putIfAbsent(date, () => fixtures(date))
        .map(
          (task) => DailyTask.fromJson({
            ...task.toJson(),
            'focus_count': sessions.values
                .where(
                  (row) =>
                      (row['taskId'] ?? row['task_day_id']) == task.id &&
                      row['kind'] == 'focus' &&
                      row['status'] == 'completed' &&
                      (int.tryParse(
                                '${row['actualSeconds'] ?? row['actual_seconds']}',
                              ) ??
                              0) >=
                          180,
                )
                .length,
          }),
        )
        .toList();
  }

  @override
  Future<void> addToToday(DailyTask task, String today) async {
    _check();
    if (task.completed || task.date == today) {
      throw const FormatException('invalid source');
    }
    final list = days.putIfAbsent(today, () => fixtures(today));
    final index = list.indexWhere((item) => item.templateId == task.templateId);
    if (index >= 0) {
      final existing = list[index];
      if (!existing.completed) {
        list[index] = DailyTask.fromJson({
          ...existing.toJson(),
          'carried_from_date': existing.carriedFromDate ?? task.date,
        });
      }
      return;
    }
    list.add(
      DailyTask.fromJson({
        ...task.toJson(),
        'id': '${task.templateId}:$today',
        'task_date': today,
        'completed_at': null,
        'carried_from_date': task.date,
      }),
    );
  }

  @override
  Future<void> setWaiting(String id, bool waiting) async {
    _check();
    for (final entry in days.entries.toList()) {
      days[entry.key] = entry.value
          .map((t) => t.id == id ? t.withWaiting(waiting) : t)
          .toList();
    }
  }

  @override
  Future<void> setCompleted(String id, String? at, String changedAt) async {
    _check();
    for (final entry in days.entries.toList()) {
      days[entry.key] = entry.value
          .map((task) => task.id == id ? task.withCompletion(at) : task)
          .toList();
    }
  }

  @override
  Future<void> saveTask(TaskDraft draft, {DailyTask? existing}) async {
    _check();
    draft.validate();
    final task = DailyTask(
      id: existing?.id ?? 'new:${draft.date}',
      templateId: existing?.templateId ?? 'new',
      date: draft.date,
      title: draft.title,
      content: draft.content,
      tutorial: draft.tutorial,
      taskValue: draft.taskValue,
      minimumGoal: draft.minimumGoal,
      completionStandard: draft.completionStandard,
      startAction: draft.startAction,
      estimatedMinutes: draft.estimatedMinutes,
      recurrence: draft.recurrence,
      weekdays: draft.weekdays,
      sortOrder: draft.sortOrder,
    );
    final list = days.putIfAbsent(draft.date, () => []);
    list.removeWhere((task) => task.id == existing?.id);
    list.add(task);
  }

  @override
  Future<void> archiveTask(DailyTask task) async {
    _check();
    days[task.date]?.removeWhere((item) => item.templateId == task.templateId);
  }

  @override
  Future<void> saveSession(Map<String, dynamic> session) async {
    _check();
    sessions[session['id'] as String] = Map.of(session);
  }

  @override
  Future<List<Map<String, dynamic>>> history() async {
    _check();
    return sessions.values.toList();
  }
}

/// Allows a test to hold network replies while the UI remains interactive.
class DelayedRepository extends FakeRepository {
  bool block = false;
  final requests = <String, Completer<List<DailyTask>>>{};
  @override
  Future<List<DailyTask>> fetchDay(String date) {
    if (!block) return super.fetchDay(date);
    final response = Completer<List<DailyTask>>();
    requests[date] = response;
    return response.future;
  }
}

class DelayedStore extends MemoryStore {
  final restored = Completer<String?>();
  @override
  Future<String?> read(String key) => restored.future;
}

class FakeFocusEngine implements FocusEngine {
  DateTime now = DateTime.utc(2026, 10, 24, 12);
  Map<String, dynamic>? state;
  final List<Map<String, dynamic>> records = [];
  int lastMinutes = 25;
  int get milliseconds => now.millisecondsSinceEpoch;
  void elapse(Duration duration) {
    now = now.add(duration);
  }

  int remaining() => state!['status'] == 'running'
      ? math.max(0, (state!['deadline'] as int) - milliseconds)
      : state!['remainingMillis'] as int;
  void record(bool completed) {
    if (records.any((record) => record['id'] == state!['id'])) return;
    records.add({
      ...state!,
      'actualSeconds': completed
          ? state!['plannedSeconds']
          : (state!['plannedSeconds'] as int) - remaining() ~/ 1000,
      'status': completed ? 'completed' : 'interrupted',
      'endedAt': milliseconds,
    });
  }

  void update() {
    if (state?['status'] == 'running') {
      final left = remaining();
      if (left == 0) {
        record(true);
        state!['status'] = 'finished';
      }
      state!['remainingMillis'] = left;
    }
  }

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    update();
    final args = arguments ?? {};
    switch (method) {
      case 'start':
        if (state != null && state!['status'] != 'finished') {
          throw StateError('active');
        }
        final minutes = args['minutes'] as int;
        if (args['kind'] == 'focus') lastMinutes = minutes;
        state = {
          ...args,
          'status': 'running',
          'plannedSeconds': minutes * 60,
          'remainingMillis': minutes * 60000,
          'startedAt': milliseconds,
          'deadline': milliseconds + minutes * 60000,
        };
      case 'pause':
        if (state?['status'] == 'running') {
          state!['remainingMillis'] = remaining();
          state!['status'] = 'paused';
        }
      case 'resume':
        if (state?['status'] == 'paused') {
          state!['deadline'] =
              milliseconds + (state!['remainingMillis'] as int);
          state!['status'] = 'running';
        }
      case 'stop':
        if (state != null && state!['status'] != 'finished') record(false);
        state = null;
      case 'dismiss':
        state = null;
      case 'ack':
        records.removeWhere(
          (record) => (args['ids'] as List).contains(record['id']),
        );
    }
    return {
      'state': state == null ? null : Map<String, dynamic>.of(state!),
      'records': records.map(Map<String, dynamic>.of).toList(),
      'lastMinutes': lastMinutes,
    };
  }
}
