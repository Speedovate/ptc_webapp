import 'dart:convert';
import 'support/merge_aware_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/offline_reference_mapper.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, replay, storageKey;

Map<String, dynamic> create(
  String resource,
  String temp, {
  Map<String, dynamic> data = const {},
}) => {
  'id': 'queue_$temp',
  'kind': 'collectionDocumentCreate',
  'target_id': temp,
  'collection_key': resource,
  'payload': {
    'id': temp,
    'submission_key': 'attempt_$temp',
    'created_at': '2026-09-01T00:00:00Z',
    'updated_at': '2026-09-02T00:00:00Z',
    ...data,
  },
  'created_at': '2026-09-02T00:00:00Z',
  'retry_count': 0,
  'is_blocked': false,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'bulk billing preserves unrelated queued work and replays original action time',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      await db.collection('bookings').doc('2').set({
        'id': '2',
        'updated_at': '2026-09-01T00:00:00Z',
      });
      await backend.writeStringList(storageKey, [
        jsonEncode({
          'id': 'unrelated',
          'kind': 'bookingBillingStatusUpdate',
          'target_id': '1',
          'payload': {'billing_status': 'paid'},
          'created_at': '2026-09-02T00:00:00Z',
          'retry_count': 0,
          'is_blocked': true,
        }),
      ]);
      final service = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
      );
      final before = DateTime.now().toUtc();
      await service.queueBookingBillingStatusUpdates({'2': 'paid'});
      await service.flushPendingMutations();
      await service.flushPendingMutations();
      final remaining = (await backend.readStringList(
        storageKey,
      )).map(jsonDecode).toList();
      expect(remaining.any((entry) => entry['id'] == 'unrelated'), true);
      expect(
        (await db.collection('bookings').doc('2').get())
            .data()!['billing_status'],
        'paid',
      );
      expect(
        DateTime.parse(
          (await db.collection('bookings').doc('2').get())
              .data()!['updated_at'],
        ).isBefore(before),
        false,
      );
    },
  );
  for (final resource in [
    'users',
    'vehicle_makes',
    'vehicle_types',
    'vehicle_sizes',
    'status_forms',
    'status_fields',
    'statuses',
  ]) {
    test(
      '$resource create skips occupied ID, preserves dates, and retry preserves later edit',
      () async {
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        await db.collection(resource).doc('1').set({
          'id': '1',
          'name': 'Existing',
        });
        final queued = create(resource, 'offline_${resource}_test');
        await replay(db, backend, [queued]);
        final documents = await db.collection(resource).get();
        expect(documents.docs, hasLength(2));
        expect(
          (await db.collection(resource).doc('1').get()).data()!['name'],
          'Existing',
        );
        final saved = db.collection(resource).doc('2');
        expect(
          (await saved.get()).data()!['updated_at'],
          '2026-09-02T00:00:00Z',
        );
        expect(
          (await saved.get()).data()!['created_at'],
          '2026-09-01T00:00:00Z',
        );
        await saved.update({'name': 'Later edit'});
        await replay(db, backend, [queued]);
        expect((await saved.get()).data()!['name'], 'Later edit');
        expect((await db.collection(resource).get()).docs, hasLength(2));
        expect(await backend.readStringList(storageKey), isEmpty);
      },
    );
  }
  for (final resource in [
    'users',
    'vehicle_makes',
    'vehicle_types',
    'vehicle_sizes',
    'status_forms',
    'status_fields',
    'statuses',
    'role_access',
  ]) {
    test('$resource update retains ID and offline action date', () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final id = resource == 'role_access' ? 'dispatcher' : '7';
      await db.collection(resource).doc(id).set({
        'id': id,
        'updated_at': '2026-09-01T00:00:00Z',
      });
      await replay(db, backend, [
        {
          'id': 'update',
          'kind': 'collectionDocumentUpsert',
          'target_id': id,
          'collection_key': resource,
          'payload': {
            'id': id,
            'name': 'Edited offline',
            'updated_at': '2026-09-02T00:00:00Z',
          },
          'base_updated_at': '2026-09-01T00:00:00Z',
          'created_at': '2026-09-02T00:00:00Z',
          'retry_count': 0,
          'is_blocked': false,
        },
      ]);
      expect((await db.collection(resource).get()).docs, hasLength(1));
      final saved = (await db.collection(resource).doc(id).get()).data()!;
      expect(saved['id'], id);
      expect(saved['updated_at'], '2026-09-02T00:00:00Z');
      expect(saved['name'], 'Edited offline');
    });
  }
  test('stale resource update cannot overwrite newer server data', () async {
    final db = MergeAwareFirestore();
    final backend = MemoryBackend();
    await db.collection('users').doc('7').set({
      'id': '7',
      'name': 'Remote',
      'updated_at': '2026-09-03T00:00:00Z',
    });
    await replay(db, backend, [
      {
        'id': 'update',
        'kind': 'collectionDocumentUpsert',
        'target_id': '7',
        'collection_key': 'users',
        'payload': {
          'id': '7',
          'name': 'Offline',
          'updated_at': '2026-09-02T00:00:00Z',
        },
        'base_updated_at': '2026-09-01T00:00:00Z',
        'created_at': '2026-09-02T00:00:00Z',
        'retry_count': 0,
        'is_blocked': false,
      },
    ]);
    expect(
      (await db.collection('users').doc('7').get()).data()!['name'],
      'Remote',
    );
    expect(
      jsonDecode(
        (await backend.readStringList(storageKey)).single,
      )['is_blocked'],
      true,
    );
  });
  test(
    'resource aliases survive restart and stay isolated by user scope',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      const temp = 'offline_users_restart';
      await replay(db, backend, [create('users', temp)]);
      final restarted = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryBackend(),
      );
      expect(
        await restarted.resolveResourceReferences({
          'user_id': temp,
        }, scope: 'signed_out'),
        {'user_id': '1'},
      );
      await expectLater(
        restarted.resolveResourceReferences({
          'user_id': temp,
        }, scope: 'another_user'),
        throwsStateError,
      );
    },
  );
  test(
    'concurrent distinct creates sharing descriptive key preserve both records',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final service = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
      );
      await Future.wait([
        for (final id in ['offline_users_first', 'offline_users_second'])
          service.queueOfflineCollectionDocumentCreate(
            collectionKey: 'users',
            provisionalId: id,
            submissionKey: 'same-description',
            document: {
              'id': id,
              'name': id,
              'updated_at': '2026-09-01T00:00:00Z',
            },
          ),
      ]);
      await service.flushPendingMutations();
      await service.flushPendingMutations();
      expect((await db.collection('users').get()).docs, hasLength(2));
      expect(await backend.readStringList(storageKey), isEmpty);
    },
  );
  test('chassis create alias resolves dependent booking reference', () async {
    final db = MergeAwareFirestore();
    final backend = MemoryBackend();
    await db.collection('bookings').doc('4').set({
      'id': '4',
      'updated_at': '2026-09-01T00:00:00Z',
    });
    await replay(db, backend, [
      {
        'id': 'chassis_create',
        'kind': 'chassisAssignment',
        'target_id': '-100',
        'collection_key': 'chassis',
        'payload': {
          'submission_key': 'chassis-attempt',
          'provisional_create': true,
          'chassis': {
            'id': -100,
            'name': 'Offline chassis',
            'updated_at': '2026-09-02T00:00:00Z',
          },
        },
        'created_at': '2026-09-02T00:00:00Z',
        'retry_count': 0,
        'is_blocked': false,
      },
      {
        'id': 'booking_edit',
        'kind': 'collectionDocumentUpsert',
        'target_id': '4',
        'collection_key': 'bookings',
        'payload': {
          'id': '4',
          'chassis_id': '-100',
          'updated_at': '2026-09-03T00:00:00Z',
        },
        'base_updated_at': '2026-09-01T00:00:00Z',
        'created_at': '2026-09-03T00:00:00Z',
        'retry_count': 0,
        'is_blocked': false,
      },
    ]);
    expect(
      (await db.collection('bookings').doc('4').get()).data()!['chassis_id'],
      '1',
    );
    expect(
      (await db.collection('chassis').doc('1').get()).data()!['name'],
      'Offline chassis',
    );
    expect(await backend.readStringList(storageKey), isEmpty);
  });
  test(
    'field create remaps form references and override keys, never text',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      const temp = 'offline_status_fields_example';
      await replay(db, backend, [
        create('status_fields', temp),
        create(
          'status_forms',
          'offline_status_forms_example',
          data: {
            'field_ids': [temp],
            'field_overrides': {
              temp: {'label': temp},
            },
            'blocked_message': temp,
            'notes': temp,
          },
        ),
      ]);
      final form = (await db.collection('status_forms').doc('1').get()).data()!;
      expect(form['field_ids'], ['1']);
      expect(form['field_overrides'], {
        '1': {'label': temp},
      });
      expect(form['blocked_message'], temp);
      expect(form['notes'], temp);
    },
  );
  test(
    'unresolved foreign key remains queued instead of writing a broken reference',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      await replay(db, backend, [
        create(
          'vehicle_makes',
          'offline_vehicle_makes_x',
          data: {'driver_id': 'offline_users_missing'},
        ),
      ]);
      expect((await db.collection('vehicle_makes').get()).docs, isEmpty);
      expect(await backend.readStringList(storageKey), hasLength(1));
    },
  );
  test(
    'legacy occupied reservation blocks create rather than overwrite',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      const temp = 'offline_users_old';
      final encoded = base64UrlEncode(utf8.encode('attempt_$temp'));
      await db.collection('manage_id').doc('users_$encoded').set({
        'document_id': '1',
      });
      await db.collection('users').doc('1').set({'id': '1', 'name': 'Keep'});
      await replay(db, backend, [create('users', temp)]);
      expect(
        (await db.collection('users').doc('1').get()).data()!['name'],
        'Keep',
      );
      final remaining = await backend.readStringList(storageKey);
      expect(jsonDecode(remaining.single)['is_blocked'], true);
    },
  );
  test(
    'mapper changes only owned references, preserving integer references',
    () {
      final data = OfflineReferenceMapper.mapDocument(
        {
          'chassis_id': -100,
          'notes': '-100',
          'status_outputs': {'answer': 'offline_users_x'},
          'driver_id': 'offline_users_x',
        },
        {'-100': '9', 'offline_users_x': '8'},
      );
      expect(data['chassis_id'], 9);
      expect(data['driver_id'], '8');
      expect(data['notes'], '-100');
      expect(data['status_outputs'], {'answer': 'offline_users_x'});
    },
  );
}
