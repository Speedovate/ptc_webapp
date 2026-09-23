// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/services/booking_photo_cleanup.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class TestBookingRequest extends BookingRequest {
  TestBookingRequest(
    MergeAwareFirestore db,
    OfflineMutationQueueService queue, {
    BookingOfflineUploadQueueService? photos,
  }) : super(
         firestore: db,
         offlineMutationQueueService: queue,
         offlineUploadQueueService: photos,
       );
  @override
  Future<void> initialize() async {}
}

class DeleteStorage extends Fake implements FirebaseStorage {
  final deleted = <String>[];
  @override
  Reference ref([String? path]) => DeleteReference(this, path!);
}

class DeleteReference extends Fake implements Reference {
  DeleteReference(this.storage, this.path);
  @override
  final DeleteStorage storage;
  final String path;
  @override
  Future<void> delete() async {
    storage.deleted.add(path);
  }
}

class SlowPhotos extends PhotoStorageService {
  final gate = Completer<void>();
  final started = Completer<void>();
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
    if (!started.isCompleted) started.complete();
    await gate.future;
    return {
      'storage_path': 'new-path',
      'download_url': 'https://example.test/new',
    };
  }
}

Map<String, dynamic> outputs(Object? photo) => {
  'pending': {
    'fields': {'photo': photo},
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'failed booking transaction retains old photo and has no cleanup intent',
    () async {
      final db = MergeAwareFirestore();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryBackend(),
        isOnline: () => false,
      );
      await db.collection('chassis').doc('3').set({
        'current_booking_id': 9,
        'current_status': 'loaded',
      });
      await db.collection('bookings').doc('10').set({
        'id': '10',
        'chassis_id': '3',
        'client_status': 'assigned',
        'status_outputs': outputs({'storage_path': 'old-path'}),
      });
      await expectLater(
        TestBookingRequest(db, queue).saveBooking(
          Booking(
            id: '10',
            chassisId: '3',
            clientStatus: 'ongoing',
            statusOutputs: outputs(null),
          ),
        ),
        throwsException,
      );
      final saved = (await db.collection('bookings').doc('10').get()).data()!;
      expect(BookingPhotoCleanup.references(saved['status_outputs']), {
        'old-path',
      });
      expect(saved['photo_cleanup_paths'], isNull);
    },
  );
  test(
    'successful replay commits cleanup intent and preserves history references',
    () async {
      final db = MergeAwareFirestore();
      var online = false;
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryBackend(),
        isOnline: () => online,
      );
      await db.collection('bookings').doc('10').set({
        'id': '10',
        'status_outputs': outputs({'storage_path': 'old-path'}),
      });
      await queue.queueCollectionDocumentUpsert(
        collectionKey: 'bookings',
        documentId: '10',
        document: {'id': '10', 'status_outputs': outputs(null)},
      );
      online = true;
      await queue.flushPendingMutations();
      final saved = (await db.collection('bookings').doc('10').get()).data()!;
      expect(saved['photo_cleanup_paths'], ['old-path']);
      final retained = <String, dynamic>{
        'status_outputs': outputs({'storage_path': 'old-path'}),
      };
      BookingPhotoCleanup.prepare(retained, saved);
      expect(retained['photo_cleanup_paths'], isEmpty);
    },
  );
  for (final referenced in [true, false]) {
    test(
      'cleanup rechecks server references before deletion: referenced=$referenced',
      () async {
        final db = MergeAwareFirestore();
        final storage = DeleteStorage();
        var online = false;
        final queue = OfflineCleanupQueueService(
          firestore: db,
          storage: storage,
          backend: MemoryBackend(),
          isOnline: () => online,
        );
        await db.collection('bookings').doc('10').set({
          'id': '10',
          'photo_cleanup_paths': ['old-path'],
          'status_outputs': outputs(
            referenced ? {'storage_path': 'old-path'} : null,
          ),
        });
        await queue.queueBookingPhotoDelete('10', 'old-path');
        online = true;
        await queue.flushPendingCleanups();
        expect(storage.deleted, referenced ? isEmpty : ['old-path']);
        final saved = (await db.collection('bookings').doc('10').get()).data()!;
        if (!referenced) {
          expect(saved['photo_cleanup_paths'], isEmpty);
          expect(
            () => BookingPhotoCleanup.prepare({
              'status_outputs': outputs({'storage_path': 'old-path'}),
            }, saved),
            throwsStateError,
          );
        }
      },
    );
  }
  test(
    'online photo save returns with durable bytes while uploader is stalled',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final photos = SlowPhotos();
      final uploads = BookingOfflineUploadQueueService(
        firestore: db,
        backend: backend,
        photoStorageService: photos,
        flushMutations: () async {},
      );
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryBackend(),
        isOnline: () => false,
      );
      await db.collection('bookings').doc('10').set({
        'id': '10',
        'status_outputs': outputs({'storage_path': 'old-path'}),
      });
      final saved = await TestBookingRequest(db, queue, photos: uploads)
          .saveBooking(
            Booking(
              id: '10',
              statusOutputs: outputs({
                'bytes': Uint8List.fromList(
                  img.encodePng(img.Image(width: 2, height: 2)),
                ),
                'name': 'photo.png',
                'mime_type': 'image/png',
              }),
            ),
          )
          .timeout(const Duration(seconds: 2));
      expect(saved.id, '10');
      final rows = backend.data['booking_pending_upload_queue_v1::signed_out']!;
      expect(rows, hasLength(1));
      expect(jsonDecode(rows.single)['bytes_base64'], isNotEmpty);
      final flush = uploads.flushPendingUploads();
      await photos.started.future.timeout(const Duration(seconds: 2));
      final drained = uploads.statusStream.firstWhere(
        (state) => state.pendingCount == 0 && !state.isSyncing,
      );
      photos.gate.complete();
      await flush;
      await drained.timeout(const Duration(seconds: 2));
      expect(
        backend.data['booking_pending_upload_queue_v1::signed_out'],
        isEmpty,
      );
    },
  );
}
