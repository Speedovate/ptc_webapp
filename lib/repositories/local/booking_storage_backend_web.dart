// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'booking_storage_backend.dart';

const _dbName = 'paltranco_local_storage';
const _storeName = 'kv';

BookingStorageBackend createBookingStorageBackend() =>
    _IndexedDbBookingStorageBackend();

class _IndexedDbBookingStorageBackend implements BookingStorageBackend {
  static Future<Object>? _databaseFuture;
  static Future<void> _operationTail = Future<void>.value();

  @override
  Future<void> initialize() async {
    await _openDatabase();
  }

  @override
  Future<List<String>> readStringList(String key) => _runSerialized(() async {
    final db = await _openDatabase() as dynamic;
    final transaction = db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    // A completed read request already has its result. Waiting for the whole
    // transaction here can hang behind another service's write transaction.
    final value = await store.getObject(key);
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return const <String>[];
  });

  @override
  Future<void> writeStringList(String key, List<String> values) =>
      _runSerialized(() async {
        final db = await _openDatabase() as dynamic;
        final transaction = db.transaction(_storeName, 'readwrite');
        final store = transaction.objectStore(_storeName);
        await store.put(values, key);
        await transaction.completed;
      });

  Future<Object> _openDatabase() async {
    return _databaseFuture ??= _openSharedDatabase();
  }

  Future<Object> _openSharedDatabase() async {
    final factory = html.window.indexedDB;
    if (factory == null) {
      throw StateError('IndexedDB is not available in this browser.');
    }

    final database = await factory.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (event) {
        final request = event.target;
        final db = (request as dynamic).result;
        if (!db.objectStoreNames!.contains(_storeName)) {
          db.createObjectStore(_storeName);
        }
      },
    );
    return database;
  }

  Future<T> _runSerialized<T>(Future<T> Function() operation) {
    final scheduled = _operationTail.then((_) => operation());
    _operationTail = scheduled.then<void>((_) {}, onError: (Object _) {});
    return scheduled;
  }
}
