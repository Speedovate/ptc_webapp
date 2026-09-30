import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;
import 'booking_photo_commit_safety_test.dart' show SlowPhotos;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final count in [0, 1, 2]) {
    test(
      'missing reservation resolves only unique committed identity: $count',
      () async {
        final db = FakeFirebaseFirestore();
        const key = 'booking_8_9_1_1790738544417000';
        for (var i = 1; i <= count; i++) {
          await db.collection('bookings').doc('$i').set({
            'id': '$i',
            'submission_key': key,
          });
        }
        expect(
          await BookingIdResolver(firestore: db).resolve('offline_$key'),
          count == 1 ? '1' : null,
        );
        expect((await db.collection('manage_id').get()).docs, isEmpty);
      },
    );
  }
  test(
    'photo checks mutation namespace for same owner before upload',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      const photoKey = 'booking_pending_upload_queue_v1::signed_out';
      backend.data[photoKey] = [
        jsonEncode({
          'id': 'photo1',
          'booking_id': '146',
          'status_key': 'ongoing',
          'field_key': 'photo',
          'bytes_base64': 'AQID',
          'file_name': 'photo.jpg',
          'waiting_for_commit': true,
          'created_at': '2026-09-25T07:04:33Z',
        }),
      ];
      backend.data[storageKey] = [
        jsonEncode({
          'id': 'edit1',
          'kind': 'collectionDocumentUpsert',
          'collection_key': 'bookings',
          'target_id': '146',
          'payload': {'id': '146'},
          'is_blocked': true,
          'last_error': 'needs review',
          'created_at': '2026-09-25T07:04:33Z',
        }),
      ];
      final photos = SlowPhotos();
      final queue = BookingOfflineUploadQueueService(
        backend: backend,
        firestore: db,
        photoStorageService: photos,
        mutationQueue: OfflineMutationQueueService(
          backend: backend,
          firestore: db,
          isOnline: () => false,
        ),
        flushMutations: () async {},
      );
      await queue.flushPendingUploads();
      await queue.flushPendingUploads();
      final saved = jsonDecode(backend.data[photoKey]!.single);
      expect(saved['wait_reason'], 'booking_mutation_pending');
      expect(saved['bytes_base64'], 'AQID');
      expect(photos.started.isCompleted, false);
      expect(backend.data[storageKey], hasLength(1));
    },
  );
  for (final legacyBlocked in [false, true]) {
    for (final owner in ['99', '86', null]) {
      test(
        'acknowledge detached delivered chassis only if reassignment proven: $owner, legacy blocked: $legacyBlocked',
        () async {
          final db = MergeAwareFirestore();
          final backend = MemoryBackend();
          final local = {
            'id': '86',
            'submission_key': 'same',
            'chassis_id': '8',
            'client_status': 'delivered',
            'updated_at': '2026-09-19T18:58:31.495',
          };
          final remote = {
            ...local,
            'chassis_id': null,
            'photo_cleanup_paths': [],
          };
          await db.collection('bookings').doc('86').set(remote);
          await db.collection('chassis').doc('8').set({
            'current_booking_id': owner,
          });
          final queue = OfflineMutationQueueService(
            backend: backend,
            firestore: db,
            isOnline: () => false,
          );
          await queue.queueCollectionDocumentUpsert(
            collectionKey: 'bookings',
            documentId: '86',
            document: local,
            baseUpdatedAt: '2026-09-17T02:10:30.386Z',
          );
          if (legacyBlocked) {
            final persisted = Map<String, dynamic>.from(
              jsonDecode(backend.data[storageKey]!.single) as Map,
            );
            persisted['is_blocked'] = true;
            persisted['retry_count'] = 1;
            persisted['last_error'] =
                'Bad state: Sync conflict: booking changed remotely before applying this edit.';
            persisted['created_at'] = '2026-09-19T10:58:31.694Z';
            backend.data[storageKey] = [jsonEncode(persisted)];
          }
          final online = OfflineMutationQueueService(
            backend: backend,
            firestore: db,
            isOnline: () => true,
          );
          await online.flushPendingMutations();
          expect(backend.data[storageKey], hasLength(owner == '99' ? 0 : 1));
          expect(
            (await db.collection('bookings').doc('86').get()).data(),
            remote,
          );
          expect((await db.collection('chassis').doc('8').get()).data(), {
            'current_booking_id': owner,
          });
        },
      );
    }
  }
}
