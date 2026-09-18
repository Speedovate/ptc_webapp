import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/legacy_booking_repair_service.dart';

const key = 'booking_8_9_1_1789534355769000';
final temp = BookingIdResolver.temporaryId(key);
Map<String, dynamic> data(String id) => {
  'id': id,
  'submission_key': key,
  'client_status': 'assigned',
  'chassis_id': '7',
  'driver_id': '3',
  'created_at': '2026-09-14T13:38:50.139',
  'updated_at': '2026-09-16T00:00:00Z',
  'notes': temp,
};
Future<List<Map<String, dynamic>>> snapshot(FakeFirebaseFirestore db) async =>
    (await db.collection('bookings').get()).docs
        .map((d) => {...d.data(), 'id': d.id})
        .toList();
Future<void> seed(FakeFirebaseFirestore db, {bool canonical = true}) async {
  await db.collection('bookings').doc(temp).set(data(temp));
  if (canonical) await db.collection('bookings').doc('84').set(data('84'));
  await db.collection('chassis').doc('7').set({
    'current_booking_id': temp,
    'current_driver_id': 3,
  });
  await db.collection('support').doc('thread').set({
    'booking_id': temp,
    'text': temp,
  });
}

Future<Map<String, dynamic>?> report(FakeFirebaseFirestore db) async =>
    (await db.collection('booking_id_repairs').doc(temp).get()).data();
