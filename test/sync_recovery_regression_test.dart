import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/booking_status_continuation.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;

const _queueKey = 'offline_mutation_queue_v1::manager';
const _boxedError =
    'Dart exception thrown from converted Future. '
    'Use the properties error and stack to recover the original error.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.writeString('paltranco_current_user_id', 'manager');
  });

  tearDown(() async {
    final auth = createAuthStorageBackend();
    await auth.remove('paltranco_current_user_id');
    await auth.remove('paltranco_known_session_user_ids');
  });

  test('booking 98 stale delivered action is proven superseded', () {
    final fixture = _booking98Fixture();
    expect(
      isProvenSupersededBookingAction(
        fixture.server,
        fixture.pending,
        baseUpdatedAt: fixture.base,
      ),
      isTrue,
    );

    final unsafe = _booking98Fixture();
    final pendingOutputs = Map<String, dynamic>.from(
      unsafe.pending['status_outputs'] as Map,
    );
    pendingOutputs['ongoing__1789815085952000'] = _event(
      key: 'ongoing__1789815085952000',
      status: 'ongoing',
      at: '2026-09-22T09:00:00.000',
      from: 'ongoing',
      to: 'delivered',
    );
    unsafe.pending['status_outputs'] = pendingOutputs;
    expect(
      isProvenSupersededBookingAction(
        unsafe.server,
        unsafe.pending,
        baseUpdatedAt: unsafe.base,
      ),
      isFalse,
    );
  });

  test('booking 98 converted-future action is already represented', () {
    final fixture = _booking98Fixture();
    final pending = _bookingDocument(
      id: '98',
      submissionKey: fixture.submissionKey,
      status: 'ongoing',
      updatedAt: '2026-09-19T18:51:25.952',
      chassisId: '2',
      outputs: Map<String, dynamic>.from(
        fixture.server['status_outputs'] as Map,
      ),
      cleanupPaths: const [
        'bookings/98/status_outputs/book__1/waybill_photo/old.jpg',
      ],
    );
    expect(
      isProvenSupersededBookingAction(
        fixture.server,
        pending,
        baseUpdatedAt: fixture.base,
      ),
      isTrue,
    );
  });

  for (final item in _chassisCases) {
    test('chassis conflict ${item.bookingId}/${item.chassisId} '
        'preserves the active owner', () {
      final fixture = _chassisFixture(item);
      expect(
        isProvenSupersededChassisAction(
          pending: fixture.pending,
          serverBooking: fixture.serverBooking,
          chassis: fixture.chassis,
          ownerBooking: fixture.ownerBooking,
          baseUpdatedAt: item.base,
        ),
        item.provesSupersession,
        reason: item.provesSupersession
            ? 'the reported evidence proves the queued action stale'
            : 'owner evidence predates the base version, so the chassis may '
                  'legitimately still be with the owner and the action must not '
                  'be retired automatically',
      );
    });
  }

  test('an owner without event evidence is not silently discarded', () {
    final fixture = _chassisFixture(_chassisCases.first);
    fixture.ownerBooking['status_outputs'] = <String, dynamic>{};
    expect(
      isProvenSupersededChassisAction(
        pending: fixture.pending,
        serverBooking: fixture.serverBooking,
        chassis: fixture.chassis,
        ownerBooking: fixture.ownerBooking,
        baseUpdatedAt: _chassisCases.first.base,
      ),
      isFalse,
    );
  });

  test(
    'recovered booking conflict is retired without a new photo cleanup',
    () async {
      final fixture = _booking98Fixture();
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('98').set(fixture.server);
      final backend = await _seedQueue(
        payload: fixture.pending,
        baseUpdatedAt: fixture.base,
        lastError: _boxedError,
        boxedErrorRechecked: true,
      );
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );

      await queue.flushPendingMutations();

      expect(await backend.readStringList(_queueKey), isEmpty);
      final saved = (await db.collection('bookings').doc('98').get()).data()!;
      expect(saved['client_status'], 'ongoing');
      expect(saved['updated_at'], fixture.server['updated_at']);
      expect(saved['photo_cleanup_claims'], isEmpty);
    },
  );

  test(
    'users/12 boxed upsert retires only when queued fields are already present',
    () async {
      const payload = <String, dynamic>{
        'id': '12',
        'name': 'Driver 12',
        'role': 'driver',
        'is_active': true,
        'updated_at': '2026-09-19T10:00:00.000Z',
      };
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('12').set({
        ...payload,
        'updated_at': '2026-09-19T10:05:00.000Z',
        'manager_note': 'preserve me',
      });
      final backend = MemoryBackend();
      await backend.writeStringList(_queueKey, [
        jsonEncode({
          'id': 'user_upsert_12',
          'kind': 'collectionDocumentUpsert',
          'target_id': '12',
          'collection_key': 'users',
          'base_updated_at': '2026-09-19T09:00:00.000Z',
          'payload': payload,
          'created_at': payload['updated_at'],
          'retry_count': 1,
          'is_blocked': true,
          'last_error': _boxedError,
        }),
      ]);
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );

      await queue.flushPendingMutations();

      expect(await backend.readStringList(_queueKey), isEmpty);
      final saved = (await db.collection('users').doc('12').get()).data()!;
      expect(saved['manager_note'], 'preserve me');
      expect(saved['name'], 'Driver 12');
    },
  );

  test('a queued is_online snapshot neither blocks retirement nor resurrects '
      'presence', () async {
    // Production shape: the queue captured `is_online: true`, but the server
    // has since seen the crew member sign out. Presence is server-owned, so
    // it must not count as a mismatch and must never be written back.
    const payload = <String, dynamic>{
      'id': '12',
      'name': 'Driver 12',
      'role': 'driver',
      'is_active': true,
      'is_online': true,
      'updated_at': '2026-09-25T09:11:56.919',
    };
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('12').set({
      ...payload,
      'is_online': false,
      'updated_at': '2026-09-25T10:00:00.000Z',
      'manager_note': 'added by the office after the edit',
    });
    final backend = MemoryBackend();
    await backend.writeStringList(_queueKey, [
      jsonEncode({
        'id': 'user_upsert_12_presence',
        'kind': 'collectionDocumentUpsert',
        'target_id': '12',
        'collection_key': 'users',
        'base_updated_at': '2026-09-23T10:12:38.902Z',
        'payload': payload,
        'created_at': '2026-09-25T01:12:04.922Z',
        'retry_count': 3,
        'is_blocked': true,
        'last_error': _boxedError,
      }),
    ]);
    final queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => true,
    );

    await queue.flushPendingMutations();

    expect(await backend.readStringList(_queueKey), isEmpty);
    final saved = (await db.collection('users').doc('12').get()).data()!;
    expect(saved['is_online'], isFalse, reason: 'presence is never replayed');
    expect(saved['manager_note'], 'added by the office after the edit');
    expect(saved['name'], 'Driver 12');
  });

  test('a queued offline sign-out still clears presence', () async {
    // The mirror image of the test above: signing out while offline is the one
    // user edit whose whole point is presence, so the queued `is_online: false`
    // must actually reach the server instead of being dropped as "stale".
    const payload = <String, dynamic>{
      'id': '12',
      'name': 'Driver 12',
      'role': 'driver',
      'is_active': true,
      'is_online': false,
      'updated_at': '2026-09-25T11:00:00.000Z',
    };
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('12').set({
      ...payload,
      'is_online': true,
      'updated_at': '2026-09-25T10:00:00.000Z',
    });
    final backend = MemoryBackend();
    await backend.writeStringList(_queueKey, [
      jsonEncode({
        'id': 'user_upsert_12_signout',
        'kind': 'collectionDocumentUpsert',
        'target_id': '12',
        'collection_key': 'users',
        'base_updated_at': '2026-09-25T10:00:00.000Z',
        'payload': payload,
        'created_at': '2026-09-25T11:00:00.000Z',
        'retry_count': 1,
        'is_blocked': false,
        'replay_presence': true,
      }),
    ]);
    final queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => true,
    );

    await queue.flushPendingMutations();

    expect(await backend.readStringList(_queueKey), isEmpty);
    final saved = (await db.collection('users').doc('12').get()).data()!;
    expect(
      saved['is_online'],
      isFalse,
      reason: 'an intentional queued sign-out must be honoured',
    );
  });

  test('a queued profile edit does not undo a sign-out', () async {
    // Coalescing must not lose a sign-out: a profile edit queued afterwards
    // carries a mirrored `is_online`, and replaying it would put the crew member
    // back online after they left.
    final db = FakeFirebaseFirestore();
    final backend = MemoryBackend();
    final queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => true,
    );
    await queue.initialize();

    await queue.queueUserUpsert(
      userId: '12',
      document: const {
        'id': '12',
        'name': 'Driver 12',
        'is_online': false,
        'updated_at': '2026-09-25T11:00:00.000Z',
      },
      baseUpdatedAt: '2026-09-25T10:00:00.000Z',
      syncPresence: true,
    );
    await queue.queueUserUpsert(
      userId: '12',
      document: const {
        'id': '12',
        'name': 'Driver 12 Jr',
        // Mirrored from before the sign-out.
        'is_online': true,
        'updated_at': '2026-09-25T11:05:00.000Z',
      },
      baseUpdatedAt: '2026-09-25T10:00:00.000Z',
    );

    final queued = await backend.readStringList(_queueKey);
    expect(queued, hasLength(1), reason: 'edits to one user coalesce');
    expect(jsonDecode(queued.single)['replay_presence'], isTrue);

    await db.collection('users').doc('12').set({
      'id': '12',
      'name': 'Driver 12',
      'is_online': true,
      'updated_at': '2026-09-25T10:00:00.000Z',
    });
    await queue.flushPendingMutations();

    final saved = (await db.collection('users').doc('12').get()).data()!;
    expect(saved['name'], 'Driver 12 Jr');
    expect(
      saved['is_online'],
      isFalse,
      reason: 'the sign-out must survive the later profile edit',
    );
  });

  test('a queued user edit merges over a newer server document', () async {
    // The queued snapshot is a whole document. The office saved a new photo and
    // a note while this device was offline, and the crew changed their phone
    // number. A wholesale replay would roll the office back; dropping the entry
    // would lose the crew's edit. The pre-edit base makes a real three-way
    // merge possible: the crew's field lands, the office's fields survive.
    const base = <String, dynamic>{
      'id': '12',
      'name': 'Manolito Jamot',
      'phone': '+639979727996',
      'photo': 'https://example.test/users/12/profile_photo/old.png',
      'is_online': true,
      'updated_at': '2026-09-23T10:12:38.902Z',
    };
    final queued = <String, dynamic>{
      ...base,
      'phone': '+639171234567',
      'updated_at': '2026-09-25T09:11:56.919',
    };
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('12').set({
      ...base,
      // The office saved these two while the device was offline.
      'photo': 'https://example.test/users/12/profile_photo/new.png',
      'manager_note': 'added by the office after the edit',
      'is_online': false,
      'updated_at': '2026-09-25T10:30:00.000Z',
    });
    final backend = MemoryBackend();
    await backend.writeStringList(_queueKey, [
      jsonEncode({
        'id': 'user_upsert_12_merge',
        'kind': 'collectionDocumentUpsert',
        'target_id': '12',
        'collection_key': 'users',
        'base_updated_at': base['updated_at'],
        'base_payload': base,
        'payload': queued,
        'created_at': '2026-09-25T01:12:04.922Z',
        'retry_count': 3,
        'is_blocked': true,
        'last_error': _boxedError,
      }),
    ]);
    final queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => true,
    );

    await queue.flushPendingMutations();

    expect(await backend.readStringList(_queueKey), isEmpty);
    final saved = (await db.collection('users').doc('12').get()).data()!;
    expect(
      saved['phone'],
      '+639171234567',
      reason: 'the edit this device actually made must land',
    );
    expect(
      saved['photo'],
      'https://example.test/users/12/profile_photo/new.png',
      reason: 'the office photo saved after the edit must not be rolled back',
    );
    expect(saved['manager_note'], 'added by the office after the edit');
    expect(saved['is_online'], isFalse, reason: 'presence is server-owned');
  });

  test('a field both sides changed is left to whoever saved last', () async {
    const base = <String, dynamic>{
      'id': '12',
      'name': 'Manolito Jamot',
      'phone': '+639979727996',
      'updated_at': '2026-09-23T10:12:38.902Z',
    };
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('12').set({
      ...base,
      // The office corrected the name after the edit was queued.
      'name': 'Manolito S. Jamot',
      'updated_at': '2026-09-25T10:30:00.000Z',
    });
    final backend = MemoryBackend();
    await backend.writeStringList(_queueKey, [
      jsonEncode({
        'id': 'user_upsert_12_both_changed',
        'kind': 'collectionDocumentUpsert',
        'target_id': '12',
        'collection_key': 'users',
        'base_updated_at': base['updated_at'],
        'base_payload': base,
        'payload': <String, dynamic>{
          ...base,
          'name': 'Manolito Jamot Jr',
          'updated_at': '2026-09-25T09:11:56.919',
        },
        'created_at': '2026-09-25T01:12:04.922Z',
        'retry_count': 1,
        'is_blocked': false,
      }),
    ]);
    final queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => true,
    );

    await queue.flushPendingMutations();

    final saved = (await db.collection('users').doc('12').get()).data()!;
    expect(
      saved['name'],
      'Manolito S. Jamot',
      reason: 'a field the office changed after the edit is theirs to keep',
    );
    expect(await backend.readStringList(_queueKey), isEmpty);
  });

  test(
    'a legacy user entry with no base cannot be merged, so it is reported',
    () async {
      // Entries queued by the old build never stored the pre-edit document, so
      // there is no way to tell which field the crew changed. Retiring with a
      // report is the only honest outcome: the newer server document is kept and
      // the drop is visible instead of silent.
      const payload = <String, dynamic>{
        'id': '12',
        'name': 'Manolito Jamot',
        'role': 'driver',
        'phone': '+639171234567',
        'updated_at': '2026-09-25T09:11:56.919',
      };
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('12').set({
        ...payload,
        'phone': '+639979727996',
        'photo': 'https://example.test/users/12/profile_photo/new.png',
        'updated_at': '2026-09-25T10:30:00.000Z',
      });
      final backend = MemoryBackend();
      await backend.writeStringList(_queueKey, [
        jsonEncode({
          'id': 'user_upsert_12_legacy',
          'kind': 'collectionDocumentUpsert',
          'target_id': '12',
          'collection_key': 'users',
          'base_updated_at': '2026-09-23T10:12:38.902Z',
          'payload': payload,
          'created_at': '2026-09-25T01:12:04.922Z',
          'retry_count': 3,
          'is_blocked': true,
          'last_error': _boxedError,
        }),
      ]);
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );

      await queue.flushPendingMutations();

      expect(await backend.readStringList(_queueKey), isEmpty);
      final saved = (await db.collection('users').doc('12').get()).data()!;
      expect(
        saved['phone'],
        '+639979727996',
        reason: 'without a base, writing would be a blind overwrite',
      );
      expect(
        saved['photo'],
        'https://example.test/users/12/profile_photo/new.png',
      );
    },
  );

  test('users/12 boxed mismatch remains blocked without overwrite', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('12').set({
      'id': '12',
      'name': 'Server name',
      'role': 'driver',
      'updated_at': '2026-09-19T10:05:00.000Z',
    });
    final backend = MemoryBackend();
    await backend.writeStringList(_queueKey, [
      jsonEncode({
        'id': 'user_upsert_12_mismatch',
        'kind': 'collectionDocumentUpsert',
        'target_id': '12',
        'collection_key': 'users',
        'base_updated_at': '2026-09-19T09:00:00.000Z',
        'payload': {
          'id': '12',
          'name': 'Local name',
          'role': 'driver',
          'updated_at': '2026-09-19T10:00:00.000Z',
        },
        'created_at': '2026-09-19T10:00:00.000Z',
        'retry_count': 1,
        'is_blocked': true,
        'last_error': _boxedError,
      }),
    ]);
    final queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => true,
    );

    await queue.flushPendingMutations();

    // The queued snapshot lost the race against a newer server version. It is
    // retired rather than left blocking, and the server's document is not
    // touched. The drop itself is reported as a `queue_edit_superseded` error.
    expect(await backend.readStringList(_queueKey), isEmpty);
    expect(
      (await db.collection('users').doc('12').get()).data()?['name'],
      'Server name',
    );
  });

  test(
    'recovered chassis conflict retires the action without changing owner',
    () async {
      final item = _chassisCases.firstWhere((value) => value.bookingId == '89');
      final fixture = _chassisFixture(item);
      final db = FakeFirebaseFirestore();
      await db
          .collection('bookings')
          .doc(item.bookingId)
          .set(fixture.serverBooking);
      await db
          .collection('bookings')
          .doc(item.ownerId)
          .set(fixture.ownerBooking);
      await db.collection('chassis').doc(item.chassisId).set(fixture.chassis);
      final backend = await _seedQueue(
        payload: fixture.pending,
        baseUpdatedAt: item.base,
        lastError:
            'Bad state: Sync conflict: chassis is active on another booking.',
        targetId: item.bookingId,
        chassisTransferRechecked: true,
      );
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );

      await queue.flushPendingMutations();

      expect(await backend.readStringList(_queueKey), isEmpty);
      // The trip's own progress is recorded: a stale chassis number must not
      // cost the crew their delivery.
      final trip = (await db.collection('bookings').doc(item.bookingId).get())
          .data()!;
      expect(trip['client_status'], item.pendingStatus);
      expect(trip['status_outputs'], isNotEmpty);
      final chassis = (await db.collection('chassis').doc(item.chassisId).get())
          .data()!;
      expect(chassis['current_booking_id'], item.ownerId);
      expect(chassis['current_status'], 'loaded');
      final owner = (await db.collection('bookings').doc(item.ownerId).get())
          .data()!;
      expect(owner['chassis_id'], item.chassisId);
    },
  );

  test(
    'bookings/98 already-applied helper entry retires without a new write',
    () async {
      // Production: the queued payload is byte-for-byte the server document
      // after the converted-Future failure, so the write had already committed.
      final queued = _appliedBooking98Payload();
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('98').set(queued);
      final backend = MemoryBackend();
      await backend.writeStringList(_queueKey, [
        jsonEncode({
          'id': 'vehicle_upsert_1789948203556000_3520beaf',
          'kind': 'collectionDocumentUpsert',
          'target_id': '98',
          'collection_key': 'bookings',
          'base_updated_at': '2026-09-18T03:42:59.818Z',
          'payload': queued,
          'created_at': '2026-09-20T23:50:03.557Z',
          'retry_count': 1,
          'is_blocked': true,
          'last_error': _boxedError,
        }),
      ]);
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );

      await queue.flushPendingMutations();

      expect(await backend.readStringList(_queueKey), isEmpty);
      final saved = (await db.collection('bookings').doc('98').get()).data()!;
      expect(saved['client_status'], 'ongoing');
      expect(
        saved['updated_at'],
        '2026-09-21T07:50:03.316',
        reason: 'the server version must not be rewritten',
      );
      expect(
        (saved['status_outputs'] as Map).keys,
        hasLength(4),
        reason: 'no duplicate or fabricated status event',
      );
    },
  );

  test('users/12 newer server version is preserved, not overwritten', () async {
    // Production payload shape: a profile-photo/licence edit that also carries
    // the read-only session fields the client mirrors back. The server is newer
    // and still holds the previous photo, so the queued snapshot is not applied
    // blindly. It is also not left blocking forever: a full snapshot that lost
    // the race can never win, so it retires and the office keeps its version.
    final payload = <String, dynamic>{
      'id': '12',
      'name': 'Manolito Jamot',
      'role': 'driver',
      'parent_client_id': null,
      'email': 'manolitojamot3@gmail.com',
      'phone': '+639979727996',
      'position': null,
      'is_active': true,
      'is_online': true,
      'photo': 'https://example.test/users/12/profile_photo/new.png',
      'license': 'https://example.test/users/12/license_photo/lic.png',
      'vehicle_type_id': null,
      'created_at': '2026-08-15T18:23:33.130',
      'updated_at': '2026-09-25T09:11:56.919',
    };
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('12').set({
      ...payload,
      'photo': 'https://example.test/users/12/profile_photo/old.png',
      'updated_at': '2026-09-25T10:00:00.000Z',
      'is_online': false,
      'manager_note': 'added by the office after the edit',
      'dispatch_code': 'D-77',
    });
    final backend = MemoryBackend();
    await backend.writeStringList(_queueKey, [
      jsonEncode({
        'id': 'vehicle_upsert_1790298724922000_4c21b217',
        'kind': 'collectionDocumentUpsert',
        'target_id': '12',
        'collection_key': 'users',
        'base_updated_at': '2026-09-23T10:12:38.902Z',
        'payload': payload,
        'created_at': '2026-09-25T01:12:04.922Z',
        'retry_count': 3,
        'is_blocked': true,
        'last_error': _boxedError,
      }),
    ]);
    final queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => true,
    );

    await queue.flushPendingMutations();

    final saved = (await db.collection('users').doc('12').get()).data()!;
    expect(
      saved['photo'],
      'https://example.test/users/12/profile_photo/old.png',
      reason: 'a newer server version must never be overwritten by a replay',
    );
    expect(saved['manager_note'], 'added by the office after the edit');
    expect(saved['is_online'], isFalse, reason: 'presence is server-owned');
    expect(
      saved['dispatch_code'],
      'D-77',
      reason: 'fields added by the office must survive the replay',
    );
    // Retired, not blocked: keeping it queued would wedge every later edit for
    // this person behind a snapshot that can never win.
    expect(await backend.readStringList(_queueKey), isEmpty);
    expect(await queue.readPendingItems('manager'), isEmpty);
  });
}

