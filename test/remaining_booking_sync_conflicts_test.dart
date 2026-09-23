import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_status_continuation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final fixtures =
      (jsonDecode(
                File(
                  'test/fixtures/remaining_booking_sync_conflicts.json',
                ).readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();
  for (final fixture in fixtures.where((f) => f['server'] != null)) {
    test(
      'reconciles reported ${fixture['target']} without losing remote edits or action times',
      () {
        final pending = Map<String, dynamic>.from(fixture['pending']);
        final server = Map<String, dynamic>.from(fixture['server']);
        final result = reconcileBookingHistory(
          server,
          pending,
          baseUpdatedAt: fixture['base_updated_at'],
          verifiedMake: {'driver_id': '13', 'helper_id': '18'},
        );
        expect(result, isNotNull);
        final outputs = result!['status_outputs'] as Map;
        for (final key in (server['status_outputs'] as Map).keys) {
          expect(outputs[key], server['status_outputs'][key]);
        }
        for (final key in (pending['status_outputs'] as Map).keys.where(
          (key) => !(server['status_outputs'] as Map).containsKey(key),
        )) {
          expect(outputs[key], pending['status_outputs'][key]);
        }
        expect(result['created_at'], pending['created_at']);
        expect(result['updated_at'], server['updated_at']);
        expect(result['client_status'], 'assigned');
      },
    );
  }
  test(
    'rejects conflicting crew, edited history, unrelated changes, and different photo',
    () {
      final f = fixtures.first;
      final original = Map<String, dynamic>.from(f['pending']);
      final server = Map<String, dynamic>.from(f['server']);
      Map<String, dynamic> clone(Map value) =>
          Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (p) => p['driver_id'] = 'other',
        (p) => p['client_id'] = 'other',
        (p) => p['status_outputs'].values.firstWhere(
          (v) => v['status_key'] == 'book',
        )['fields']['van_number'] = 'other',
        (p) => p['status_outputs'].values.firstWhere(
          (v) => v['status_key'] == 'book',
        )['fields']['waybill_photo']['size'] = 1,
      ]) {
        final pending = clone(original);
        mutate(pending);
        expect(
          reconcileBookingHistory(
            server,
            pending,
            baseUpdatedAt: f['base_updated_at'],
          ),
          isNull,
        );
      }
      final assignedServer = {...server, 'driver_id': 'another-driver'};
      expect(
        reconcileBookingHistory(
          assignedServer,
          original,
          baseUpdatedAt: f['base_updated_at'],
        ),
        isNull,
      );
    },
  );
  test(
    'device rechecks five persisted errors once and drains proven assignments',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      final entries = <String>[];
      for (final f in fixtures.where((f) => f['server'] != null)) {
        final pending = Map<String, dynamic>.from(f['pending']);
        await db
            .collection('bookings')
            .doc(pending['id'])
            .set(Map<String, dynamic>.from(f['server']));
        await db.collection('chassis').doc(pending['chassis_id']).set({
          'id': pending['chassis_id'],
          'current_status': 'ready',
        });
        entries.add(
          jsonEncode({
            'id': f['entry_id'],
            'kind': 'collectionDocumentUpsert',
            'target_id': pending['id'],
            'collection_key': 'bookings',
            'payload': pending,
            'base_updated_at': f['base_updated_at'],
            'created_at': f['action_at'],
            'retry_count': 1,
            'is_blocked': true,
            'last_error': f['error'],
            'booking_continuation_rechecked': true,
          }),
        );
      }
      await db.collection('vehicle_makes').doc('4').set({
        'driver_id': '13',
        'helper_id': '18',
      });
      await backend.writeStringList(storageKey, entries);
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      await queue.initialize();
      await queue.flushPendingMutations();
      expect(await backend.readStringList(storageKey), isEmpty);
      for (final f in fixtures.where((f) => f['server'] != null)) {
        final doc =
            (await db.collection('bookings').doc(f['pending']['id']).get())
                .data()!;
        expect(doc['client_status'], 'assigned');
        expect(doc['updated_at'], f['server']['updated_at']);
        for (final key in (f['server']['status_outputs'] as Map).keys) {
          expect(
            doc['status_outputs'][key],
            f['server']['status_outputs'][key],
          );
        }
      }
      await queue.flushPendingMutations();
      expect(await backend.readStringList(storageKey), isEmpty);
    },
  );

  test(
    'edited create resumes at its reserved ID without creating another booking',
    () async {
      final f = fixtures.last;
      final pending = Map<String, dynamic>.from(f['pending']);
      final source = Map<String, dynamic>.from(jsonDecode(jsonEncode(pending)));
      source['updated_at'] = source['created_at'];
      source['status_outputs'] = Map<String, dynamic>.from(
        source['status_outputs'],
      )..removeWhere((key, value) => value['status_key'] != 'book');
      for (final key in ['client_status', 'driver_status', 'helper_status']) {
        source[key] = 'pending';
      }
      for (final key in ['driver_id', 'helper_id', 'chassis_id']) {
        source[key] = null;
      }
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('124').set({...source, 'id': '124'});
      await db.collection('chassis').doc('9').set({
        'id': '9',
        'current_status': 'ready',
      });
      await db
          .collection('manage_id')
          .doc(BookingIdResolver.reservationId(pending['submission_key']))
          .set({
            'resource_key': 'bookings',
            'submission_key': pending['submission_key'],
            'document_id': '124',
            'source_document': source,
          });
      final backend = MemoryBackend();
      await backend.writeStringList(storageKey, [
        jsonEncode({
          'id': f['entry_id'],
          'kind': 'bookingCreate',
          'target_id': pending['id'],
          'collection_key': 'bookings',
          'payload': pending,
          'created_at': f['action_at'],
          'retry_count': 1,
          'is_blocked': true,
          'last_error': f['error'],
        }),
      ]);
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      await queue.initialize();
      await queue.flushPendingMutations();
      expect(await backend.readStringList(storageKey), isEmpty);
      final bookings = await db.collection('bookings').get();
      expect(bookings.docs, hasLength(1));
      expect(bookings.docs.single.id, '124');
      expect(
        bookings.docs.single.data()['status_outputs'],
        pending['status_outputs'],
      );
      expect(bookings.docs.single.data()['updated_at'], pending['updated_at']);
      await queue.flushPendingMutations();
      expect((await db.collection('bookings').get()).docs, hasLength(1));
    },
  );
  test(
    'unproven conflicts stay queued and are not automatically retried repeatedly',
    () async {
      final f = fixtures.first;
      final pending = {
        ...Map<String, dynamic>.from(f['pending']),
        'driver_id': 'different',
      };
      final db = FakeFirebaseFirestore();
      await db
          .collection('bookings')
          .doc('115')
          .set(Map<String, dynamic>.from(f['server']));
      final backend = MemoryBackend();
      await backend.writeStringList(storageKey, [
        jsonEncode({
          'id': f['entry_id'],
          'kind': 'collectionDocumentUpsert',
          'target_id': '115',
          'collection_key': 'bookings',
          'payload': pending,
          'created_at': f['action_at'],
          'base_updated_at': f['base_updated_at'],
          'retry_count': 1,
          'is_blocked': true,
          'last_error': f['error'],
        }),
      ]);
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      await queue.initialize();
      await queue.flushPendingMutations();
      final first = (await backend.readStringList(storageKey));
      expect(first, hasLength(1));
      final entry = jsonDecode(first.single) as Map;
      expect(entry['is_blocked'], true);
      expect(entry['booking_history_rechecked'], true);
      expect(entry['payload'], pending);
      await queue.flushPendingMutations();
      expect(await backend.readStringList(storageKey), first);
      expect(
        (await db.collection('bookings').doc('115').get()).data(),
        f['server'],
      );
    },
  );
}
