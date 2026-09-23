import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/sync_error_log_service.dart';
import 'package:webapp/services/sync_diagnostic_outbox.dart';

class MemoryLogs implements BookingStorageBackend {
  final values = <String, List<String>>{};
  @override
  Future<void> initialize() async {}
  @override
  Future<List<String>> readStringList(String key) async =>
      List.of(values[key] ?? []);
  @override
  Future<void> writeStringList(String key, List<String> v) async {
    values[key] = List.of(v);
  }
}

class StalledLogs extends MemoryLogs {
  final gate = Completer<void>();
  bool stall = true;
  @override
  Future<void> writeStringList(String key, List<String> value) async {
    if (stall && key.startsWith('${SyncDiagnosticOutbox.prefix}_row_')) {
      stall = false;
      await gate.future;
    }
    await super.writeStringList(key, value);
  }
}

Future<void> capture(
  SyncErrorLogService service, {
  int attempt = 1,
  String entry = 'queue1',
  String error = 'permission-denied',
}) => service.capture(
  source: 'offline_media_sync_service.dart',
  operation: 'supportMessage',
  entryId: entry,
  target: 'threads/thread1',
  owner: '13',
  actionAt: '2026-09-22T01:00:00Z',
  failedAt: '2026-09-22T02:00:00Z',
  error: error,
  stack: 'package:webapp/services/offline_media_sync_service.dart:600',
  attempt: attempt,
  details: {'field_key': 'photo', 'firebase_code': 'permission-denied'},
);
List<String> reports(MemoryLogs backend) => [
  for (final entry in backend.values.entries)
    if (entry.key.startsWith('${SyncDiagnosticOutbox.prefix}_row_'))
      ...entry.value,
];
Future<void> waitFor(bool Function() ready) async {
  final until = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(until)) {
      throw StateError('Condition did not complete');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'queued, retrying and blocked actions cannot be resolved or deleted',
    () async {
      final disk = MemoryLogs();
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
      await capture(service);
      await service.flush();
      for (final state in ['syncing', 'retrying', 'blocked']) {
        disk.values['offline_media_sync_queue_v1::13'] = [
          jsonEncode({'id': 'queue1', 'state': state, 'last_error': 'failure'}),
        ];
        await service.resolveQueueEntries('offline_media_sync_queue_v1::13', {
          'queue1',
        });
        await service.flush();
        expect(deletes, 0);
        expect(jsonDecode(reports(disk).single)['resolved_at'], isNull);
      }
      // The successful replay has durably removed its action before cleanup.
      disk.values['offline_media_sync_queue_v1::13'] = [];
      await service.resolveQueueEntries('offline_media_sync_queue_v1::13', {
        'queue1',
      });
      await service.flush();
      expect(deletes, 1);
    },
  );

  test(
    'resolution deletes only this device and suppresses late callbacks after restart',
    () async {
      final remote = <String, Map<String, dynamic>>{};
      final a = MemoryLogs(), b = MemoryLogs();
      SyncErrorLogService create(MemoryLogs disk) => SyncErrorLogService(
        backend: disk,
        online: () => true,
        metadata: (_) async => {},
        writer: (id, row) async => remote[id] = Map.of(row),
        deleter: (id) async {
          remote.remove(id);
        },
      );
      final first = create(a), other = create(b);
      await first.start();
      await other.start();
      await capture(first);
      await first.flush();
      await capture(other);
      await other.flush();
      expect(remote.length, 2);
      final otherId = jsonDecode(reports(b).single)['id'];
      await first.resolveQueueEntries('offline_media_sync_queue_v1::13', {
        'queue1',
      });
      await first.flush();
      expect(remote.keys, [otherId]);
      final restarted = create(a);
      await restarted.start();
      await capture(restarted, attempt: 99);
      await restarted.flush();
      expect(remote.keys, [otherId]);
      await restarted.resolveQueueEntries('offline_media_sync_queue_v1::13', {
        'queue1',
      });
      await restarted.flush();
      expect(remote.keys, [otherId]);
    },
  );

  test(
    'shared tabs order a late upload before deletion without re-creating the log',
    () async {
      final disk = MemoryLogs();
      final gate = Completer<void>();
      final entered = Completer<void>();
      final remote = <String, Map<String, dynamic>>{};
      var writes = 0, deletes = 0;
      SyncErrorLogService create() => SyncErrorLogService(
        backend: disk,
        online: () => true,
        metadata: (_) async => {},
        uploadTimeout: const Duration(milliseconds: 20),
        writer: (id, row) async {
          writes++;
          if (!entered.isCompleted) entered.complete();
          await gate.future;
          remote[id] = row;
        },
        deleter: (id) async {
          deletes++;
          remote.remove(id);
        },
      );
      final a = create(), b = create();
      await a.start();
      await b.start();
      await capture(a);
      await entered.future;
      await a.flush();
      await b.resolveQueueEntries('offline_media_sync_queue_v1::13', {
        'queue1',
      });
      await b.flush();
      await capture(b, attempt: 2);
      expect(writes, 1);
      gate.complete();
      await a.flush();
      await b.flush();
      await waitFor(() => remote.isEmpty && deletes == 1);
      expect(remote, isEmpty);
      expect(deletes, 1);
      await capture(a, attempt: 3);
      await a.flush();
      expect(writes, 1);
      expect(remote, isEmpty);
    },
  );

  test(
    'legacy reports migrate without changing IDs or original failure times',
    () async {
      final backend = MemoryLogs();
      final first = SyncErrorLogService(
        backend: backend,
        online: () => false,
        metadata: (_) async => {},
      );
      await capture(first);
      final legacy = reports(backend).single;
      backend.values.clear();
      backend.values[SyncErrorLogService.storageKey] = [legacy];
      final remote = <Map<String, dynamic>>[];
      final restored = SyncErrorLogService(
        backend: backend,
        online: () => true,
        metadata: (_) async => {},
        writer: (_, row) async => remote.add(row),
      );
      await restored.start();
      final old = jsonDecode(legacy);
      expect(remote.single['id'], old['id']);
      expect(remote.single['action_at'], old['action_at']);
      expect(remote.single['first_failed_at'], old['first_failed_at']);
      expect(backend.values[SyncErrorLogService.storageKey], isEmpty);
    },
  );

  test(
    'offline errors survive restart, upload with context and remain remotely after queue removal',
    () async {
      final backend = MemoryLogs();
      final remote = <String, Map<String, dynamic>>{};
      var online = false;
      SyncErrorLogService service() => SyncErrorLogService(
        backend: backend,
        online: () => online,
        writer: (id, data) async {
          remote[id] = data;
        },
        metadata: (owner) async => {
          'user_id': owner,
          'role': 'driver',
          'app_version': '1.0.1',
          'build_number': '9',
        },
      );
      await capture(service());
      expect(remote, isEmpty);
      final restored = service();
      online = true;
      await restored.start();
      expect(remote.length, 1);
      final log = remote.values.single;
      expect(log['role'], 'driver');
      expect(log['action_at'], '2026-09-22T01:00:00Z');
      expect(log['first_failed_at'], '2026-09-22T02:00:00Z');
      expect(
        log['stack_trace'],
        contains('offline_media_sync_service.dart:600'),
      );
      expect(jsonDecode(log['copy_report'])['error'], 'permission-denied');
      await restored.flush();
      expect(remote.length, 1);
      expect(jsonDecode(reports(backend).single)['dirty'], false);
    },
  );
  test(
    'duplicate callbacks and restart do not create duplicate writes; retries coalesce',
    () async {
      final backend = MemoryLogs();
      var time = DateTime.utc(2026, 9, 22);
      final writes = <Map<String, dynamic>>[];
      final service = SyncErrorLogService(
        backend: backend,
        online: () => true,
        now: () => time,
        writer: (_, data) async {
          writes.add(data);
        },
        metadata: (_) async => {},
      );
      await service.start();
      await capture(service);
      await service.flush();
      await capture(service);
      await capture(service, attempt: 2);
      await service.flush();
      expect(writes.length, 1);
      time = time.add(const Duration(minutes: 5));
      await service.flush();
      expect(writes.length, 2);
      expect(writes.last['occurrences'], 2);
      expect(writes.last['id'], writes.first['id']);
    },
  );
  test(
    'logger failures preserve local logs and enforce cooldown without recursion',
    () async {
      final backend = MemoryLogs();
      var time = DateTime.utc(2026, 9, 22);
      var attempts = 0;
      var fail = true;
      final service = SyncErrorLogService(
        backend: backend,
        online: () => true,
        now: () => time,
        metadata: (_) async => {},
        writer: (_, _) async {
          attempts++;
          if (fail) throw StateError('denied');
        },
      );
      await service.start();
      await capture(service);
      await service.flush();
      for (var i = 0; i < 10; i++) {
        await service.flush();
      }
      expect(attempts, 1);
      expect(jsonDecode(reports(backend).single)['dirty'], true);
      time = time.add(const Duration(minutes: 1));
      fail = false;
      await service.flush();
      expect(attempts, 2);
    },
  );
  test(
    'single flight drains more than one batch and captures entries arriving during writes',
    () async {
      final backend = MemoryLogs();
      final remote = <String>{};
      final gate = Completer<void>();
      final service = SyncErrorLogService(
        backend: backend,
        online: () => true,
        metadata: (_) async => {},
        writer: (id, _) async {
          await gate.future;
          remote.add(id);
        },
      );
      await service.start();
      await capture(service, entry: 'queue0');
      final flushing = service.flush();
      for (var i = 1; i < 25; i++) {
        await capture(service, entry: 'queue$i');
      }
      gate.complete();
      await flushing;
      await service.flush();
      expect(remote.length, 25);
    },
  );
  test(
    'credentials redacted and diagnostics have explicit size-limit markers',
    () async {
      final backend = MemoryLogs();
      final service = SyncErrorLogService(
        backend: backend,
        online: () => false,
        metadata: (_) async => {},
      );
      await capture(
        service,
        error: 'token=abc password: hidden "secret":"xyz" Bearer JWT',
      );
      final log = jsonDecode(reports(backend).single);
      expect(log['error'], isNot(contains('abc')));
      expect(log['error'], isNot(contains('hidden')));
      expect(log['error'], isNot(contains('xyz')));
      expect(log['error'], isNot(contains('JWT')));
      await capture(service, entry: 'large', error: 'x' * 17000);
      final last = jsonDecode(reports(backend).last);
      expect(last['diagnostic_truncated'], true);
    },
  );
  test(
    'backfills existing blocked actions without altering the queue',
    () async {
      final backend = MemoryLogs();
      final queue = jsonEncode({
        'id': 'legacy',
        'kind': 'bookingUpdate',
        'target_id': '98',
        'created_at': '2026-09-19T10:00:00Z',
        'retry_count': 3,
        'is_blocked': true,
        'last_error': 'Sync conflict',
        'error_diagnostics':
            'Failed at (UTC): 2026-09-20T00:00:00Z\nStack trace: original',
      });
      backend.values['offline_mutation_queue_v1::signed_out'] = [queue];
      final remote = <Map<String, dynamic>>[];
      final service = SyncErrorLogService(
        backend: backend,
        online: () => true,
        metadata: (_) async => {},
        writer: (_, d) async {
          remote.add(d);
        },
      );
      await service.start();
      expect(remote.single['kind'], 'persisted_queue_failure');
      expect(remote.single['first_failed_at'], '2026-09-20T00:00:00Z');
      expect(backend.values['offline_mutation_queue_v1::signed_out'], [queue]);
    },
  );
  test(
    'foreground reports preserve source and sanitize nested context',
    () async {
      final backend = MemoryLogs();
      final service = SyncErrorLogService(
        backend: backend,
        online: () => false,
        metadata: (_) async => {},
      );
      await service.report(
        const FormatException('invalid document'),
        StackTrace.fromString('save.dart:42'),
        source: 'save.dart',
        operation: 'save booking',
        target: 'bookings/7',
        details: {
          'nested': {'password': 'private', 'value': 'token=abc'},
        },
      );
      final row = jsonDecode(reports(backend).single);
      expect(row['stack_trace'], 'save.dart:42');
      expect(row['details']['suspected_layer'], 'data_structure');
      expect(row['details']['nested']['password'], '[REDACTED]');
      expect(jsonEncode(row), isNot(contains('abc')));
    },
  );

  test('stalls restart observation on reconnect and report recovery', () async {
    final backend = MemoryLogs();
    var time = DateTime.utc(2026, 9, 23);
    var online = false;
    final service = SyncErrorLogService(
      backend: backend,
      online: () => online,
      now: () => time,
      metadata: (_) async => {},
    );
    void observe(int pending, bool syncing) => service.observeQueue(
      'mutation',
      pending: pending,
      failed: 0,
      syncing: syncing,
      processed: 0,
      total: pending,
    );
    List<dynamic> rows() => reports(backend).map(jsonDecode).toList();
    observe(2, false);
    time = time.add(const Duration(minutes: 3));
    await service.checkForStalls();
    expect(rows(), isEmpty);
    online = true;
    service.observeNetwork(true);
    await service.checkForStalls();
    expect(rows().where((r) => r['kind'] == 'queue_stalled'), isEmpty);
    time = time.add(const Duration(seconds: 91));
    observe(2, true);
    await service.checkForStalls();
    expect(rows().where((r) => r['kind'] == 'queue_stalled'), hasLength(1));
    await service.checkForStalls();
    expect(rows().where((r) => r['kind'] == 'queue_stalled'), hasLength(1));
    observe(0, false);
    // Await capture serialization after the unawaited recovery notification.
    await service.report(
      StateError('barrier'),
      StackTrace.empty,
      source: 'test',
      operation: 'barrier',
    );
    expect(rows().where((r) => r['kind'] == 'queue_recovered'), hasLength(1));
    final stalled = rows().firstWhere((r) => r['kind'] == 'queue_stalled');
    expect(stalled['details']['no_progress_seconds'], 91);
    expect(stalled['details']['recent_network_transitions'], isNotEmpty);
  });

  test('queue progress resets stall deadline', () async {
    final backend = MemoryLogs();
    var time = DateTime.utc(2026, 9, 23);
    final service = SyncErrorLogService(
      backend: backend,
      online: () => true,
      now: () => time,
      metadata: (_) async => {},
    );
    void observe(int pending, int processed) => service.observeQueue(
      'mutation',
      pending: pending,
      failed: 0,
      syncing: true,
      processed: processed,
      total: 3,
    );
    observe(3, 0);
    time = time.add(const Duration(seconds: 80));
    observe(2, 1);
    time = time.add(const Duration(seconds: 80));
    await service.checkForStalls();
    expect(reports(backend), isEmpty);
    time = time.add(const Duration(seconds: 11));
    await service.checkForStalls();
    expect(reports(backend), hasLength(1));
  });

  test('timed out diagnostic upload keeps a single actual writer', () async {
    final backend = MemoryLogs();
    var time = DateTime.utc(2026, 9, 23);
    var hung = true;
    var writes = 0;
    final gate = Completer<void>();
    final service = SyncErrorLogService(
      backend: backend,
      online: () => true,
      now: () => time,
      metadata: (_) async => {},
      uploadTimeout: const Duration(milliseconds: 20),
      writer: (_, _) async {
        writes++;
        if (hung) await gate.future;
      },
    );
    await service.start();
    await capture(service);
    await waitFor(() => writes == 1);
    await service.flush();
    expect(jsonDecode(reports(backend).single)['dirty'], true);
    time = time.add(const Duration(minutes: 1));
    hung = false;
    await service.flush();
    expect(writes, 1);
    expect(jsonDecode(reports(backend).single)['dirty'], true);
    gate.complete();
    await service.flush();
    await waitFor(() => jsonDecode(reports(backend).single)['dirty'] == false);
    expect(writes, 1);
    expect(jsonDecode(reports(backend).single)['dirty'], false);
  });
  test(
    'stalled persistence bounds callers and preserves serialized late writes',
    () async {
      final backend = StalledLogs();
      final service = SyncErrorLogService(
        backend: backend,
        online: () => false,
        metadata: (_) async => {},
        localPersistenceTimeout: const Duration(milliseconds: 20),
      );
      await capture(
        service,
        entry: 'first',
      ).timeout(const Duration(seconds: 1));
      await capture(
        service,
        entry: 'second',
      ).timeout(const Duration(seconds: 1));
      backend.gate.complete();
      await capture(service, entry: 'third');
      final rows = reports(backend).map(jsonDecode).toList();
      expect(rows.map((r) => r['queue_entry_id']).toSet(), {
        'first',
        'second',
        'third',
      });
    },
  );
  test(
    'corrupt outbox rows are quarantined and healthy/new reports upload',
    () async {
      final backend = MemoryLogs();
      var online = false;
      final remote = <Map<String, dynamic>>[];
      final service = SyncErrorLogService(
        backend: backend,
        online: () => online,
        metadata: (_) async => {},
        writer: (_, data) async {
          remote.add(data);
        },
      );
      backend.values[SyncErrorLogService.storageKey] = [
        '{broken-json',
        '{"id":"incomplete"}',
      ];
      await capture(service, entry: 'healthy');
      await capture(service, entry: 'new');
      online = true;
      await service.start();
      expect(remote.map((r) => r['queue_entry_id']).toSet(), {
        'healthy',
        'new',
      });
      expect(
        backend.values['${SyncErrorLogService.storageKey}_quarantine'],
        hasLength(2),
      );
    },
  );
}
