import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:webapp/repositories/local/auth_storage_backend.dart';

class LocalFormDraftService {
  LocalFormDraftService({
    AuthStorageBackend? store,
  }) : _store = store ?? createAuthStorageBackend();

  static final LocalFormDraftService instance = LocalFormDraftService();

  final AuthStorageBackend _store;
  final Map<String, Timer> _writeTimers = {};
  Future<void>? _initializeFuture;

  Future<void> initialize() {
    return _initializeFuture ??= _store.initialize();
  }

  Future<Map<String, dynamic>?> readMap(String key) async {
    await initialize();
    final raw = await _store.readString(key);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _deserializeValue(Map<String, dynamic>.from(decoded))
            as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<void> writeMap(
    String key,
    Map<String, dynamic> value, {
    Duration debounce = const Duration(milliseconds: 180),
  }) async {
    await initialize();
    _writeTimers[key]?.cancel();
    final completer = Completer<void>();
    _writeTimers[key] = Timer(debounce, () async {
      try {
        final serialized = jsonEncode(_serializeValue(value));
        await _store.writeString(key, serialized);
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        _writeTimers.remove(key);
      }
    });
    return completer.future;
  }

  Future<void> writeMapNow(String key, Map<String, dynamic> value) async {
    await initialize();
    _writeTimers.remove(key)?.cancel();
    final serialized = jsonEncode(_serializeValue(value));
    await _store.writeString(key, serialized);
  }

  Future<void> remove(String key) async {
    await initialize();
    _writeTimers.remove(key)?.cancel();
    await _store.remove(key);
  }

  dynamic _serializeValue(dynamic value) {
    if (value == null ||
        value is String ||
        value is num ||
        value is bool) {
      return value;
    }
    if (value is DateTime) {
      return <String, dynamic>{
        '__draft_type': 'datetime',
        'value': value.toIso8601String(),
      };
    }
    if (value is Uint8List) {
      return <String, dynamic>{
        '__draft_type': 'bytes',
        'value': base64Encode(value),
      };
    }
    if (value is List) {
      return value.map(_serializeValue).toList(growable: false);
    }
    if (value is Map) {
      return value.map<String, dynamic>(
        (key, item) => MapEntry(key.toString(), _serializeValue(item)),
      );
    }
    return value.toString();
  }

  dynamic _deserializeValue(dynamic value) {
    if (value is List) {
      return value.map(_deserializeValue).toList(growable: false);
    }
    if (value is Map) {
      final normalized = Map<String, dynamic>.from(value);
      final type = normalized['__draft_type']?.toString();
      if (type == 'bytes') {
        final raw = normalized['value']?.toString() ?? '';
        if (raw.isEmpty) {
          return Uint8List(0);
        }
        try {
          return Uint8List.fromList(base64Decode(raw));
        } catch (_) {
          return Uint8List(0);
        }
      }
      if (type == 'datetime') {
        return DateTime.tryParse(normalized['value']?.toString() ?? '');
      }
      return normalized.map<String, dynamic>(
        (key, item) => MapEntry(key, _deserializeValue(item)),
      );
    }
    return value;
  }
}
