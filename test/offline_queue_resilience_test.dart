import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/kpi/crew_kpi_store.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;

/// A device store whose initialization never answers.
class StalledInitBackend extends MemoryBackend {
  final gate = Completer<void>();
  int initializeCalls = 0;

  @override
  Future<void> initialize() {
    initializeCalls++;
    return gate.future;
  }
}

class _FakeFirebaseStorage implements FirebaseStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StalledPhotoStorage extends PhotoStorageService {
  _StalledPhotoStorage() : super(storage: _FakeFirebaseStorage());

  bool stall = true;
  int uploadCalls = 0;
  Future<void> Function()? onUpload;

  @override
  Future<Map<String, dynamic>> uploadBookingPhoto({
    required Uint8List bytes,
    required String bookingId,
    required String statusKey,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    uploadCalls++;
    if (onUpload != null) {
      await onUpload!();
    }
    if (stall) {
      return Completer<Map<String, dynamic>>().future;
    }
    return {
      'name': fileName,
      'download_url': 'https://example.test/booking-$fileName',
      'storage_path':
          'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/$fileName',
      'mime_type': mimeType ?? 'image/png',
      'size': size ?? bytes.length,
    };
  }

  @override
  Future<Map<String, dynamic>> uploadUserPhoto({
    required Uint8List bytes,
    required String userId,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    uploadCalls++;
    if (onUpload != null) {
      await onUpload!();
    }
    if (stall) {
      return Completer<Map<String, dynamic>>().future;
    }
    return {
      'name': fileName,
      'download_url': 'https://example.test/user-$fileName',
      'storage_path': 'users/$userId/$fieldKey/$fileName',
      'mime_type': mimeType ?? 'image/png',
      'size': size ?? bytes.length,
    };
  }

  @override
  Future<void> deleteByPath(String? storagePath) async {}
}

Map<String, dynamic> _booking({
  required String id,
  required String driver,
  required String helper,
  String? make = '4',
  String status = 'delivered',
  String deliveredAt = '2026-09-19T10:00:00Z',
  String createdAt = '2026-09-18T10:00:00Z',
}) => {
  'id': id,
  'driver_id': driver,
  'helper_id': helper,
  'vehicle_make_id': make,
  'client_status': status,
  'delivered_at': deliveredAt,
  'created_at': createdAt,
  'submission_key': 'submission-$id',
  'status_outputs': {
    'book__1': {
      'status_key': 'book',
      'submitted_at': '2026-09-18T10:00:00Z',
      'fields': {
        'origin': 'Puerto Princesa City',
        'destination': 'Puerto Princesa City',
        'destination_barangay': 'San Jose',
      },
    },
  },
};

Future<void> _seedKpi(FakeFirebaseFirestore db) async {
  await db.collection('operations_catalog').doc('settings').set({});
  await db.collection('pm_kpi_records').doc('ZmxlZXQ_settings').set({
    'kind': 'settings',
  });
  await db.collection('vehicle_makes').doc('4').set({
    'code': 'PM7',
    'driver_id': '13',
    'helper_id': '18',
  });
  await db
      .collection('bookings')
      .doc('1')
      .set(_booking(id: '1', driver: '13', helper: '18'));
}

CrewKpiStore _store(FakeFirebaseFirestore db, {required UserModel user}) =>
    CrewKpiStore(
      firestore: db,
      cache: FirestoreCacheStore(),
      currentUser: () async => user,
      allowed: (_) => true,
      online: () => true,
      pending: () async => const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.writeString('paltranco_current_user_id', '13');
  });
  tearDown(() async {
    final auth = createAuthStorageBackend();
    await auth.remove('paltranco_current_user_id');
    await auth.remove('paltranco_known_session_user_ids');
  });

