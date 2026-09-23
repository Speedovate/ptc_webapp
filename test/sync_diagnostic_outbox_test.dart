import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/sync_diagnostic_outbox.dart';

class _Store implements BookingStorageBackend {
  final data = <String, List<String>>{};
  final written = <String>[];
  @override
  Future<void> initialize() async {}
  @override
  Future<List<String>> readStringList(String key) async => data[key] ?? [];
  @override
  Future<void> writeStringList(String key, List<String> rows) async {
    written.add(key);
    data[key] = List.of(rows);
  }
}

void main() {
  test(
    'large backlog updates only the affected report and its small index',
    () async {
      final backend = _Store();
      final outbox = SyncDiagnosticOutbox(backend);
      final fingerprints = <String>[];
      for (var i = 0; i < 180; i++) {
        final fingerprint = sha256.convert(utf8.encode('$i')).toString();
        fingerprints.add(fingerprint);
        await outbox.put({
          'id': '$i',
          'fingerprint': fingerprint,
          'occurrences': 1,
          'dirty': true,
          'error': 'x' * 16000,
        });
      }
      backend.written.clear();
      final row = (await outbox.get(fingerprints[90]))!..['occurrences'] = 2;
      await outbox.put(row);
      expect(backend.written.length, 2);
      expect(
        backend.written.where((key) => key.contains('_row_')).single,
        endsWith(fingerprints[90]),
      );
      final restored = SyncDiagnosticOutbox(backend);
      final ready = await restored.ready(DateTime.now());
      expect(ready.length, 20);
      for (final row in ready) {
        await restored.put({
          ...row,
          'dirty': false,
          'last_uploaded_at': DateTime.now().toIso8601String(),
        });
      }
      final next = await restored.ready(DateTime.now());
      expect(next.length, 20);
      expect(
        next
            .map((r) => r['id'])
            .toSet()
            .intersection(ready.map((r) => r['id']).toSet()),
        isEmpty,
      );
      expect((await restored.get(fingerprints[90]))!['occurrences'], 2);
    },
  );
}
