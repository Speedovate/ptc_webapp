// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';

import 'package:idb_shim/idb_browser.dart';

/// Durable browser storage for Firestore-derived UI data.
///
/// `shared_preferences` on web uses localStorage, whose small quota is easily
/// exceeded by booking histories and support conversations. IndexedDB has a
/// much larger durable quota and survives a fully closed browser session.
class FirestoreCachePersistence {
  static const _databaseName = 'paltranco_firestore_cache';
  static const _storeName = 'resources';

  Database? _database;
  Future<Database>? _openingDatabase;

  bool get isAvailable => true;

  Future<Database> _openDatabase() {
    final existing = _database;
    if (existing != null) {
      return Future<Database>.value(existing);
    }
    final opening = _openingDatabase;
    if (opening != null) {
      return opening;
    }
    final future = idbFactoryBrowser
        .open(
          _databaseName,
          version: 1,
          onUpgradeNeeded: (VersionChangeEvent event) {
            final database = event.database;
            if (!database.objectStoreNames.contains(_storeName)) {
              database.createObjectStore(_storeName);
            }
          },
        )
        .then((database) {
          _database = database;
          return database;
        });
    _openingDatabase = future;
    return future.whenComplete(() => _openingDatabase = null);
  }

  Future<String?> read(String key) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, 'readonly');
    final value = await transaction.objectStore(_storeName).getObject(key);
    await transaction.completed;
    return value is String ? value : null;
  }

  Future<void> write(String key, String value) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, 'readwrite');
    await transaction.objectStore(_storeName).put(value, key);
    await transaction.completed;
  }

  Future<void> remove(String key) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, 'readwrite');
    await transaction.objectStore(_storeName).delete(key);
    await transaction.completed;
  }

  Future<void> removeWhere(bool Function(String key) predicate) async {
    final database = await _openDatabase();
    final transaction = database.transaction(_storeName, 'readwrite');
    final store = transaction.objectStore(_storeName);
    final keys = await store.getAllKeys();
    for (final key in keys) {
      if (key is String && predicate(key)) {
        await store.delete(key);
      }
    }
    await transaction.completed;
  }
}

FirestoreCachePersistence createFirestoreCachePersistence() =>
    FirestoreCachePersistence();
