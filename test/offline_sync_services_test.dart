import 'booking_status_continuation_test.dart' as fixture;
import 'dart:convert';
import 'support/merge_aware_firestore.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/services/support_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Browser AuthStorage uses localStorage, not the SharedPreferences mock.
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.remove('paltranco_current_user_id');
    await auth.remove('paltranco_known_session_user_ids');
  });

  test(
    'booking conflict retains exact versions and changed fields without overwriting',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = _MemoryBookingStorageBackend();
      const base = '2026-09-22T00:00:00Z';
      const remote = '2026-09-22T01:00:00Z';
      const pending = '2026-09-22T02:00:00Z';
      final server = {
        'id': '121',
        'amount': 900,
        'updated_at': remote,
        'client_status': 'Delivered',
      };
      await db.collection('bookings').doc('121').set(server);
      const key = 'offline_mutation_queue_v1::signed_out';
      await backend.writeStringList(key, [
        jsonEncode({
          'id': 'conflict-context',
          'kind': 'collectionDocumentUpsert',
          'target_id': '121',
          'collection_key': 'bookings',
          'base_updated_at': base,
          'created_at': pending,
          'retry_count': 0,
          'is_blocked': false,
          'payload': {
            'id': '121',
            'amount': 1000,
            'updated_at': pending,
            'client_status': 'Pending',
          },
        }),
      ]);
      final service = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      await service.flushPendingMutations();
      final saved =
          jsonDecode((await backend.readStringList(key)).single) as Map;
      expect(saved['is_blocked'], true);
      expect(saved['created_at'], pending);
      final diagnostics = saved['error_diagnostics'] as String;
      expect(diagnostics, contains('"base_updated_at":"$base"'));
      expect(diagnostics, contains('"server_updated_at":"$remote"'));
      expect(diagnostics, contains('"pending_updated_at":"$pending"'));
      expect(diagnostics, contains('"differing_fields"'));
      expect(diagnostics, contains('"pending_payload"'));
      expect(diagnostics, contains('"server_document"'));
      expect(diagnostics, contains('"amount":1000'));
      expect(diagnostics, contains('"amount":900'));
      expect(diagnostics, contains('"amount"'));
      expect((await db.collection('bookings').doc('121').get()).data(), server);
    },
  );

  for (final sameContents in [true, false]) {
    test(
      'blocked booking recovery preserves server; identical=$sameContents',
      () async {
        final db = FakeFirebaseFirestore();
        final backend = _MemoryBookingStorageBackend();
        const key = 'offline_mutation_queue_v1::signed_out';
        final server = {
          'id': '121',
          'amount': 900,
          'updated_at': '2026-09-23T03:00:00Z',
        };
        await db.collection('bookings').doc('121').set(server);
        await backend.writeStringList(key, [
          jsonEncode({
            'id': 'legacy-conflict',
            'kind': 'collectionDocumentUpsert',
            'collection_key': 'bookings',
            'target_id': '121',
            'base_updated_at': '2026-09-23T00:00:00Z',
            'created_at': '2026-09-23T01:00:00Z',
            'retry_count': 0,
            'is_blocked': true,
            'last_error':
                'Bad state: Sync conflict: booking changed remotely before applying this edit.',
            'payload': {
              ...server,
              'amount': sameContents ? 900 : 1000,
              'updated_at': '2026-09-23T01:00:00Z',
            },
          }),
        ]);
        final service = OfflineMutationQueueService(
          firestore: db,
          backend: backend,
          isOnline: () => true,
        );
        await service.flushPendingMutations();
        final remaining = await backend.readStringList(key);
        if (sameContents) {
          expect(remaining, isEmpty);
        } else {
          final entry = jsonDecode(remaining.single) as Map;
          expect(entry['is_blocked'], true);
          expect(entry['booking_conflict_rechecked'], true);
          expect(entry['base_updated_at'], '2026-09-23T00:00:00Z');
          await service.flushPendingMutations();
          expect(await backend.readStringList(key), remaining);
        }
        expect(
          (await db.collection('bookings').doc('121').get()).data(),
          server,
        );
      },
    );
  }

  test(
    'boxed create recovers once and retains the actual identity error',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = _MemoryBookingStorageBackend();
      const key = 'offline_mutation_queue_v1::signed_out';
      await backend.writeStringList(key, [
        jsonEncode({
          'id': 'legacy-create',
          'kind': 'bookingCreate',
          'collection_key': 'bookings',
          'target_id': 'offline_booking_wrong',
          'created_at': '2026-09-23T01:00:00Z',
          'retry_count': 0,
          'is_blocked': true,
          'last_error': 'Dart exception thrown from converted Future.',
          'payload': {'submission_key': 'actual-key'},
        }),
      ]);
      final service = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      await service.flushPendingMutations();
      final remaining = await backend.readStringList(key);
      final entry = jsonDecode(remaining.single) as Map;
      expect(entry['boxed_error_rechecked'], true);
      expect(entry['is_blocked'], true);
      expect(
        entry['last_error'],
        contains('offline booking identity is inconsistent'),
      );
      expect(entry['created_at'], '2026-09-23T01:00:00Z');
      await service.flushPendingMutations();
      expect(await backend.readStringList(key), remaining);
      expect((await db.collection('bookings').get()).docs, isEmpty);
    },
  );

  test(
    'boxed create recovery allocates unused ID and preserves timestamps',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = _MemoryBookingStorageBackend();
      const key = 'offline_mutation_queue_v1::signed_out';
      const submission = 'recovery-valid';
      final temporaryId = BookingIdResolver.temporaryId(submission);
      const when = '2026-09-22T01:00:00Z';
      await db.collection('bookings').doc('1').set({'id': '1', 'amount': 321});
      await backend.writeStringList(key, [
        jsonEncode({
          'id': 'recover-create',
          'kind': 'bookingCreate',
          'collection_key': 'bookings',
          'target_id': temporaryId,
          'created_at': when,
          'retry_count': 0,
          'is_blocked': true,
          'last_error': 'Dart exception thrown from converted Future.',
          'payload': {
            'id': temporaryId,
            'submission_key': submission,
            'created_at': when,
            'updated_at': when,
            'client_status': 'Pending',
          },
        }),
      ]);
      final service = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      await service.flushPendingMutations();
      expect(await backend.readStringList(key), isEmpty);
      final created = (await db.collection('bookings').doc('2').get()).data()!;
      expect(created['created_at'], when);
      expect(created['updated_at'], when);
      expect((await db.collection('bookings').doc('1').get()).data(), {
        'id': '1',
        'amount': 321,
      });
      await service.flushPendingMutations();
      expect((await db.collection('bookings').get()).docs, hasLength(2));
    },
  );

  test('manual retry keeps the original booking version guard', () async {
    final backend = _MemoryBookingStorageBackend();
    const key = 'offline_mutation_queue_v1::signed_out';
    await backend.writeStringList(key, [
      jsonEncode({
        'id': 'retry',
        'kind': 'collectionDocumentUpsert',
        'collection_key': 'bookings',
        'target_id': '121',
        'base_updated_at': 'original',
        'created_at': 'action-time',
        'retry_count': 0,
        'is_blocked': true,
        'payload': {'amount': 1000},
      }),
    ]);
    final service = OfflineMutationQueueService(
      firestore: FakeFirebaseFirestore(),
      backend: backend,
      isOnline: () => false,
    );
    await service.retryBlockedConflict('retry');
    final entry = jsonDecode((await backend.readStringList(key)).single) as Map;
    expect(entry['base_updated_at'], 'original');
    expect(entry['created_at'], 'action-time');
    expect(entry['is_blocked'], false);
    expect(entry['payload'], {'amount': 1000});
  });

  test(
    'legacy continuation rechecks once, commits status with original offline time',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = _MemoryBookingStorageBackend();
      const key = 'offline_mutation_queue_v1::signed_out';
      final server = fixture.server();
      final pending = fixture.pending();
      await db.collection('bookings').doc('7').set(server);
      await backend.writeStringList(key, [
        jsonEncode({
          'id': 'continue-status',
          'kind': 'collectionDocumentUpsert',
          'collection_key': 'bookings',
          'target_id': '7',
          'created_at': pending['updated_at'],
          'base_updated_at': server['created_at'],
          'payload': pending,
          'retry_count': 0,
          'is_blocked': true,
          'booking_conflict_rechecked': true,
          'last_error':
              'Sync conflict: booking changed remotely before applying this edit.',
        }),
      ]);
      final service = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      await service.flushPendingMutations();
      expect(await backend.readStringList(key), isEmpty);
      expect((await db.collection('bookings').doc('7').get()).data(), {
        ...pending,
        'photo_cleanup_claims': [],
        'photo_cleanup_paths': [],
      });
      await service.flushPendingMutations();
      expect((await db.collection('bookings').doc('7').get()).data(), {
        ...pending,
        'photo_cleanup_claims': [],
        'photo_cleanup_paths': [],
      });
    },
  );

  for (final kind in ['media', 'cleanup', 'mutations', 'booking photos']) {
    test('reading $kind status does not feed another status event', () async {
      final backend = _MemoryBookingStorageBackend();
      final db = FakeFirebaseFirestore();
      final dynamic service = switch (kind) {
        'media' => OfflineMediaSyncService(
          firestore: db,
          backend: backend,
          isOnline: () => false,
        ),
        'cleanup' => OfflineCleanupQueueService(
          backend: backend,
          isOnline: () => false,
        ),
        'mutations' => OfflineMutationQueueService(
          firestore: db,
          backend: backend,
          isOnline: () => false,
        ),
        _ => BookingOfflineUploadQueueService(firestore: db, backend: backend),
      };
      await service.initialize();
      await Future<void>.delayed(Duration.zero);
      var events = 0;
      final sub = service.statusStream.listen((dynamic _) => events++);
      for (var i = 0; i < 3; i++) {
        await service.readScopedStatuses();
      }
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(
        events,
        0,
        reason: 'A status read must not trigger another status read',
      );
    });
  }

  test(
    'queue inspection is scoped and never starts sync or publishes status',
    () async {
      final backend = _MemoryBookingStorageBackend();
      final db = FakeFirebaseFirestore();
      const key = 'offline_mutation_queue_v1::owner';
      final raw = jsonEncode({
        'id': 'inspect',
        'kind': 'bookingCreate',
        'target_id': 'offline_booking_inspect',
        'collection_key': 'bookings',
        'payload': {},
        'created_at': '2026-09-19T02:30:00Z',
        'retry_count': 0,
        'is_blocked': false,
      });
      await backend.writeStringList(key, [raw]);
      final service = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
      );
      var events = 0;
      final sub = service.statusStream.listen((_) => events++);
      final items = await service.readPendingItems('owner');
      expect(items, hasLength(1));
      expect(items.single.title, 'Create booking');
      expect(items.single.createdAt, DateTime.utc(2026, 9, 19, 2, 30));
      expect(await service.readPendingItems('another-account'), isEmpty);
      expect(await service.readPendingItems(''), isEmpty);
      expect(await backend.readStringList(key), [raw]);
      expect((await db.collection('bookings').get()).docs, isEmpty);
      expect(events, 0);
      await sub.cancel();
    },
  );

  for (final field in ['profile_photo', 'license_photo']) {
    test(
      'successive offline $field changes preserve newest photo and action time',
      () async {
        var online = false;
        final db = MergeAwareFirestore();
        final backend = _MemoryBookingStorageBackend();
        final column = field == 'license_photo' ? 'license' : 'photo';
        await db.collection('users').doc('7').set({column: 'https://old'});
        final service = OfflineMediaSyncService(
          firestore: db,
          backend: backend,
          photoStorageService: _FakeUserPhotoStorageService(),
          isOnline: () => online,
        );
        final bytes = Uint8List.fromList(
          img.encodePng(img.Image(width: 2, height: 2)),
        );
        final first = await service.queueUserPhotoUpload(
          userId: '7',
          fieldKey: field,
          bytes: bytes,
          fileName: 'first.png',
          originalValue: 'https://old',
        );
        final second = await service.queueUserPhotoUpload(
          userId: '7',
          fieldKey: field,
          bytes: bytes,
          fileName: 'second.png',
          originalValue: first.previewUrl,
        );
        await Future<void>.delayed(Duration.zero);
        final reopened = OfflineMediaSyncService(
          firestore: db,
          backend: backend,
          photoStorageService: _FakeUserPhotoStorageService(),
          isOnline: () => online,
        );
        await reopened.initialize();
        await Future<void>.delayed(Duration.zero);
        online = true;
        await reopened.flushPendingOperations();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        final saved = (await db.collection('users').doc('7').get()).data()!;
        expect(
          saved[column],
          anyOf(endsWith('second.jpg'), endsWith('second.png')),
        );
        expect(saved['photo_updated_at'], second.queuedAt.toIso8601String());
        expect(
          await backend.readStringList(
            'offline_media_sync_queue_v1::signed_out',
          ),
          isEmpty,
        );
      },
    );
  }

  test(
    'replacement queued during photo upload uses exact predecessor receipt',
    () async {
      var online = false;
      final db = MergeAwareFirestore();
      final backend = _MemoryBookingStorageBackend();
      final storage = _PausedUserPhotos();
      await db.collection('users').doc('7').set({'photo': 'https://old'});
      final service = OfflineMediaSyncService(
        firestore: db,
        backend: backend,
        photoStorageService: storage,
        isOnline: () => online,
      );
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      final first = await service.queueUserPhotoUpload(
        userId: '7',
        fieldKey: 'profile_photo',
        bytes: bytes,
        fileName: 'first.png',
        originalValue: 'https://old',
      );
      await Future<void>.delayed(Duration.zero);
      online = true;
      final flush = service.flushPendingOperations();
      await storage.started.future;
      online = false;
      await service.queueUserPhotoUpload(
        userId: '7',
        fieldKey: 'profile_photo',
        bytes: bytes,
        fileName: 'second.png',
        originalValue: first.previewUrl,
      );
      storage.release.complete();
      await flush;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      online = true;
      await service.flushPendingOperations();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        (await db.collection('users').doc('7').get()).data()!['photo'],
        anyOf(endsWith('second.jpg'), endsWith('second.png')),
      );
      expect(
        await backend.readStringList('offline_media_sync_queue_v1::signed_out'),
        isEmpty,
      );
    },
  );

  test(
    'legacy photo chain survives lost acknowledgement without restoring old photo',
    () async {
      var online = false;
      const key = 'offline_media_sync_queue_v1::signed_out';
      final db = MergeAwareFirestore();
      final backend = _MemoryBookingStorageBackend();
      final original = <String, dynamic>{
        'id': 'first',
        'kind': 'userUpload',
        'user_id': '7',
        'field_key': 'profile_photo',
        'file_name': 'first.png',
        'mime_type': 'image/png',
        'bytes_base64': base64Encode([1, 2, 3]),
        'original_value': 'https://old',
        'created_at': '2026-09-01T00:00:00Z',
      };
      final second = {
        ...original,
        'id': 'second',
        'file_name': 'second.png',
        'original_value': 'data:image/png;base64,${base64Encode([1, 2, 3])}',
        'created_at': '2026-09-02T00:00:00Z',
      };
      await backend.writeStringList(key, [
        jsonEncode(original),
        jsonEncode(second),
      ]);
      // Server committed the predecessor, but the browser lost its acknowledgement.
      await db.collection('users').doc('7').set({
        'photo': 'https://committed',
        'offline_photo_uploads': {
          'profile_photo': {'id': 'first', 'url': 'https://committed'},
        },
      });
      final service = OfflineMediaSyncService(
        firestore: db,
        backend: backend,
        photoStorageService: _FakeUserPhotoStorageService(),
        isOnline: () => online,
      );
      await service.initialize();
      await Future<void>.delayed(Duration.zero);
      online = true;
      await service.flushPendingOperations();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(
        (await db.collection('users').doc('7').get()).data()!['photo'],
        endsWith('second.png'),
      );
      expect(await backend.readStringList(key), isEmpty);
    },
  );

  test(
    'a failed predecessor retains the replacement without uploading it early',
    () async {
      var online = false;
      final db = MergeAwareFirestore();
      final backend = _MemoryBookingStorageBackend();
      final storage = _FailingUserPhotos();
      await db.collection('users').doc('7').set({'photo': 'https://old'});
      final service = OfflineMediaSyncService(
        firestore: db,
        backend: backend,
        photoStorageService: storage,
        isOnline: () => online,
      );
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      final first = await service.queueUserPhotoUpload(
        userId: '7',
        fieldKey: 'profile_photo',
        bytes: bytes,
        fileName: 'first.png',
        originalValue: 'https://old',
      );
      await service.queueUserPhotoUpload(
        userId: '7',
        fieldKey: 'profile_photo',
        bytes: bytes,
        fileName: 'second.png',
        originalValue: first.previewUrl,
      );
      await Future<void>.delayed(Duration.zero);
      online = true;
      await service.flushPendingOperations();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(storage.calls, 1);
      expect(
        await backend.readStringList('offline_media_sync_queue_v1::signed_out'),
        hasLength(2),
      );
      expect(
        (await db.collection('users').doc('7').get()).data()!['photo'],
        'https://old',
      );
    },
  );

  test(
    'stale predecessor receipt cannot authorize overwriting a newer server photo',
    () async {
      var online = false;
      final db = MergeAwareFirestore();
      final backend = _MemoryBookingStorageBackend();
      final storage = _FailingUserPhotos()..fail = false;
      const key = 'offline_media_sync_queue_v1::signed_out';
      await db.collection('users').doc('7').set({
        'photo': 'https://newer',
        'offline_photo_uploads': {
          'profile_photo': {'id': 'first', 'url': 'https://old'},
        },
      });
      await backend.writeStringList(key, [
        jsonEncode({
          'id': 'second',
          'kind': 'userUpload',
          'user_id': '7',
          'field_key': 'profile_photo',
          'file_name': 'second.png',
          'bytes_base64': base64Encode([1, 2, 3]),
          'original_value': 'data:image/png;base64,AQID',
          'previous_upload_id': 'first',
          'created_at': '2026-09-02T00:00:00Z',
        }),
      ]);
      final service = OfflineMediaSyncService(
        firestore: db,
        backend: backend,
        photoStorageService: storage,
        isOnline: () => online,
      );
      await service.initialize();
      await Future<void>.delayed(Duration.zero);
      online = true;
      await service.flushPendingOperations();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(storage.calls, 0);
      expect(
        (await db.collection('users').doc('7').get()).data()!['photo'],
        'https://newer',
      );
      expect(await backend.readStringList(key), hasLength(1));
    },
  );

  for (final overlap in [false, true]) {
    test(
      overlap
          ? 'media flush merge preserves photo enqueued during local commit'
          : 'failed photo stays durable and repeated flushes respect backoff',
      () async {
        const key = 'offline_media_sync_queue_v1::signed_out';
        final backend = _PausedMediaBackend();
        final photos = _FailingUserPhotos()..fail = !overlap;
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('users').doc('7').set({'id': '7'});
        await backend.writeStringList(key, [
          jsonEncode({
            'id': 'original_photo',
            'kind': 'userUpload',
            'created_at': '2026-06-29T00:00:00.000Z',
            'retry_count': 0,
            'user_id': '7',
            'field_key': 'profile_photo',
            'file_name': 'profile.png',
            'bytes_base64': base64Encode([1, 2, 3]),
          }),
        ]);
        backend.pauseEmpty = overlap;
        final service = OfflineMediaSyncService(
          firestore: firestore,
          backend: backend,
          photoStorageService: photos,
          supportStorageService: _FakeSupportStorageService(),
        );
        await service.initialize();
        if (overlap) {
          await backend.paused.future.timeout(const Duration(seconds: 2));
          photos.fail = true;
          final enqueue = service.queueUserPhotoUpload(
            userId: '7',
            fieldKey: 'license_photo',
            bytes: Uint8List.fromList(
              img.encodePng(img.Image(width: 2, height: 2)),
            ),
            fileName: 'license.png',
            originalValue: null,
          );
          await Future<void>.delayed(const Duration(milliseconds: 60));
          backend.resume.complete();
          await enqueue;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await service.flushPendingOperations();
        final queued = await backend.readStringList(key);
        expect(queued, hasLength(1));
        final entry = jsonDecode(queued.single) as Map<String, dynamic>;
        expect(entry['bytes_base64'], isNotEmpty);
        expect(entry['last_error'], isNotEmpty);
        expect(entry['retry_count'], 1);
        expect(entry['next_retry_at'], isNotNull);
        final calls = photos.calls;
        final writes = backend.writes;
        for (var i = 0; i < 3; i++) {
          await service.flushPendingOperations();
        }
        expect(photos.calls, calls);
        expect(
          backend.writes,
          writes,
          reason: 'Backoff must not rewrite photo payloads',
        );
        expect(service.currentStatus.failedCount, 1);
        if (!overlap) {
          expect(entry['created_at'], '2026-06-29T00:00:00.000Z');
        }
      },
    );
  }

  group('BookingOfflineUploadQueueService', () {
    test(
      'account switch during photo preparation preserves originating queue',
      () async {
        final auth = createAuthStorageBackend();
        await auth.initialize();
        await auth.writeString('paltranco_current_user_id', 'photo_A');
        addTearDown(() => auth.remove('paltranco_current_user_id'));
        final backend = _MemoryBookingStorageBackend();
        final service = BookingOfflineUploadQueueService(
          firestore: FakeFirebaseFirestore(),
          backend: backend,
          photoStorageService: _FakeBookingPhotoStorageService(),
          flushMutations: () async {},
        );
        await service.initialize();
        final saving = service.enqueueBookingPhoto(
          bookingId: '1',
          statusKey: 'delivered',
          fieldKey: 'proof',
          bytes: Uint8List.fromList(
            img.encodePng(img.Image(width: 2, height: 2)),
          ),
          fileName: 'proof.png',
        );
        // ImageUploadProcessor yields for 16ms before processing the image.
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await auth.writeString('paltranco_current_user_id', 'photo_B');
        await saving;
        expect(
          await backend.readStringList(
            'booking_pending_upload_queue_v1::photo_A',
          ),
          hasLength(1),
        );
        expect(
          await backend.readStringList(
            'booking_pending_upload_queue_v1::photo_B',
          ),
          isEmpty,
        );
      },
    );

    test(
      'concurrent flush calls share ownership while mutations are pending',
      () async {
        final pending = Completer<void>();
        final started = Completer<void>();
        var calls = 0;
        final service = BookingOfflineUploadQueueService(
          firestore: FakeFirebaseFirestore(),
          backend: _MemoryBookingStorageBackend(),
          flushMutations: () {
            calls++;
            if (!started.isCompleted) started.complete();
            return pending.future;
          },
        );
        await service.initialize();
        await started.future;
        await Future.wait(
          List.generate(5, (_) => service.flushPendingUploads()),
        );
        expect(calls, 1);
        pending.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
    );

    test(
      'replays pending booking photo upload when field is still pending',
      () async {
        final firestore = FakeFirebaseFirestore();
        final backend = _MemoryBookingStorageBackend();
        final photoService = _FakeBookingPhotoStorageService();
        final service = BookingOfflineUploadQueueService(
          firestore: firestore,
          backend: backend,
          photoStorageService: photoService,
        );

        const pendingUploadId = 'booking_upload_test_1';
        await firestore.collection('bookings').doc('1').set({
          'id': '1',
          'status_outputs': {
            'book': {
              'fields': {
                'waybill_photo': {
                  'name': 'waybill.png',
                  'mime_type': 'image/png',
                  'size': 3,
                  'pending_upload': true,
                  'pending_upload_id': pendingUploadId,
                },
              },
            },
          },
        });

        await backend.writeStringList(
          'booking_pending_upload_queue_v1::signed_out',
          <String>[
            jsonEncode({
              'id': pendingUploadId,
              'booking_id': '1',
              'status_key': 'book',
              'field_key': 'waybill_photo',
              'bytes_base64': base64Encode(Uint8List.fromList([1, 2, 3])),
              'file_name': 'waybill.png',
              'mime_type': 'image/png',
              'size': 3,
              'created_at': DateTime.utc(2026, 6, 29).toIso8601String(),
              'retry_count': 0,
              'last_error': null,
            }),
          ],
        );

        await service.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 120));

        final saved = (await firestore.collection('bookings').doc('1').get())
            .data()!;
        final value =
            (((saved['status_outputs'] as Map)['book'] as Map)['fields']
                    as Map)['waybill_photo']
                as Map;

        expect(
          value['download_url'],
          'https://example.com/booking-waybill.png',
        );
        expect(value.containsKey('pending_upload'), isFalse);
        expect(photoService.uploadCalls, 1);
      },
    );

    test(
      'retains photo until booking marker arrives and preserves action time',
      () async {
        final firestore = FakeFirebaseFirestore();
        final backend = _MemoryBookingStorageBackend();
        final photos = _FakeBookingPhotoStorageService();
        final service = BookingOfflineUploadQueueService(
          firestore: firestore,
          backend: backend,
          photoStorageService: photos,
          flushMutations: () async {},
        );
        const key = 'booking_pending_upload_queue_v1::signed_out';
        const occurredAt = '2026-06-29T08:00:00.000Z';
        await backend.writeStringList(key, [
          jsonEncode({
            'id': 'waiting_photo',
            'booking_id': '1',
            'status_key': 'delivered',
            'field_key': 'photo',
            'bytes_base64': base64Encode([1, 2, 3]),
            'file_name': 'proof.png',
            'mime_type': 'image/png',
            'size': 3,
            'created_at': occurredAt,
            'retry_count': 0,
          }),
        ]);
        await service.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(await backend.readStringList(key), hasLength(1));
        expect(photos.uploadCalls, 0);
        await firestore.collection('bookings').doc('1').set({
          'id': '1',
          'created_at': occurredAt,
          'updated_at': occurredAt,
          'delivered_at': occurredAt,
          'status_outputs': {
            'delivered': {
              'submitted_at': occurredAt,
              'fields': {
                'photo': {
                  'pending_upload': true,
                  'pending_upload_id': 'waiting_photo',
                },
              },
            },
          },
        });
        await service.flushPendingUploads();
        expect(photos.uploadCalls, 1);
        expect(await backend.readStringList(key), isEmpty);
        final saved = (await firestore.collection('bookings').doc('1').get())
            .data()!;
        expect(saved['created_at'], occurredAt);
        expect(saved['updated_at'], occurredAt);
        expect(saved['delivered_at'], occurredAt);
        expect(
          (saved['status_outputs'] as Map)['delivered']['submitted_at'],
          occurredAt,
        );
      },
    );

    test(
      'resolves temporary booking photo to confirmed ID after restart',
      () async {
        final firestore = FakeFirebaseFirestore();
        final backend = _MemoryBookingStorageBackend();
        final photoService = _FakeBookingPhotoStorageService();
        final service = BookingOfflineUploadQueueService(
          firestore: firestore,
          backend: backend,
          photoStorageService: photoService,
        );

        const submission = 'booking_8_9_1_1789534355769000';
        await firestore
            .collection('manage_id')
            .doc(BookingIdResolver.reservationId(submission))
            .set({
              'resource_key': 'bookings',
              'submission_key': submission,
              'document_id': '1',
            });
        const pendingUploadId = 'booking_upload_test_1';
        await firestore.collection('bookings').doc('1').set({
          'id': '1',
          'submission_key': submission,
          'status_outputs': {
            'book': {
              'fields': {
                'waybill_photo': {
                  'name': 'waybill.png',
                  'mime_type': 'image/png',
                  'size': 3,
                  'pending_upload': true,
                  'pending_upload_id': pendingUploadId,
                },
              },
            },
          },
        });

        await backend.writeStringList(
          'booking_pending_upload_queue_v1::signed_out',
          <String>[
            jsonEncode({
              'id': pendingUploadId,
              'booking_id': BookingIdResolver.temporaryId(submission),
              'status_key': 'book',
              'field_key': 'waybill_photo',
              'bytes_base64': base64Encode(Uint8List.fromList([1, 2, 3])),
              'file_name': 'waybill.png',
              'mime_type': 'image/png',
              'size': 3,
              'created_at': DateTime.utc(2026, 6, 29).toIso8601String(),
              'retry_count': 0,
              'last_error': null,
            }),
          ],
        );

        await service.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 120));

        final saved = (await firestore.collection('bookings').doc('1').get())
            .data()!;
        final value =
            (((saved['status_outputs'] as Map)['book'] as Map)['fields']
                    as Map)['waybill_photo']
                as Map;

        expect(
          value['download_url'],
          'https://example.com/booking-waybill.png',
        );
        expect(value.containsKey('pending_upload'), isFalse);
        expect(photoService.uploadCalls, 1);
      },
    );

    test(
      'does not overwrite newer booking field if pending marker is gone',
      () async {
        final firestore = FakeFirebaseFirestore();
        final backend = _MemoryBookingStorageBackend();
        final photoService = _FakeBookingPhotoStorageService();
        final service = BookingOfflineUploadQueueService(
          firestore: firestore,
          backend: backend,
          photoStorageService: photoService,
        );

        const pendingUploadId = 'booking_upload_test_2';
        await firestore.collection('bookings').doc('1').set({
          'id': '1',
          'status_outputs': {
            'book': {
              'fields': {
                'waybill_photo': {
                  'name': 'server-waybill.png',
                  'download_url': 'https://server/newer.png',
                },
              },
            },
          },
        });

        await backend.writeStringList(
          'booking_pending_upload_queue_v1::signed_out',
          <String>[
            jsonEncode({
              'id': pendingUploadId,
              'booking_id': '1',
              'status_key': 'book',
              'field_key': 'waybill_photo',
              'bytes_base64': base64Encode(Uint8List.fromList([1, 2, 3])),
              'file_name': 'waybill.png',
              'mime_type': 'image/png',
              'size': 3,
              'created_at': DateTime.utc(2026, 6, 29).toIso8601String(),
              'retry_count': 0,
              'last_error': null,
            }),
          ],
        );

        await service.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 120));

        final saved = (await firestore.collection('bookings').doc('1').get())
            .data()!;
        final value =
            (((saved['status_outputs'] as Map)['book'] as Map)['fields']
                    as Map)['waybill_photo']
                as Map;

        expect(value['download_url'], 'https://server/newer.png');
        expect(photoService.deletedPaths, isEmpty);
        expect(photoService.uploadCalls, 0);
      },
    );

    test(
      'records why a queued photo is waiting and surfaces it after repeated no-progress cycles',
      () async {
        final auth = createAuthStorageBackend();
        await auth.initialize();
        await auth.writeString('paltranco_current_user_id', '7');
        await auth.writeStringList('paltranco_known_session_user_ids', ['7']);
        addTearDown(() async {
          await auth.remove('paltranco_current_user_id');
          await auth.remove('paltranco_known_session_user_ids');
        });
        final firestore = FakeFirebaseFirestore();
        final backend = _MemoryBookingStorageBackend();
        final photoService = _FakeBookingPhotoStorageService();
        final service = BookingOfflineUploadQueueService(
          firestore: firestore,
          backend: backend,
          photoStorageService: photoService,
          flushMutations: () async {},
        );
        const key = 'booking_pending_upload_queue_v1::7';
        final stagedAt = DateTime.utc(2026, 6, 29, 8);
        await backend.writeStringList(key, [
          jsonEncode({
            'id': 'photo_a',
            'booking_id': '145',
            'status_key': 'delivered__1',
            'field_key': 'proof',
            'bytes_base64': base64Encode([1, 2, 3]),
            'file_name': 'proof.png',
            'mime_type': 'image/png',
            'size': 3,
            'created_at': stagedAt.toIso8601String(),
            'retry_count': 0,
            'waiting_for_commit': true,
          }),
        ]);

        await service.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await service.flushPendingUploads();

        final waiting =
            jsonDecode((await backend.readStringList(key)).single)
                as Map<String, dynamic>;
        expect(waiting['wait_reason'], 'booking_missing');
        expect(waiting['wait_count'], greaterThanOrEqualTo(1));
        expect(waiting['last_error'], isNull);
        expect(photoService.uploadCalls, 0);

        final waitingItem = (await service.readPendingItems('7')).single;
        expect(waitingItem.statusLabel, contains('Waiting for the booking'));
        expect(waitingItem.hasError, isFalse);

        for (var cycle = 0; cycle < 4; cycle++) {
          await service.flushPendingUploads();
        }

        final stuck =
            jsonDecode((await backend.readStringList(key)).single)
                as Map<String, dynamic>;
        expect(stuck['wait_count'], greaterThan(3));
        expect('${stuck['last_error']}', contains('still waiting'));
        expect('${stuck['error_diagnostics']}', contains('wait_reason'));
        expect(photoService.uploadCalls, 0);

        final stuckItem = (await service.readPendingItems('7')).single;
        expect(stuckItem.statusLabel, 'Waiting to retry');
        expect(stuckItem.errorMessage, isNotNull);
      },
    );

    test(
      'reclaims a queued photo the server already replaced and waits when the booking is still older',
      () async {
        final firestore = FakeFirebaseFirestore();
        final backend = _MemoryBookingStorageBackend();
        final photoService = _FakeBookingPhotoStorageService();
        final service = BookingOfflineUploadQueueService(
          firestore: firestore,
          backend: backend,
          photoStorageService: photoService,
          flushMutations: () async {},
        );
        const key = 'booking_pending_upload_queue_v1::signed_out';
        final stagedAt = DateTime.utc(2026, 6, 29, 8);
        await backend.writeStringList(key, [
          jsonEncode({
            'id': 'photo_a',
            'booking_id': '144',
            'status_key': 'delivered__1',
            'field_key': 'proof',
            'bytes_base64': base64Encode([1, 2, 3]),
            'file_name': 'proof.png',
            'mime_type': 'image/png',
            'size': 3,
            'created_at': stagedAt.toIso8601String(),
            'retry_count': 0,
            'waiting_for_commit': true,
          }),
        ]);
        // The booking moved past the staged photo, so no queued booking write
        // can restore its marker and this entry can never be applied.
        await firestore.collection('bookings').doc('144').set({
          'id': '144',
          'updated_at': stagedAt
              .add(const Duration(minutes: 5))
              .toIso8601String(),
          'status_outputs': {
            'delivered__1': {
              'fields': {
                'proof': {
                  'pending_upload': true,
                  'pending_upload_id': 'photo_b',
                },
              },
            },
          },
        });

        await service.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await service.flushPendingUploads();

        expect(await backend.readStringList(key), isEmpty);
        expect(photoService.uploadCalls, 0);
        final saved = (await firestore.collection('bookings').doc('144').get())
            .data()!;
        expect(
          (((saved['status_outputs'] as Map)['delivered__1'] as Map)['fields']
              as Map)['proof']['pending_upload_id'],
          'photo_b',
        );

        // A booking older than the staged photo may still be the write that
        // carries this marker, so the entry waits instead of being reclaimed.
        await firestore.collection('bookings').doc('144').set({
          'id': '144',
          'updated_at': stagedAt
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          'status_outputs': {
            'delivered__1': {
              'fields': {
                'proof': {
                  'pending_upload': true,
                  'pending_upload_id': 'photo_b',
                },
              },
            },
          },
        });
        await backend.writeStringList(key, [
          jsonEncode({
            'id': 'photo_a',
            'booking_id': '144',
            'status_key': 'delivered__1',
            'field_key': 'proof',
            'bytes_base64': base64Encode([1, 2, 3]),
            'file_name': 'proof.png',
            'mime_type': 'image/png',
            'size': 3,
            'created_at': stagedAt.toIso8601String(),
            'retry_count': 0,
            'waiting_for_commit': true,
          }),
        ]);
        await service.flushPendingUploads();

        final waiting =
            jsonDecode((await backend.readStringList(key)).single)
                as Map<String, dynamic>;
        expect(waiting['wait_reason'], 'marker_superseded');
        expect(waiting['last_error'], isNull);
        expect(photoService.uploadCalls, 0);
      },
    );

    test(
      'releases the flush lock when the booking mutation flush never answers',
      () async {
        final firestore = FakeFirebaseFirestore();
        final backend = _MemoryBookingStorageBackend();
        final photoService = _FakeBookingPhotoStorageService();
        var mutationFlushCalls = 0;
        final stalled = Completer<void>();
        final service = BookingOfflineUploadQueueService(
          firestore: firestore,
          backend: backend,
          photoStorageService: photoService,
          flushMutations: () {
            mutationFlushCalls++;
            return stalled.future;
          },
          mutationFlushTimeout: const Duration(milliseconds: 200),
        );
        const key = 'booking_pending_upload_queue_v1::signed_out';
        await backend.writeStringList(key, [
          jsonEncode({
            'id': 'photo_a',
            'booking_id': '1',
            'status_key': 'delivered',
            'field_key': 'proof',
            'bytes_base64': base64Encode([1, 2, 3]),
            'file_name': 'proof.png',
            'mime_type': 'image/png',
            'size': 3,
            'created_at': '2026-06-29T08:00:00.000Z',
            'retry_count': 0,
          }),
        ]);
        await firestore.collection('bookings').doc('1').set({
          'id': '1',
          'updated_at': '2026-06-29T08:00:00.000Z',
          'status_outputs': {
            'delivered': {
              'fields': {
                'proof': {
                  'pending_upload': true,
                  'pending_upload_id': 'photo_a',
                },
              },
            },
          },
        });

        await service.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(
          stalled.isCompleted,
          isFalse,
          reason: 'the stalled dependency must still be pending',
        );
        expect(
          await backend.readStringList(key),
          hasLength(1),
          reason: 'a stalled cycle must keep the queued photo',
        );

        // A wedged lock would make every later timer and resume event return
        // without touching the queue again.
        await service.flushPendingUploads();
        expect(
          mutationFlushCalls,
          greaterThanOrEqualTo(2),
          reason: 'a timed-out cycle must release the flush lock',
        );

        stalled.complete();
        await service.flushPendingUploads();
        expect(await backend.readStringList(key), isEmpty);
        expect(photoService.uploadCalls, 1);
      },
    );
  });

  group('OfflineMediaSyncService', () {
    test(
      'replays queued user profile photo when server value is unchanged',
      () async {
        final firestore = FakeFirebaseFirestore();
        final backend = _MemoryBookingStorageBackend();
        final photoService = _FakeUserPhotoStorageService();
        final supportStorageService = _FakeSupportStorageService();
        final service = OfflineMediaSyncService(
          firestore: firestore,
          backend: backend,
          photoStorageService: photoService,
          supportStorageService: supportStorageService,
        );

        await firestore.collection('users').doc('7').set({
          'id': '7',
          'role': 'client',
          'name': 'Adryc',
          'photo': 'https://server/old.png',
        });

        await backend.writeStringList(
          'offline_media_sync_queue_v1::signed_out',
          <String>[
            jsonEncode({
              'id': 'user_upload_test_1',
              'kind': 'userUpload',
              'created_at': DateTime.utc(2026, 6, 29).toIso8601String(),
              'retry_count': 0,
              'last_error': null,
              'user_id': '7',
              'field_key': 'profile_photo',
              'file_name': 'profile.png',
              'mime_type': 'image/png',
              'size': 3,
              'bytes_base64': base64Encode(Uint8List.fromList([1, 2, 3])),
              'original_value': 'https://server/old.png',
            }),
          ],
        );

        await service.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 80));

        final saved = (await firestore.collection('users').doc('7').get())
            .data()!;
        expect(saved['photo'], 'https://example.com/user-profile.png');
      },
    );

    test(
      'does not overwrite newer user photo if server changed first',
      () async {
        final firestore = FakeFirebaseFirestore();
        final backend = _MemoryBookingStorageBackend();
        final photoService = _FakeUserPhotoStorageService();
        final supportStorageService = _FakeSupportStorageService();
        final service = OfflineMediaSyncService(
          firestore: firestore,
          backend: backend,
          photoStorageService: photoService,
          supportStorageService: supportStorageService,
        );

        await firestore.collection('users').doc('7').set({
          'id': '7',
          'role': 'client',
          'name': 'Adryc',
          'photo': 'https://server/old.png',
        });

        await firestore.collection('users').doc('7').update({
          'photo': 'https://server/newer.png',
        });

        await backend.writeStringList(
          'offline_media_sync_queue_v1::signed_out',
          <String>[
            jsonEncode({
              'id': 'user_upload_test_2',
              'kind': 'userUpload',
              'created_at': DateTime.utc(2026, 6, 29).toIso8601String(),
              'retry_count': 0,
              'last_error': null,
              'user_id': '7',
              'field_key': 'profile_photo',
              'file_name': 'profile.png',
              'mime_type': 'image/png',
              'size': 3,
              'bytes_base64': base64Encode(Uint8List.fromList([1, 2, 3])),
              'original_value': 'https://server/old.png',
            }),
          ],
        );

        await service.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 80));

        final saved = (await firestore.collection('users').doc('7').get())
            .data()!;
        expect(saved['photo'], 'https://server/newer.png');
      },
    );

    test(
      'support retry is idempotent and older offline message preserves newer preview',
      () async {
        final firestore = FakeFirebaseFirestore();
        final backend = _MemoryBookingStorageBackend();
        final service = OfflineMediaSyncService(
          firestore: firestore,
          backend: backend,
          photoStorageService: _FakeUserPhotoStorageService(),
          supportStorageService: _FakeSupportStorageService(),
        );
        final thread = firestore.collection('support').doc('thread-1');
        await thread.set({
          'last_message_text': 'Newer message',
          'last_message_at': '2026-09-18T00:00:00.000Z',
        });
        const key = 'offline_media_sync_queue_v1::signed_out';
        final entry = jsonEncode({
          'id': 'stable_message',
          'kind': 'supportMessage',
          'created_at': '2026-06-29T00:00:00.000Z',
          'retry_count': 0,
          'thread_id': 'thread-1',
          'sender_user_id': '1',
          'sender_role': 'admin',
          'sender_name': 'Admin',
          'text': 'Older message',
          'attachments': [],
          'thread_document': {
            'last_message_text': 'Stale snapshot',
            'last_message_at': '2026-06-28T00:00:00.000Z',
          },
        });
        await backend.writeStringList(key, [entry]);
        await service.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await backend.writeStringList(key, [entry]);
        await service.flushPendingOperations();
        final messages = await thread.collection('messages').get();
        expect(messages.docs, hasLength(1));
        expect(messages.docs.single.id, 'stable_message');
        expect(
          messages.docs.single.data()['created_at'],
          '2026-06-29T00:00:00.000Z',
        );
        expect(
          (await thread.get()).data()!['last_message_text'],
          'Newer message',
        );
      },
    );

    test('replays queued support message and attachment', () async {
      final firestore = FakeFirebaseFirestore();
      final backend = _MemoryBookingStorageBackend();
      final photoService = _FakeUserPhotoStorageService();
      final supportStorageService = _FakeSupportStorageService();
      final service = OfflineMediaSyncService(
        firestore: firestore,
        backend: backend,
        photoStorageService: photoService,
        supportStorageService: supportStorageService,
      );

      await firestore
          .collection('support')
          .doc('thread-1')
          .set(
            const SupportThread(
              id: 'thread-1',
              requesterUserId: '7',
              requesterRole: 'client',
              requesterName: 'Adryc Allen Catapang',
              requesterPhoto: null,
              topicKey: supportTopicGeneral,
              topicLabel: 'General',
              isActive: true,
            ).toMap(),
          );

      const sender = UserModel(
        id: '1',
        role: 'admin',
        name: 'PALTRANCO Transport Corporation',
      );

      await backend.writeStringList(
        'offline_media_sync_queue_v1::signed_out',
        <String>[
          jsonEncode({
            'id': 'support_message_test_1',
            'kind': 'supportMessage',
            'created_at': DateTime.utc(2026, 6, 29).toIso8601String(),
            'retry_count': 0,
            'last_error': null,
            'thread_id': 'thread-1',
            'sender_user_id': sender.id,
            'sender_role': sender.role,
            'sender_name': sender.name,
            'sender_photo': sender.photo,
            'text': 'Hello from queued support',
            'attachments': [
              {
                'bytes_base64': base64Encode(Uint8List.fromList([9, 8, 7])),
                'file_name': 'support.png',
                'mime_type': 'image/png',
                'size': 3,
              },
            ],
          }),
        ],
      );

      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final messages = await firestore
          .collection('support')
          .doc('thread-1')
          .collection('messages')
          .get();
      expect(messages.docs, hasLength(1));

      final message = messages.docs.single.data();
      expect(message['text'], 'Hello from queued support');
      expect((message['attachments'] as List).length, 1);

      final thread =
          (await firestore.collection('support').doc('thread-1').get()).data()!;
      expect(thread['last_message_text'], 'Hello from queued support');
    });
  });
}

