import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/utils/functions.dart';

import 'booking_id_resolver_test.dart' show MemoryBackend;

class FailingBackend extends MemoryBackend {
  bool failNextWrite = false;

  @override
  Future<void> writeStringList(String key, List<String> values) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('simulated interrupted local write');
    }
    await super.writeStringList(key, values);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'staged booking cannot replay and survives restart with original media and time',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      var online = false;
      final key = 'booking_8_9_1_1791929171081000';
      final id = BookingIdResolver.temporaryId(key);
      final actionAt = '2026-10-14T06:06:16.112Z';
      final photo = Uint8List.fromList([1, 2, 3, 255]);
      final source = <String, dynamic>{
        'id': id,
        'submission_key': key,
        'created_at': actionAt,
        'updated_at': actionAt,
        'status_outputs': {
          'book__1791929171081000': {
            'submitted_at': actionAt,
            'fields': {
              'waybill_photo': {'name': 'waybill.jpg', 'bytes': photo},
            },
          },
        },
      };
      final service = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      await service.stageOfflineBookingCreate(
        provisionalId: id,
        submissionKey: key,
        document: source,
      );
      online = true;
      await service.flushPendingMutations();
      expect((await db.collection('bookings').get()).docs, isEmpty);
      expect(service.currentStatus.failedCount, 0);

      final restarted = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      final staged = await restarted.readStagedOfflineBookingCreates();
      expect(staged, hasLength(1));
      final recovered = Map<String, dynamic>.from(
        staged.single['document'] as Map,
      );
      final outputs = Map<String, dynamic>.from(
        recovered['status_outputs'] as Map,
      );
      final book = Map<String, dynamic>.from(outputs.values.single as Map);
      final fields = Map<String, dynamic>.from(book['fields'] as Map);
      expect(decodePhotoBytes(fields['waybill_photo']), photo);
      expect(recovered['created_at'], actionAt);
      expect(book['submitted_at'], actionAt);

      fields['waybill_photo'] = {'name': 'waybill.jpg', 'pending_upload': true};
      book['fields'] = fields;
      outputs[outputs.keys.single] = book;
      recovered['status_outputs'] = outputs;
      await restarted.queueOfflineBookingCreate(
        provisionalId: id,
        submissionKey: key,
        document: recovered,
        onlyIfStaged: true,
      );
      await restarted.flushPendingMutations();
      final bookings = (await db.collection('bookings').get()).docs;
      expect(bookings, hasLength(1));
      expect(bookings.single.data()['created_at'], actionAt);
      expect(
        (bookings.single.data()['status_outputs'] as Map)
            .values
            .single['submitted_at'],
        actionAt,
      );
      expect(await restarted.readStagedOfflineBookingCreates(), isEmpty);
    },
  );

  test(
    'failed final queue write leaves the complete staged source for retry',
    () async {
      final backend = FailingBackend();
      final db = FakeFirebaseFirestore();
      final service = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => false,
      );
      const key = 'booking_8_9_1_1791957845495000';
      final id = BookingIdResolver.temporaryId(key);
      final source = <String, dynamic>{
        'id': id,
        'submission_key': key,
        'created_at': '2026-10-14T06:04:10.527Z',
        'status_outputs': {
          'book': {
            'fields': {
              'photo': {
                'bytes': Uint8List.fromList([9, 8, 7]),
              },
            },
          },
        },
      };
      await service.stageOfflineBookingCreate(
        provisionalId: id,
        submissionKey: key,
        document: source,
      );
      backend.failNextWrite = true;
      await expectLater(
        service.queueOfflineBookingCreate(
          provisionalId: id,
          submissionKey: key,
          document: {...source, 'status_outputs': {}},
        ),
        throwsStateError,
      );
      final restarted = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => false,
      );
      final staged = await restarted.readStagedOfflineBookingCreates();
      expect(staged, hasLength(1));
      final recovered = staged.single['document'] as Map;
      expect(recovered['created_at'], source['created_at']);
      final photo =
          ((recovered['status_outputs'] as Map)['book']
              as Map)['fields']['photo'];
      expect(decodePhotoBytes(photo), Uint8List.fromList([9, 8, 7]));
    },
  );

  test(
    'failed first source write stops before any booking is accepted',
    () async {
      final backend = FailingBackend()..failNextWrite = true;
      final service = OfflineMutationQueueService(
        firestore: FakeFirebaseFirestore(),
        backend: backend,
        isOnline: () => false,
      );
      const key = 'booking_8_9_1_1791957845495000';
      final id = BookingIdResolver.temporaryId(key);
      await expectLater(
        service.stageOfflineBookingCreate(
          provisionalId: id,
          submissionKey: key,
          document: {'id': id, 'submission_key': key},
        ),
        throwsStateError,
      );
      expect(await service.readStagedOfflineBookingCreates(), isEmpty);
    },
  );

  test(
    'an overlapping edit cannot replace the only saved photo source',
    () async {
      final service = OfflineMutationQueueService(
        firestore: FakeFirebaseFirestore(),
        backend: MemoryBackend(),
        isOnline: () => false,
      );
      const key = 'booking_8_9_1_1791960701949000';
      final id = BookingIdResolver.temporaryId(key);
      await service.stageOfflineBookingCreate(
        provisionalId: id,
        submissionKey: key,
        document: {
          'id': id,
          'submission_key': key,
          'status_outputs': {
            'book': {
              'fields': {
                'photo': {
                  'bytes': Uint8List.fromList([5, 4, 3]),
                },
              },
            },
          },
        },
      );
      await expectLater(
        service.queueCollectionDocumentUpsert(
          collectionKey: 'bookings',
          documentId: id,
          document: {'id': id, 'status_outputs': {}},
        ),
        throwsStateError,
      );
      final staged = await service.readStagedOfflineBookingCreates();
      expect(staged, hasLength(1));
      final recovered = staged.single['document'] as Map;
      final photo =
          ((recovered['status_outputs'] as Map)['book']
              as Map)['fields']['photo'];
      expect(decodePhotoBytes(photo), Uint8List.fromList([5, 4, 3]));
    },
  );

  test(
    'booking request resumes staged media and finalizes the original create',
    () async {
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      final mutations = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => false,
      );
      final photos = BookingOfflineUploadQueueService(
        firestore: db,
        backend: backend,
        mutationQueue: mutations,
        flushMutations: () async {},
      );
      const key = 'booking_8_9_1_1791929171081000';
      final id = BookingIdResolver.temporaryId(key);
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      await mutations.stageOfflineBookingCreate(
        provisionalId: id,
        submissionKey: key,
        document: {
          'id': id,
          'submission_key': key,
          'created_at': '2026-10-14T06:06:16.112Z',
          'status_outputs': {
            'book__1791929171081000': {
              'submitted_at': '2026-10-14T06:06:16.112Z',
              'fields': {
                'waybill_photo': {
                  'name': 'waybill.png',
                  'mime_type': 'image/png',
                  'bytes': bytes,
                },
              },
            },
          },
        },
      );
      await BookingRequest(
        firestore: db,
        offlineMutationQueueService: mutations,
        offlineUploadQueueService: photos,
      ).resumeStagedOfflineBookingCreates();
      expect(await mutations.readStagedOfflineBookingCreates(), isEmpty);
      expect(await mutations.readPendingItems('signed_out'), hasLength(1));
      expect(await photos.readPendingItems('signed_out'), hasLength(1));
    },
  );

  test(
    'booking initialization rechecks staged sources after sign-in',
    () async {
      final auth = createAuthStorageBackend();
      await auth.initialize();
      await auth.writeString('paltranco_current_user_id', '8');
      final db = FakeFirebaseFirestore();
      final backend = MemoryBackend();
      final mutations = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => false,
      );
      final photos = BookingOfflineUploadQueueService(
        firestore: db,
        backend: backend,
        mutationQueue: mutations,
        flushMutations: () async {},
      );
      const key = 'booking_8_9_1_1791929171081000';
      final id = BookingIdResolver.temporaryId(key);
      await mutations.stageOfflineBookingCreate(
        provisionalId: id,
        submissionKey: key,
        document: {'id': id, 'submission_key': key, 'status_outputs': {}},
      );
      await auth.remove('paltranco_current_user_id');
      final request = BookingRequest(
        firestore: db,
        offlineMutationQueueService: mutations,
        offlineUploadQueueService: photos,
      );
      await request.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await auth.writeString('paltranco_current_user_id', '8');
      expect(await mutations.readStagedOfflineBookingCreates(), hasLength(1));
      await request.initialize();
      for (var attempt = 0; attempt < 40; attempt++) {
        if ((await mutations.readStagedOfflineBookingCreates()).isEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await mutations.readStagedOfflineBookingCreates(), isEmpty);
      expect(await mutations.readPendingItems('8'), hasLength(1));
      mutations.dispose();
      await auth.remove('paltranco_current_user_id');
    },
  );
}
