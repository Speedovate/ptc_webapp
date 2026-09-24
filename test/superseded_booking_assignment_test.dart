import 'dart:convert';
import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/booking_status_continuation.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;

Map<String, dynamic> clone(Map value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/superseded_booking_assignment.json',
            ).readAsStringSync(),
          )
          as Map;
  final server = clone(fixture['server']);
  final source = clone(fixture['source']);
  final pending = {...clone(fixture['pending']), 'id': '120'};
  test(
    'actual report preserves latest schedule, photo, amount and original action time; replay is identical',
    () {
      final result = reconcileBookingHistory(
        server,
        pending,
        baseUpdatedAt: source['updated_at'],
      );
      expect(result, isNotNull);
      expect(
        {...result!}..remove('status_outputs'),
        {...server}..remove('status_outputs'),
      );
      expect(result['status_outputs'], {
        ...server['status_outputs'],
        'pending__1790042535551000':
            pending['status_outputs']['pending__1790042535551000'],
      });
      expect(
        reconcileBookingHistory(
          result,
          pending,
          baseUpdatedAt: source['updated_at'],
        ),
        result,
      );
    },
  );
  test(
    'rejects different crew, actor, history, unknown fields and non-later assignment',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (p) => p['driver_id'] = '17',
        (p) => p['client_id'] = 'other',
        (p) =>
            p['status_outputs']['pending__1790042535551000']['submitted_by'] =
                'other',
        (p) =>
            p['status_outputs']['pending__1790042535551000']['fields']['amount'] =
                1,
        (p) =>
            p['status_outputs']['book__1790042459964000']['fields']['van_number'] =
                'other',
        (p) {
          p['updated_at'] = '2026-09-23T10:00:00';
          p['status_outputs']['pending__1790042535551000']['submitted_at'] =
              p['updated_at'];
        },
      ]) {
        final changed = clone(pending);
        mutate(changed);
        expect(
          reconcileBookingHistory(
            server,
            changed,
            baseUpdatedAt: source['updated_at'],
          ),
          isNull,
        );
      }
    },
  );
  for (final conflict in [false, true]) {
    test('persisted already-rechecked create recovery, unsafe=$conflict', () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      await db.collection('bookings').doc('120').set(server);
      // An unrelated current chassis owner must never be touched by history repair.
      final chassis = {
        'id': '9',
        'current_status': 'loaded',
        'current_booking_id': '999',
      };
      await db.collection('chassis').doc('9').set(chassis);
      await db
          .collection('manage_id')
          .doc(BookingIdResolver.reservationId(pending['submission_key']))
          .set({
            'resource_key': 'bookings',
            'submission_key': pending['submission_key'],
            'document_id': '120',
            'source_document': source,
          });
      final payload = clone(fixture['pending']);
      if (conflict) payload['driver_id'] = 'different';
      await backend.writeStringList(storageKey, [
        jsonEncode({
          'id': 'reported-create',
          'kind': 'bookingCreate',
          'target_id': payload['id'],
          'collection_key': 'bookings',
          'payload': payload,
          'created_at': '2026-09-22T02:01:08.662Z',
          'retry_count': 1,
          'is_blocked': true,
          'booking_history_rechecked': true,
          'last_error':
              'Bad state: Sync conflict: booking was edited while its create was syncing. Review the pending edit.',
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
      expect(saved.length, conflict ? 1 : 0);
      if (conflict) {
        expect(
          jsonDecode(saved.single)['booking_assignment_history_rechecked'],
          true,
        );
        expect(jsonDecode(saved.single)['is_blocked'], true);
        expect(
          (await db.collection('bookings').doc('120').get()).data(),
          server,
        );
      } else {
        expect(
          (await db.collection('bookings').doc('120').get()).data(),
          reconcileBookingHistory(
            server,
            pending,
            baseUpdatedAt: source['updated_at'],
          ),
        );
      }
      expect((await db.collection('chassis').doc('9').get()).data(), chassis);
      expect((await db.collection('bookings').get()).docs, hasLength(1));
      await queue.flushPendingMutations();
      expect(await backend.readStringList(storageKey), saved);
    });
  }
}