class _MemoryBookingStorageBackend implements BookingStorageBackend {
  final Map<String, List<String>> _store = {};
  int writes = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<String>> readStringList(String key) async {
    return List<String>.from(_store[key] ?? const []);
  }

  @override
  Future<void> writeStringList(String key, List<String> values) async {
    writes++;
    _store[key] = List<String>.from(values);
  }
}

class _FakeFirebaseStorage implements FirebaseStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBookingPhotoStorageService extends PhotoStorageService {
  _FakeBookingPhotoStorageService() : super(storage: _FakeFirebaseStorage());

  int uploadCalls = 0;
  final List<String> deletedPaths = <String>[];

  @override
  Future<Map<String, dynamic>> uploadBookingPhoto({
    required Uint8List bytes,
    required String bookingId,
    required String statusKey,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    uploadCalls += 1;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return {
      'name': fileName,
      'download_url': 'https://example.com/booking-$fileName',
      'storage_path':
          'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/fake.png',
      'mime_type': mimeType ?? 'image/png',
      'size': size ?? bytes.length,
    };
  }

  @override
  Future<void> deleteByPath(String? storagePath) async {
    if (storagePath != null) {
      deletedPaths.add(storagePath);
    }
  }
}

class _FakeUserPhotoStorageService extends PhotoStorageService {
  _FakeUserPhotoStorageService() : super(storage: _FakeFirebaseStorage());