  group('crew KPI assignment rules', () {
    test('a deactivated make is not an assignment and legacy null is', () async {
      const driver = UserModel(id: '13', role: 'driver');
      final db = FakeFirebaseFirestore();
      await _seedKpi(db);
      await db.collection('vehicle_makes').doc('5').set({
        'code': 'PM8',
        'driver_id': '13',
        'helper_id': '18',
        'is_active': false,
      });
      await db
          .collection('bookings')
          .doc('2')
          .set(
            _booking(
              id: '2',
              driver: '13',
              helper: '18',
              make: '5',
              deliveredAt: '2026-09-20T10:00:00Z',
            ),
          );

      // A day this crew member never worked, on a truck that no longer counts.
      await db.collection('pm_kpi_records').doc('NQ_2026-09-22').set({
        'kind': 'day',
        'day': '2026-09-22',
        'salary_confirmed': true,
        'daily_rate': 999,
        'driver_salary': 5000,
        'trip_rates': [
          {
            'signature': 'other',
            'booking_id': '9',
            'driver_id': '77',
            'helper_id': '88',
            'driver': 4000,
            'helper': 900,
            'route': 'San Jose',
          },
        ],
      });

      final data = (await _store(db, user: driver).load(driver))!;
      expect((data['makes'] as List).map((m) => m['id']), [
        '4',
      ], reason: 'an is_active=false make must not be a current assignment');
      expect(
        (data['makes'] as List).single['is_active'],
        isNull,
        reason: 'a legacy make without the flag keeps its assignment',
      );
      final records = (data['records'] as List).cast<Map>();
      expect(
        records.where((r) => r['make_id'] == '5'),
        isEmpty,
        reason: 'a day this crew member never worked must not be loaded',
      );
      expect(jsonEncode(data), isNot(contains('5000')));
    });

    test('a historical booking never becomes a current assignment', () async {
      const driver = UserModel(id: '13', role: 'driver');
      final db = FakeFirebaseFirestore();
      await _seedKpi(db);
      // Truck 4 is now assigned to another crew member.
      await db.collection('vehicle_makes').doc('4').set({
        'code': 'PM7',
        'driver_id': '77',
        'helper_id': '88',
      });
      await db.collection('bookings').doc('3').set({
        ..._booking(
          id: '3',
          driver: '13',
          helper: '18',
          make: null,
          deliveredAt: '2026-09-21T10:00:00Z',
        ),
        'created_at': '2026-09-20T10:00:00Z',
      });

      final data = (await _store(db, user: driver).load(driver))!;
      expect(
        data['makes'],
        isEmpty,
        reason: 'no make is assigned to this crew member any more',
      );
      final rows = crewKpiTransactions(driver, data);
      final trip = rows.firstWhere(
        (row) => row['label'] == 'Booking 3' && row['type'] == 'Share',
      );
      expect(
        trip['status'],
        'Unconfirmed',
        reason: 'a truck that is no longer assigned cannot confirm this trip',
      );
    });

    test(
      'a pre-cutoff legacy booking still resolves its confirmed truck',
      () async {
        const driver = UserModel(id: '17', role: 'driver');
        final db = FakeFirebaseFirestore();
        await db.collection('operations_catalog').doc('settings').set({});
        await db.collection('pm_kpi_records').doc('ZmxlZXQ_settings').set({
          'kind': 'settings',
        });
        await db.collection('vehicle_makes').doc('2').set({'code': 'PM5'});
        await db.collection('bookings').doc('7').set({
          ..._booking(
            id: '7',
            driver: '17',
            helper: '14',
            make: null,
            createdAt: '2026-09-01T10:00:00Z',
            deliveredAt: '2026-09-02T10:00:00Z',
          ),
        });

        final data = (await _store(db, user: driver).load(driver))!;
        expect(
          (data['legacy_makes'] as List).map((m) => m['id']),
          contains('2'),
        );
        expect(
          crewKpiTransactions(
            driver,
            data,
          ).where((row) => row['label'] == 'Booking 7'),
          isNotEmpty,
        );
      },
    );
  });

  group('bounded local stores', () {
    test('mutation queue initialization cannot hang forever', () async {
      final queue = OfflineMutationQueueService(
        backend: StalledInitBackend(),
        firestore: FakeFirebaseFirestore(),
        isOnline: () => false,
        localStorageTimeout: const Duration(milliseconds: 40),
      );

      await expectLater(queue.initialize(), throwsA(isA<TimeoutException>()));
      expect(queue.currentStatus.isSyncing, isFalse);
    });

    test('cleanup queue initialization cannot hang forever', () async {
      final queue = OfflineCleanupQueueService(
        backend: StalledInitBackend(),
        isOnline: () => false,
        localStorageTimeout: const Duration(milliseconds: 40),
      );

      await expectLater(queue.initialize(), throwsA(isA<TimeoutException>()));
      expect(queue.currentStatus.isSyncing, isFalse);
    });

    test('media queue initialization cannot hang forever', () async {
      final queue = OfflineMediaSyncService(
        backend: StalledInitBackend(),
        firestore: FakeFirebaseFirestore(),
        isOnline: () => false,
        localStorageTimeout: const Duration(milliseconds: 40),
      );

      await expectLater(queue.initialize(), throwsA(isA<TimeoutException>()));
      expect(queue.currentStatus.isSyncing, isFalse);
    });
  });

