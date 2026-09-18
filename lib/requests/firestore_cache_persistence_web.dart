// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

/// Durable cache only. Pending user mutations live in their separate queues.
class FirestoreCachePersistence {
  FirestoreCachePersistence({
    this.operationTimeout = const Duration(seconds: 5),
    Future<Object> Function()? openDatabase,
  }) : _providedOpenDatabase = openDatabase;

  static const _databaseName = 'paltranco_firestore_cache';
  static const _storeName = 'resources';
  final Duration operationTimeout;
  final Future<Object> Function()? _providedOpenDatabase;
  Object? _database;
  Future<Object>? _openingDatabase;
  Object? _activeTransaction;
  int _connectionEpoch = 0;
  Future<void> _operationTail = Future<void>.value();

  bool get isAvailable => html.window.indexedDB != null;

  Future<Object> _openDatabase() {
    final existing = _database;
    if (existing != null) return Future<Object>.value(existing);
    final opening = _openingDatabase;
    if (opening != null) return opening;
    final epoch = _connectionEpoch;
    final future = () async {
      final database =
          await (_providedOpenDatabase?.call() ?? _openNativeDatabase());
      if (epoch != _connectionEpoch) {
        // A timed-out open must not replace the recovered connection later.
        (database as dynamic).close();
        throw StateError('Cache connection was superseded.');
      }
      _database = database;
      return database;
    }();
    _openingDatabase = future;
    return future.whenComplete(() {
      if (identical(_openingDatabase, future)) _openingDatabase = null;
    });
  }

  Future<Object> _openNativeDatabase() async {
    final factory = html.window.indexedDB;
    if (factory == null) throw StateError('IndexedDB is not available.');
    return factory.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        final database = (event.target as dynamic).result;
        if (!database.objectStoreNames!.contains(_storeName)) {
          database.createObjectStore(_storeName);
        }
      },
    );
  }

  Future<T> _transaction<T>(
    String mode,
    Future<T> Function(dynamic store) action,
  ) async {
    final database = await _openDatabase() as dynamic;
    final transaction = database.transaction(_storeName, mode);
    _activeTransaction = transaction;
    // Observe transaction errors immediately, including timeout-triggered aborts.
    final results = await Future.wait<Object?>([
      action(transaction.objectStore(_storeName)),
      transaction.completed as Future<dynamic>,
    ], eagerError: true);
    if (identical(_activeTransaction, transaction)) _activeTransaction = null;
    return results.first as T;
  }

  Future<String?> read(String key) => _runSerialized(
    () => _transaction<String?>('readonly', (store) async {
      final value = await store.getObject(key);
      return value is String ? value : null;
    }),
  );

  Future<void> write(String key, String value) => _runSerialized(
    () => _transaction<void>('readwrite', (store) async {
      await store.put(value, key);
    }),
  );

  Future<void> remove(String key) => _runSerialized(
    () => _transaction<void>('readwrite', (store) async {
      await store.delete(key);
    }),
  );

  Future<void> removeWhere(bool Function(String key) predicate) =>
      _runSerialized(
        () => _transaction<void>('readwrite', (store) async {
          final keys = await store.getAllKeys();
          for (final key in keys) {
            if (key is String && predicate(key)) await store.delete(key);
          }
        }),
      );

  void _resetConnection() {
    _connectionEpoch++;
    try {
      (_activeTransaction as dynamic)?.abort();
    } catch (_) {}
    try {
      (_database as dynamic)?.close();
    } catch (_) {}
    _activeTransaction = null;
    _database = null;
    _openingDatabase = null;
  }

  Future<T> _runSerialized<T>(Future<T> Function() operation) {
    final scheduled = _operationTail.then((_) async {
      try {
        return await operation().timeout(operationTimeout);
      } catch (_) {
        // Release the queue and reopen on the next operation. Aborting the old
        // transaction prevents a late write from overwriting recovered data.
        _resetConnection();
        rethrow;
      }
    });
    _operationTail = scheduled.then<void>((_) {}, onError: (Object _) {});
    return scheduled;
  }
}

FirestoreCachePersistence createFirestoreCachePersistence() =>
    FirestoreCachePersistence();
