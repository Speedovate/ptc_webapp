import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/sync_error_log_service.dart';
import 'sync_error_log_service_test.dart'
    show MemoryLogs, capture, reports, waitFor;

class _SlowIndexLogs extends MemoryLogs {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool delayIndex = false;
  @override
  Future<List<String>> readStringList(String key) async {
    if (delayIndex && key == 'sync_error_log_v2_index_0') {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return super.readStringList(key);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('active errors upload before a stalled resolved-log deletion', () async {
    final backend = MemoryLogs();
    final deleteGate = Completer<void>();
    final operations = <String>[];
    final service = SyncErrorLogService(
      backend: backend,
      online: () => true,
      uploadTimeout: const Duration(milliseconds: 30),
      metadata: (owner) async => {'user_id': owner},
      writer: (_, data) async {
        operations.add('write:${data['queue_entry_id']}');
      },
      deleter: (_) {
        operations.add('delete');
        return deleteGate.future;
      },
    );
    addTearDown(service.dispose);
    addTearDown(() {
      if (!deleteGate.isCompleted) deleteGate.complete();
    });
    await capture(service, entry: 'old_completed');
    await service.resolveQueueEntries('offline_media_sync_queue_v1::13', {
      'old_completed',
    });
    await capture(service, entry: 'still_failed');
    await service.start();
    await waitFor(() => operations.contains('delete'));
    expect(operations, ['write:still_failed', 'delete']);
    final report = await service.localDiagnosticReport('13');
    expect(
      report['diagnostic_upload']['phase'],
      'delete_resolved_remote_report',
    );
    final active = (report['reports'] as List).singleWhere(
      (row) => row['queue_entry_id'] == 'still_failed',
    );
    expect(active['dirty'], false);
    expect(active['action_at'], '2026-09-22T01:00:00Z');
    deleteGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test(
    'slow local index scan continues past capture deadline and uploads once',
    () async {
      final backend = _SlowIndexLogs();
      var writes = 0;
      final service = SyncErrorLogService(
        backend: backend,
        online: () => true,
        localPersistenceTimeout: const Duration(milliseconds: 10),
        uploadTimeout: const Duration(milliseconds: 30),
        metadata: (owner) async => {'user_id': owner},
        writer: (_, _) async {
          writes++;
        },
      );
      addTearDown(service.dispose);
      addTearDown(() {
        if (!backend.release.isCompleted) backend.release.complete();
      });
      await capture(service);
      backend.delayIndex = true;
      await service.start();
      await backend.entered.future;
      final blocked = await service.localDiagnosticReport('13');
      expect(blocked['reports_complete'], false);
      expect(blocked['diagnostic_upload']['phase'], 'read_local_outbox');
      expect(blocked['diagnostic_upload']['in_flight'], true);
      expect(blocked['diagnostic_upload']['last_error'], isNull);
      expect(blocked['diagnostic_upload']['caller_wait_expired'], true);
      expect(writes, 0);
      expect(jsonDecode(reports(backend).single)['dirty'], true);
      backend.release.complete();
      await waitFor(
        () =>
            writes == 1 &&
            jsonDecode(reports(backend).single)['dirty'] == false,
      );
      await service.flush();
      expect(writes, 1);
      expect(
        jsonDecode(reports(backend).single)['action_at'],
        '2026-09-22T01:00:00Z',
      );
    },
  );

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
