// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'persistent_image_cache_store.dart';

const _dbName = 'paltranco_local_storage';
const _storeName = 'kv';

PersistentImageCacheStore createPersistentImageCacheStore() =>
    _IndexedDbPersistentImageCacheStore();

class _IndexedDbPersistentImageCacheStore implements PersistentImageCacheStore {
  Object? _database;

  @override
  Future<void> initialize() async {
    await _openDatabase();
  }

  @override
  Future<String?> readString(String key) async {
    final db = await _openDatabase() as dynamic;
    final transaction = db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    final value = await store.getObject(key);
    await transaction.completed;
    return value?.toString();
  }

  @override
  Future<void> writeString(String key, String value) async {
    final db = await _openDatabase() as dynamic;
    final transaction = db.transaction(_storeName, 'readwrite');
    final store = transaction.objectStore(_storeName);
    await store.put(value, key);
    await transaction.completed;
  }

  @override
  Future<void> remove(String key) async {
    final db = await _openDatabase() as dynamic;
    final transaction = db.transaction(_storeName, 'readwrite');
    final store = transaction.objectStore(_storeName);
    await store.delete(key);
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
