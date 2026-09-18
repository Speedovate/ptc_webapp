import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart'
    show MemoryBackend, storageKey, booking, key, temp;
import 'support/merge_aware_firestore.dart';

const chassisKey = 'linked_chassis_action';
const chassisId = '-101';
const bookingTime = '2026-09-01T01:00:00Z';
const chassisTime = '2026-09-01T02:00:00Z';
Map<String, dynamic> chassisDocument() => {
  'id': -101,
  'name': 'New chassis',
  'current_booking_id': temp,
  'created_at': chassisTime,
  'updated_at': chassisTime,
};
Future<void> queuePair(
  OfflineMutationQueueService queue,
  bool chassisFirst,
) async {
  Future<void> addChassis() => queue.queueChassisAssignment(
    documentId: chassisId,
    submissionKey: chassisKey,
    chassisDocument: chassisDocument(),
    previousBookingId: null,
    nextBookingId: temp,
    isProvisionalCreate: true,
  );
  Future<void> addBooking() => queue.queueOfflineBookingCreate(
    provisionalId: temp,
    submissionKey: key,
    document: {
      ...booking(),
      'chassis_id': chassisId,
      'created_at': bookingTime,
      'updated_at': bookingTime,
    },
  );
  if (chassisFirst) {
    await addChassis();
    await addBooking();
  } else {
    await addBooking();
    await addChassis();
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.remove('paltranco_current_user_id');
    await auth.remove('paltranco_known_session_user_ids');
    await auth.remove('offline_mutation_queue_aliases_v1::$storageKey');
  });
  for (final chassisFirst in [true, false]) {
    test(
      'mutually dependent creates sync in one pass, chassisFirst=$chassisFirst',
      () async {
        var online = false;
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        final queue = OfflineMutationQueueService(
          firestore: db,
          backend: backend,
          isOnline: () => online,
        );
        await queuePair(queue, chassisFirst);
        online = true;
        await queue.flushPendingMutations();
        expect(await backend.readStringList(storageKey), isEmpty);
        final savedBooking = (await db.collection('bookings').doc('1').get())
            .data()!;
        final savedChassis = (await db.collection('chassis').doc('1').get())
            .data()!;
        expect(savedBooking['chassis_id'], '1');
        expect(savedChassis['current_booking_id'], 1);
        expect(savedBooking['updated_at'], bookingTime);
        expect(savedBooking['created_at'], bookingTime);
        expect(savedChassis['updated_at'], chassisTime);
        expect(savedChassis['created_at'], chassisTime);
      },
    );
  }
  test(
    'restart after lost acknowledgement preserves later edits on both linked records',
    () async {
      var online = false;
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      await queuePair(queue, true);
      final originalEntries = await backend.readStringList(storageKey);
      online = true;
      await queue.flushPendingMutations();
      await db.collection('bookings').doc('1').update({
        'client_status': 'delivered',
      });
      await db.collection('chassis').doc('1').update({'name': 'Later edit'});
      await backend.writeStringList(storageKey, originalEntries);
      final restarted = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
      );
      await restarted.initialize();
      await restarted.flushPendingMutations();
      expect(await backend.readStringList(storageKey), isEmpty);
      expect(
        (await db.collection('bookings').doc('1').get())
            .data()!['client_status'],
        'delivered',
      );
      expect(
        (await db.collection('chassis').doc('1').get()).data()!['name'],
        'Later edit',
      );
      expect((await db.collection('bookings').get()).docs, hasLength(1));
      expect((await db.collection('chassis').get()).docs, hasLength(1));
    },
  );
  test(
    'occupied linked chassis reservation preserves both queued actions and server record',
    () async {
      var online = false;
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      await db.collection('chassis').doc('5').set({
        'id': 5,
        'name': 'Existing',
      });
      await db
          .collection('manage_id')
          .doc('chassis_${base64UrlEncode(utf8.encode(chassisKey))}')
          .set({
            'resource_key': 'chassis',
            'submission_key': chassisKey,
            'document_id': '5',
          });
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      await queuePair(queue, true);
      online = true;
      await queue.flushPendingMutations();
      expect((await db.collection('bookings').get()).docs, isEmpty);
      expect(
        (await db.collection('chassis').doc('5').get()).data()!['name'],
        'Existing',
      );
      final pending = (await backend.readStringList(
        storageKey,
      )).map(jsonDecode).toList();
      expect(pending, hasLength(2));
      expect(pending.every((entry) => entry['is_blocked'] == true), true);
    },
  );
  test(
    'acknowledgement retry of chassis create cannot restore or conflict with later edits',
    () async {
      var online = false;
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      final original = chassisDocument()..remove('current_booking_id');
      await queue.queueChassisAssignment(
        documentId: chassisId,
        submissionKey: chassisKey,
        chassisDocument: original,
        previousBookingId: null,
        nextBookingId: null,
        isProvisionalCreate: true,
        baseUpdatedAt: bookingTime,
      );
      final savedQueue = await backend.readStringList(storageKey);
      online = true;
      await queue.flushPendingMutations();
      await db.collection('chassis').doc('1').update({
        'name': 'Newer remote edit',
        'updated_at': '2026-09-02T00:00:00Z',
      });
      await backend.writeStringList(storageKey, savedQueue);
      await queue.flushPendingMutations();
      expect(await backend.readStringList(storageKey), isEmpty);
      expect(
        (await db.collection('chassis').doc('1').get()).data()!['name'],
        'Newer remote edit',
      );
    },
  );
  test(
    'edit arriving during chassis create becomes versioned update, not conflicting create retry',
    () async {
      var online = false;
      final db = _PauseSecondTransaction();
      final backend = MemoryBackend();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      final original = chassisDocument()..remove('current_booking_id');
      await queue.queueChassisAssignment(
        documentId: chassisId,
        submissionKey: chassisKey,
        chassisDocument: original,
        previousBookingId: null,
        nextBookingId: null,
        isProvisionalCreate: true,
      );
      online = true;
      final syncing = queue.flushPendingMutations();
      await db.started.future;
      online = false;
      await queue.queueChassisAssignment(
        documentId: chassisId,
        submissionKey: chassisKey,
        chassisDocument: {
          ...original,
          'name': 'Edited while syncing',
          'updated_at': '2026-09-01T03:00:00Z',
        },
        previousBookingId: null,
        nextBookingId: null,
        isProvisionalCreate: false,
        baseUpdatedAt: chassisTime,
      );
      db.release.complete();
      await syncing;
      online = true;
      await queue.flushPendingMutations();
      expect(await backend.readStringList(storageKey), isEmpty);
      final saved = (await db.collection('chassis').doc('1').get()).data()!;
      expect(saved['name'], 'Edited while syncing');
      expect(saved['created_at'], chassisTime);
      expect(saved['updated_at'], '2026-09-01T03:00:00Z');
      expect((await db.collection('chassis').get()).docs, hasLength(1));
    },
  );
}

class _PauseSecondTransaction extends MergeAwareFirestore {
  int calls = 0;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    final call = ++calls;
    return super.runTransaction(
      (tx) async {
        final result = await handler(tx);
        if (call == 2) {
          started.complete();
          await release.future;
        }
        return result;
      },
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}
