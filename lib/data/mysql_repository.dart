import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:mysql_client_plus/mysql_client_plus.dart';

import '../models/task.dart';
import 'task_repository.dart';

class MySqlTaskRepository implements TaskRepository {
  MySqlTaskRepository(
    this.config, {
    this.requestTimeout = const Duration(seconds: 15),
    this.connectionFactory,
  });
  final Map<String, dynamic> config;
  final Duration requestTimeout;
  final Future<MySQLConnection> Function()? connectionFactory;
  Future<void> _tail = Future.value();
  static Future<MySqlTaskRepository> load() async => MySqlTaskRepository(
    jsonDecode(await rootBundle.loadString('config/database.json'))
        as Map<String, dynamic>,
  );

  Future<T> _connection<T>(Future<T> Function(MySQLConnection) action) {
    final result = Completer<T>();
    _tail = _tail
        .then((_) async {
          MySQLConnection? connection;
          var expired = false;
          Future<T> execute() async {
            final opened =
                await (connectionFactory?.call() ??
                    MySQLConnection.createConnection(
                      host: config['host'] as String,
                      port: config['port'] as int,
                      userName: config['user'] as String,
                      password: config['password'] as String,
                      databaseName: config['database'] as String,
                      secure: true,
                      onBadCertificate: (X509Certificate cert) =>
                          sha256.convert(cert.der).toString() ==
                              config['certificateSha256'] &&
                          DateTime.now().isAfter(cert.startValidity) &&
                          DateTime.now().isBefore(cert.endValidity),
                    ));
            connection = opened;
            // A timed-out socket creation can still finish later. It must not
            // authenticate or execute a stale request after the queue advances.
            if (expired) {
              opened.getSocket().destroy();
              throw TimeoutException('Database request timed out');
            }
            await opened.connect(timeoutMs: 8000);
            if (expired) throw TimeoutException('Database request timed out');
            final socket = opened.getSocket();
            if (socket is! SecureSocket ||
                socket.peerCertificate == null ||
                sha256.convert(socket.peerCertificate!.der).toString() !=
                    config['certificateSha256']) {
              throw const HandshakeException(
                'Database certificate does not match the configured pin',
              );
            }
            await opened.execute("SET time_zone = '+00:00'");
            if (expired) throw TimeoutException('Database request timed out');
            return action(opened);
          }

          try {
            result.complete(
              await execute().timeout(
                requestTimeout,
                onTimeout: () {
                  expired = true;
                  connection?.getSocket().destroy();
                  throw TimeoutException('Database request timed out');
                },
              ),
            );
          } catch (error, stack) {
            result.completeError(error, stack);
          } finally {
            if (connection != null && !expired) {
              try {
                await connection!.close().timeout(const Duration(seconds: 1));
              } catch (_) {
                // The client cannot gracefully close during a failed handshake
                // or an unfinished query. Always release the underlying socket.
                connection!.getSocket().destroy();
              }
            }
          }
        })
        .catchError((Object _) {});
    return result.future;
  }