Map<String, dynamic> _appliedBooking98Payload() {
  const submissionKey = 'booking_8_9_1_1789632885309000';
  final book = _event(
    key: 'book__1789632885310000',
    status: 'book',
    at: '2026-09-17T16:14:45.310',
    from: 'book',
    to: 'pending',
  );
  final pending = _event(
    key: 'pending__1789632930119000',
    status: 'pending',
    at: '2026-09-17T16:15:30.119',
    from: 'pending',
    to: 'assigned',
  );
  final assigned = _plainEvent(
    key: 'assigned__1789632998781000',
    status: 'assigned',
    at: '2026-09-17T16:16:38.781',
  );
  final reassigned = _event(
    key: 'assigned__1789948203316000',
    status: 'assigned',
    at: '2026-09-21T07:50:03.316',
    from: 'assigned',
    to: 'ongoing',
    by: '18',
  );
  return _bookingDocument(
    id: '98',
    submissionKey: submissionKey,
    status: 'ongoing',
    updatedAt: '2026-09-21T07:50:03.316',
    chassisId: '2',
    outputs: {
      book['key'] as String: book['event'] as Map<String, dynamic>,
      pending['key'] as String: pending['event'] as Map<String, dynamic>,
      assigned['key'] as String: assigned['event'] as Map<String, dynamic>,
      reassigned['key'] as String: reassigned['event'] as Map<String, dynamic>,
    },
  );
}

