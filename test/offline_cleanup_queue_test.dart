import 'dart:async';
import 'dart:convert';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;

const queueKey = 'offline_cleanup_queue_v1::signed_out';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.remove('paltranco_current_user_id');
    await auth.remove('paltranco_known_session_user_ids');
  });

  test('concurrent path and folder enqueues retain every cleanup', () async {
    final backend = MemoryBackend();
    final queue = OfflineCleanupQueueService(
      backend: backend,
      storage: _Storage(),
      isOnline: () => false,
    );
    await Future.wait([
      queue.queueDeleteByPath('photos/one.png'),
      queue.queueDeleteByPath('photos/two.png'),
      queue.queueDeleteFolder('photos/old'),
    ]);
    final saved = (await backend.readStringList(
      queueKey,
    )).map(jsonDecode).toList();
    expect(saved, hasLength(3));
    expect(
      saved.map((entry) => entry['target_path']),
      unorderedEquals(['photos/one.png', 'photos/two.png', 'photos/old']),
    );
  });

  for (final samePath in [false, true]) {
    test(
      'enqueue during cleanup sync survives merge, samePath=$samePath',
      () async {
        var online = false;
        final started = Completer<void>();
        final release = Completer<void>();
        final backend = MemoryBackend();
        final storage = _Storage()
          ..onDelete = (path) async {
            started.complete();
            await release.future;
          };
        final queue = OfflineCleanupQueueService(
          backend: backend,
          storage: storage,
          isOnline: () => online,
        );
        await queue.queueDeleteByPath('photos/one.png');
        final original = (await backend.readStringList(queueKey)).single;
        online = true;
        final syncing = queue.flushPendingCleanups();
        await started.future;
        online = false;
        await queue.queueDeleteByPath(
          samePath ? 'photos/one.png' : 'photos/two.png',
        );
        release.complete();
        await syncing;
        final pending = await backend.readStringList(queueKey);
        expect(pending, hasLength(1));
        expect(
          jsonDecode(pending.single)['id'],
          isNot(jsonDecode(original)['id']),
        );
        expect(
          jsonDecode(pending.single)['target_path'],
          samePath ? 'photos/one.png' : 'photos/two.png',
        );
        storage.onDelete = (_) async {};
        online = true;
        await queue.flushPendingCleanups();
        expect(await backend.readStringList(queueKey), isEmpty);
        expect(storage.deleted, hasLength(2));
      },
    );
  }

  test(
    'account switch while local write waits keeps both actions in originating queue',
    () async {
      final auth = createAuthStorageBackend();
      await auth.initialize();
      await auth.writeString('paltranco_current_user_id', 'cleanup_A');
      addTearDown(() => auth.remove('paltranco_current_user_id'));
      final backend = _PausedBackend();
      final queue = OfflineCleanupQueueService(
        backend: backend,
        storage: _Storage(),
        isOnline: () => false,
      );
      final first = queue.queueDeleteByPath('photos/one.png');
      await backend.started.future;
      final second = queue.queueDeleteFolder('photos/old');
      await Future<void>.delayed(Duration.zero);
      await auth.writeString('paltranco_current_user_id', 'cleanup_B');
      backend.release.complete();
      await Future.wait([first, second]);
      expect(
        await backend.readStringList('offline_cleanup_queue_v1::cleanup_A'),
        hasLength(2),
      );
      expect(
        await backend.readStringList('offline_cleanup_queue_v1::cleanup_B'),
        isEmpty,
      );
    },
  );

  test(
    'failed cleanup retains its action time and retry deadline across reopening',
    () async {
      var online = false;
      final backend = _CountingBackend();
      final storage = _Storage()
        ..onDelete = (_) async {
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'unauthorized',
            message: 'Not authorized',
          );
        };
      final queue = OfflineCleanupQueueService(
        backend: backend,
        storage: storage,
        isOnline: () => online,
      );
      await queue.queueDeleteByPath('photos/one.png');
      final original = jsonDecode(
        (await backend.readStringList(queueKey)).single,
      );
      online = true;
      await queue.flushPendingCleanups();
      final entry = jsonDecode((await backend.readStringList(queueKey)).single);
      expect(entry['created_at'], original['created_at']);
      expect(entry['retry_count'], 1);
      expect(entry['last_error'], isNotEmpty);
      expect(entry['next_retry_at'], isNotNull);
      expect(queue.currentStatus.failedCount, 1);
      final writes = backend.writes;
      final reopened = OfflineCleanupQueueService(
        backend: backend,
        storage: storage,
        isOnline: () => online,
      );
      for (var i = 0; i < 3; i++) {
        await reopened.flushPendingCleanups();
      }
      expect(storage.deleted, hasLength(1));
      expect(
        backend.writes,
        writes,
        reason: 'Backoff must not rewrite cleanup entries',
      );
      expect(await backend.readStringList(queueKey), hasLength(1));
    },
  );

  test(
    'malformed booking photo target is terminal and is not retried',
    () async {
      final backend = MemoryBackend();
      final storage = _Storage();
      final db = FakeFirebaseFirestore();
      await backend.writeStringList(queueKey, [
        jsonEncode({
          'id': 'bookingPhoto_bad',
          'kind': 'bookingPhoto',
          'target_path': jsonEncode({'booking_id': '148', 'path': ''}),
          'created_at': '2026-09-25T06:04:19.637Z',
          'retry_count': 1,
          'last_error': 'TimeoutException after 0:00:10.000000',
        }),
      ]);
      final queue = OfflineCleanupQueueService(
        backend: backend,
        storage: storage,
        firestore: db,
        isOnline: () => true,
      );

      await queue.flushPendingCleanups();

      expect(await backend.readStringList(queueKey), isEmpty);
      expect(storage.deleted, isEmpty);
    },
  );

  test('booking photo enqueue rejects blank and mismatched paths', () async {
    final backend = MemoryBackend();
    final queue = OfflineCleanupQueueService(
      backend: backend,
      storage: _Storage(),
      isOnline: () => false,
    );

    await queue.queueBookingPhotoDelete('148', '');
    await queue.queueBookingPhotoDelete(
      '148',
      'bookings/149/status_outputs/book__1/waybill_photo/old.jpg',
    );

    expect(await backend.readStringList(queueKey), isEmpty);
  });

  test(
    'claimed booking photo remains visible when the object still exists',
    () async {
      const path =
          'bookings/148/status_outputs/book__1790316138146000/waybill_photo/old.jpg';
      final backend = MemoryBackend();
      final db = FakeFirebaseFirestore();
      final storage = _Storage()..onExists = (_) async => true;
      await db.collection('bookings').doc('148').set({
        'id': '148',
        'photo_cleanup_paths': [path],
        'photo_cleanup_claims': [path],
        'status_outputs': <String, dynamic>{},
      });
      await backend.writeStringList(queueKey, [
        jsonEncode({
          'id': 'bookingPhoto_claimed',
          'kind': 'bookingPhoto',
          'target_path': jsonEncode({'booking_id': '148', 'path': path}),
          'created_at': '2026-09-25T06:04:19.637Z',
          'retry_count': 1,
          'last_error': 'TimeoutException after 0:00:10.000000',
        }),
      ]);
      final queue = OfflineCleanupQueueService(
        backend: backend,
        storage: storage,
        firestore: db,
        isOnline: () => true,
      );

      await queue.flushPendingCleanups();

      final retained = jsonDecode(
        (await backend.readStringList(queueKey)).single,
      );
      expect(retained['last_error'], contains('cleanup is still claimed'));
      expect(retained['next_retry_at'], isNotNull);
      expect(storage.deleted, isEmpty);
    },
  );

  test(
    'recoverable claimed booking photo finalizes bookkeeping when object is gone',
    () async {
      const path =
          'bookings/148/status_outputs/book__1790316138146000/waybill_photo/old.jpg';
      final backend = MemoryBackend();
      final db = FakeFirebaseFirestore();
      final storage = _Storage()..onExists = (_) async => false;
      await db.collection('bookings').doc('148').set({
        'id': '148',
        'photo_cleanup_paths': [path],
        'photo_cleanup_claims': [path],
        'status_outputs': <String, dynamic>{},
      });
      await backend.writeStringList(queueKey, [
        jsonEncode({
          'id': 'bookingPhoto_claimed_absent',
          'kind': 'bookingPhoto',
          'target_path': jsonEncode({'booking_id': '148', 'path': path}),
          'created_at': '2026-09-25T06:04:19.637Z',
          'retry_count': 1,
          'last_error': 'TimeoutException after 0:00:10.000000',
        }),
      ]);
      final queue = OfflineCleanupQueueService(
        backend: backend,
        storage: storage,
        firestore: db,
        isOnline: () => true,
      );

      await queue.flushPendingCleanups();

      expect(await backend.readStringList(queueKey), isEmpty);
      final booking = (await db.collection('bookings').doc('148').get()).data();
      expect(booking?['photo_cleanup_paths'], isEmpty);
      expect(booking?['photo_cleanup_claims'], isEmpty);
      expect(storage.deleted, isEmpty);
    },
  );

  test('booking photo timeout remains retryable', () async {
    const path =
        'bookings/148/status_outputs/book__1790316138146000/waybill_photo/old.jpg';
    final backend = MemoryBackend();
    final db = FakeFirebaseFirestore();
    final storage = _Storage()
      ..onDelete = (_) async {
        throw TimeoutException('network timeout');
      };
    await db.collection('bookings').doc('148').set({
      'id': '148',
      'photo_cleanup_paths': [path],
      'photo_cleanup_claims': <String>[],
      'status_outputs': <String, dynamic>{},
    });
    await backend.writeStringList(queueKey, [
      jsonEncode({
        'id': 'bookingPhoto_timeout',
        'kind': 'bookingPhoto',
        'target_path': jsonEncode({'booking_id': '148', 'path': path}),
        'created_at': '2026-09-25T06:04:19.637Z',
        'retry_count': 0,
      }),
    ]);
    final queue = OfflineCleanupQueueService(
      backend: backend,
      storage: storage,
      firestore: db,
      isOnline: () => true,
    );

    await queue.flushPendingCleanups();

    final retained = jsonDecode(
      (await backend.readStringList(queueKey)).single,
    );
    expect(retained['retry_count'], 1);
    expect(retained['error_diagnostics'], contains('TimeoutException'));
    expect(retained['next_retry_at'], isNotNull);
  });

  group('claimed cleanup review', () {
    const path =
        'bookings/148/status_outputs/book__1790316138146000/waybill_photo/old.jpg';

    Future<_ClaimedCleanup> seed({
      required MemoryBackend backend,
      required FakeFirebaseFirestore db,
      required _Storage storage,
      required String entryId,
    }) async {
      await db.collection('bookings').doc('148').set({
        'id': '148',
        'photo_cleanup_paths': [path],
        'photo_cleanup_claims': [path],
        'status_outputs': <String, dynamic>{},
      });
      await backend.writeStringList(queueKey, [
        jsonEncode({
          'id': entryId,
          'kind': 'bookingPhoto',
          'target_path': jsonEncode({'booking_id': '148', 'path': path}),
          'created_at': '2026-09-25T06:04:19.637Z',
          'retry_count': 2,
          'last_error':
              'Bad state: Sync conflict: cleanup is still claimed and the '
              'photo exists. Review the queued cleanup before retrying.',
        }),
      ]);
      return _ClaimedCleanup(entryId);
    }

    test('a claimed cleanup is offered as a review item', () async {
      final backend = MemoryBackend();
      final db = FakeFirebaseFirestore();
      final storage = _Storage()..onExists = (_) async => true;
      final queued = await seed(
        backend: backend,
        db: db,
        storage: storage,
        entryId: 'bookingPhoto_review',
      );
      final queue = OfflineCleanupQueueService(
        backend: backend,
        storage: storage,
        firestore: db,
        isOnline: () => false,
      );

      final item = (await queue.readPendingItems('signed_out')).single;
      expect(item.isBlocked, isTrue);
      expect(
        item.conflictId,
        '${OfflineCleanupQueueService.claimedCleanupPrefix}${queued.entryId}',
      );
      expect(item.statusLabel, 'Needs review');
    });

    test(
      'a plain retry never deletes a claimed object that still exists',
      () async {
        final backend = MemoryBackend();
        final db = FakeFirebaseFirestore();
        final storage = _Storage()..onExists = (_) async => true;
        await seed(
          backend: backend,
          db: db,
          storage: storage,
          entryId: 'bookingPhoto_plain_retry',
        );
        final queue = OfflineCleanupQueueService(
          backend: backend,
          storage: storage,
          firestore: db,
          isOnline: () => true,
        );

        await queue.flushPendingCleanups();

        expect(storage.deleted, isEmpty);
        final booking = (await db.collection('bookings').doc('148').get())
            .data();
        expect(booking?['photo_cleanup_claims'], [path]);
      },
    );

    test(
      'keeping the local change deletes the claimed object and unblocks',
      () async {
        final backend = MemoryBackend();
        final db = FakeFirebaseFirestore();
        final storage = _Storage()..onExists = (_) async => true;
        final queued = await seed(
          backend: backend,
          db: db,
          storage: storage,
          entryId: 'bookingPhoto_keep',
        );
        final queue = OfflineCleanupQueueService(
          backend: backend,
          storage: storage,
          firestore: db,
          isOnline: () => true,
        );

        final resolved = await queue.resolveClaimedCleanup(
          '${OfflineCleanupQueueService.claimedCleanupPrefix}${queued.entryId}',
          keepLocal: true,
          storageKey: queueKey,
        );
        expect(resolved, isTrue);
        await queue.flushPendingCleanups();

        expect(storage.deleted, [path]);
        expect(await backend.readStringList(queueKey), isEmpty);
        final booking = (await db.collection('bookings').doc('148').get())
            .data();
        expect(booking?['photo_cleanup_claims'], isEmpty);
        expect(booking?['photo_cleanup_paths'], isEmpty);
      },
    );

    test('discarding the cleanup also releases the server claim', () async {
      final backend = MemoryBackend();
      final db = FakeFirebaseFirestore();
      final storage = _Storage()..onExists = (_) async => true;
      final queued = await seed(
        backend: backend,
        db: db,
        storage: storage,
        entryId: 'bookingPhoto_discard',
      );
      final queue = OfflineCleanupQueueService(
        backend: backend,
        storage: storage,
        firestore: db,
        isOnline: () => true,
      );

      final resolved = await queue.resolveClaimedCleanup(
        '${OfflineCleanupQueueService.claimedCleanupPrefix}${queued.entryId}',
        keepLocal: false,
        storageKey: queueKey,
      );

      expect(resolved, isTrue);
      expect(await backend.readStringList(queueKey), isEmpty);
      expect(storage.deleted, isEmpty);
      final booking = (await db.collection('bookings').doc('148').get()).data();
      expect(
        booking?['photo_cleanup_claims'],
        isEmpty,
        reason: 'a discarded cleanup must not leave the booking blocked',
      );
      expect(booking?['photo_cleanup_paths'], isEmpty);
    });

    test('resolving an unknown cleanup entry reports no work', () async {
      final queue = OfflineCleanupQueueService(
        backend: MemoryBackend(),
        storage: _Storage(),
        firestore: FakeFirebaseFirestore(),
        isOnline: () => false,
      );
      expect(
        await queue.resolveClaimedCleanup(
          'cleanup:missing',
          keepLocal: true,
          storageKey: queueKey,
        ),
        isFalse,
      );
    });
  });
}

class _ClaimedCleanup {
  const _ClaimedCleanup(this.entryId);

  final String entryId;
}

class _Storage extends Fake implements FirebaseStorage {
  final deleted = <String>[];
  Future<void> Function(String) onDelete = (_) async {};
  Future<bool> Function(String) onExists = (_) async => true;
  @override
  Reference ref([String? path]) => _Reference(this, path!);
}

class _Reference extends Fake implements Reference {
  _Reference(this.storage, this.path);
  @override
  final _Storage storage;
  final String path;
  @override
  Future<FullMetadata> getMetadata() async {
    final exists = await storage.onExists(path);
    if (!exists) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
        message: 'Object not found',
      );
    }
    return FullMetadata({'fullPath': path});
  }

  @override
  Future<void> delete() async {
    storage.deleted.add(path);
    await storage.onDelete(path);
  }
}

class _PausedBackend extends MemoryBackend {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> writeStringList(String key, List<String> values) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.writeStringList(key, values);
  }
}

class _CountingBackend extends MemoryBackend {
  int writes = 0;

  @override
  Future<void> writeStringList(String key, List<String> values) async {
    writes++;
    await super.writeStringList(key, values);
  }
}
