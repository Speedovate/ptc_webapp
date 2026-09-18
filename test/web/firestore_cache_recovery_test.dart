@TestOn('browser')
library;

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/requests/firestore_cache_persistence_web.dart';

class _Database {
  final bool stall;
  bool closed = false;
  _Transaction? lastTransaction;
  final data = <String, String>{};
  _Database({this.stall = false});
  _Transaction transaction(String name, String mode) =>
      lastTransaction = _Transaction(this, stall);
  void close() {
    closed = true;
  }
}

class _Transaction {
  final _Database database;
  final bool stall;
  final done = Completer<void>();
  bool aborted = false;
  _Transaction(this.database, this.stall);
  Future<void> get completed => done.future;
  _Transaction objectStore(String name) => this;
  Future<void> put(String value, String key) async {
    if (stall) return Completer<void>().future;
    database.data[key] = value;
    done.complete();
  }

  Future<Object?> getObject(String key) async {
    done.complete();
    return database.data[key];
  }

  void abort() {
    aborted = true;
    if (!done.isCompleted) done.completeError(StateError('aborted'));
  }
}

void main() {
  test('stalled transaction is aborted and queued writes recover', () async {
    final stuck = _Database(stall: true);
    final healthy = _Database();
    var opens = 0;
    final cache = FirestoreCachePersistence(
      operationTimeout: const Duration(milliseconds: 30),
      openDatabase: () async => opens++ == 0 ? stuck : healthy,
    );
    final failed = expectLater(
      cache.write('bookings', 'old'),
      throwsA(isA<TimeoutException>()),
    );
    final next = cache.write('bookings', 'new');
    await failed;
    await next;
    expect(stuck.lastTransaction?.aborted, isTrue);
    expect(stuck.closed, isTrue);
    expect(await cache.read('bookings'), 'new');
  });

  test('late database open cannot replace the recovered connection', () async {
    final delayed = Completer<Object>();
    final old = _Database();
    final healthy = _Database();
    var opens = 0;
    final cache = FirestoreCachePersistence(
      operationTimeout: const Duration(milliseconds: 30),
      openDatabase: () => opens++ == 0 ? delayed.future : Future.value(healthy),
    );
    await expectLater(
      cache.write('key', 'old'),
      throwsA(isA<TimeoutException>()),
    );
    await cache.write('key', 'new');
    delayed.complete(old);
    await Future<void>.delayed(Duration.zero);
    expect(old.closed, isTrue);
    expect(await cache.read('key'), 'new');
    expect(opens, 2);
  });

  test('real IndexedDB survives repeated reads and writes', () async {
    final cache = FirestoreCachePersistence();
    final key = 'resume-test-${DateTime.now().microsecondsSinceEpoch}';
    await cache.write(key, 'draft-cache');
    expect(await cache.read(key), 'draft-cache');
    await cache.remove(key);
    expect(await cache.read(key), isNull);
  });
}