Future<MemoryBackend> _seedQueue({
  required Map<String, dynamic> payload,
  required String baseUpdatedAt,
  required String lastError,
  String targetId = '98',
  bool boxedErrorRechecked = false,
  bool chassisTransferRechecked = false,
}) async {
  final backend = MemoryBackend();
  await backend.writeStringList(_queueKey, [
    jsonEncode({
      'id': 'vehicle_upsert_${DateTime.now().microsecondsSinceEpoch}',
      'kind': 'collectionDocumentUpsert',
      'target_id': targetId,
      'collection_key': 'bookings',
      'base_updated_at': baseUpdatedAt,
      'payload': payload,
      'created_at': payload['updated_at'],
      'retry_count': 1,
      'is_blocked': true,
      'last_error': lastError,
      'boxed_error_rechecked': boxedErrorRechecked,
      'booking_history_rechecked': true,
      'booking_continuation_rechecked': true,
      'chassis_transfer_rechecked': chassisTransferRechecked,
    }),
  ]);
  return backend;
}

_MapFixture _booking98Fixture() {
  const base = '2026-09-18T03:42:59.818Z';
  const submissionKey = 'booking_8_9_1_1789632885309000';
  final book = _event(
    key: 'book__1789632885310000',
    status: 'book',
    at: '2026-09-17T16:14:45.310',
    from: 'book',
    to: 'pending',
  );
  final pending = _event(
    key: 'pending__1789632930119000',
    status: 'pending',
    at: '2026-09-17T16:15:30.119',
    from: 'pending',
    to: 'assigned',
  );
  final assigned = _plainEvent(
    key: 'assigned__1789632998781000',
    status: 'assigned',
    at: '2026-09-17T16:16:38.781',
  );
  final common = <String, dynamic>{
    book['key'] as String: book['event'] as Map<String, dynamic>,
    pending['key'] as String: pending['event'] as Map<String, dynamic>,
    assigned['key'] as String: assigned['event'] as Map<String, dynamic>,
  };
  final serverAssigned = _event(
    key: 'assigned__1789948203316000',
    status: 'assigned',
    at: '2026-09-21T07:50:03.316',
    from: 'assigned',
    to: 'ongoing',
    by: '18',
  );
  final localAssigned = _event(
    key: 'assigned__1789815052508000',
    status: 'assigned',
    at: '2026-09-19T18:50:52.508',
    from: 'assigned',
    to: 'ongoing',
  );
  final localOngoing = _event(
    key: 'ongoing__1789815085952000',
    status: 'ongoing',
    at: '2026-09-19T18:51:25.952',
    from: 'ongoing',
    to: 'delivered',
  );
  final server = _bookingDocument(
    id: '98',
    submissionKey: submissionKey,
    status: 'ongoing',
    updatedAt: '2026-09-21T07:50:03.316',
    chassisId: '2',
    outputs: {
      ...common,
      serverAssigned['key'] as String: serverAssigned['event'] as Map,
    },
  );
  final pendingDocument = _bookingDocument(
    id: '98',
    submissionKey: submissionKey,
    status: 'delivered',
    updatedAt: '2026-09-19T18:51:25.952',
    chassisId: '2',
    outputs: {
      ...common,
      localAssigned['key'] as String: localAssigned['event'] as Map,
      localOngoing['key'] as String: localOngoing['event'] as Map,
    },
    deliveredAt: '2026-09-19T18:51:25.952Z',
    cleanupPaths: const [
      'bookings/98/status_outputs/book__1789632885310000/waybill_photo/old.jpg',
    ],
  );
  return _MapFixture(
    server: server,
    pending: pendingDocument,
    base: base,
    submissionKey: submissionKey,
  );
}

