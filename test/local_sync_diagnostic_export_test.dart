import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/sync_error_log_service.dart';
import 'sync_error_log_service_test.dart'
    show MemoryLogs, capture, reports, waitFor;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'failed diagnostic upload is visible locally without recursive logging',
    () async {
      final backend = MemoryLogs();
      var writes = 0;
      final service = SyncErrorLogService(
        backend: backend,
        online: () => true,
        metadata: (owner) async => {'user_id': owner},
        writer: (_, _) async {
          writes++;
          throw StateError('[cloud_firestore/unavailable] client is offline');
        },
      );
      addTearDown(service.dispose);
      await capture(service);
      await service.start();
      final exported = await service.localDiagnosticReport('13');
      expect(
        exported['diagnostic_upload']['last_error'],
        contains('cloud_firestore/unavailable'),
      );
      expect(exported['diagnostic_upload']['retry_after'], isNotNull);
      expect((exported['reports'] as List), hasLength(1));
      expect((exported['reports'] as List).single['dirty'], true);
      expect(writes, 1);
    },
  );

  test(
    'offline export reads only owner diagnostics without writes or acknowledgement',
    () async {
      final backend = MemoryLogs();
      var writes = 0;
      final service = SyncErrorLogService(
        backend: backend,
        online: () => false,
        metadata: (owner) async => {'user_id': owner},
        writer: (_, _) async {
          writes++;
        },
      );
      addTearDown(service.dispose);
      await capture(service);
      await service.capture(
        source: 'offline_media_sync_service.dart',
        operation: 'supportMessage',
        entryId: 'other',
        target: 'threads/other',
        owner: '99',
        error: 'other owner error',
        stack: '',
        attempt: 1,
      );
      final before = jsonEncode(backend.values);
      final exported = await service.localDiagnosticReport('13');
      final rows = exported['reports'] as List;
      expect(rows, hasLength(1));
      expect(rows.single['queue_entry_id'], 'queue1');
      expect(rows.single['action_at'], '2026-09-22T01:00:00Z');
      expect(rows.single['dirty'], true);
      expect(rows.single['firebase_console_diagnostic'], isA<Map>());
      expect(writes, 0);
      expect(jsonEncode(backend.values), before);
      expect(() => jsonEncode(exported), returnsNormally);
    },
  );

  test(
    'stalled Firestore logger remains exportable with durable original failure',
    () async {
      final backend = MemoryLogs();
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      var writes = 0;
      final service = SyncErrorLogService(
        backend: backend,
        online: () => true,
        uploadTimeout: const Duration(milliseconds: 10),
        metadata: (owner) async => {'user_id': owner},
        writer: (_, _) {
          writes++;
          return gate.future;
        },
      );
      addTearDown(service.dispose);
      await capture(service);
      await service.start();
      await waitFor(() => writes == 1);
      final exported = await service.localDiagnosticReport('13');
      expect(exported['diagnostic_upload']['in_flight'], true);
      expect(exported['diagnostic_upload']['caller_wait_expired'], true);
      expect((exported['reports'] as List).single['dirty'], true);
      expect(
        jsonDecode(reports(backend).single)['action_at'],
        '2026-09-22T01:00:00Z',
      );
      await service.flush();
      expect(
        writes,
        1,
        reason: 'Copy/retry must not duplicate an unfinished SDK write',
      );
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    },
  );
}