  @override
  Future<List<DailyTask>> fetchDay(String date) =>
      _connection((connection) async {
        final weekday = DateTime.parse(date).weekday;
        await connection.execute(
          '''INSERT IGNORE INTO la_task_days
      (id, template_id, task_date, title, content, tutorial,
       task_value, minimum_goal, completion_standard, start_action, estimated_minutes, sort_order, space)
      SELECT CONCAT(id, ':', :date), id, :date, title, content, tutorial,
        task_value, minimum_goal, completion_standard, start_action, estimated_minutes, sort_order, space
      FROM la_task_templates WHERE space = 'life' AND active = TRUE AND start_date <= :date
      AND ((recurrence = 'once' AND start_date = :date) OR recurrence = 'daily'
        OR (recurrence = 'weekly' AND FIND_IN_SET(:weekday, weekdays) > 0))''',
          {'date': date, 'weekday': weekday},
        );
        await connection.execute(
          """INSERT IGNORE INTO la_task_days
      (id, template_id, task_date, title, content, tutorial, task_value, minimum_goal,
       completion_standard, start_action, estimated_minutes, sort_order, space)
      SELECT CONCAT(t.id, ':', t.start_date), t.id, t.start_date, t.title, t.content,
       t.tutorial, t.task_value, t.minimum_goal, t.completion_standard, t.start_action,
       t.estimated_minutes, t.sort_order, t.space
      FROM la_task_templates t WHERE t.space = 'work' AND t.active = TRUE
       AND t.start_date <= :today
       AND NOT EXISTS (SELECT 1 FROM la_task_days d WHERE d.template_id = t.id AND d.space = 'work')""",
          {'today': dayKey(chinaNow())},
        );
        final result = await connection.execute(
          '''SELECT d.*, t.recurrence, t.weekdays, t.start_date AS schedule_start_date,
        (SELECT COUNT(*) FROM la_focus_sessions f WHERE f.task_day_id = d.id
          AND f.kind = 'focus' AND f.status = 'completed' AND f.actual_seconds >= 180) AS focus_count
      FROM la_task_days d JOIN la_task_templates t ON d.template_id = t.id
      WHERE d.space = 'life' AND d.task_date = :date AND (:date < :today OR d.completed_at IS NOT NULL
        OR d.carried_from_date IS NOT NULL
        OR (t.active = TRUE AND t.start_date <= :date AND
          ((t.recurrence = 'once' AND t.start_date = :date) OR t.recurrence = 'daily'
            OR (t.recurrence = 'weekly' AND FIND_IN_SET(:weekday, t.weekdays) > 0))))
      ORDER BY d.sort_order, d.id''',
          {'date': date, 'today': dayKey(chinaNow()), 'weekday': weekday},
        );
        final work = await connection.execute(
          """SELECT d.*, t.recurrence, t.weekdays, t.start_date AS schedule_start_date,
        (SELECT COUNT(*) FROM la_focus_sessions f WHERE f.task_day_id = d.id
          AND f.kind = 'focus' AND f.status = 'completed' AND f.actual_seconds >= 180) AS focus_count
      FROM la_task_days d JOIN la_task_templates t ON t.id = d.template_id
      WHERE d.space = 'work' AND d.task_date <= :today
      AND (d.completed_at IS NOT NULL OR (t.active = TRUE AND NOT EXISTS
        (SELECT 1 FROM la_task_days newer WHERE newer.template_id = d.template_id
          AND newer.space = 'work' AND newer.task_date > d.task_date AND newer.task_date <= :today)))
      ORDER BY d.sort_order, d.id""",
          {'today': dayKey(chinaNow())},
        );
        return [
          ...result.rows,
          ...work.rows,
        ].map((row) => DailyTask.fromJson(row.assoc())).toList();
      });

  @override
  Future<void> addToToday(DailyTask task, String today) => _connection((
    connection,
  ) async {
    if (task.space == 'work') throw const FormatException('工作任务持续保留，无需加入今天');
    await connection.transactional((transaction) async {
      final result = await transaction.execute(
        'SELECT task_date, completed_at FROM la_task_days WHERE id = :id FOR UPDATE',
        {'id': task.id},
      );
      if (result.rows.isEmpty) throw const FormatException('找不到这项任务');
      final source = result.rows.first.assoc();
      if (source['completed_at'] != null ||
          source['task_date'].toString().substring(0, 10) == today) {
        throw const FormatException('只能将其他日期未完成的任务加入今天');
      }
      await transaction.execute(
        '''INSERT INTO la_task_days
          (id, template_id, task_date, carried_from_date, title, content, tutorial,
           task_value, minimum_goal, completion_standard, start_action, estimated_minutes, sort_order, space)
        SELECT CONCAT(template_id, ':', :today), template_id, :today, task_date,
          title, content, tutorial, task_value, minimum_goal, completion_standard,
          start_action, estimated_minutes, sort_order, space
        FROM la_task_days AS source_task WHERE id = :id
        ON DUPLICATE KEY UPDATE carried_from_date = IF(la_task_days.completed_at IS NULL,
          COALESCE(la_task_days.carried_from_date, VALUES(carried_from_date)), la_task_days.carried_from_date)''',
        {'id': task.id, 'today': today},
      );
    });
  });

  @override
  Future<void> setWaiting(String id, bool waiting) =>
      _connection((connection) async {
        await connection.execute(
          "UPDATE la_task_days SET waiting = :waiting WHERE id = :id AND space = 'work'",
          {'id': id, 'waiting': waiting ? 1 : 0},
        );
      });

  @override
  Future<void> setCompleted(String id, String? completedAt, String changedAt) =>
      _connection((connection) async {
        await connection.execute(
          '''UPDATE la_task_days SET completed_at = :completed,
        updated_at = UTC_TIMESTAMP(3) WHERE id = :id''',
          {'completed': completedAt, 'id': id},
        );
      });

