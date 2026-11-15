import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_assistant/data/mysql_repository.dart';
import 'package:mysql_client_plus/mysql_client_plus.dart';

class _Certificate implements X509Certificate {
  @override
  Uint8List get der => Uint8List.fromList([1, 2, 3]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Socket implements SecureSocket {
  @override
  X509Certificate get peerCertificate => _Certificate();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Row implements ResultSetRow {
  _Row(this.values);
  final Map<String, String?> values;
  @override
  Map<String, String?> assoc() => values;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Result implements IResultSet {
  _Result([this.rows = const []]);
  @override
  final Iterable<ResultSetRow> rows;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StepConnection implements MySQLConnection {
  final row = <String, String?>{
    'steps': jsonEncode([
      {'id': 'first', 'title': '第一步'},
      {'id': 'second', 'title': '第二步'},
      {'id': 'third', 'title': '第三步'},
    ]),
    'step_progress': jsonEncode({'first': true}),
  };
  bool inTransaction = false, missingTask = false;
  int writes = 0;
  final queries = <String>[];

  @override
  Socket getSocket() => _Socket();
  @override
  Future<void> connect({int timeoutMs = 10000}) async {}
  @override
  Future<void> close() async {}
  @override
  Future<T> transactional<T>(
    FutureOr<T> Function(MySQLConnection conn) callback,
  ) async {
    expect(inTransaction, isFalse);
    inTransaction = true;
    try {
      return await callback(this);
    } finally {
      inTransaction = false;
    }
  }

  @override
  Future<IResultSet> execute(
    String query, [
    Map<String, dynamic>? params,
    bool iterable = false,
    Duration? queryTimeout,
  ]) async {
    queries.add(query);
    if (query.startsWith('SELECT')) {
      expect(inTransaction, isTrue);
      expect(query, contains('FOR UPDATE'));
      return _Result(missingTask ? [] : [_Row(Map.of(row))]);
    }
    if (query.startsWith('UPDATE')) {
      expect(inTransaction, isTrue);
      row['step_progress'] = params!['progress'] as String;
      writes++;
    }
    return _Result();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MySqlTaskRepository _repository(_StepConnection connection) =>
    MySqlTaskRepository({
      'certificateSha256': sha256.convert(_Certificate().der).toString(),
    }, connectionFactory: () async => connection);

void main() {
  test(
    'Updating different steps preserves the other completed steps',
    () async {
      final connection = _StepConnection();
      final repository = _repository(connection);
      await Future.wait([
        repository.setStepCompleted('task', 'second', true),
        repository.setStepCompleted('task', 'third', true),
      ]);
      expect(jsonDecode(connection.row['step_progress']!), {
        'first': true,
        'second': true,
        'third': true,
      });
      await repository.setStepCompleted('task', 'second', false);
      expect(jsonDecode(connection.row['step_progress']!), {
        'first': true,
        'second': false,
        'third': true,
      });
      expect(connection.writes, 3);
    },
  );

  test(
    'A removed step is ignored without recreating it or changing progress',
    () async {
      final connection = _StepConnection();
      final before = connection.row['step_progress'];
      await _repository(connection).setStepCompleted('task', 'removed', true);
      expect(connection.writes, 0);
      expect(connection.row['step_progress'], before);
    },
  );

  test(
    'A removed task is safely acknowledged without a replacement row',
    () async {
      final connection = _StepConnection()..missingTask = true;
      await _repository(connection)
          .setStepCompleted('removed-task', 'first', true);
      expect(connection.writes, 0);
    },
  );
}
