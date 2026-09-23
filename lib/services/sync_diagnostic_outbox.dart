import 'dart:convert';
import 'diagnostic_write_lock.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';

/// Each report is durable independently. Sharded indexes contain only upload
/// metadata, so retrying one error never serializes unrelated error/stack text.
/// Index mutations use an origin-wide browser lock, including pruning.
class SyncDiagnosticOutbox {
  SyncDiagnosticOutbox(this.backend);
  final BookingStorageBackend backend;
  static const prefix = 'sync_error_log_v2';
  static const shards = 64;
  String _bucket(String fingerprint) =>
      '${prefix}_index_${int.parse(fingerprint.substring(0, 2), radix: 16) % shards}';
  String _row(String fingerprint) => '${prefix}_row_$fingerprint';

  Future<void> _quarantine(String key, String raw) async {
    // Preserve damaged records for inspection while healthy reports continue.
    // Values were already sanitized before persistence.
    await backend.writeStringList('${prefix}_quarantine_${key.hashCode}', [
      raw.length > 64000 ? raw.substring(0, 64000) : raw,
    ]);
  }

  Future<List<Map<String, dynamic>>> _index(String key) async {
    final entries = <Map<String, dynamic>>[];
    for (final raw in await backend.readStringList(key)) {
      try {
        final row = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch('${row['fingerprint']}')) {
          throw const FormatException('Invalid index fingerprint');
        }
        entries.add(row);
      } catch (_) {
        try {
          await _quarantine(key, raw);
        } catch (_) {
          /* Keep reading healthy entries. */
        }
      }
    }
    return entries;
  }

  Future<Map<String, dynamic>?> get(String fingerprint) async {
    final rows = await backend.readStringList(_row(fingerprint));
    if (rows.isEmpty) return null;
    try {
      final row = Map<String, dynamic>.from(jsonDecode(rows.single) as Map);
      if (row['id'] is! String ||
          row['fingerprint'] != fingerprint ||
          row['occurrences'] is! int) {
        throw const FormatException('Invalid diagnostic record');
      }
      return row;
    } catch (_) {
      try {
        await _quarantine(_row(fingerprint), rows.join());
      } catch (_) {
        /* Keep reading healthy reports. */
      }
      return null;
    }
  }

  Future<void> put(Map<String, dynamic> row) =>
      withDiagnosticWriteLock(() => _put(row));

  Future<void> _put(Map<String, dynamic> row) async {
    final fingerprint = row['fingerprint'] as String;
    final key = _bucket(fingerprint);
    final entries = await _index(key);
    entries.removeWhere((e) => e['fingerprint'] == fingerprint);
    entries.add({
      'fingerprint': fingerprint,
      'dirty': row['dirty'],
      'last_uploaded_at': row['last_uploaded_at'],
    });
    // Register before writing a new row: a interrupted write can leave a
    // harmless missing row, never an undiscoverable persisted report.
    await backend.writeStringList(key, entries.map(jsonEncode).toList());
    await backend.writeStringList(_row(fingerprint), [jsonEncode(row)]);
    // Keep up to eight acknowledged receipts per shard (512 overall).
    final receipts = entries.where((e) => e['dirty'] != true).toList();
    if (receipts.length > 8) {
      final expired = receipts.take(receipts.length - 8).toList();
      entries.removeWhere(expired.contains);
      await backend.writeStringList(key, entries.map(jsonEncode).toList());
      for (final entry in expired) {
        await backend.writeStringList(_row(entry['fingerprint'] as String), []);
      }
    }
  }

  Future<List<Map<String, dynamic>>> ready(
    DateTime now, {
    int limit = 20,
  }) async {
    final result = <Map<String, dynamic>>[];
    for (var shard = 0; shard < shards; shard++) {
      for (final entry in await _index('${prefix}_index_$shard')) {
        final sent = DateTime.tryParse('${entry['last_uploaded_at']}');
        if (entry['dirty'] != true ||
            (sent != null &&
                now.difference(sent) < const Duration(minutes: 5))) {
          continue;
        }
        final row = await get(entry['fingerprint'] as String);
        if (row != null && row['dirty'] == true) result.add(row);
        if (result.length == limit) return result;
      }
      // Large backlogs must leave room for input/paint between index shards.
      await Future<void>.delayed(Duration.zero);
    }
    return result;
  }
}
