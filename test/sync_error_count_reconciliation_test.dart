import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/sync_error_log_service.dart';
import 'sync_error_log_service_test.dart' show MemoryLogs, waitFor;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    '18 reports become 11 attention and one waiting without changing queue',
    () async {
      final disk = MemoryLogs();
      const scope = 'offline_mutation_queue_v1::signed_out';
      Map<String, dynamic> action(int i) => {
        'id': 'a$i',
        'kind': 'collectionDocumentUpsert',
        'collection_key': 'bookings',
        'target_id': '152',
        'is_blocked': true,
        'last_error': 'conflict',
        'retry_count': 1,
      };
      disk.values[scope] = List.generate(18, (i) => jsonEncode(action(i)));
      final remote = <String, Map<String, dynamic>>{};
      var deletes = 0;
      final service = SyncErrorLogService(
        backend: disk,
        online: () => true,
        metadata: (_) async => {},
        writer: (id, data) async {
          remote[id] = data;
        },
        deleter: (id) async {
          remote.remove(id);
          deletes++;
        },
      );
      await service.start();
      expect(remote.length, 18);
      final pending = List.generate(
        12,
        (i) => jsonEncode(
          i == 11
              ? {...action(i), 'is_blocked': false, 'last_error': null}
              : action(i),
        ),
      );
      disk.values[scope] = pending;
      service.observeQueue(
        'offline_mutation_queue_service.dart',
        pending: 12,
        failed: 11,
        syncing: true,
        processed: 0,
        total: 12,
      );
      await service.refreshQueueDiagnostics();
      await service.flush();
      expect(deletes, 0);
      expect(disk.values[scope], pending);
      service.observeQueue(
        'offline_mutation_queue_service.dart',
        pending: 12,
        failed: 11,
        syncing: false,
        processed: 0,
        total: 12,
      );
      await service.refreshQueueDiagnostics();
      await service.flush();
      await waitFor(
        () =>
            remote.values
                .where((r) => r['attention_required'] == true)
                .length ==
            11,
      );
      expect(deletes, 6);
      expect(disk.values[scope], pending);
      await service.refreshQueueDiagnostics();
      await service.flush();
      expect(deletes, 6);
      await service.capture(
        source: 'offline_mutation_queue_service.dart',
        operation: 'collectionDocumentUpsert',
        entryId: 'a17',
        target: 'bookings/152',
        owner: 'signed_out',
        error: 'late conflict',
        stack: '',
        attempt: 2,
      );
      await service.flush();
      expect(
        remote.values.where((r) => r['attention_required'] == true).length,
        11,
      );
      expect(deletes, 6);
      service.dispose();
    },
  );
  test('malformed snapshot never authorizes deletion', () async {
    final disk = MemoryLogs();
    const scope = 'offline_mutation_queue_v1::signed_out';
    disk.values[scope] = [
      jsonEncode({'id': 'a', 'is_blocked': true, 'last_error': 'conflict'}),
    ];
    var deletes = 0;
    final service = SyncErrorLogService(
      backend: disk,
      online: () => true,
      metadata: (_) async => {},
      writer: (_, _) async {},
      deleter: (_) async {
        deletes++;
      },
    );
    await service.start();
    disk.values[scope] = ['broken-json'];
    await service.refreshQueueDiagnostics();
    await service.flush();
    expect(deletes, 0);
    expect(disk.values[scope], ['broken-json']);
    service.dispose();
  });
}
