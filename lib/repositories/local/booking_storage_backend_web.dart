// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'booking_storage_backend.dart';

const _dbName = 'paltranco_local_storage';
const _storeName = 'kv';

BookingStorageBackend createBookingStorageBackend() =>
    _IndexedDbBookingStorageBackend();

class _IndexedDbBookingStorageBackend implements BookingStorageBackend {
  Object? _database;

  @override
  Future<void> initialize() async {
    await _openDatabase();
  }

  @override
  Future<List<String>> readStringList(String key) async {
    final db = await _openDatabase() as dynamic;
    final transaction = db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final value = await store.getObject(key);
    await transaction.completed;
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return const [];
  }

  @override
  Future<void> writeStringList(String key, List<String> values) async {
    final db = await _openDatabase() as dynamic;
    final transaction = db.transaction(_storeName, 'readwrite');
    final store = transaction.objectStore(_storeName);
    await store.put(values, key);
    await transaction.completed;
  }

  Future<Object> _openDatabase() async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

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
    _database = database;
    return database;
  }
}