class _MapFixture {
  const _MapFixture({
    required this.server,
    required this.pending,
    required this.base,
    required this.submissionKey,
  });

  final Map<String, dynamic> server;
  final Map<String, dynamic> pending;
  final String base;
  final String submissionKey;
}

class _ChassisCase {
  const _ChassisCase({
    required this.bookingId,
    required this.chassisId,
    required this.ownerId,
    required this.ownerStatus,
    required this.pendingStatus,
    required this.pendingAt,
    required this.ownerAt,
    required this.base,
    this.provesSupersession = true,
  });

  final String bookingId;
  final String chassisId;
  final String ownerId;
  final String ownerStatus;
  final String pendingStatus;
  final String pendingAt;
  final String ownerAt;
  final String base;

  /// Whether the *reported* server evidence proves the queued action stale.
  final bool provesSupersession;
}

/// The five chassis conflicts reported from production on 2026-09-25, with the
/// timestamps exactly as logged.
///
/// `140` is the one case the server cannot prove: owner booking 100 was last
/// touched on 2026-09-19, five days *before* the version booking 140's queued
/// edit was based on, so the chassis may legitimately still be with 100. It
/// must stay blocked and reviewable instead of being silently retired.
const _chassisCases = <_ChassisCase>[
  _ChassisCase(
    bookingId: '144',
    chassisId: '4',
    ownerId: '94',
    ownerStatus: 'check',
    pendingStatus: 'delivered',
    pendingAt: '2026-09-25T09:56:25.573',
    ownerAt: '2026-09-25T01:28:01.137Z',
    base: '2026-09-25T09:26:48.892',
  ),
  _ChassisCase(
    bookingId: '83',
    chassisId: '9',
    ownerId: '105',
    ownerStatus: 'check',
    pendingStatus: 'ongoing',
    pendingAt: '2026-09-21T07:01:42.811',
    ownerAt: '2026-09-19T10:41:38.686Z',
    base: '2026-09-17T06:14:52.586Z',
  ),
  _ChassisCase(
    bookingId: '140',
    chassisId: '1',
    ownerId: '100',
    ownerStatus: 'check',
    pendingStatus: 'delivered',
    pendingAt: '2026-09-25T07:57:26.642',
    ownerAt: '2026-09-19T10:33:13.728Z',
    base: '2026-09-24T13:46:28.109',
    provesSupersession: false,
  ),
  _ChassisCase(
    bookingId: '91',
    chassisId: '8',
    ownerId: '122',
    ownerStatus: 'ongoing',
    pendingStatus: 'delivered',
    pendingAt: '2026-09-19T18:41:19.702',
    ownerAt: '2026-09-23T11:17:30.564Z',
    base: '2026-09-17T08:10:34.829Z',
  ),
  _ChassisCase(
    bookingId: '89',
    chassisId: '2',
    ownerId: '98',
    ownerStatus: 'ongoing',
    pendingStatus: 'delivered',
    pendingAt: '2026-09-19T18:45:00.922',
    ownerAt: '2026-09-21T07:50:03.316Z',
    base: '2026-09-17T08:15:30.723Z',
  ),
];

