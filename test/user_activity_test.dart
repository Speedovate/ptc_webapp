import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('online activity only patches timestamp for every role', () async {
    final db = MergeAwareFirestore();
    final backend = MemoryBackend();
    final queue = OfflineMutationQueueService(
      backend: backend,
      firestore: db,
      isOnline: () => true,
    );
    for (final role in [
      'Admin',
      'Dispatcher',
      'Driver',
      'Helper',
      'Investor',
      'Client',
      'Manager',
    ]) {
      final ref = db.collection('users').doc(role);
      final original = {
        'role': role,
        'name': 'Existing name',
        'driver_id': '17',
        'updated_at': '2026-10-01T00:00:00.000Z',
      };
      await ref.set(original);
      await queue.recordUserActivity(role, DateTime.utc(2026, 10, 2));
      expect((await ref.get()).data(), {
        ...original,
        'updated_at': '2026-10-02T00:00:00.000Z',
      });
    }
    expect(
      await backend.readStringList('offline_mutation_queue_v1::signed_out'),
      isEmpty,
    );
  });

  test(
    'offline openings coalesce, persist across restart, preserve action time and newer profile',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final ref = db.collection('users').doc('13');
      await ref.set({
        'name': 'Original',
        'updated_at': '2026-10-01T00:00:00.000Z',
      });
      final offline = OfflineMutationQueueService(
        backend: backend,
        firestore: db,
        isOnline: () => false,
      );
      await offline.recordUserActivity('13', DateTime.utc(2026, 10, 2, 8));
      await offline.recordUserActivity('13', DateTime.utc(2026, 10, 2, 9));
      expect(
        await backend.readStringList('offline_mutation_queue_v1::signed_out'),
        hasLength(1),
      );
      await ref.update({'name': 'Changed remotely'});
      final online = OfflineMutationQueueService(
        backend: backend,
        firestore: db,
        isOnline: () => true,
      );
      await online.initialize();
      await online.flushPendingMutations();
      expect((await ref.get()).data(), {
        'name': 'Changed remotely',
        'updated_at': '2026-10-02T09:00:00.000Z',
      });
      expect(
        await backend.readStringList('offline_mutation_queue_v1::signed_out'),
        isEmpty,
      );
      await online.recordUserActivity('13', DateTime.utc(2026, 10, 2, 7));
      expect(
        (await ref.get()).data()!['updated_at'],
        '2026-10-02T09:00:00.000Z',
      );
    },
  );

  test(
    'pending profile edit is applied before activity without losing fields',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      var online = false;
      final queue = OfflineMutationQueueService(
        backend: backend,
        firestore: db,
        isOnline: () => online,
      );
      final ref = db.collection('users').doc('13');
      final original = {
        'id': '13',
        'name': 'Old name',
        'updated_at': '2026-10-01T00:00:00.000Z',
      };
      await ref.set(original);
      await queue.queueUserUpsert(
        userId: '13',
        document: {
          ...original,
          'name': 'Offline edit',
          'updated_at': '2026-10-02T08:00:00.000Z',
        },
        baseUpdatedAt: original['updated_at'],
        baseDocument: original,
      );
      await queue.recordUserActivity('13', DateTime.utc(2026, 10, 2, 9));
      online = true;
      await queue.flushPendingMutations();
      expect((await ref.get()).data()!['name'], 'Offline edit');
      expect(
        (await ref.get()).data()!['updated_at'],
        '2026-10-02T09:00:00.000Z',
      );
      expect(
        await backend.readStringList('offline_mutation_queue_v1::signed_out'),
        isEmpty,
      );
    },
  );

  test('activity does not recreate deleted users', () async {
    final db = MergeAwareFirestore();
    final queue = OfflineMutationQueueService(
      backend: MemoryBackend(),
      firestore: db,
      isOnline: () => true,
    );
    await queue.recordUserActivity('deleted', DateTime.utc(2026, 10, 2));
    expect((await db.collection('users').doc('deleted').get()).exists, isFalse);
  });
}
