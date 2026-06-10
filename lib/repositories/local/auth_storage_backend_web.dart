// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'auth_storage_backend.dart';

const _dbName = 'paltranco_local_storage';
const _storeName = 'kv';
const _legacySharedPreferencesPrefix = 'flutter.';

AuthStorageBackend createAuthStorageBackend() => _IndexedDbAuthStorageBackend();

class _IndexedDbAuthStorageBackend implements AuthStorageBackend {
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
    dynamic value = await store.getObject(key);
    await transaction.completed;

    value ??= await _readLegacyValue(key);
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

  @override
  Future<String?> readString(String key) async {
    final db = await _openDatabase() as dynamic;
    final transaction = db.transaction(_storeName, 'readonly');
    final store = transaction.objectStore(_storeName);
    dynamic value = await store.getObject(key);
    await transaction.completed;

    value ??= await _readLegacyValue(key);
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
    html.window.localStorage.remove('$_legacySharedPreferencesPrefix$key');
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

  Future<Object?> _readLegacyValue(String key) async {
    final raw = html.window.localStorage['$_legacySharedPreferencesPrefix$key'];
    if (raw == null) {
      return null;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      decoded = raw;
    }

    if (decoded is List) {
      await writeStringList(
        key,
        decoded.map((item) => item.toString()).toList(),
      );
      html.window.localStorage.remove('$_legacySharedPreferencesPrefix$key');
      return decoded;
    }

    if (decoded is String) {
      await writeString(key, decoded);
      html.window.localStorage.remove('$_legacySharedPreferencesPrefix$key');
      return decoded;
    }

    return null;
  }
}
