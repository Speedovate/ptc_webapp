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
        isTrue,
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
      final chassis = (await db.collection('chassis').doc(item.chassisId).get())
          .data()!;
      expect(chassis['current_booking_id'], item.ownerId);
      expect(chassis['current_status'], 'loaded');
      final owner = (await db.collection('bookings').doc(item.ownerId).get())
          .data()!;
      expect(owner['chassis_id'], item.chassisId);
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
  });

  final String bookingId;
  final String chassisId;
  final String ownerId;
  final String ownerStatus;
  final String pendingStatus;
  final String pendingAt;
  final String ownerAt;
  final String base;
}

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
    ownerAt: '2026-09-25T09:28:06.463',
    base: '2026-09-17T06:14:52.586Z',
  ),
  _ChassisCase(
    bookingId: '140',
    chassisId: '1',
    ownerId: '100',
    ownerStatus: 'check',
    pendingStatus: 'delivered',
    pendingAt: '2026-09-25T07:57:26.642',
    ownerAt: '2026-09-25T01:28:01.137Z',
    base: '2026-09-24T13:46:28.109',
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
    ownerAt: '2026-09-23T11:00:00.000Z',
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
