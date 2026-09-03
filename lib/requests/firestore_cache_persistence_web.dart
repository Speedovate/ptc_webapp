// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

/// Durable browser storage for Firestore-derived UI data.
///
/// `shared_preferences` on web uses localStorage, whose small quota is easily
/// exceeded by booking histories and support conversations. IndexedDB has a
/// much larger durable quota and survives a fully closed browser session.
class FirestoreCachePersistence {
  static const _databaseName = 'paltranco_firestore_cache';
  static const _storeName = 'resources';

  Object? _database;
  Future<Object>? _openingDatabase;
  Future<void> _operationTail = Future<void>.value();

  bool get isAvailable => html.window.indexedDB != null;

  Future<Object> _openDatabase() {
    final existing = _database;
    if (existing != null) {
      return Future<Object>.value(existing);
    }
    final opening = _openingDatabase;
    if (opening != null) {
      return opening;
    }
    final future = _openNativeDatabase();
    _openingDatabase = future;
    return future.whenComplete(() => _openingDatabase = null);
  }

  Future<Object> _openNativeDatabase() async {
    final factory = html.window.indexedDB;
    if (factory == null) {
      throw StateError('IndexedDB is not available in this browser.');
    }
    final database = await factory.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        final request = event.target;
        final database = (request as dynamic).result;
        if (!database.objectStoreNames!.contains(_storeName)) {
          database.createObjectStore(_storeName);
        }
      },
    );
    _database = database;
    return database;
  }

  Future<String?> read(String key) => _runSerialized(() async {
    final database = await _openDatabase() as dynamic;
    final transaction = database.transaction(_storeName, 'readonly');
    final value = await transaction.objectStore(_storeName).getObject(key);
    await transaction.completed;
    return value is String ? value : null;
  });

  Future<void> write(String key, String value) => _runSerialized(() async {
    final database = await _openDatabase() as dynamic;
    final transaction = database.transaction(_storeName, 'readwrite');
    await transaction.objectStore(_storeName).put(value, key);
    await transaction.completed;
  });

  Future<void> remove(String key) => _runSerialized(() async {
    final database = await _openDatabase() as dynamic;
    final transaction = database.transaction(_storeName, 'readwrite');
    await transaction.objectStore(_storeName).delete(key);
    await transaction.completed;
  });

  Future<void> removeWhere(bool Function(String key) predicate) =>
      _runSerialized(() async {
        final database = await _openDatabase() as dynamic;
        final transaction = database.transaction(_storeName, 'readwrite');
        final store = transaction.objectStore(_storeName);
        final keys = await store.getAllKeys();
        for (final key in keys) {
          if (key is String && predicate(key)) {
            await store.delete(key);
          }
        }
        await transaction.completed;
      });

  Future<T> _runSerialized<T>(Future<T> Function() operation) {
    final scheduled = _operationTail.then((_) => operation());
    _operationTail = scheduled.then<void>((_) {}, onError: (Object _) {});
    return scheduled;
  }
}

FirestoreCachePersistence createFirestoreCachePersistence() =>
    FirestoreCachePersistence();
