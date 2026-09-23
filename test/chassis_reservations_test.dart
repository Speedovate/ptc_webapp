import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/models/chassis_action_history.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/chassis.request.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class ReservationRequest extends BookingRequest {
  ReservationRequest(MergeAwareFirestore db, OfflineMutationQueueService queue)
    : super(firestore: db, offlineMutationQueueService: queue);
  @override
  Future<void> initialize() async {}
}

class ReservationChassisRequest extends ChassisRequest {
  ReservationChassisRequest(
    MergeAwareFirestore db,
    OfflineMutationQueueService queue,
  ) : super(firestore: db, offlineMutationQueueService: queue);
  @override
  Future<void> initialize() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final queued in [false, true]) {
    test(
      'reservations, activation, release and crew history, queued=$queued',
      () async {
        final db = MergeAwareFirestore();
        var online = false;
        final queue = OfflineMutationQueueService(
          firestore: db,
          backend: MemoryBackend(),
          isOnline: () => online,
        );
        final request = ReservationRequest(db, queue);
        var tick = 0;
        Future<void> save(String id, String stage) async {
          final old = (await db.collection('bookings').doc(id).get()).data();
          final booking = Booking(
            id: id,
            chassisId: '3',
            clientStatus: stage,
            driver: UserModel(id: 'driver$id'),
            helper: UserModel(id: 'helper$id'),
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 23, 0, 0, ++tick),
          );
          if (queued) {
            online = false;
            await queue.queueCollectionDocumentUpsert(
              collectionKey: 'bookings',
              documentId: id,
              document: {
                ...booking.toMap(),
                'driver_id': 'driver$id',
                'helper_id': 'helper$id',
              },
              baseUpdatedAt: old?['updated_at']?.toString(),
            );
            online = true;
            await queue.flushPendingMutations();
            expect(await queue.readPendingItems('signed_out'), isEmpty);
            online = false;
          } else {
            await request.saveBooking(booking);
          }
        }

        await db.collection('chassis').doc('3').set({
          'id': 3,
          'current_status': 'ready',
        });
        await save('9', 'assigned');
        expect(
          (await db.collection('chassis').doc('3').get())
              .data()!['current_booking_id'],
          isNull,
        );
        await save('9', 'ongoing');
        await save('10', 'assigned');
        await save('11', 'assigned');
        final active = (await db.collection('chassis').doc('3').get()).data()!;
        expect(active['current_booking_id'], 9);
        expect(active['current_status'], 'loaded');
        expect(active['current_driver_id'], 'driver9');
        for (final id in ['9', '10', '11']) {
          final data = (await db.collection('bookings').doc(id).get()).data()!;
          expect(data['chassis_id'], '3');
          expect(data['driver_id'], 'driver$id');
          expect(data['helper_id'], 'helper$id');
        }
        await save('11', 'cancelled');
        expect(
          (await db.collection('chassis').doc('3').get())
              .data()!['current_booking_id'],
          9,
        );
        await save('9', 'confirm');
        await save('10', 'ongoing');
        final chassis = (await db.collection('chassis').doc('3').get()).data()!;
        expect(chassis['current_booking_id'], 10);
        expect(chassis['current_driver_id'], 'driver10');
        // Editing a released booking must not touch the new active assignment.
        await save('9', 'confirm');
        expect(
          (await db.collection('chassis').doc('3').get())
              .data()!['current_booking_id'],
          10,
        );
        final docs = await db.collection('bookings').get();
        final history = ChassisActionHistory.fromBookings(
          Chassis.fromMap(chassis),
          docs.docs.map((doc) {
            final data = doc.data();
            return Booking.fromMap({
              ...data,
              'driver': {'id': data['driver_id']},
              'helper': {'id': data['helper_id']},
            });
          }),
        );
        expect(history.assignments, hasLength(3));
        expect(
          history.assignmentLabel(
            history.assignments.firstWhere((b) => b.id == '10'),
          ),
          'Active',
        );
        expect(
          history.assignments.firstWhere((b) => b.id == '9').helper?.id,
          'helper9',
        );
      },
    );
  }

  test(
    'offline create reserves an occupied chassis without displacing active crew',
    () async {
      final db = MergeAwareFirestore();
      var online = false;
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryBackend(),
        isOnline: () => online,
      );
      await db.collection('chassis').doc('3').set({
        'id': 3,
        'current_booking_id': 9,
        'current_status': 'loaded',
        'current_driver_id': 7,
      });
      await db.collection('bookings').doc('9').set({
        'id': '9',
        'chassis_id': '3',
        'client_status': 'ongoing',
      });
      const key = 'advance-reservation';
      await queue.queueOfflineBookingCreate(
        provisionalId: BookingIdResolver.temporaryId(key),
        submissionKey: key,
        document: {
          'submission_key': key,
          'client_status': 'assigned',
          'chassis_id': '3',
          'driver_id': '17',
          'helper_id': '18',
        },
      );
      online = true;
      await queue.flushPendingMutations();
      expect(await queue.readPendingItems('signed_out'), isEmpty);
      expect(
        (await db.collection('chassis').doc('3').get())
            .data()!['current_booking_id'],
        9,
      );
      final docs = await db.collection('bookings').get();
      expect(
        docs.docs.where((d) => d.data()['chassis_id'] == '3'),
        hasLength(2),
      );
    },
  );
  for (final queued in [false, true]) {
    test(
      'chassis editor retains all links and active crew, queued=$queued',
      () async {
        final db = MergeAwareFirestore();
        var online = false;
        final queue = OfflineMutationQueueService(
          firestore: db,
          backend: MemoryBackend(),
          isOnline: () => online,
        );
        final request = ReservationChassisRequest(db, queue);
        await db.collection('chassis').doc('3').set({
          'id': 3,
          'name': 'Shared',
          'current_booking_id': 9,
          'current_status': 'loaded',
          'current_driver_id': 7,
        });
        for (final id in ['9', '10', '11']) {
          await db.collection('bookings').doc(id).set({
            'id': id,
            'client_status': id == '9' ? 'ongoing' : 'assigned',
            'driver_id': 'driver$id',
            'helper_id': 'helper$id',
            if (id == '9') 'chassis_id': '3',
          });
        }
        for (final id in ['10', '11']) {
          final chassis = Chassis(
            id: 3,
            name: 'Shared',
            isActive: true,
            currentStatus: 'ready',
            bookingReferenceId: id,
          );
          if (queued) {
            await queue.queueChassisAssignment(
              documentId: '3',
              submissionKey: 'editor',
              isProvisionalCreate: false,
              chassisDocument: chassis.toMap(),
              previousBookingId: '9',
              nextBookingId: id,
            );
          } else {
            final saved = await request.saveChassis(
              chassis,
              previousBookingId: '9',
            );
            expect(saved.bookingReferenceId, '9');
          }
        }
        if (queued) {
          online = true;
          await queue.flushPendingMutations();
          expect(await queue.readPendingItems('signed_out'), isEmpty);
        }
        final chassis = (await db.collection('chassis').doc('3').get()).data()!;
        expect(chassis['current_booking_id'], 9);
        expect(chassis['current_driver_id'], 7);
        expect(chassis['current_status'], 'loaded');
        for (final id in ['9', '10', '11']) {
          final booking = (await db.collection('bookings').doc(id).get())
              .data()!;
          expect(booking['chassis_id'], '3');
          expect(booking['helper_id'], 'helper$id');
        }
      },
    );
  }

  test(
    'direct activation refuses an occupied chassis and preserves reservation',
    () async {
      final db = MergeAwareFirestore();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryBackend(),
        isOnline: () => false,
      );
      final request = ReservationRequest(db, queue);
      await db.collection('chassis').doc('3').set({
        'id': 3,
        'current_booking_id': 9,
        'current_status': 'loaded',
      });
      await db.collection('bookings').doc('9').set({
        'id': '9',
        'chassis_id': '3',
        'client_status': 'ongoing',
      });
      await db.collection('bookings').doc('10').set({
        'id': '10',
        'chassis_id': '3',
        'client_status': 'assigned',
      });
      await expectLater(
        request.saveBooking(
          Booking(id: '10', chassisId: '3', clientStatus: 'ongoing'),
        ),
        throwsA(
          predicate(
            (e) => '$e'.contains('chassis is active on another booking'),
          ),
        ),
      );
      expect(
        (await db.collection('bookings').doc('10').get())
            .data()!['client_status'],
        'assigned',
      );
      expect(
        (await db.collection('chassis').doc('3').get())
            .data()!['current_booking_id'],
        9,
      );
    },
  );

  test(
    'legacy ready reservation yields to actual activation without losing its link',
    () async {
      final db = MergeAwareFirestore();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryBackend(),
        isOnline: () => false,
      );
      final request = ReservationRequest(db, queue);
      await db.collection('chassis').doc('3').set({
        'id': 3,
        'current_booking_id': 9,
        'current_status': 'ready',
      });
      await db.collection('bookings').doc('9').set({
        'id': '9',
        'chassis_id': '3',
        'client_status': 'assigned',
      });
      await request.saveBooking(
        Booking(id: '10', chassisId: '3', clientStatus: 'ongoing'),
      );
      expect(
        (await db.collection('chassis').doc('3').get())
            .data()!['current_booking_id'],
        10,
      );
      expect(
        (await db.collection('bookings').doc('9').get()).data()!['chassis_id'],
        '3',
      );
    },
  );
}
