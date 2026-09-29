import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'booking_photo_commit_safety_test.dart' show SlowPhotos;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final recoverable in [true, false]) {
    test(
      'photo marker recovery preserves action time and bytes: $recoverable',
      () async {
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        const key = 'booking_pending_upload_queue_v1::signed_out';
        const at = '2026-09-25T07:04:33.425Z';
        final entry = {
          'id': 'upload1',
          'booking_id': '146',
          'status_key': 'old-key',
          'field_key': 'delivery_form_photo',
          'bytes_base64': 'AQID',
          'file_name': 'delivery.jpg',
          'mime_type': 'image/jpeg',
          'size': 3,
          'waiting_for_commit': true,
          'created_at': at,
          'retry_count': 0,
        };
        backend.data[key] = [jsonEncode(entry)];
        await db.collection('bookings').doc('146').set({
          'updated_at': '2026-09-26T08:00:00.000Z',
          'status_outputs': {
            'new-key': {
              'fields': {
                if (recoverable)
                  'delivery_form_photo': {
                    'pending_upload_id': 'upload1',
                    'pending_upload': true,
                    'name': 'delivery.jpg',
                    'mime_type': 'image/jpeg',
                    'size': 3,
                  },
              },
            },
          },
        });
        final photos = SlowPhotos();
        final service = BookingOfflineUploadQueueService(
          firestore: db,
          backend: backend,
          photoStorageService: photos,
          flushMutations: () async {},
          mutationQueue: OfflineMutationQueueService(
            firestore: db,
            backend: MemoryBackend(),
            isOnline: () => false,
          ),
        );
        final flush = service.flushPendingUploads();
        if (recoverable) {
          await photos.started.future.timeout(const Duration(seconds: 3));
          final done = service.statusStream.firstWhere(
            (s) => !s.isSyncing && s.pendingCount == 0,
          );
          photos.gate.complete();
          await flush;
          await done.timeout(const Duration(seconds: 3));
          expect(backend.data[key], isEmpty);
          final saved = (await db.collection('bookings').doc('146').get())
              .data()!;
          expect(saved['updated_at'], '2026-09-26T08:00:00.000Z');
          expect(
            saved['status_outputs']['new-key']['fields']['delivery_form_photo']['download_url'],
            'https://example.test/new',
          );
        } else {
          await flush;
          await service.flushPendingUploads();
          final kept = jsonDecode(backend.data[key]!.single);
          expect(kept['bytes_base64'], 'AQID');
          expect(kept['created_at'], at);
          expect(photos.started.isCompleted, isFalse);
        }
      },
    );
  }
}
