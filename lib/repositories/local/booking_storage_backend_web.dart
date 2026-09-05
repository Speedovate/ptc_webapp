// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'booking_storage_backend.dart';

const _dbName = 'paltranco_local_storage';
const _storeName = 'kv';
const _mirrorPrefix = 'paltranco_local_storage_mirror_';

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
  Future<List<String>> readStringList(String key) {
    final mirrored = _readMirror(key);
    if (mirrored != null) {
      return Future<List<String>>.value(mirrored);
    }
    return _runSerialized(() async {
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
  }

  @override
  Future<void> writeStringList(String key, List<String> values) async {
    final mirrorWritten = _writeMirror(key, values);
    final indexedDbWrite = _runSerialized(() async {
      final db = await _openDatabase() as dynamic;
      final transaction = db.transaction(_storeName, 'readwrite');
      final store = transaction.objectStore(_storeName);
      await store.put(values, key);
      // Request success means the browser accepted the write. Waiting for
      // transaction completion can stall the UI behind an unrelated IDB
      // transaction; the localStorage mirror already preserves this queue.
    });
    if (mirrorWritten) {
      unawaited(indexedDbWrite.catchError((_) {}));
      return;
    }
    await indexedDbWrite;
  }

  List<String>? _readMirror(String key) {
    final raw = html.window.localStorage['$_mirrorPrefix$key'];
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toList(growable: false);
      }
    } catch (_) {
      // Fall back to IndexedDB when the mirror is unavailable or malformed.
    }
    return null;
  }

  bool _writeMirror(String key, List<String> values) {
    try {
      html.window.localStorage['$_mirrorPrefix$key'] = jsonEncode(values);
      return true;
    } catch (_) {
      // IndexedDB remains the durable fallback when localStorage is blocked.
      return false;
    }
  }

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
