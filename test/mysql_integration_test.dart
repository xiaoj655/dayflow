@Tags(['database'])
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mysql_client_plus/mysql_client_plus.dart';
import 'package:life_assistant/data/mysql_repository.dart';
import 'package:life_assistant/models/task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Pinned TLS, daily generation, history snapshots, completion and focus writes',
    () async {
      final config = jsonDecode(
        await rootBundle.loadString('config/database.json'),
      ) as Map<String, dynamic>;
      final repository = MySqlTaskRepository(config);
      final connection = await MySQLConnection.createConnection(
        host: config['host'],
        port: config['port'],
        userName: config['user'],
        password: config['password'],
        databaseName: config['database'],
        secure: true,
        onBadCertificate: (cert) =>
            sha256.convert(cert.der).toString() == config['certificateSha256'],
      );
      await connection.connect();
      await connection.execute("SET time_zone = '+00:00'");
      final templateId = newId(), sessionId = newId(), carryId = newId();
      final marker = 'integration-$templateId';
      final today = dayKey(chinaNow());
      final yesterday = dayKey(chinaNow().subtract(const Duration(days: 1)));
      try {
        await connection.execute(
          '''INSERT INTO la_task_templates
        (id,title,content,tutorial,recurrence,start_date,sort_order)
        VALUES (:id,:title,'中文内容\n第二行','可选教程','daily',:date,0)''',
          {'id': templateId, 'title': marker, 'date': yesterday},
        );
        final old = (await repository.fetchDay(yesterday))
            .singleWhere((task) => task.templateId == templateId);
        var current = (await repository.fetchDay(today))
            .singleWhere((task) => task.templateId == templateId);
        expect(current.content, '中文内容\n第二行');
        expect(current.tutorial, '可选教程');
        expect(
          (await repository.fetchDay(today))
              .where((task) => task.templateId == templateId)
              .length,
          1,
        );
        await repository.saveTask(
          TaskDraft(
            title: marker,
            content: '中文内容\n第二行',
            tutorial: '可选教程',
            date: yesterday,
            recurrence: 'daily',
            taskValue: '拓宽知识',
            minimumGoal: '读一节',
            completionStandard: '写一句收获',
            startAction: '先翻开书',
            estimatedMinutes: 17,
          ),
          existing: current,
        );
        current = (await repository.fetchDay(today))
            .singleWhere((task) => task.templateId == templateId);
        expect(current.taskValue, '拓宽知识');
        expect(current.minimumGoal, '读一节');
        expect(current.completionStandard, '写一句收获');
        expect(current.startAction, '先翻开书');
        expect(current.estimatedMinutes, 17);
        await repository.setCompleted(
          current.id,
          sqlTime(DateTime.now()),
          sqlTime(DateTime.now()),
        );
        current = (await repository.fetchDay(today))
            .singleWhere((task) => task.templateId == templateId);
        expect(current.completed, isTrue);
        await repository.saveTask(
          TaskDraft(
            title: '$marker updated',
            content: '新内容',
            date: yesterday,
            recurrence: 'daily',
          ),
          existing: current,
        );
        final historical = (await repository.fetchDay(yesterday))
            .singleWhere((task) => task.id == old.id);
        expect(historical.title, marker);
        expect(historical.startAction, isNull);
        final completed = (await repository.fetchDay(today))
            .singleWhere((task) => task.id == current.id);
        expect(
          completed.title,
          marker,
        ); // Completed copies are immutable snapshots.
        expect(completed.startAction, '先翻开书');
        expect(completed.estimatedMinutes, 17);
        await repository.addToToday(old, today);
        final stillCompleted = (await repository.fetchDay(today))
            .singleWhere((task) => task.id == current.id);
        expect(stillCompleted.completed, isTrue);
        await repository.saveTask(
          TaskDraft(
            id: carryId,
            title: 'carry-$carryId',
            content: '独立任务',
            date: yesterday,
            startAction: '第一步',
            estimatedMinutes: 17,
          ),
        );
        final source = (await repository.fetchDay(yesterday))
            .singleWhere((task) => task.templateId == carryId);
        await repository.addToToday(source, today);
        await repository.addToToday(source, today);
        final copies = (await repository.fetchDay(today))
            .where((task) => task.templateId == carryId)
            .toList();
        expect(copies, hasLength(1));
        expect(copies.single.carriedFromDate, yesterday);
        expect(copies.single.startAction, '第一步');
        expect(copies.single.estimatedMinutes, 17);
        expect(
          (await repository.fetchDay(yesterday))
              .singleWhere((task) => task.id == source.id)
              .completed,
          isFalse,
        );
        final start = DateTime.now().subtract(const Duration(minutes: 5));
        final record = <String, dynamic>{
          'id': sessionId,
          'taskId': current.id,
          'taskTitle': marker,
          'kind': 'focus',
          'plannedSeconds': 300,
          'actualSeconds': 300,
          'status': 'completed',
          'startedAt': start.millisecondsSinceEpoch,
          'endedAt': DateTime.now().millisecondsSinceEpoch,
        };
        await repository.saveSession(record);
        await repository.saveSession(record);
        final count = await connection.execute(
          'SELECT COUNT(*) AS n FROM la_focus_sessions WHERE id=:id',
          {'id': sessionId},
        );
        expect(count.rows.first.colByName('n'), '1');
        await repository.archiveTask(current);
        expect(
          (await repository.fetchDay(yesterday))
              .any((task) => task.id == old.id),
          isTrue,
        );
      } finally {
        await connection.execute(
          'DELETE FROM la_task_days WHERE template_id=:id',
          {'id': carryId},
        );
        await connection.execute('DELETE FROM la_task_templates WHERE id=:id', {
          'id': carryId,
        });
        await connection.execute('DELETE FROM la_focus_sessions WHERE id=:id', {
          'id': sessionId,
        });
        await connection.execute(
          'DELETE FROM la_task_days WHERE template_id=:id',
          {'id': templateId},
        );
        await connection.execute('DELETE FROM la_task_templates WHERE id=:id', {
          'id': templateId,
        });
        await connection.close();
      }
    },
    skip: !const bool.fromEnvironment('RUN_DATABASE_TEST'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