class _ChassisFixture {
  _ChassisFixture({
    required this.pending,
    required this.serverBooking,
    required this.chassis,
    required this.ownerBooking,
  });

  final Map<String, dynamic> pending;
  final Map<String, dynamic> serverBooking;
  final Map<String, dynamic> chassis;
  final Map<String, dynamic> ownerBooking;
}

_ChassisFixture _chassisFixture(_ChassisCase item) {
  final baseEvent = _event(
    key: 'book__${item.bookingId}',
    status: 'book',
    at: '2026-09-16T10:00:00.000',
    from: 'book',
    to: 'pending',
  );
  final pendingEvent = item.pendingStatus == 'ongoing'
      ? _event(
          key: 'ongoing__${item.bookingId}',
          status: 'assigned',
          at: item.pendingAt,
          from: 'assigned',
          to: 'ongoing',
        )
      : _event(
          key: 'ongoing__${item.bookingId}',
          status: 'ongoing',
          at: item.pendingAt,
          from: 'ongoing',
          to: 'delivered',
        );
  final ownerEvent = _event(
    key: 'ongoing__owner_${item.ownerId}',
    status: 'ongoing',
    at: item.ownerAt,
    from: 'assigned',
    to: 'ongoing',
  );
  final common = <String, dynamic>{
    baseEvent['key'] as String: baseEvent['event'] as Map,
  };
  final server = _bookingDocument(
    id: item.bookingId,
    submissionKey: 'submission_${item.bookingId}',
    status: 'assigned',
    updatedAt: item.base,
    chassisId: null,
    outputs: common,
  );
  final pending = _bookingDocument(
    id: item.bookingId,
    submissionKey: 'submission_${item.bookingId}',
    status: item.pendingStatus,
    updatedAt: item.pendingAt,
    chassisId: item.chassisId,
    outputs: {
      ...common,
      pendingEvent['key'] as String: pendingEvent['event'] as Map,
    },
  );
  final owner = _bookingDocument(
    id: item.ownerId,
    submissionKey: 'submission_${item.ownerId}',
    status: item.ownerStatus,
    updatedAt: item.ownerAt,
    chassisId: item.chassisId,
    outputs: {ownerEvent['key'] as String: ownerEvent['event'] as Map},
  );
  return _ChassisFixture(
    pending: pending,
    serverBooking: server,
    ownerBooking: owner,
    chassis: {
      'id': item.chassisId,
      'current_booking_id': item.ownerId,
      'current_status': 'loaded',
    },
  );
}

