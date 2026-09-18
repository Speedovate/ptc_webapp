import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/requests/chassis.request.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart'
    show MemoryBackend, replay, storageKey, booking, key, temp;
import 'support/merge_aware_firestore.dart';

const driverTemp = 'offline_users_new_driver';
final actionAt = DateTime.utc(2026, 9, 1, 10);
Chassis pendingChassis() => Chassis(
  id: -101,
  name: 'Offline chassis',
  isActive: true,
  currentStatus: Chassis.loaded,
  bookingReferenceId: temp,
  driverReferenceId: driverTemp,
  createdAt: actionAt,
  updatedAt: actionAt,
  submissionKey: 'chassis_pending_new',
);
Map<String, dynamic> chassisEntry(
  Chassis chassis, {
  String? base,
  String? previous,
}) => {
  'id': 'chassis_action',
  'kind': 'chassisAssignment',
  'target_id': '${chassis.id}',
  'collection_key': 'chassis',
  'base_updated_at': base,
  'payload': {
    'chassis': chassis.toMap(),
    'submission_key': chassis.submissionKey,
    'provisional_create': chassis.id < 0,
    'previous_booking_id': previous,
    'next_booking_id': chassis.bookingReferenceId,
  },
  'created_at': chassis.updatedAt!.toIso8601String(),
  'retry_count': 0,
  'is_blocked': false,
};
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.remove('paltranco_current_user_id');
    await auth.remove('paltranco_known_session_user_ids');
    for (final scope in ['signed_out', 'A', 'B']) {
      await auth.remove(
        'offline_mutation_queue_aliases_v1::offline_mutation_queue_v1::$scope',
      );
    }
  });
  test(
    'request saves new temporary references and preserves chassis identity on edit',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
      );
      final request = ChassisRequest(
        firestore: db,
        offlineMutationQueueService: queue,
        queueInitializer: () async {},
      );
      addTearDown(request.dispose);
      final saved = await request.saveChassis(
        Chassis(
          id: 0,
          name: 'New offline',
          isActive: true,
          currentStatus: Chassis.loaded,
          bookingReferenceId: temp,
          driverReferenceId: driverTemp,
        ),
      );
      expect(saved.id, lessThan(0));
      expect(saved.bookingReferenceId, temp);
      expect(saved.driverReferenceId, driverTemp);
      final edited = await request.saveChassis(
        saved.copyWith(name: 'Edited offline'),
        previousBookingId: temp,
      );
      expect(edited.id, saved.id);
      expect(edited.submissionKey, saved.submissionKey);
      expect(edited.createdAt, saved.createdAt);
      final queued = await queue.readQueuedCollectionDocuments(
        collectionKey: 'chassis',
      );
      expect(
        queued.any(
          (doc) =>
              doc['name'] == 'Edited offline' &&
              doc['current_booking_id'] == temp,
        ),
        true,
      );
      expect((await db.collection('chassis').get()).docs, isEmpty);
    },
  );
  test(
    'legacy integer and string IDs retain numeric storage and numeric accessors',
    () {
      for (final value in [7, '7']) {
        final chassis = Chassis.fromMap({
          'id': 1,
          'current_booking_id': value,
          'current_driver_id': value,
        });
        expect(chassis.currentBookingId, 7);
        expect(chassis.bookingReferenceId, '7');
        expect(chassis.currentDriverId, 7);
        expect(chassis.driverReferenceId, '7');
        expect(chassis.toMap()['current_booking_id'], 7);
        expect(chassis.toMap()['current_driver_id'], 7);
      }
    },
  );
  test(
    'temporary references survive JSON restart, edits, display and explicit clearing',
    () {
      final restored = Chassis.fromMap(
        jsonDecode(jsonEncode(pendingChassis().toMap())),
      );
      final edited = restored.copyWith(name: 'Edited');
      expect(edited.bookingReferenceId, temp);
      expect(edited.driverReferenceId, driverTemp);
      expect(edited.currentBookingId, isNull);
      expect(edited.dropdownLabel(), contains(temp));
      expect(edited.copyWith(currentBookingId: 9).bookingReferenceId, '9');
      expect(
        edited.copyWith(clearCurrentBookingId: true).bookingReferenceId,
        isNull,
      );
      expect(
        edited.copyWith(clearCurrentDriverId: true).driverReferenceId,
        isNull,
      );
      expect(edited.toMap()['created_at'], actionAt.toIso8601String());
    },
  );
  test(
    'restart replays new driver, new booking and chassis with correct numeric links and action time',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final restored = Chassis.fromMap(
        jsonDecode(jsonEncode(pendingChassis().toMap())),
      );
      await replay(db, backend, [
        {
          'id': 'driver_create',
          'kind': 'collectionDocumentCreate',
          'target_id': driverTemp,
          'collection_key': 'users',
          'payload': {
            'id': driverTemp,
            'submission_key': 'new_driver',
            'role': 'driver',
            'name': 'Offline driver',
          },
          'created_at': actionAt.toIso8601String(),
          'retry_count': 0,
          'is_blocked': false,
        },
        {
          'id': 'booking_create',
          'kind': 'bookingCreate',
          'target_id': temp,
          'collection_key': 'bookings',
          'payload': booking()..['submission_key'] = key,
          'created_at': actionAt.toIso8601String(),
          'retry_count': 0,
          'is_blocked': false,
        },
        chassisEntry(restored),
      ]);
      expect(await backend.readStringList(storageKey), isEmpty);
      final saved = (await db.collection('chassis').doc('1').get()).data()!;
      expect(saved['current_booking_id'], 1);
      expect(saved['current_driver_id'], 1);
      expect(saved['created_at'], actionAt.toIso8601String());
      expect(saved['updated_at'], actionAt.toIso8601String());
      expect(
        (await db.collection('bookings').doc('1').get()).data()!['chassis_id'],
        '1',
      );
      expect(
        (await db.collection('users').doc('1').get()).data()!['name'],
        'Offline driver',
      );
    },
  );
  test(
    'legacy provisional chassis deletion resolves its own create and preserves occupied ID',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      await db.collection('chassis').doc('5').set({
        'id': 5,
        'name': 'Existing server chassis',
      });
      final create = chassisEntry(
        pendingChassis().copyWith(
          id: 5,
          clearCurrentBookingId: true,
          clearCurrentDriverId: true,
        ),
      );
      (create['payload'] as Map)['provisional_create'] = true;
      await replay(db, backend, [
        create,
        {
          'id': 'delete',
          'kind': 'chassisDelete',
          'target_id': '5',
          'collection_key': 'chassis',
          'payload': {'requires_create_resolution': true},
          'created_at': actionAt.toIso8601String(),
          'retry_count': 0,
          'is_blocked': false,
        },
      ]);
      expect(
        (await db.collection('chassis').doc('5').get()).data()!['name'],
        'Existing server chassis',
      );
      expect((await db.collection('chassis').get()).docs, hasLength(1));
      expect(await backend.readStringList(storageKey), isEmpty);
    },
  );
  test(
    'unresolved provisional delete cannot delete an occupied numeric chassis',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      await db.collection('chassis').doc('5').set({'id': 5, 'name': 'Keep'});
      await replay(db, backend, [
        {
          'id': 'delete',
          'kind': 'chassisDelete',
          'target_id': '5',
          'collection_key': 'chassis',
          'payload': {'requires_create_resolution': true},
          'created_at': actionAt.toIso8601String(),
          'retry_count': 0,
          'is_blocked': false,
        },
      ]);
      expect(
        (await db.collection('chassis').doc('5').get()).data()!['name'],
        'Keep',
      );
      expect(await backend.readStringList(storageKey), hasLength(1));
    },
  );
  test(
    'another device chassis edit blocks stale assignment without touching either booking',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      await db.collection('chassis').doc('5').set({
        'id': 5,
        'name': 'Remote edit',
        'current_booking_id': 8,
        'updated_at': '2026-09-03T00:00:00Z',
      });
      await db.collection('bookings').doc('8').set({
        'id': '8',
        'chassis_id': '5',
      });
      await db.collection('bookings').doc('9').set({'id': '9'});
      final pending = pendingChassis().copyWith(
        id: 5,
        currentBookingId: 9,
        clearCurrentDriverId: true,
      );
      await replay(db, backend, [
        chassisEntry(pending, base: '2026-09-01T00:00:00Z', previous: '8'),
      ]);
      expect(
        (await db.collection('chassis').doc('5').get()).data()!['name'],
        'Remote edit',
      );
      expect(
        (await db.collection('bookings').doc('8').get()).data()!['chassis_id'],
        '5',
      );
      expect(
        (await db.collection('bookings').doc('9').get()).data()!.containsKey(
          'chassis_id',
        ),
        false,
      );
      expect(
        jsonDecode(
          (await backend.readStringList(storageKey)).single,
        )['is_blocked'],
        true,
      );
    },
  );
  test(
    'switching account during local queue write keeps action in originating account',
    () async {
      final prefs = createAuthStorageBackend();
      await prefs.initialize();
      await prefs.writeString('paltranco_current_user_id', 'A');
      final backend = _PausingBackend();
      final service = OfflineMutationQueueService(
        firestore: MergeAwareFirestore(),
        backend: backend,
      );
      await service.initialize();
      await service.flushPendingMutations();
      backend.pauseNextRead = true;
      final saving = service.queueCollectionDocumentUpsert(
        collectionKey: 'users',
        documentId: 'offline_users_unresolved',
        document: {'id': 'offline_users_unresolved', 'name': 'A action'},
      );
      await backend.readStarted.future;
      await prefs.writeString('paltranco_current_user_id', 'B');
      backend.release.complete();
      await saving;
      await service.flushPendingMutations();
      expect(
        await backend.readStringList('offline_mutation_queue_v1::A'),
        hasLength(1),
      );
      expect(
        await backend.readStringList('offline_mutation_queue_v1::B'),
        isEmpty,
      );
    },
  );
}

class _PausingBackend extends MemoryBackend {
  bool pauseNextRead = false;
  final readStarted = Completer<void>();
  final release = Completer<void>();
  @override
  Future<List<String>> readStringList(String key) async {
    final result = await super.readStringList(key);
    if (pauseNextRead) {
      pauseNextRead = false;
      readStarted.complete();
      await release.future;
    }
    return result;
  }
}
