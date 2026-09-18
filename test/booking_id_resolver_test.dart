import 'dart:convert';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';

const key = 'booking_8_9_1_1789534355769000';
final temp = BookingIdResolver.temporaryId(key);
const storageKey = 'offline_mutation_queue_v1::signed_out';
Map<String, dynamic> booking() => {
  'id': temp,
  'submission_key': key,
  'updated_at': '2026-09-16T01:00:00Z',
  'status': 'book',
  'notes': temp,
};
Map<String, dynamic> entry(
  String kind, {
  Map<String, dynamic>? payload,
  String? base,
}) => {
  'id': 'queue_$kind',
  'kind': kind,
  'target_id': temp,
  'collection_key': 'bookings',
  'payload': payload ?? booking(),
  'base_updated_at': base,
  'created_at': '2026-09-16T01:00:00Z',
  'retry_count': 0,
  'is_blocked': false,
};
Future<void> replay(
  FakeFirebaseFirestore db,
  MemoryBackend backend,
  List<Map<String, dynamic>> entries,
) async {
  await backend.writeStringList(storageKey, entries.map(jsonEncode).toList());
  final service = OfflineMutationQueueService(firestore: db, backend: backend);
  await service.initialize();
  await service.flushPendingMutations();
}

Future<void> reserve(FakeFirebaseFirestore db, {String targetKey = key}) async {
  await db
      .collection('manage_id')
      .doc(BookingIdResolver.reservationId(key))
      .set({
        'resource_key': 'bookings',
        'submission_key': key,
        'document_id': '84',
      });
  await db.collection('bookings').doc('84').set({
    ...booking(),
    'id': '84',
    'submission_key': targetKey,
  });
}