Map<String, dynamic> _bookingDocument({
  required String id,
  required String submissionKey,
  required String status,
  required String updatedAt,
  required Object? chassisId,
  required Map<String, dynamic> outputs,
  String? deliveredAt,
  List<String> cleanupPaths = const [],
}) {
  return {
    'id': id,
    'submission_key': submissionKey,
    'created_at': '2026-09-16T10:00:00.000',
    'updated_at': updatedAt,
    'client_status': status,
    'driver_status': status,
    'helper_status': status,
    'chassis_id': chassisId,
    'driver_id': '13',
    'helper_id': '18',
    'client_id': '8',
    'billing_status': 'unpaid',
    'status_outputs': outputs,
    'photo_cleanup_paths': cleanupPaths,
    'photo_cleanup_claims': const <String>[],
    'delivered_at': ?deliveredAt,
  };
}

Map<String, dynamic> _event({
  required String key,
  required String status,
  required String at,
  required String from,
  required String to,
  String by = '8',
}) {
  return {
    'key': key,
    'event': <String, dynamic>{
      'status_key': status,
      'submitted_at': at,
      'submitted_by': by,
      'submitted_role': 'dispatcher',
      'submitted_roles': const ['dispatcher'],
      'fields': <String, dynamic>{},
      'status_form': {
        'is_main_form': true,
        'current_status_key': from,
        'next_status_key': to,
      },
    },
  };
}

Map<String, dynamic> _plainEvent({
  required String key,
  required String status,
  required String at,
}) {
  return {
    'key': key,
    'event': <String, dynamic>{
      'status_key': status,
      'submitted_at': at,
      'submitted_by': '8',
      'submitted_role': 'dispatcher',
      'submitted_roles': const ['dispatcher'],
      'fields': <String, dynamic>{'amount': '100'},
      'status_form': null,
    },
  };
}
