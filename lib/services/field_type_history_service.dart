import 'dart:async';
import 'dart:convert';

import 'package:webapp/models/status_field.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';

/// Optional, disposable suggestions. Never part of a business-write transaction.
class FieldTypeHistoryService {
  FieldTypeHistoryService({AuthStorageBackend? storage})
    : _storage = storage ?? createAuthStorageBackend();

  static final instance = FieldTypeHistoryService();
  final AuthStorageBackend _storage;
  Future<void> _writes = Future.value();
  static const maxEntries = 500;
  static const maxPerField = 30;

  static bool excluded(String value) {
    final key = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return key.contains('waybill') ||
        key.contains('deliveryform') ||
        key.contains('password') ||
        key.contains('secret') ||
        key.contains('token') ||
        key.contains('otp') ||
        RegExp(
          r'(^|[ _-])pin($|[ _-])',
          caseSensitive: false,
        ).hasMatch(value) ||
        key.contains('uniqueidentifier');
  }

  static String? fieldKey(StatusField field) {
    if ((!['text', 'email', 'phone', 'number'].contains(field.type ?? 'text') &&
            !field.isChassisLocationInput) ||
        excluded('${field.key} ${field.title}') ||
        (field.key ?? '').endsWith('_id')) {
      return null;
    }
    final id = field.id?.trim() ?? '';
    // Never group different fields by title or by a provisional identity.
    if (id.isEmpty || id.startsWith('offline_') || id.startsWith('-')) {
      return null;
    }
    return 'flow:$id';
  }

  Future<String?> currentAccount() async {
    try {
      await _storage.initialize();
      final id = (await _storage.readString(
        'paltranco_current_user_id',
      ))?.trim();
      return id == null || id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  String _key(String account) => 'field_type_history_v1::$account';

  Future<List<Map<String, dynamic>>> _read(String account) async {
    final raw = await _storage.readStringList(_key(account));
    final entries = <Map<String, dynamic>>[];
    for (final value in raw.take(maxEntries)) {
      try {
        final item = jsonDecode(value);
        if (item is Map<String, dynamic> &&
            item['field'] is String &&
            item['value'] is String &&
            item['at'] is String) {
          entries.add(item);
        }
      } catch (_) {
        // Bad optional history must not affect form input or business queues.
      }
    }
    return entries;
  }

  Future<List<String>> suggestions(String field, String prefix) async {
    try {
      final account = await currentAccount();
      if (account == null) return [];
      final entries = await _read(account);
      if (await currentAccount() != account) return [];
      final query = prefix.trim().toLowerCase();
      return entries
          .where((e) => e['field'] == field)
          .map((e) => e['value'] as String)
          .where((v) => v.toLowerCase().startsWith(query))
          .take(10)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Call only after the existing save/queue operation has succeeded.
  /// Account and values are captured by the caller before it awaits that save.
  Future<void> record(
    String? account,
    Map<String, String> values,
    DateTime at,
  ) {
    if (account == null || account.isEmpty || values.isEmpty) {
      return Future.value();
    }
    final captured = Map<String, String>.of(values);
    final next = _writes.then((_) async {
      try {
        await _storage.initialize();
        final entries = await _read(account);
        for (final entry in captured.entries) {
          final value = entry.value.trim();
          if (value.isEmpty || value.length > 300) continue;
          final existing = entries
              .where(
                (e) =>
                    e['field'] == entry.key &&
                    (e['value'] as String).toLowerCase() == value.toLowerCase(),
              )
              .firstOrNull;
          final existingAt = DateTime.tryParse(
            existing?['at'] as String? ?? '',
          );
          if (existingAt != null && existingAt.isAfter(at)) continue;
          entries.removeWhere(
            (e) =>
                e['field'] == entry.key &&
                (e['value'] as String).toLowerCase() == value.toLowerCase(),
          );
          entries.add({
            'field': entry.key,
            'value': value,
            'at': at.toUtc().toIso8601String(),
          });
        }
        entries.sort(
          (a, b) => (b['at'] as String).compareTo(a['at'] as String),
        );
        final counts = <String, int>{};
        final retained = entries
            .where((e) {
              final field = e['field'] as String;
              counts[field] = (counts[field] ?? 0) + 1;
              return counts[field]! <= maxPerField;
            })
            .take(maxEntries)
            .map(jsonEncode)
            .toList();
        await _storage.writeStringList(_key(account), retained);
      } catch (_) {
        // Suggestions never turn a successful save into an apparent failure.
      }
    });
    _writes = next;
    return next;
  }

  static Map<String, String> valuesFor(
    List<StatusField> fields,
    Map<String, dynamic> answers,
  ) => {
    for (final field in fields)
      if (fieldKey(field) != null &&
          (answers[field.key] is String || answers[field.key] is num))
        fieldKey(field)!: answers[field.key].toString(),
  };
}
