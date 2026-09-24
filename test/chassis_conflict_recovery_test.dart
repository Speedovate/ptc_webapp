import 'dart:convert';
import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final report =
      jsonDecode(
            File(
              'test/fixtures/booking_83_chassis_conflict.json',
            ).readAsStringSync(),
          )
          as Map;
  for (final occupied in [true, false]) {
    test(
      'reported Start Delivery rechecks once; chassis occupied=$occupied',
      () async {
        final pending = Map<String, dynamic>.from(report['pending_payload']);
        final server = {
          ...pending,
          'client_status': 'assigned',
          'driver_status': 'assigned',
          'helper_status': 'assigned',
          'updated_at': report['base_updated_at'],
          'status_outputs': Map<String, dynamic>.from(pending['status_outputs'])
            ..remove('assigned__1789945302811000'),
        };
        final db = FakeFirebaseFirestore();
        await db.collection('bookings').doc('83').set(server);
        final chassis = {
          'id': '9',
          'current_status': occupied ? 'loaded' : 'ready',
          'current_booking_id': occupied ? '999' : null,
          'location': 'Garage',
        };
        await db.collection('chassis').doc('9').set(chassis);
        final owner = {
          'id': '999',
          'client_status': 'ongoing',
          'chassis_id': '9',
          'updated_at': '2026-09-24T10:00:00',
        };
        await db.collection('bookings').doc('999').set(owner);
        final backend = MemoryBackend();
        await backend.writeStringList(storageKey, [
          jsonEncode({
            'id': report['queue_entry_id'],
            'kind': 'collectionDocumentUpsert',
            'target_id': '83',
            'collection_key': 'bookings',
            'payload': pending,
            'base_updated_at': report['base_updated_at'],
            'created_at': report['action_at'],
            'retry_count': 1,
            'is_blocked': true,
            'last_error':
                'Bad state: Sync conflict: chassis is active on another booking. Its advance reservation is preserved; release the active booking before starting this one.',
          }),
        ]);
        final queue = OfflineMutationQueueService(
          firestore: db,
          backend: backend,
          isOnline: () => true,
        );
        await queue.initialize();
        await queue.flushPendingMutations();
        final saved = await backend.readStringList(storageKey);
        if (occupied) {
          expect(saved, hasLength(1));
          final entry = jsonDecode(saved.single);
          expect(entry['is_blocked'], true);
          expect(entry['chassis_conflict_rechecked'], true);
          expect(entry['payload'], pending);
          expect(entry['error_diagnostics'], contains('server_chassis'));
          expect(
            entry['error_diagnostics'],
            contains('owner_booking_document'),
          );
          expect(entry['last_error'], contains('Booking 999'));
          expect(
            (await db.collection('bookings').doc('83').get()).data(),
            server,
          );
          expect(
            (await db.collection('chassis').doc('9').get()).data(),
            chassis,
          );
        } else {
          expect(saved, isEmpty);
          final actual = (await db.collection('bookings').doc('83').get())
              .data()!;
          expect(actual['client_status'], 'ongoing');
          expect(actual['updated_at'], pending['updated_at']);
          expect(actual['status_outputs'], pending['status_outputs']);
        }
        expect(
          (await db.collection('bookings').doc('999').get()).data(),
          owner,
        );
        await queue.flushPendingMutations();
        expect(await backend.readStringList(storageKey), saved);
      },
    );
  }
}