  @override
  Future<void> saveTask(TaskDraft draft, {DailyTask? existing}) =>
      _connection((connection) async {
        draft.validate();
        final id = existing?.templateId ?? draft.id ?? newId();
        await connection.transactional((transaction) async {
          await transaction.execute(
            '''INSERT INTO la_task_templates
        (id, title, content, tutorial, task_value, minimum_goal, completion_standard,
         start_action, estimated_minutes, recurrence, start_date, weekdays, sort_order, space)
        VALUES (:id, :title, :content, :tutorial, :value, :goal, :standard,
          :action, :estimate, :recurrence, :date, :weekdays, :sort, :space)
        ON DUPLICATE KEY UPDATE title = VALUES(title), content = VALUES(content),
          tutorial = VALUES(tutorial), task_value = VALUES(task_value),
          minimum_goal = VALUES(minimum_goal), completion_standard = VALUES(completion_standard),
          start_action = VALUES(start_action), estimated_minutes = VALUES(estimated_minutes), recurrence = VALUES(recurrence),
          start_date = VALUES(start_date), weekdays = VALUES(weekdays), sort_order = VALUES(sort_order), space = VALUES(space)''',
            {
              'space': draft.space,
              'id': id,
              'title': draft.title.trim(),
              'content': draft.content.trim(),
              'tutorial': draft.tutorial?.trim().isEmpty == true
                  ? null
                  : draft.tutorial?.trim(),
              'value': _optional(draft.taskValue),
              'goal': _optional(draft.minimumGoal),
              'standard': _optional(draft.completionStandard),
              'action': _optional(draft.startAction),
              'estimate': draft.estimatedMinutes,
              'recurrence': draft.recurrence,
              'date': draft.date,
              'weekdays': draft.weekdays.join(','),
              'sort': draft.sortOrder,
            },
          );
          // Editing a schedule updates today's/future generated copies, never history.
          await transaction.execute(
            '''UPDATE la_task_days SET title = :title,
        content = :content, tutorial = :tutorial, sort_order = :sort,
        task_value = :value, minimum_goal = :goal, completion_standard = :standard,
        start_action = :action, estimated_minutes = :estimate, space = :space
        WHERE template_id = :id AND (task_date >= :today OR (space = 'work' AND id = :workId)) AND completed_at IS NULL''',
            {
              'space': draft.space,
              'id': id,
              'title': draft.title.trim(),
              'content': draft.content.trim(),
              'tutorial': draft.tutorial,
              'sort': draft.sortOrder,
              'value': _optional(draft.taskValue),
              'goal': _optional(draft.minimumGoal),
              'standard': _optional(draft.completionStandard),
              'action': _optional(draft.startAction),
              'estimate': draft.estimatedMinutes,
              'today': dayKey(chinaNow()),
              'workId': existing?.id ?? '',
            },
          );
        });
      });

  @override
  Future<void> archiveTask(DailyTask task) => _connection((connection) async {
    await connection.execute(
      'UPDATE la_task_templates SET active = FALSE WHERE id = :id',
      {'id': task.templateId},
    );
  });

  @override
  Future<void> saveSession(Map<String, dynamic> session) =>
      _connection((connection) async {
        await connection.execute(
          '''INSERT INTO la_focus_sessions
      (id, task_day_id, task_title, kind, planned_seconds, actual_seconds, status, started_at, ended_at, space)
      VALUES (:id, :taskId, :taskTitle, :kind, :plannedSeconds, :actualSeconds, :status, :started, :ended, :space)
      ON DUPLICATE KEY UPDATE actual_seconds = VALUES(actual_seconds), status = VALUES(status), ended_at = VALUES(ended_at)''',
          {
            ...session,
            'taskId': session['taskId'] == '' ? null : session['taskId'],
            'space': session['space'] ?? 'life',
            'started': sqlTime(
              DateTime.fromMillisecondsSinceEpoch(session['startedAt'] as int),
            ),
            'ended': sqlTime(
              DateTime.fromMillisecondsSinceEpoch(session['endedAt'] as int),
            ),
          },
        );
      });

  @override
  Future<List<Map<String, dynamic>>> history() => _connection((
    connection,
  ) async {
    final result = await connection.execute(
      '''SELECT id, space, task_title, kind, planned_seconds,
      actual_seconds, status, started_at, ended_at FROM la_focus_sessions
      ORDER BY started_at DESC''',
    );
    return result.rows.map((row) => <String, dynamic>{...row.assoc()}).toList();
  });
}

String? _optional(String? value) =>
    value?.trim().isEmpty == false ? value!.trim() : null;
