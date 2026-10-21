import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/sync_error_log_service.dart';
import 'package:webapp/services/sync_diagnostic_outbox.dart';
import 'sync_error_log_service_test.dart' show MemoryLogs, reports;
import 'booking254_pending_preview_recovery_test.dart' show Photos;
import 'support/merge_aware_firestore.dart';

const _photoScope = 'booking_pending_upload_queue_v1::8';
const _activityScope = 'offline_mutation_queue_v1::8';
const _failedAt = '2026-10-21T05:27:38.200Z';
const _photos = [
  (
    '1791960701949000',
    'booking_upload_1791960707132000_409d279a',
    '1000142075.jpg',
    72531,
    '2026-10-14T06:51:46.988Z',
  ),
  (
    '1791957845495000',
    'booking_upload_1791957854281000_4a51fd83',
    '1000142073.jpg',
    200100,
    '2026-10-14T06:04:10.527Z',
  ),
  (
    '1791929171081000',
    'booking_upload_1791929179742000_bb9462bf',
    '1000142021.jpg',
    238479,
    '2026-10-13T22:06:16.112Z',
  ),
];

class _Db extends MergeAwareFirestore {
  bool unavailable = false;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> action, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    if (unavailable) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Connection failed.',
      );
    }
    return super.runTransaction(
      action,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.writeString('paltranco_current_user_id', '8');
    await auth.writeStringList('paltranco_known_session_user_ids', ['8']);
  });
  for (final (stamp, id, name, size, actionAt) in _photos) {
    final bookingId = 'offline_booking_8_9_1_$stamp';
    final row = <String, dynamic>{
      'id': id,
      'booking_id': bookingId,
      'status_key': 'book__$stamp',
      'field_key': 'waybill_photo',
      'file_name': name,
      'size': size,
      'mime_type': 'image/jpeg',
      'bytes_base64': base64Encode(Uint8List(size)),
      'created_at': actionAt,
      'wait_reason': 'temporary_booking_id',
      'wait_count': 126,
      'retry_count': 14,
      'last_error': 'Failed to get document because the client is offline.',
      'error_diagnostics':
          'Failed at (UTC): $_failedAt\nOriginal error evidence',
    };
    test(
      '$name restored after +55 reopens its log without losing original evidence',
      () async {
        final disk = MemoryLogs();
        var online = false;
        final remote = <String, Map<String, dynamic>>{};
        SyncErrorLogService logger() => SyncErrorLogService(
          backend: disk,
          online: () => online,
          metadata: (_) async => {'user_id': '8'},
          writer: (id, data) async => remote[id] = Map.of(data),
          deleter: (id) async => remote.remove(id),
        );
        final before = logger();
        await before.start();
        await before.capture(
          source: 'booking_offline_upload_queue_service.dart',
          operation: 'bookingPhotoUpload',
          entryId: id,
          target: 'bookings/$bookingId',
          error: row['last_error'],
          stack: row['error_diagnostics'],
          attempt: 14,
          owner: '8',
          actionAt: actionAt,
          failedAt: _failedAt,
        );
        online = true;
        await before.flush();
        await before.resolveQueueEntries(_photoScope, {id});
        await before.flush();
        expect(remote, isEmpty);
        expect(
          await SyncDiagnosticOutbox(disk).isResolved(_photoScope, id),
          true,
        );
        before.dispose();
        disk.values[_photoScope] = [jsonEncode(row)];
        final reopened = logger();
        addTearDown(reopened.dispose);
        await reopened.start();
        await reopened.flush();
        final saved = remote.values.single;
        expect(saved['queue_entry_id'], id);
        expect(saved['attention_required'], true);
        expect(saved['resolved_at'], isNull);
        expect(saved['previous_resolution_at'], isNotNull);
        expect(saved['first_failed_at'], _failedAt);
        expect(saved['action_at'], actionAt);
        expect(
          saved['details']['queue_snapshot']['photo_upload']['local_bytes_present'],
          true,
        );
        expect(jsonDecode(disk.values[_photoScope]!.single), row);
        expect(
          await SyncDiagnosticOutbox(disk).isResolved(_photoScope, id),
          false,
        );
      },
    );

    test(
      '$name foreground retry finds a newly committed booking during lookup backoff',
      () async {
        final db = _Db();
        final disk = MemoryLogs();
        final mutations = OfflineMutationQueueService(
          backend: disk,
          firestore: db,
          isOnline: () => false,
        );
        addTearDown(mutations.dispose);
        final photos = Photos();
        final queue = BookingOfflineUploadQueueService(
          backend: disk,
          firestore: db,
          mutationQueue: mutations,
          photoStorageService: photos,
          flushMutations: () async {},
          cachedBookingReader: (_) async => null,
        );
        await queue.initialize();
        await Future<void>.delayed(Duration.zero);
        disk.values[_photoScope] = [jsonEncode(row)];
        // Seed a completed missing lookup. A normal background pass must respect
        // the gate; a foreground retry can check again without overlapping reads.
        expect(
          await BookingIdResolver(firestore: db).resolve(bookingId),
          isNull,
        );
        final canonical = <String, dynamic>{
          'id': '700',
          'submission_key': bookingId.substring('offline_'.length),
          'client_id': '9',
          'client_status': 'assigned',
          'driver_id': '17',
          'created_at': actionAt,
          'updated_at': '2026-10-21T05:30:00Z',
          'status_outputs': {
            'book__$stamp': {
              'status_key': 'book',
              'submitted_by': '8',
              'submitted_at': actionAt,
              'fields': {
                'waybill_photo': {
                  'pending_upload': true,
                  'pending_upload_id': id,
                  'name': name,
                  'size': size,
                  'mime_type': 'image/jpeg',
                },
              },
            },
          },
        };
        await db.collection('bookings').doc('700').set(canonical);
        await queue.flushPendingUploads(background: true);
        expect(disk.values[_photoScope], hasLength(1));
        expect(photos.uploads, 0);
        expect(
          jsonDecode(disk.values[_photoScope]!.single)['error_diagnostics'],
          contains('"gate_reason":"backoff"'),
        );
        await queue.flushPendingUploads();
        expect(disk.values[_photoScope], isEmpty);
        expect(photos.uploads, 1);
        final saved = (await db.collection('bookings').doc('700').get())
            .data()!;
        for (final field in [
          'client_status',
          'driver_id',
          'created_at',
          'updated_at',
        ]) {
          expect(saved[field], canonical[field]);
        }
        expect(
          saved['status_outputs']['book__$stamp']['submitted_at'],
          actionAt,
        );
        await queue.flushPendingUploads();
        expect(photos.uploads, 1);
      },
    );
  }

  test(
    'restored action reopens even when its old diagnostic receipt was pruned',
    () async {
      final disk = MemoryLogs();
      var online = false;
      final remote = <String, Map<String, dynamic>>{};
      final logger = SyncErrorLogService(
        backend: disk,
        online: () => online,
        metadata: (_) async => {'user_id': '8'},
        writer: (id, data) async => remote[id] = Map.of(data),
      );
      addTearDown(logger.dispose);
      await logger.start();
      const id = 'pruned_photo_receipt';
      await logger.resolveQueueEntries(_photoScope, {id});
      expect(reports(disk), isEmpty);
      expect(
        await SyncDiagnosticOutbox(disk).isResolved(_photoScope, id),
        true,
      );
      const actionAt = '2026-10-14T06:51:46.988Z';
      final row = {
        'id': id,
        'booking_id': 'offline_booking_8_9_1_1791960701949000',
        'status_key': 'book__1791960701949000',
        'field_key': 'waybill_photo',
        'created_at': actionAt,
        'retry_count': 11,
        'size': 3,
        'bytes_base64': 'AQID',
        'last_error': 'Client is offline',
        'error_diagnostics': 'Failed at (UTC): $_failedAt\nOriginal evidence',
      };
      disk.values[_photoScope] = [jsonEncode(row)];
      await logger.refreshQueueDiagnostics();
      online = true;
      await logger.flush();
      expect(remote.values.single['queue_entry_id'], id);
      expect(remote.values.single['first_failed_at'], _failedAt);
      expect(remote.values.single['action_at'], actionAt);
      expect(remote.values.single['attention_required'], true);
      expect(jsonDecode(disk.values[_photoScope]!.single), row);
    },
  );

  test(
    'reported activity retries stay durable, become visible, then sync original timestamp',
    () async {
      final db = _Db();
      final disk = MemoryLogs();
      var online = false;
      var now = DateTime.utc(2026, 10, 21, 5, 28);
      const actionAt = '2026-10-21T05:26:32.428Z';
      const id = 'user_activity_1792560392438000_4b9a2450';
      final queue = OfflineMutationQueueService(
        backend: disk,
        firestore: db,
        isOnline: () => online,
      );
      addTearDown(queue.dispose);
      await queue.initialize();
      await db.collection('users').doc('8').set({
        'id': '8',
        'updated_at': '2026-10-20T00:00:00Z',
      });
      disk.values[_activityScope] = [
        jsonEncode({
          'id': id,
          'kind': 'userActivity',
          'collection_key': 'users',
          'target_id': '8',
          'payload': {'updated_at': actionAt},
          'created_at': actionAt,
          'retry_count': 6,
          'is_blocked': false,
          'last_error': 'Connection failed.',
        }),
      ];
      db.unavailable = true;
      online = true;
      await queue.flushPendingMutations();
      final pending = jsonDecode(disk.values[_activityScope]!.single);
      expect(pending['is_blocked'], false);
      expect(pending['payload'], {'updated_at': actionAt});
      expect(pending['created_at'], actionAt);
      expect(pending['retry_count'], 7);
      final remote = <String, Map<String, dynamic>>{};
      final logger = SyncErrorLogService(
        backend: disk,
        online: () => online,
        now: () => now,
        metadata: (_) async => {'user_id': '8'},
        writer: (id, data) async {
          if (db.unavailable) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'unavailable',
            );
          }
          remote[id] = Map.of(data);
        },
        deleter: (id) async => remote.remove(id),
      );
      addTearDown(logger.dispose);
      await logger.start();
      await logger.flush();
      expect(remote, isEmpty);
      expect(jsonDecode(reports(disk).single)['dirty'], true);
      expect(jsonDecode(reports(disk).single)['attention_required'], true);
      db.unavailable = false;
      now = now.add(const Duration(minutes: 2));
      await logger.flush();
      expect(remote.values.single['attention_required'], true);
      expect(
        remote
            .values
            .single['firebase_console_diagnostic']['evidence']['firebase_code'],
        'unavailable',
      );
      await queue.flushPendingMutations();
      expect(disk.values[_activityScope], isEmpty);
      expect(
        (await db.collection('users').doc('8').get()).data()!['updated_at'],
        actionAt,
      );
      await logger.resolveQueueEntries(_activityScope, {id});
      await logger.flush();
      expect(remote, isEmpty);
    },
  );

  test(
    'same-attempt evidence arriving during upload is not falsely acknowledged',
    () async {
      final disk = MemoryLogs();
      var online = false;
      final started = Completer<void>(), release = Completer<void>();
      final sent = <Map<String, dynamic>>[];
      final logger = SyncErrorLogService(
        backend: disk,
        online: () => online,
        metadata: (_) async => {'user_id': '8'},
        writer: (_, row) async {
          sent.add(Map.of(row));
          if (sent.length == 1) {
            started.complete();
            await release.future;
          }
        },
      );
      addTearDown(logger.dispose);
      await logger.start();
      Future<void> capture(String stage) => logger.capture(
        source: 'booking_offline_upload_queue_service.dart',
        operation: 'bookingPhotoUpload',
        owner: '8',
        entryId: 'photo_race',
        target: 'bookings/pending',
        attempt: 11,
        error: 'Waiting for identity',
        stack: '',
        failedAt: _failedAt,
        details: {
          'identity_lookup': {'gate_reason': stage},
        },
      );
      await capture('shared_in_flight');
      online = true;
      final flushing = logger.flush();
      await started.future;
      await capture('backoff');
      release.complete();
      await flushing;
      expect(sent, hasLength(2));
      expect(sent.last['details']['identity_lookup']['gate_reason'], 'backoff');
      expect(sent.last['occurrences'], 1);
      expect(jsonDecode(reports(disk).single)['dirty'], false);
    },
  );
}
