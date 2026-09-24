import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/booking_chassis_lifecycle.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'chassis_reservations_test.dart'
    show ReservationRequest, ReservationChassisRequest;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final queued in [false, true]) {
    test(
      'new Ongoing atomically detaches old active; keeps reservations/history, queued=$queued',
      () async {
        final db = MergeAwareFirestore();
        var online = false;
        final queue = OfflineMutationQueueService(
          firestore: db,
          backend: MemoryBackend(),
          isOnline: () => online,
        );
        final request = ReservationRequest(db, queue);
        const previous = '2026-09-21T00:00:00Z';
        const history = {
          'started': {
            'submitted_at': previous,
            'fields': {'chassis_id': '3'},
          },
        };
        await db.collection('chassis').doc('3').set({
          'id': 3,
          'current_booking_id': 9,
          'current_status': 'loaded',
          'updated_at': previous,
        });
        await db.collection('bookings').doc('9').set({
          'id': '9',
          'client_status': 'ongoing',
          'chassis_id': '3',
          'updated_at': previous,
          'status_outputs': history,
          'driver_id': '7',
        });
        await db.collection('bookings').doc('11').set({
          'id': '11',
          'client_status': 'assigned',
          'chassis_id': '3',
          'updated_at': previous,
        });
        final booking = Booking(
          id: '10',
          chassisId: '3',
          clientStatus: 'ongoing',
          driver: const UserModel(id: '12'),
          updatedAt: DateTime.utc(2026, 9, 22),
        );
        if (queued) {
          await queue.queueCollectionDocumentUpsert(
            collectionKey: 'bookings',
            documentId: '10',
            document: {...booking.toMap(), 'driver_id': '12'},
          );
          online = true;
          await queue.flushPendingMutations();
          expect(await queue.readPendingItems('signed_out'), isEmpty);
        } else {
          await request.saveBooking(booking);
        }
        final old = (await db.collection('bookings').doc('9').get()).data()!;
        expect(old['chassis_id'], isNull);
        expect(old['client_status'], 'ongoing');
        expect(old['driver_id'], '7');
        expect(old['status_outputs'], history);
        expect(
          (await db.collection('bookings').doc('10').get())
              .data()!['chassis_id'],
          '3',
        );
        expect(
          (await db.collection('bookings').doc('11').get())
              .data()!['chassis_id'],
          '3',
        );
        expect(
          (await db.collection('chassis').doc('3').get())
              .data()!['current_booking_id'],
          10,
        );
        if (queued) {
          await queue.flushPendingMutations();
          expect(
            (await db.collection('chassis').doc('3').get())
                .data()!['current_booking_id'],
            10,
          );
        }
      },
    );
  }
  for (final queued in [false, true]) {
    test(
      'chassis editor transfers an Ongoing booking atomically, queued=$queued',
      () async {
        final db = MergeAwareFirestore();
        var online = false;
        final queue = OfflineMutationQueueService(
          firestore: db,
          backend: MemoryBackend(),
          isOnline: () => online,
        );
        const previous = '2026-09-01T00:00:00Z';
        await db.collection('chassis').doc('3').set({
          'id': 3,
          'current_booking_id': 9,
          'current_status': 'loaded',
          'updated_at': previous,
        });
        await db.collection('bookings').doc('9').set({
          'id': '9',
          'client_status': 'ongoing',
          'chassis_id': '3',
          'updated_at': previous,
        });
        await db.collection('bookings').doc('10').set({
          'id': '10',
          'client_status': 'ongoing',
          'chassis_id': null,
          'driver_id': '12',
          'updated_at': previous,
        });
        final chassis = Chassis(
          id: 3,
          name: 'Transfer',
          isActive: true,
          currentStatus: 'ready',
          bookingReferenceId: '10',
        );
        if (queued) {
          await queue.queueChassisAssignment(
            documentId: '3',
            submissionKey: 'editor',
            isProvisionalCreate: false,
            chassisDocument: chassis.toMap(),
            previousBookingId: '9',
            nextBookingId: '10',
          );
          online = true;
          await queue.flushPendingMutations();
          expect(await queue.readPendingItems('signed_out'), isEmpty);
        } else {
          await ReservationChassisRequest(
            db,
            queue,
          ).saveChassis(chassis, previousBookingId: '9');
        }
        expect(
          (await db.collection('bookings').doc('9').get())
              .data()!['chassis_id'],
          isNull,
        );
        expect(
          (await db.collection('bookings').doc('10').get())
              .data()!['chassis_id'],
          '3',
        );
        final actual = (await db.collection('chassis').doc('3').get()).data()!;
        expect(actual['current_booking_id'].toString(), '10');
        expect(actual['current_status'], 'loaded');
        expect(actual['current_driver_id'].toString(), '12');
      },
    );
  }
  test(
    'old or equal offline action cannot steal newer owner; Philippine timestamps normalized',
    () {
      for (final time in [
        '2026-09-21T07:00:00',
        '2026-09-21T08:00:00',
        'bad',
      ]) {
        expect(
          chassisBookingToUnassign(
            bookingId: '83',
            booking: {
              'client_status': 'ongoing',
              'chassis_id': '9',
              'updated_at': time,
            },
            chassis: {
              'current_booking_id': '120',
              'updated_at': '2026-09-21T00:00:00Z',
            },
            ownerBooking: {
              'client_status': 'ongoing',
              'chassis_id': '9',
              'updated_at': '2026-09-21T00:00:00Z',
            },
          ),
          isNull,
        );
      }
      expect(
        chassisBookingToUnassign(
          bookingId: '83',
          booking: {
            'client_status': 'ongoing',
            'chassis_id': '9',
            'updated_at': '2026-09-21T08:00:01',
          },
          chassis: {
            'current_booking_id': '120',
            'updated_at': '2026-09-21T00:00:00Z',
          },
          ownerBooking: {
            'client_status': 'ongoing',
            'chassis_id': '9',
            'updated_at': '2026-09-21T00:00:00Z',
          },
        ),
        '120',
      );
    },
  );
}
