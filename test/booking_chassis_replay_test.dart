import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final expectations = {
    'delivered': ('loaded', 10, null),
    'check': ('loaded', 10, null),
    'empty': ('empty', 10, null),
    'return': ('return', 10, 8),
    'confirm': ('ready', null, null),
    'cancelled': ('ready', null, null),
  };
  for (final stage in expectations.keys) {
    test(
      'coalesced offline $stage and same-stage retry preserve chassis lifecycle',
      () async {
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        var online = false;
        final queue = OfflineMutationQueueService(
          firestore: db,
          backend: backend,
          isOnline: () => online,
        );
        final original = <String, dynamic>{
          'id': '10',
          'chassis_id': '3',
          'driver_id': '7',
          'client_status': 'ongoing',
          'updated_at': '2026-09-01T00:00:00Z',
        };
        await db.collection('bookings').doc('10').set(original);
        await db.collection('chassis').doc('3').set({
          'id': 3,
          'current_status': 'loaded',
          'current_booking_id': 10,
          'current_driver_id': 7,
        });
        final delivered = {
          ...original,
          'client_status': 'delivered',
          'updated_at': '2026-09-01T01:00:00Z',
        };
        final finalDoc = {
          ...delivered,
          'client_status': stage,
          'driver_status': stage,
          'helper_status': stage,
          'updated_at': '2026-09-01T02:00:00Z',
          'status_outputs': {
            'return': {
              'submitted_at': '2026-09-01T01:30:00Z',
              'fields': {'return_driver_id': '8', 'chassis_location': 'Depot'},
            },
          },
        };
        await queue.queueCollectionDocumentUpsert(
          collectionKey: 'bookings',
          documentId: '10',
          document: delivered,
          baseUpdatedAt: original['updated_at'] as String,
        );
        await queue.queueCollectionDocumentUpsert(
          collectionKey: 'bookings',
          documentId: '10',
          document: finalDoc,
          baseUpdatedAt: delivered['updated_at'] as String,
        );
        expect(await backend.readStringList(storageKey), hasLength(1));
        online = true;
        await queue.flushPendingMutations();
        for (var attempt = 0; attempt < 2; attempt++) {
          final chassis = (await db.collection('chassis').doc('3').get())
              .data()!;
          final expected = expectations[stage]!;
          expect(chassis['current_status'], expected.$1);
          expect(chassis['current_booking_id'], expected.$2);
          expect(chassis['current_driver_id'], expected.$3);
          expect(chassis['updated_at'], finalDoc['updated_at']);
          if (stage == 'cancelled') {
            expect(chassis['location'], 'Garage');
          }
          expect(
            (await db.collection('bookings').doc('10').get())
                .data()!['client_status'],
            stage,
          );
          if (stage == 'empty') {
            expect(chassis['location'], 'Depot');
          }
          if (attempt == 0) {
            await queue.queueCollectionDocumentUpsert(
              collectionKey: 'bookings',
              documentId: '10',
              document: finalDoc,
              baseUpdatedAt: finalDoc['updated_at'] as String,
            );
            await queue.flushPendingMutations();
          }
        }
        expect(await backend.readStringList(storageKey), isEmpty);
      },
    );
  }
  test(
    'completed booking edit cannot clear or reclaim a reassigned chassis',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      var online = false;
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      final document = <String, dynamic>{
        'id': '10',
        'chassis_id': '3',
        'driver_id': '7',
        'client_status': 'confirm',
        'updated_at': '2026-09-01T00:00:00Z',
      };
      final assigned = <String, dynamic>{
        'id': 3,
        'current_status': 'loaded',
        'current_booking_id': 99,
        'current_driver_id': 88,
      };
      await db.collection('bookings').doc('10').set(document);
      await db.collection('chassis').doc('3').set(assigned);
      await queue.queueCollectionDocumentUpsert(
        collectionKey: 'bookings',
        documentId: '10',
        document: {
          ...document,
          'notes': 'edited',
          'updated_at': '2026-09-01T01:00:00Z',
        },
        baseUpdatedAt: document['updated_at'] as String,
      );
      online = true;
      await queue.flushPendingMutations();
      expect(await backend.readStringList(storageKey), isEmpty);
      expect((await db.collection('chassis').doc('3').get()).data(), assigned);
      expect(
        (await db.collection('bookings').doc('10').get()).data()!['notes'],
        'edited',
      );
      expect(await backend.readStringList(storageKey), isEmpty);
    },
  );
}
