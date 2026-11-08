import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/local_store.dart';
import '../data/task_repository.dart';
import '../models/focus_session.dart';
import '../models/task.dart';
import '../platform/focus_engine.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.store,
    required this.engine,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final TaskRepository repository;
  final LocalStore store;
  final FocusEngine engine;
  final DateTime Function() clock;
  String space = 'life';
  List<DailyTask> get visibleTasks =>
      tasks.where((t) => t.space == space).toList();
  Future<void> selectSpace(String value) async {
    if (!['life', 'work'].contains(value)) return;
    space = value;
    _notify();
    await _persist();
  }

  String date = dayKey(chinaNow());
  List<DailyTask> tasks = [];
  FocusSession? focus;
  int lastMinutes = 25;
  bool dndEnabled = false;
  bool initializing = true;
  bool loading = false, offline = false;
  bool _closed = false;
  final Map<String, dynamic> _cache = {};
  final Map<String, Map<String, dynamic>> _historyCache = {};
  final Map<String, dynamic> _pendingCompletion = {};
  final Map<String, Map<String, dynamic>> _pendingSessions = {};
  Future<void> _writes = Future.value();
  Future<void>? _refreshing, _focusReading;
  String get today => dayKey(chinaNow(clock()));
  List<DailyTask> get pending =>
      visibleTasks.where((task) => !task.completed).toList();
  List<DailyTask> get completed =>
      visibleTasks.where((task) => task.completed).toList();

  Future<void> initialize() async {
    try {
      date = dayKey(chinaNow(clock()));
      final saved = await store.read('life_assistant.v1');
      if (saved != null) {
        try {
          final data = jsonDecode(saved) as Map<String, dynamic>;
          space = data['space'] == 'work' ? 'work' : 'life';
          for (final entry
              in (data['history'] as Map<String, dynamic>? ?? {}).entries) {
            _historyCache[entry.key] = Map<String, dynamic>.from(
              entry.value as Map,
            );
          }
          _cache.addAll(data['days'] as Map<String, dynamic>? ?? {});
          _pendingCompletion.addAll(
            data['completion'] as Map<String, dynamic>? ?? {},
          );
          for (final entry
              in (data['sessions'] as Map<String, dynamic>? ?? {}).entries) {
            _pendingSessions[entry.key] = Map<String, dynamic>.from(
              entry.value as Map,
            );
          }
        } on FormatException {
          /* A damaged cache must not prevent opening the app. */
        }
      }
      _loadCache();
      await refreshFocus();
    } finally {
      initializing = false;
      _notify();
    }
  }

  void _loadCache() {
    final rows = _cache[date] as List<dynamic>? ?? [];
    tasks = rows
        .map((row) => DailyTask.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    _applyPending();
    _notify();
  }

  void _applyPending() {
    tasks = tasks.map((task) {
      final change = _pendingCompletion[task.id] as Map?;
      return change == null
          ? task
          : task.withCompletion(change['completedAt'] as String?);
    }).toList();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> _persist() {
    _cache[date] = tasks.map((task) => task.toJson()).toList();
    final snapshot = jsonEncode({
      'history': _historyCache,
      'space': space,
      'days': _cache,
      'completion': _pendingCompletion,
      'sessions': _pendingSessions,
    });
    _writes = _writes
        .catchError((Object _) {})
        .then((_) => store.write('life_assistant.v1', snapshot));
    return _writes;
  }

  Future<void> selectDate(DateTime value) {
    if (_closed) return Future.value();
    date = dayKey(value);
    _loadCache();
    return refresh();
  }

  Future<void> addToToday(DailyTask task) async {
    final target = today;
    if (task.completed || task.date == target) {
      throw const FormatException('只能将其他日期未完成的任务加入今天');
    }
    if (_refreshing != null) await _refreshing;
    await repository.addToToday(task, target);
    await selectDate(DateTime.parse(target));
  }

  Future<void> refresh() {
    if (_closed) return Future.value();
    if (_refreshing != null) return _refreshing!;
    final done = Completer<void>();
    _refreshing = done.future;
    unawaited(_refreshLatest(done));
    return done.future;
  }

  Future<void> _refreshLatest(Completer<void> done) async {
    loading = true;
    _notify();
    try {
      String requested;
      do {
        requested = date;
        await _refreshDay(requested);
        // Skip intermediate selections; an old response must never replace the
        // currently selected day's tasks. Keep one database request at a time.
      } while (!_closed && requested != date);
      done.complete();
    } catch (error, stack) {
      done.completeError(error, stack);
    } finally {
      _refreshing = null;
      loading = false;
      _notify();
    }
  }

  Future<void> _refreshDay(String requested) async {
    final watch = Stopwatch()..start();
    try {
      // Persist acknowledgements only after the corresponding DB write succeeds.
      for (final entry in Map<String, dynamic>.from(
        _pendingCompletion,
      ).entries) {
        final change = Map<String, dynamic>.from(entry.value as Map);
        await repository.setCompleted(
          entry.key,
          change['completedAt'] as String?,
          change['changedAt'] as String,
        );
        if (jsonEncode(_pendingCompletion[entry.key]) == jsonEncode(change)) {
          _pendingCompletion.remove(entry.key);
        }
      }
      for (final entry in Map<String, Map<String, dynamic>>.from(
        _pendingSessions,
      ).entries) {
        await repository.saveSession(entry.value);
        _pendingSessions.remove(entry.key);
      }
      final rows = await repository.fetchDay(requested);
      if (_closed) return;
      _cache[requested] = rows.map((task) => task.toJson()).toList();
      if (date == requested) {
        tasks = rows;
        _applyPending();
        offline = false;
        _notify();
      }
      await _persist();
    } catch (_) {
      if (_closed) return;
      if (date == requested) offline = true;
      await _persist();
    } finally {
      if (kDebugMode) {
        debugPrint('Task refresh $requested: ${watch.elapsedMilliseconds}ms');
      }
    }
  }

  Future<void> toggle(DailyTask task) async {
    final now = sqlTime(clock());
    final value = task.completed ? null : now;
    _pendingCompletion[task.id] = {'completedAt': value, 'changedAt': now};
    tasks = tasks
        .map((item) => item.id == task.id ? item.withCompletion(value) : item)
        .toList();
    _notify();
    await _persist();
    unawaited(refresh());
  }

  Future<void> saveTask(TaskDraft draft, {DailyTask? existing}) async {
    await repository.saveTask(draft, existing: existing);
    await refresh();
  }

  Future<void> archive(DailyTask task) async {
    await repository.archiveTask(task);
    await refresh();
  }

  Future<void> refreshFocus() =>
      _focusReading ??= _readFocus().whenComplete(() => _focusReading = null);
  Future<void> _readFocus() async {
    try {
      await _applyFocus(await engine.call('get'));
    } on MissingPluginException {
      /* Non-Android tooling can still manage tasks. */
    }
  }

  Future<void> _applyFocus(Map<String, dynamic> snapshot) async {
    dndEnabled = snapshot['dndEnabled'] == true;
    final state = snapshot['state'];
    focus = state is Map
        ? FocusSession.fromJson(Map<String, dynamic>.from(state))
        : null;
    lastMinutes = (snapshot['lastMinutes'] as num?)?.toInt() ?? lastMinutes;
    final records = snapshot['records'] as List? ?? [];
    if (records.isNotEmpty) {
      for (final item in records) {
        final row = Map<String, dynamic>.from(item as Map);
        _pendingSessions[row['id'] as String] = row;
        _historyCache[row['id'] as String] = {
          'id': row['id'],
          'space': row['space'] ?? 'life',
          'task_title': row['taskTitle'],
          'kind': row['kind'],
          'status': row['status'],
          'actual_seconds': row['actualSeconds'],
          'started_at': sqlTime(
            DateTime.fromMillisecondsSinceEpoch(row['startedAt'] as int),
          ),
          'ended_at': sqlTime(
            DateTime.fromMillisecondsSinceEpoch(row['endedAt'] as int),
          ),
        };
      }
      await _persist();
      await engine.call('ack', {
        'ids': records.map((record) => (record as Map)['id']).toList(),
      });
      unawaited(refresh());
    }
    _notify();
  }

  Future<List<Map<String, dynamic>>> history() async {
    try {
      for (final row in await repository.history()) {
        _historyCache[row['id']?.toString() ??
                '${row['started_at']}-${row['task_title']}'] =
            row;
      }
      await _persist();
    } catch (_) {
      if (_historyCache.isEmpty) rethrow;
    }
    return _historyCache.values.toList()..sort(
      (a, b) =>
          b['started_at'].toString().compareTo(a['started_at'].toString()),
    );
  }

  Future<void> start(DailyTask task, int minutes, {bool rest = false}) async {
    if (minutes < 5 || minutes > 180 || minutes % 5 != 0) {
      throw const FormatException('时长须为 5 分钟的倍数');
    }
    await _applyFocus(
      await engine.call('start', {
        'id': newId(),
        'space': task.space,
        'taskId': task.id,
        'taskTitle': task.title,
        'startAction': task.startAction,
        'minutes': minutes,
        'kind': rest ? 'rest' : 'focus',
      }),
    );
  }

  Future<void> focusAction(String method) async =>
      _applyFocus(await engine.call(method));

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
