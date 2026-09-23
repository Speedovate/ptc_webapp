import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';

class MemoryStorage implements BookingStorageBackend {
  final data = <String, List<String>>{};
  @override
  Future<void> initialize() async {}
  @override
  Future<List<String>> readStringList(String key) async => [...?data[key]];
  @override
  Future<void> writeStringList(String key, List<String> values) async {
    data[key] = [...values];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.writeString('paltranco_current_user_id', 'manager');
    await auth.remove('paltranco_known_session_user_ids');
  });
  tearDown(() async {
    await createAuthStorageBackend().remove('paltranco_current_user_id');
  });
  test(
    'incident counts and rating rules persist offline and sync original action times',
    () async {
      var online = false;
      final backend = MemoryStorage();
      final db = FakeFirebaseFirestore();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      final document = <String, dynamic>{
        'id': 'NA_settings',
        'make_id': '4',
        'kind': 'settings',
        'updated_at': '2026-09-22T01:00:00Z',
        'user_incident_counts': {
          '13': {
            '2026-09-19': {
              'complaints': 1,
              'accidents': 0,
              'user_id': '13',
              'user_role': 'driver',
              'recorded_at': '2026-09-22T01:00:00Z',
            },
          },
          '18': {
            '2026-09-19': {
              'complaints': 0,
              'accidents': 1,
              'user_id': '18',
              'user_role': 'helper',
              'recorded_at': '2026-09-22T01:00:00Z',
            },
          },
        },
        'rating_rules': {
          'target_percent': 40,
          'gross_satisfactory_min': 40,
          'gross_excellent_min': 51,
        },
        'incident_counts': {
          '2026-09-19': {
            'complaints': 1,
            'accidents': 0,
            'recorded_at': '2026-09-22T01:00:00Z',
            'recorded_by': 'manager',
          },
        },
      };
      await queue.saveCollectionDocumentOnlineFirst(
        collectionKey: 'pm_kpi_records',
        documentId: 'NA_settings',
        document: document,
      );
      final restored = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      expect(await restored.readPendingItems('manager'), hasLength(1));
      online = true;
      await restored.flushPendingMutations();
      await restored.flushPendingMutations();
      expect(
        (await db.collection('pm_kpi_records').doc('NA_settings').get()).data(),
        document,
      );
      expect(await restored.readPendingItems('manager'), isEmpty);
    },
  );
  test(
    'KPI offline action syncs once, preserving original date and no numeric reservation',
    () async {
      var online = false;
      final db = FakeFirebaseFirestore();
      final service = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryStorage(),
        isOnline: () => online,
      );
      final document = {
        'id': 'NA_2026-09-01',
        'make_id': '4',
        'day': '2026-09-01',
        'fuel': 1500,
        'updated_at': '2026-09-02T01:00:00Z',
      };
      await service.queueCollectionDocumentUpsert(
        collectionKey: 'pm_kpi_records',
        documentId: document['id']! as String,
        document: document,
      );
      expect((await db.collection('pm_kpi_records').get()).docs, isEmpty);
      expect(await service.readPendingItems('other-account'), isEmpty);
      expect(
        (await service.readPendingItems('manager')).single.recordLabel,
        contains('PM KPI'),
      );
      online = true;
      await service.flushPendingMutations();
      await service.flushPendingMutations();
      expect((await db.collection('pm_kpi_records').get()).docs, hasLength(1));
      expect(
        (await db.collection('pm_kpi_records').doc('NA_2026-09-01').get())
            .data(),
        document,
      );
      expect(await service.readPendingItems('manager'), isEmpty);
      expect((await db.collection('manage_id').get()).docs, isEmpty);
    },
  );
  test(
    'concurrent first save never overwrites another manager record',
    () async {
      var online = false;
      final db = FakeFirebaseFirestore();
      final service = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryStorage(),
        isOnline: () => online,
      );
      const id = 'NA_2026-09-01';
      await service.queueCollectionDocumentUpsert(
        collectionKey: 'pm_kpi_records',
        documentId: id,
        document: {'id': id, 'fuel': 100, 'updated_at': '2026-09-02T01:00:00Z'},
      );
      await db.collection('pm_kpi_records').doc(id).set({
        'id': id,
        'fuel': 200,
        'updated_at': '2026-09-02T02:00:00Z',
      });
      online = true;
      await service.flushPendingMutations();
      expect(
        (await db.collection('pm_kpi_records').doc(id).get()).data()!['fuel'],
        200,
      );
      expect(
        (await service.readPendingItems('manager')).single.isBlocked,
        isTrue,
      );
    },
  );
  test('stale KPI edit is blocked; normal versioned edit succeeds', () async {
    var online = false;
    final db = FakeFirebaseFirestore();
    final service = OfflineMutationQueueService(
      firestore: db,
      backend: MemoryStorage(),
      isOnline: () => online,
    );
    const id = 'NA_settings';
    await db.collection('pm_kpi_records').doc(id).set({
      'id': id,
      'threshold': 10000,
      'updated_at': '2026-09-01T00:00:00Z',
    });
    await service.queueCollectionDocumentUpsert(
      collectionKey: 'pm_kpi_records',
      documentId: id,
      baseUpdatedAt: '2026-09-01T00:00:00Z',
      document: {
        'id': id,
        'threshold': 5000,
        'updated_at': '2026-09-02T00:00:00Z',
      },
    );
    online = true;
    await service.flushPendingMutations();
    expect(
      (await db.collection('pm_kpi_records').doc(id).get())
          .data()!['threshold'],
      5000,
    );
    online = false;
    await service.queueCollectionDocumentUpsert(
      collectionKey: 'pm_kpi_records',
      documentId: id,
      baseUpdatedAt: '2026-09-01T00:00:00Z',
      document: {
        'id': id,
        'threshold': 2000,
        'updated_at': '2026-09-03T00:00:00Z',
      },
    );
    online = true;
    await service.flushPendingMutations();
    expect(
      (await db.collection('pm_kpi_records').doc(id).get())
          .data()!['threshold'],
      5000,
    );
    expect(
      (await service.readPendingItems('manager')).single.isBlocked,
      isTrue,
    );
  });
}