void main() {
  test('two occupied mappings become 106 and 107 in creation order', () async {
    final db = FakeFirebaseFirestore();
    final originals = <String, Map<String, dynamic>>{};
    final temps = <String>[];
    for (final pair in [
      ('71', 'booking_8_9_1_1789364330139000', '2026-09-14T13:38:50'),
      ('84', key, '2026-09-16T12:52:35'),
    ]) {
      final temporaryId = BookingIdResolver.temporaryId(pair.$2);
      temps.add(temporaryId);
      final numeric = <String, dynamic>{
        'id': pair.$1,
        'submission_key': pair.$2,
        'created_at': pair.$3,
        'client_status': 'assigned',
        'status_outputs': {'amount': 3000},
      };
      originals[pair.$1] = numeric;
      await db.collection('bookings').doc(pair.$1).set(numeric);
      await db.collection('bookings').doc(temporaryId).set({
        ...numeric,
        'id': temporaryId,
        'status_outputs': {'original': true},
      });
      await db
          .collection('manage_id')
          .doc(BookingIdResolver.reservationId(pair.$2))
          .set({
            'resource_key': 'bookings',
            'submission_key': pair.$2,
            'document_id': pair.$1,
          });
    }
    await db.collection('bookings').doc('105').set({'id': '105'});
    await db.collection('manage_count').doc('bookings_counter').set({
      'next_id': 106,
    });
    await LegacyBookingRepairService(
      firestore: db,
    ).repairSnapshot((await snapshot(db)).reversed.toList());
    for (var i = 0; i < temps.length; i++) {
      final target = '${106 + i}';
      expect(
        (await db.collection('bookings').doc(target).get())
            .data()?['status_outputs'],
        {'original': true},
      );
      expect(await BookingIdResolver(firestore: db).resolve(temps[i]), target);
    }
    for (final entry in originals.entries) {
      expect(
        (await db.collection('bookings').doc(entry.key).get()).data(),
        entry.value,
      );
    }
  });

  test(
    'revisits legacy conflict once, skips reserved IDs and keeps occupied mapping',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      final occupied = data('84');
      await db.collection('bookings').doc(temp).update({
        'client_status': 'cancelled',
        'chassis_id': null,
      });
      await db.collection('chassis').doc('7').update({
        'current_booking_id': 84,
      });
      await db.collection('bookings').doc('105').set({'id': '105'});
      await db.collection('manage_count').doc('bookings_counter').set({
        'next_id': 106,
      });
      final oldReservation = {
        'resource_key': 'bookings',
        'submission_key': key,
        'document_id': '84',
      };
      await db
          .collection('manage_id')
          .doc(BookingIdResolver.reservationId(key))
          .set(oldReservation);
      await db.collection('manage_id').doc('another_reservation').set({
        'resource_key': 'bookings',
        'submission_key': 'another',
        'document_id': '106',
      });
      await db.collection('booking_id_repairs').doc(temp).set({
        'status': 'needs_review',
        'target_id': '84',
        'reason': 'Booking contents differ; do not choose by timestamp',
      });
      await LegacyBookingRepairService(
        firestore: db,
      ).repairSnapshot(await snapshot(db));
      final saved = (await db.collection('bookings').doc('107').get()).data()!;
      expect(saved['created_at'], data(temp)['created_at']);
      expect(saved['updated_at'], data(temp)['updated_at']);
      expect(saved['submission_key'], 'booking_split_$temp');
      expect(saved['original_submission_key'], key);
      expect(
        (await db.collection('bookings').doc('84').get()).data(),
        occupied,
      );
      expect(
        (await db.collection('chassis').doc('7').get())
            .data()?['current_booking_id'],
        84,
      );
      expect(
        (await db
                .collection('manage_id')
                .doc(BookingIdResolver.reservationId(key))
                .get())
            .data(),
        oldReservation,
      );
      expect(
        (await db.collection('support').doc('thread').get())
            .data()?['booking_id'],
        '107',
      );
      expect(
        await BookingIdResolver(
          firestore: db,
        ).resolve(temp, submissionKey: key),
        '107',
      );
      await LegacyBookingRepairService(
        firestore: db,
      ).repairSnapshot(await snapshot(db));
      expect(
        (await db.collection('manage_count').doc('bookings_counter').get())
            .data()?['next_id'],
        108,
      );
      expect((await report(db))?['resolution'], 'keep_both_new_id');
    },
  );

  test('normal numeric bookings do not start repair work', () async {
    final db = FakeFirebaseFirestore();
    final service = LegacyBookingRepairService(firestore: db);
    expect(service.hasCandidates([data('84')]), false);
    await service.repairSnapshot([data('84')]);
    expect((await db.collection('booking_id_repairs').get()).docs, isEmpty);
  });
  test(
    'archives duplicate and remaps explicit references without changing booking',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      await db.collection('bookings').doc(temp).update({
        'updated_at': '2026-09-17T00:00:00Z',
      });
      await db.collection('manage_count').doc('bookings_counter').set({
        'next_id': 100,
      });
      await LegacyBookingRepairService(
        firestore: db,
      ).repairSnapshot(await snapshot(db));
      expect((await db.collection('bookings').doc(temp).get()).exists, false);
      expect(
        (await db.collection('bookings').doc('84').get()).data(),
        data('84'),
      );
      expect((await db.collection('chassis').doc('7').get()).data(), {
        'current_booking_id': 84,
        'current_driver_id': 3,
      });
      expect((await db.collection('support').doc('thread').get()).data(), {
        'booking_id': '84',
        'text': temp,
      });
      expect(
        (await db.collection('manage_count').doc('bookings_counter').get())
            .data()?['next_id'],
        100,
      );
      expect((await report(db))?['status'], 'repaired');
      final archive = await db
          .collection('booking_id_repairs')
          .doc(temp)
          .collection('snapshots')
          .doc('source')
          .get();
      expect(archive.data()?['updated_at'], '2026-09-17T00:00:00Z');
      expect(await BookingIdResolver(firestore: db).resolve(temp), '84');
    },
  );
  test(
    'orphan migrates to unused numeric ID without replacing occupied ID',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db, canonical: false);
      await db.collection('bookings').doc('87').set({
        'id': '87',
        'submission_key': 'other',
      });
      await db.collection('manage_count').doc('bookings_counter').set({
        'next_id': 87,
      });
      await LegacyBookingRepairService(
        firestore: db,
      ).repairSnapshot(await snapshot(db));
      expect(
        (await db.collection('bookings').doc('88').get()).data(),
        data('88'),
      );
      expect(
        (await db.collection('bookings').doc('87').get())
            .data()?['submission_key'],
        'other',
      );
      expect(
        (await db.collection('manage_count').doc('bookings_counter').get())
            .data()?['next_id'],
        89,
      );
      expect((await db.collection('bookings').doc(temp).get()).exists, false);
    },
  );
  test(
    'cancelled temporary booking receives separate ID without changing assigned booking',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      await db.collection('bookings').doc(temp).update({
        'client_status': 'cancelled',
      });
      final service = LegacyBookingRepairService(firestore: db);
      final occupied = (await db.collection('bookings').doc('84').get()).data();
      await service.repairSnapshot(await snapshot(db));
      expect(
        (await db.collection('bookings').doc('84').get()).data(),
        occupied,
      );
      expect(
        (await db.collection('bookings').doc('85').get())
            .data()?['client_status'],
        'cancelled',
      );
      expect((await report(db))?['resolution'], 'keep_both_new_id');
      expect(
        (await db.collection('chassis').doc('7').get())
            .data()?['current_booking_id'],
        85,
      );
      final after = await snapshot(db);
      expect(service.hasCandidates(after), false);
      // A new session also leaves the already-reported conflict alone.
      await LegacyBookingRepairService(firestore: db).repairSnapshot(after);
      expect(await snapshot(db), after);
    },
  );
  test(
    'ambiguous submission key and incorrect reservation never merge',
    () async {
      for (final ambiguous in [true, false]) {
        final db = FakeFirebaseFirestore();
        await seed(db);
        if (ambiguous) {
          await db.collection('bookings').doc('85').set(data('85'));
        } else {
          await db
              .collection('manage_id')
              .doc(BookingIdResolver.reservationId(key))
              .set({
                'resource_key': 'bookings',
                'submission_key': key,
                'document_id': '85',
              });
        }
        final before = await snapshot(db);
        await LegacyBookingRepairService(firestore: db).repairSnapshot(before);
        expect(await snapshot(db), before);
        expect((await report(db))?['status'], 'needs_review');
      }
    },
  );
  test(
    'another nonnumeric document with the same identity prevents migration',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db, canonical: false);
      await db
          .collection('bookings')
          .doc('unknown_legacy')
          .set(data('unknown_legacy'));
      final before = await snapshot(db);
      await LegacyBookingRepairService(firestore: db).repairSnapshot(before);
      expect(await snapshot(db), before);
      expect((await report(db))?['status'], 'needs_review');
    },
  );
  test(
    'another booking owning the chassis blocks repair without reassignment',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      await db.collection('chassis').doc('7').update({
        'current_booking_id': 99,
      });
      await LegacyBookingRepairService(
        firestore: db,
      ).repairSnapshot(await snapshot(db));
      expect((await db.collection('bookings').doc(temp).get()).exists, true);
      expect(
        (await db.collection('chassis').doc('7').get())
            .data()?['current_booking_id'],
        99,
      );
      expect((await report(db))?['status'], 'needs_review');
    },
  );
  test(
    're-reads changed booking instead of trusting snapshot used to schedule repair',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      final oldSnapshot = await snapshot(db);
      await db.collection('bookings').doc('84').update({
        'driver_id': 'another_driver',
      });
      await LegacyBookingRepairService(
        firestore: db,
      ).repairSnapshot(oldSnapshot);
      expect(
        (await db.collection('bookings').doc('84').get()).data()?['driver_id'],
        'another_driver',
      );
      expect((await db.collection('bookings').doc(temp).get()).exists, false);
      expect((await report(db))?['status'], 'repaired');
    },
  );
  test(
    'concurrent snapshot callbacks share one repair and restart is idempotent',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      final documents = await snapshot(db);
      final service = LegacyBookingRepairService(firestore: db);
      final first = service.repairSnapshot(documents);
      expect(identical(first, service.repairSnapshot(documents)), true);
      await first;
      await LegacyBookingRepairService(firestore: db).repairSnapshot(documents);
      expect((await db.collection('bookings').get()).docs, hasLength(1));
      expect(
        (await db.collection('booking_id_repairs').get()).docs,
        hasLength(1),
      );
    },
  );
  test(
    'missing submission key remains for review, never guessed from waybill',
    () async {
      final db = FakeFirebaseFirestore();
      await seed(db);
      await db.collection('bookings').doc(temp).set({
        'id': temp,
        'waybill_number': 'same',
      });
      await LegacyBookingRepairService(
        firestore: db,
      ).repairSnapshot(await snapshot(db));
      expect((await db.collection('bookings').doc(temp).get()).exists, true);
      expect((await report(db))?['status'], 'needs_review');
    },
  );
}