  group('media flush lock', () {
    test(
      'a stalled flush releases the lock and keeps the entry queued',
      () async {
        final db = FakeFirebaseFirestore();
        await db.collection('users').doc('13').set({
          'id': '13',
          'photo': 'https://example.test/old.png',
        });
        final backend = MemoryBackend();
        await backend.writeStringList('offline_media_sync_queue_v1::13', [
          jsonEncode({
            'id': 'media_1',
            'kind': 'userUpload',
            'user_id': '13',
            'field_key': 'photo',
            'file_name': 'new.png',
            'bytes_base64': base64Encode([1, 2, 3]),
            'original_value': 'https://example.test/old.png',
            'created_at': '2026-09-19T10:00:00.000Z',
            'retry_count': 0,
          }),
        ]);
        final uploads = _StalledPhotoStorage();
        final queue = OfflineMediaSyncService(
          backend: backend,
          firestore: db,
          photoStorageService: uploads,
          isOnline: () => true,
          flushTimeout: const Duration(milliseconds: 60),
        );

        await queue.flushPendingOperations().timeout(
          const Duration(seconds: 10),
        );

        expect(queue.currentStatus.isSyncing, isFalse);
        expect(
          await backend.readStringList('offline_media_sync_queue_v1::13'),
          hasLength(1),
          reason: 'a timed-out flush must not drop the queued photo',
        );

        // The released lock lets a later attempt run again.
        uploads.stall = false;
        await queue.flushPendingOperations().timeout(
          const Duration(seconds: 10),
        );
        expect(uploads.uploadCalls, greaterThan(0));
      },
    );
  });

  group('media identity waits', () {
    test(
      'an unresolvable identity keeps the entry with a visible reason',
      () async {
        final db = FakeFirebaseFirestore();
        final backend = MemoryBackend();
        await backend.writeStringList('offline_media_sync_queue_v1::13', [
          jsonEncode({
            'id': 'media_provisional',
            'kind': 'userUpload',
            'user_id': 'offline_user_9',
            'field_key': 'photo',
            'file_name': 'new.png',
            'bytes_base64': base64Encode([1, 2, 3]),
            'original_value': null,
            'created_at': '2026-09-19T10:00:00.000Z',
            'retry_count': 0,
          }),
        ]);
        final queue = OfflineMediaSyncService(
          backend: backend,
          firestore: db,
          photoStorageService: _StalledPhotoStorage(),
          isOnline: () => true,
        );

        await queue.flushPendingOperations();

        final retained = jsonDecode(
          (await backend.readStringList(
            'offline_media_sync_queue_v1::13',
          )).single,
        );
        expect(
          retained['last_error'],
          contains('temporarily unavailable'),
          reason: 'a dropped entry would look identical to a successful upload',
        );
        expect((await queue.readPendingItems('13')).single.hasError, isTrue);
      },
    );
  });

  group('upload failures stay visible', () {
    const storageKey = 'booking_pending_upload_queue_v1::13';

    Future<BookingOfflineUploadQueueService> queuePhoto({
      required FakeFirebaseFirestore db,
      required MemoryBackend backend,
      required _StalledPhotoStorage uploads,
    }) async {
      final service = BookingOfflineUploadQueueService(
        backend: backend,
        firestore: db,
        photoStorageService: uploads,
        flushMutations: () async {},
        mutationQueue: OfflineMutationQueueService(
          backend: MemoryBackend(),
          firestore: db,
          isOnline: () => false,
        ),
      );
      await service.initialize();
      await service.enqueueBookingPhoto(
        bookingId: '1',
        statusKey: 'delivered',
        fieldKey: 'proof',
        bytes: Uint8List.fromList(
          img.encodePng(img.Image(width: 2, height: 2)),
        ),
        fileName: 'proof.png',
      );
      final queued =
          jsonDecode((await backend.readStringList(storageKey)).single)
              as Map<String, dynamic>;
      // The server owns this placeholder when the upload starts.
      await db.collection('bookings').doc('1').set({
        'id': '1',
        'status_outputs': {
          'delivered': {
            'status_key': 'delivered',
            'fields': {
              'proof': {'pending_upload_id': queued['id']},
            },
          },
        },
      });
      return service;
    }

    test(
      'a permanent failure that still applies keeps a visible error',
      () async {
        final db = FakeFirebaseFirestore();
        final backend = MemoryBackend();
        final uploads = _StalledPhotoStorage()
          ..onUpload = () async =>
              throw StateError('storage rejected this upload permanently');
        final service = await queuePhoto(
          db: db,
          backend: backend,
          uploads: uploads,
        );

        // Let the enqueue-triggered flush finish, then run a deterministic cycle.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await service.flushPendingUploads();

        final retained =
            jsonDecode((await backend.readStringList(storageKey)).single)
                as Map<String, dynamic>;
        expect(retained['retry_count'], greaterThanOrEqualTo(1));
        expect(retained['last_error'], contains('permanently'));
        final item = (await service.readPendingItems('13')).single;
        expect(item.hasError, isTrue);
        expect(item.errorMessage, contains('permanently'));
      },
    );
  });
}
