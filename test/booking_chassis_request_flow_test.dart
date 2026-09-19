import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/view_models/shared/booking_workflow.vm.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;
import 'support/merge_aware_firestore.dart';

// Exercise real save/replay code without starting unrelated global listeners.
class _Request extends BookingRequest {
  _Request(MergeAwareFirestore db, OfflineMutationQueueService queue)
    : super(firestore: db, offlineMutationQueueService: queue);
  @override
  Future<void> initialize() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.remove('paltranco_current_user_id');
    await auth.remove('paltranco_known_session_user_ids');
    await FirestoreCacheStore.instance.writeDocumentMaps('bookings', []);
  });

  Future<Booking> seed(MergeAwareFirestore db) async {
    final booking = Booking(
      id: '10',
      chassisId: '3',
      driver: const UserModel(id: '7'),
      clientStatus: 'assigned',
      driverStatus: 'assigned',
      helperStatus: 'assigned',
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );
    await db.collection('bookings').doc('10').set(booking.toMap());
    await db.collection('chassis').doc('3').set({
      'id': 3,
      'current_status': 'ready',
      'current_booking_id': 10,
      'current_driver_id': 7,
    });
    await FirestoreCacheStore.instance.writeDocumentMaps('bookings', [
      booking.toMap(),
    ]);
    return booking;
  }

  test(
    'online save follows every stage, edits preserve cleared links, and released chassis stays with new owner',
    () async {
      final db = MergeAwareFirestore();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryBackend(),
        isOnline: () => false,
      );
      final request = _Request(db, queue);
      var booking = await seed(db);
      final stages = {
        'assigned': ('ready', 10, 7),
        'ongoing': ('loaded', 10, 7),
        'delivered': ('loaded', 10, null),
        'check': ('loaded', 10, null),
        'empty': ('empty', 10, null),
        'return': ('return', 10, 8),
        'confirm': ('ready', null, null),
      };
      for (final entry in stages.entries) {
        booking = booking.copyWith(
          clientStatus: entry.key,
          driverStatus: entry.key,
          helperStatus: entry.key,
          statusOutputs: {
            'return': {
              'submitted_at': '2026-09-19T01:00:00Z',
              'fields': {'return_driver_id': '8', 'chassis_location': 'Depot'},
            },
          },
        );
        for (var edit = 0; edit < 2; edit++) {
          booking = await request.saveBooking(booking);
          expect(booking.localSyncStatus, isNull);
          final chassis = (await db.collection('chassis').doc('3').get())
              .data()!;
          expect(chassis['current_status'], entry.value.$1, reason: entry.key);
          expect(
            chassis['current_booking_id'],
            entry.value.$2,
            reason: entry.key,
          );
          expect(
            chassis['current_driver_id'],
            entry.value.$3,
            reason: entry.key,
          );
          final stored = (await db.collection('bookings').doc('10').get())
              .data()!;
          expect(stored['client_status'], entry.key);
          expect(stored['driver_status'], entry.key);
          expect(stored['helper_status'], entry.key);
          if (entry.key == 'empty') expect(chassis['location'], 'Depot');
        }
      }
      final reassigned = {
        'id': 3,
        'current_status': 'loaded',
        'current_booking_id': 99,
        'current_driver_id': 88,
      };
      await db.collection('chassis').doc('3').set(reassigned);
      await request.saveBooking(booking);
      expect(
        (await db.collection('chassis').doc('3').get()).data(),
        reassigned,
      );
    },
  );

  for (final role in ['driver', 'helper']) {
    for (final stage in [
      'finish',
      'finished',
      'complete',
      'completed',
      'delivered',
    ]) {
      test(
        '$role $stage submission persists locally, replays from reopened queue and preserves action time',
        () async {
          final db = MergeAwareFirestore();
          final backend = MemoryBackend();
          final queue = OfflineMutationQueueService(
            firestore: db,
            backend: backend,
            isOnline: () => false,
          );
          final request = _Request(db, queue);
          final booking = (await seed(db)).copyWith(clientStatus: 'ongoing');
          await db.collection('bookings').doc('10').set(booking.toMap());
          await FirestoreCacheStore.instance.writeDocumentMaps('bookings', [
            booking.toMap(),
          ]);
          final vm = BookingWorkflowViewModel(bookingRepository: request);
          addTearDown(vm.dispose);
          vm.user = UserModel(id: '7', role: role);
          vm.booking = booking;
          final before = DateTime.now();
          final saved = await vm
              .submitSpecificForm(
                StatusForm(
                  id: 'delivery',
                  currentStatusKey: 'ongoing',
                  nextStatusKey: stage,
                  role: role,
                ),
                {'notes': 'Received offline'},
              )
              .timeout(const Duration(seconds: 3));
          expect(saved, isNotNull);
          expect(vm.isSubmitting, isFalse);
          expect(saved!.localSyncStatus, 'queued');
          expect(saved.updatedAt!.isBefore(before), isFalse);
          expect(saved.clientStatus, stage);
          expect(saved.driverStatus, stage);
          expect(saved.helperStatus, stage);
          if (stage == 'delivered') {
            expect(saved.updatedAt, saved.deliveredAt);
          }
          expect(saved.createdAt, booking.createdAt);
          expect(await backend.readStringList(storageKey), hasLength(1));
          expect(
            (await db.collection('bookings').doc('10').get())
                .data()!['client_status'],
            'ongoing',
          );
          // A different queue instance reads the persisted entry after reconnect.
          final reopened = OfflineMutationQueueService(
            firestore: db,
            backend: backend,
            isOnline: () => true,
          );
          await reopened.initialize();
          await reopened.flushPendingMutations();
          expect(await backend.readStringList(storageKey), isEmpty);
          final stored = (await db.collection('bookings').doc('10').get())
              .data()!;
          for (final field in [
            'client_status',
            'driver_status',
            'helper_status',
          ]) {
            expect(stored[field], stage);
          }
          final outputs = stored['status_outputs'] as Map;
          expect(outputs, hasLength(1));
          final action = outputs.values.single as Map;
          expect(
            DateTime.parse(action['submitted_at']).toUtc(),
            saved.updatedAt!.toUtc(),
          );
          expect(action['fields']['notes'], 'Received offline');
          if (stage == 'delivered') {
            expect(
              DateTime.parse(stored['delivered_at']).toUtc(),
              saved.deliveredAt!.toUtc(),
            );
          }
          expect(
            DateTime.parse(stored['updated_at']).toUtc(),
            saved.updatedAt!.toUtc(),
          );
          final chassis = (await db.collection('chassis').doc('3').get())
              .data()!;
          expect(
            chassis['current_status'],
            stage == 'delivered' ? 'loaded' : 'ready',
          );
          expect(chassis['current_booking_id'], 10);
          expect(chassis['current_driver_id'], stage == 'delivered' ? null : 7);
          expect(
            DateTime.parse(chassis['updated_at']).toUtc(),
            saved.updatedAt!.toUtc(),
          );
        },
      );
    }
  }
}