  @override
  Future<Map<String, dynamic>> uploadUserPhoto({
    required Uint8List bytes,
    required String userId,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    final suffix = fieldKey == 'license_photo' ? 'license' : 'user';
    return {
      'name': fileName,
      'download_url': 'https://example.com/$suffix-$fileName',
      'storage_path': 'users/$userId/$fieldKey/fake.png',
      'mime_type': mimeType ?? 'image/png',
      'size': size ?? bytes.length,
    };
  }

  @override
  Future<void> deleteByPath(String? storagePath) async {}
}

class _FakeSupportStorageService extends SupportStorageService {
  _FakeSupportStorageService() : super(storage: _FakeFirebaseStorage());

  @override
  Future<SupportAttachment> uploadAttachment({
    required Uint8List bytes,
    required String threadId,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    return SupportAttachment(
      name: fileName,
      downloadUrl: 'https://example.com/support-$fileName',
      storagePath: 'support/$threadId/attachments/$fileName',
      mimeType: mimeType ?? 'image/png',
      size: size ?? bytes.length,
    );
  }
}

class _PausedMediaBackend extends _MemoryBookingStorageBackend {
  bool pauseEmpty = false;
  final paused = Completer<void>();
  final resume = Completer<void>();
  @override
  Future<void> writeStringList(String key, List<String> values) async {
    if (pauseEmpty && values.isEmpty && !paused.isCompleted) {
      paused.complete();
      await resume.future;
    }
    await super.writeStringList(key, values);
  }
}

class _FailingUserPhotos extends _FakeUserPhotoStorageService {
  bool fail = true;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> uploadUserPhoto({
    required Uint8List bytes,
    required String userId,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    calls++;
    if (fail) {
      throw StateError('Upload forbidden');
    }
    return super.uploadUserPhoto(
      bytes: bytes,
      userId: userId,
      fieldKey: fieldKey,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
    );
  }
}

class _PausedUserPhotos extends _FakeUserPhotoStorageService {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<Map<String, dynamic>> uploadUserPhoto({
    required Uint8List bytes,
    required String userId,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.uploadUserPhoto(
      bytes: bytes,
      userId: userId,
      fieldKey: fieldKey,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
    );
  }
}
