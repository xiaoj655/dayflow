import 'dart:async';
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
  bool destroyed = false;

  @override
  X509Certificate get peerCertificate => _Certificate();

  @override
  void destroy() => destroyed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Result implements IResultSet {
  @override
  Iterable<ResultSetRow> get rows => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connection implements MySQLConnection {
  final socket = _Socket();
  final queries = <String>[];
  int connectCalls = 0, closeCalls = 0;
  Future<void> Function()? onConnect, closeResponse;
  Future<IResultSet> Function(String)? onExecute;

  @override
  Socket getSocket() => socket;

  @override
  Future<void> connect({int timeoutMs = 10000}) async {
    connectCalls++;
    await onConnect?.call();
  }

  @override
  Future<IResultSet> execute(
    String query, [
    Map<String, dynamic>? params,
    bool iterable = false,
    Duration? queryTimeout,
  ]) async {
    queries.add(query);
    return onExecute?.call(query) ?? _Result();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    await closeResponse?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MySqlTaskRepository _repository(
  Future<MySQLConnection> Function() factory, {
  String? pin,
}) => MySqlTaskRepository(
  {'certificateSha256': pin ?? sha256.convert(_Certificate().der).toString()},
  requestTimeout: const Duration(seconds: 2),
  connectionFactory: factory,
);

void main() {
  testWidgets('A stalled query times out and releases the next request', (
    tester,
  ) async {
    final stalled = _Connection();
    final healthy = _Connection();
    final response = Completer<IResultSet>();
    stalled.onExecute = (query) async =>
        query.startsWith('SET ') ? _Result() : response.future;
    var opens = 0;
    final repository = _repository(
      () async => opens++ == 0 ? stalled : healthy,
    );
    final failed = expectLater(
      repository.setWaiting('first', true),
      throwsA(isA<TimeoutException>()),
    );
    final next = repository.setWaiting('second', false);
    await tester.pump();
    expect(stalled.queries, hasLength(2));
    await tester.pump(const Duration(seconds: 2));
    await failed;
    await next;
    expect(stalled.socket.destroyed, isTrue);
    expect(healthy.queries, hasLength(2));
    expect(healthy.closeCalls, 1);
  });

  testWidgets('A late handshake cannot execute queries after its timeout', (
    tester,
  ) async {
    final stalled = _Connection();
    final healthy = _Connection();
    final handshake = Completer<void>();
    stalled.onConnect = () => handshake.future;
    var opens = 0;
    final repository = _repository(
      () async => opens++ == 0 ? stalled : healthy,
    );
    final failed = expectLater(
      repository.history(),
      throwsA(isA<TimeoutException>()),
    );
    final next = repository.history();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await failed;
    expect(await next, isEmpty);
    handshake.complete();
    await tester.pump();
    expect(stalled.socket.destroyed, isTrue);
    expect(stalled.queries, isEmpty);
  });

  testWidgets('A late socket is destroyed before authentication', (
    tester,
  ) async {
    final opening = Completer<MySQLConnection>();
    final late = _Connection();
    final healthy = _Connection();
    var opens = 0;
    final repository = _repository(
      () => opens++ == 0 ? opening.future : Future.value(healthy),
    );
    final failed = expectLater(
      repository.history(),
      throwsA(isA<TimeoutException>()),
    );
    final next = repository.history();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await failed;
    expect(await next, isEmpty);
    opening.complete(late);
    await tester.pump();
    expect(late.socket.destroyed, isTrue);
    expect(late.connectCalls, 0);
    expect(late.queries, isEmpty);
  });

  testWidgets('A certificate mismatch is rejected before any SQL', (
    tester,
  ) async {
    final connection = _Connection();
    final repository = _repository(() async => connection, pin: 'wrong-pin');
    final failed = expectLater(
      repository.history(),
      throwsA(isA<HandshakeException>()),
    );
    await tester.pump();
    await failed;
    expect(connection.queries, isEmpty);
    expect(connection.closeCalls, 1);
  });

  testWidgets('Failed handshakes release sockets even when close rejects', (
    tester,
  ) async {
    final failedConnection = _Connection();
    failedConnection.onConnect = () async =>
        throw StateError('Handshake failed');
    failedConnection.closeResponse = () async =>
        throw StateError('Not connected');
    final healthy = _Connection();
    var opens = 0;
    final repository = _repository(
      () async => opens++ == 0 ? failedConnection : healthy,
    );
    final failed = expectLater(repository.history(), throwsStateError);
    final next = repository.history();
    await tester.pump();
    await failed;
    expect(await next, isEmpty);
    expect(failedConnection.socket.destroyed, isTrue);
    expect(failedConnection.queries, isEmpty);
  });

  testWidgets('Stalled graceful closure cannot block later requests', (
    tester,
  ) async {
    final closing = Completer<void>();
    final first = _Connection()..closeResponse = () => closing.future;
    final healthy = _Connection();
    var opens = 0;
    final repository = _repository(() async => opens++ == 0 ? first : healthy);
    final request = repository.history();
    final next = repository.history();
    await tester.pump();
    expect(await request, isEmpty);
    expect(opens, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(await next, isEmpty);
    expect(first.socket.destroyed, isTrue);
    closing.complete();
    await tester.pump();
  });
}
