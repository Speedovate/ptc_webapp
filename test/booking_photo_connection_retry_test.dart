import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class _InterruptedPhotos extends PhotoStorageService {
  bool connected = false;
  int attempts = 0;
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
    attempts++;
    if (!connected) {
      throw Exception('Please check your internet connection and try again.');
    }
    return {
      'name': fileName,
      'size': size,
      'mime_type': mimeType,
      'storage_path':
          'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/photo.jpg',
      'download_url': 'https://example.test/photo.jpg',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final row in [
    (
      '146',
      'ongoing__1790921635088000',
      'booking_upload_1790921635280000_213058',
      '2026-10-02T06:13:55.211Z',
      'camera_1790921628998.jpg',
      62416,
    ),
    (
      '147',
      'ongoing__1790921665124000',
      'booking_upload_1790921665345000_8a193e12',
      '2026-10-02T06:14:25.288Z',
      'camera_1790921658859.jpg',
      63819,
    ),
  ]) {
    test(
      'Booking ${row.$1} interrupted upload retains bytes and retries successfully',
      () async {
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        final photos = _InterruptedPhotos();
        const key = 'booking_pending_upload_queue_v1::signed_out';
        final original = {
          'id': row.$3,
          'booking_id': row.$1,
          'status_key': row.$2,
          'field_key': 'delivery_form_photo',
          'bytes_base64': 'AQID',
          'file_name': row.$5,
          'mime_type': 'image/jpeg',
          'size': row.$6,
          'created_at': row.$4,
          'waiting_for_commit': false,
          'retry_count': 2,
          'last_error':
              'Exception: Please check your internet connection and try again.',
        };
        backend.data[key] = [jsonEncode(original)];
        // Model the server placeholder required for an upload; the network logs
        // do not include a server snapshot, so this is a controlled retry scenario.
        final server = {
          'id': row.$1,
          'client_status': 'delivered',
          'updated_at': row.$4,
          'delivered_at': row.$4,
          'status_outputs': {
            row.$2: {
              'submitted_at': row.$4,
              'fields': {
                'delivery_form_photo': {
                  'pending_upload': true,
                  'pending_upload_id': row.$3,
                  'name': row.$5,
                  'size': row.$6,
                  'mime_type': 'image/jpeg',
                },
              },
            },
          },
        };
        await db.collection('bookings').doc(row.$1).set(server);
        final service = BookingOfflineUploadQueueService(
          backend: backend,
          firestore: db,
          photoStorageService: photos,
          flushMutations: () async {},
          mutationQueue: OfflineMutationQueueService(
            backend: backend,
            firestore: db,
            isOnline: () => false,
          ),
        );
        await service.flushPendingUploads();
        final retained = jsonDecode(backend.data[key]!.single);
        expect(retained['bytes_base64'], original['bytes_base64']);
        expect(retained['created_at'], original['created_at']);
        expect(retained['retry_count'], 3);
        expect(
          (await db.collection('bookings').doc(row.$1).get()).data(),
          server,
        );
        photos.connected = true;
        await service.flushPendingUploads();
        expect(backend.data[key], isEmpty);
        expect(photos.attempts, 2);
        final saved = (await db.collection('bookings').doc(row.$1).get())
            .data()!;
        expect(saved['delivered_at'], server['delivered_at']);
        expect(saved['updated_at'], server['updated_at']);
        expect(
          saved['status_outputs'][row
              .$2]['fields']['delivery_form_photo']['pending_upload_id'],
          isNull,
        );
        await service.flushPendingUploads();
        expect(photos.attempts, 2);
      },
    );
  }
}