void main() {
  test(
    'stale create cannot replay into occupied ID after separate-ID migration',
    () async {
      final db = FakeFirebaseFirestore();
      await reserve(db);
      final original = (await db.collection('bookings').doc('84').get()).data();
      await db.collection('booking_id_repairs').doc(temp).set({
        'status': 'repaired',
        'resolution': 'keep_both_new_id',
        'target_id': '106',
      });
      final backend = MemoryBackend();
      await replay(db, backend, [entry('bookingCreate')]);
      expect(
        (await db.collection('bookings').doc('84').get()).data(),
        original,
      );
      expect(await backend.readStringList(storageKey), isNotEmpty);
      expect((await db.collection('bookings').doc('106').get()).exists, false);
    },
  );
  test('numeric snapshots bypass reconciliation allocations', () {
    final documents = List.generate(
      1000,
      (i) => <String, dynamic>{
        'id': '${i + 1}',
        'submission_key': 'booking_$i',
      },
    );
    expect(
      identical(BookingIdResolver.reconcileCopies(documents), documents),
      isTrue,
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'requires confirmed submission identity, never matches editable fields',
    () async {
      final db = FakeFirebaseFirestore();
      final resolver = BookingIdResolver(firestore: db);
      await db.collection('bookings').doc('84').set({...booking(), 'id': '84'});
      expect(await resolver.resolve(temp), isNull);
      await reserve(db);
      resolver.invalidate(temp);
      expect(await resolver.resolve(temp), '84');
      await reserve(db, targetKey: 'different_submission');
      await expectLater(resolver.resolve(temp), throwsStateError);
      expect(await resolver.resolve('offline_booking_arbitrary'), isNull);
    },
  );
  test(
    'resolver instances share only identical in-flight identities',
    () async {
      final db = FakeFirebaseFirestore();
      await reserve(db);
      final first = BookingIdResolver(
        firestore: db,
      ).resolve(temp, submissionKey: key);
      final second = BookingIdResolver(
        firestore: db,
      ).resolve(temp, submissionKey: key);
      expect(identical(first, second), true);
      final wrong = BookingIdResolver(
        firestore: db,
      ).resolve(temp, submissionKey: 'wrong');
      await expectLater(wrong, throwsStateError);
      expect(await first, '84');
      expect(await second, '84');
    },
  );
  test(
    'confirmed queued create releases a previously missing mapping',
    () async {
      final db = FakeFirebaseFirestore();
      final resolver = BookingIdResolver(firestore: db);
      expect(await resolver.resolve(temp), isNull);
      await replay(db, MemoryBackend(), [entry('bookingCreate')]);
      expect(await resolver.resolve(temp), '1');
    },
  );
  test(
    'queued deletion of a temporary copy cannot delete canonical booking',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      await reserve(db);
      await replay(db, backend, [entry('collectionDocumentDelete')]);
      expect((await db.collection('bookings').doc('84').get()).exists, true);
      expect(
        jsonDecode(
          (await backend.readStringList(storageKey)).single,
        )['is_blocked'],
        true,
      );
    },
  );
  test(
    'collapses only identical cache copies; preserves conflicts and ambiguity',
    () {
      final original = booking();
      final numeric = {...original, 'id': '84'};
      expect(BookingIdResolver.reconcileCopies([original, numeric]), [numeric]);
      expect(original['id'], temp);
      expect(
        BookingIdResolver.reconcileCopies([
          original,
          {...numeric, 'status': 'assigned'},
        ]),
        hasLength(2),
      );
      expect(
        BookingIdResolver.reconcileCopies([
          original,
          numeric,
          {...numeric, 'id': '85'},
        ]),
        hasLength(3),
      );
    },
  );
  test(
    'creates next unused numeric ID and retry preserves newer data and counter',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      await db.collection('manage_count').doc('bookings_counter').set({
        'next_id': 84,
      });
      await db.collection('bookings').doc('84').set({
        'id': '84',
        'submission_key': 'other',
      });
      await replay(db, backend, [entry('bookingCreate')]);
      expect(
        (await db.collection('bookings').doc('85').get())
            .data()?['submission_key'],
        key,
      );
      expect((await db.collection('bookings').doc(temp).get()).exists, false);
      expect(await backend.readStringList(storageKey), isEmpty);
      await db.collection('bookings').doc('85').update({'status': 'assigned'});
      await db.collection('manage_count').doc('bookings_counter').update({
        'next_id': 100,
      });
      await replay(db, backend, [entry('bookingCreate')]);
      expect(
        (await db.collection('bookings').doc('85').get()).data()?['status'],
        'assigned',
      );
      expect(
        (await db.collection('manage_count').doc('bookings_counter').get())
            .data()?['next_id'],
        100,
      );
      expect(await backend.readStringList(storageKey), isEmpty);
    },
  );
  test(
    'changed retried create stays blocked instead of losing pending edit',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      await replay(db, backend, [entry('bookingCreate')]);
      await replay(db, backend, [
        entry('bookingCreate', payload: {...booking(), 'notes': 'changed'}),
      ]);
      final pending = jsonDecode(
        (await backend.readStringList(storageKey)).single,
      );
      expect(pending['is_blocked'], true);
      expect(pending['payload']['notes'], 'changed');
      expect(
        (await db.collection('bookings').doc('1').get()).data()?['notes'],
        temp,
      );
    },
  );
  test(
    'restart resolves edits without aliases and does not rewrite notes',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      await reserve(db);
      await replay(db, backend, [
        entry(
          'collectionDocumentUpsert',
          base: booking()['updated_at'],
          payload: {...booking(), 'updated_at': '2026-09-16T02:00:00Z'},
        ),
      ]);
      final saved = (await db.collection('bookings').doc('84').get()).data()!;
      expect(saved['id'], '84');
      expect(saved['notes'], temp);
      expect((await db.collection('bookings').doc(temp).get()).exists, false);
      expect(await backend.readStringList(storageKey), isEmpty);
    },
  );
  test(
    'stale or unversioned edits cannot overwrite canonical booking',
    () async {
      for (final base in [null, '2026-09-15T01:00:00Z']) {
        final db = FakeFirebaseFirestore();
        final backend = MemoryBackend();
        await reserve(db);
        await replay(db, backend, [
          entry(
            'collectionDocumentUpsert',
            base: base,
            payload: {
              ...booking(),
              'status': 'cancelled',
              'updated_at': '2026-09-16T02:00:00Z',
            },
          ),
        ]);
        expect(
          (await db.collection('bookings').doc('84').get()).data()?['status'],
          'book',
        );
        expect(
          jsonDecode(
            (await backend.readStringList(storageKey)).single,
          )['is_blocked'],
          true,
        );
      }
    },
  );
  test(
    'unidentified legacy edit cannot remove canonical submission identity',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      await reserve(db);
      final payload = booking()..remove('submission_key');
      await replay(db, backend, [
        entry(
          'collectionDocumentUpsert',
          base: booking()['updated_at'],
          payload: payload,
        ),
      ]);
      expect(
        (await db.collection('bookings').doc('84').get())
            .data()?['submission_key'],
        key,
      );
      expect(
        jsonDecode(
          (await backend.readStringList(storageKey)).single,
        )['is_blocked'],
        true,
      );
    },
  );
  test(
    'unconfirmed IDs remain queued without creating a temporary server row',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      await replay(db, backend, [
        entry('collectionDocumentUpsert', base: booking()['updated_at']),
      ]);
      expect((await db.collection('bookings').get()).docs, isEmpty);
      expect(await backend.readStringList(storageKey), hasLength(1));
    },
  );
  test(
    'mismatched reservation blocks create without changing another booking',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      await reserve(db, targetKey: 'another_submission');
      await replay(db, backend, [entry('bookingCreate')]);
      expect(
        (await db.collection('bookings').doc('84').get())
            .data()?['submission_key'],
        'another_submission',
      );
      expect(
        jsonDecode(
          (await backend.readStringList(storageKey)).single,
        )['is_blocked'],
        true,
      );
    },
  );
  test(
    'edit queued during create survives and replays against confirmed ID',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = EditingBackend(db);
      await replay(db, backend, [entry('bookingCreate')]);
      final pending =
          jsonDecode((await backend.readStringList(storageKey)).single)
              as Map<String, dynamic>;
      expect(pending['kind'], 'collectionDocumentUpsert');
      expect(pending['target_id'], '1');
      expect(pending['payload']['notes'], 'edited during sync');
      await replay(db, backend, [pending]);
      expect(
        (await db.collection('bookings').doc('1').get()).data()?['notes'],
        'edited during sync',
      );
      expect(await backend.readStringList(storageKey), isEmpty);
    },
  );
  test(
    'chassis owned by another booking is never stolen by offline create',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      await db.collection('chassis').doc('7').set({'current_booking_id': 90});
      await replay(db, backend, [
        entry('bookingCreate', payload: {...booking(), 'chassis_id': 7}),
      ]);
      expect(
        (await db.collection('chassis').doc('7').get())
            .data()?['current_booking_id'],
        90,
      );
      expect((await db.collection('bookings').get()).docs, isEmpty);
      expect(
        jsonDecode(
          (await backend.readStringList(storageKey)).single,
        )['is_blocked'],
        true,
      );
    },
  );
}

class MemoryBackend implements BookingStorageBackend {
  final data = <String, List<String>>{};
  @override
  Future<void> initialize() async {}
  @override
  Future<List<String>> readStringList(String key) async =>
      List.of(data[key] ?? []);
  @override
  Future<void> writeStringList(String key, List<String> values) async {
    data[key] = List.of(values);
  }
}

class EditingBackend extends MemoryBackend {
  EditingBackend(this.db);
  final FakeFirebaseFirestore db;
  bool edited = false;
  @override
  Future<List<String>> readStringList(String key) async {
    if (!edited &&
        key == storageKey &&
        (await db.collection('bookings').doc('1').get()).exists) {
      edited = true;
      final items = await super.readStringList(key);
      final item = jsonDecode(items.single) as Map<String, dynamic>;
      item['payload']['notes'] = 'edited during sync';
      item['payload']['updated_at'] = '2026-09-16T02:00:00Z';
      await writeStringList(key, [jsonEncode(item)]);
    }
    return super.readStringList(key);
  }
}
