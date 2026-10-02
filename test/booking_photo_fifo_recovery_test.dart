import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class _Photos extends PhotoStorageService {
  final calls = <String>[];
  bool failOld = false;
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
    calls.add(fileName);
    if (failOld && fileName == 'old.jpg') throw StateError('upload failed');
    return {
      'name': fileName,
      'storage_path': 'bookings/$bookingId/$fileName',
      'download_url': 'https://example.test/$fileName',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final failOld in [false, true]) {
    test(
      'Booking 63 preserves older photo before latest, failure=$failOld',
      () async {
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        final photos = _Photos()..failOld = failOld;
        const key = 'booking_pending_upload_queue_v1::signed_out';
        const oldStatus = 'ongoing__1790906099857000';
        const latestStatus = 'ongoing__1790910838388000';
        const originalTime = '2026-10-02T01:55:00.060Z';
        Map<String, dynamic> entry(
          String id,
          String status,
          String at,
          String name,
        ) => {
          'id': id,
          'booking_id': '63',
          'status_key': status,
          'field_key': 'delivery_form_photo',
          'file_name': name,
          'bytes_base64': 'AQID',
          'created_at': at,
          'waiting_for_commit': true,
        };
        final old = entry('old', oldStatus, originalTime, 'old.jpg');
        final latest = entry(
          'latest',
          latestStatus,
          '2026-10-02T03:13:58.712Z',
          'latest.jpg',
        );
        backend.data[key] = [jsonEncode(latest), jsonEncode(old)];
        final server = <String, dynamic>{
          'id': '63',
          'client_status': 'delivered',
          'updated_at': '2026-10-02T11:13:58.388',
          'delivered_at': '2026-10-02T03:13:58.388Z',
          'status_outputs': {
            latestStatus: {
              'submitted_at': '2026-10-02T11:13:58.388',
              'status_form': {'next_status_key': 'delivered'},
              'fields': {
                'delivery_form_number': '036603',
                'delivery_form_photo': {
                  'pending_upload_id': 'latest',
                  'pending_upload': true,
                },
              },
            },
          },
        };
        await db.collection('bookings').doc('63').set(server);
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
        if (failOld) {
          expect(photos.calls, ['old.jpg']);
          expect(backend.data[key], hasLength(2));
          expect(
            (await db.collection('bookings').doc('63').get()).data(),
            server,
          );
          photos.failOld = false;
          photos.calls.clear();
          await service.flushPendingUploads();
        }
        expect(photos.calls, ['old.jpg', 'latest.jpg']);
        expect(backend.data[key], isEmpty);
        final saved = (await db.collection('bookings').doc('63').get()).data()!;
        expect(saved['client_status'], server['client_status']);
        expect(saved['delivered_at'], server['delivered_at']);
        expect(saved['updated_at'], server['updated_at']);
        final outputs = saved['status_outputs'] as Map;
        expect(
          outputs.containsKey(oldStatus),
          false,
          reason: 'Do not invent the missing delivery form',
        );
        expect(outputs['photo__old']['submitted_at'], originalTime);
        expect(
          outputs['photo__old']['fields']['delivery_form_photo']['name'],
          'old.jpg',
        );
        expect(
          outputs[latestStatus]['fields']['delivery_form_photo']['name'],
          'latest.jpg',
        );
        expect(
          outputs[latestStatus]['fields']['delivery_form_number'],
          '036603',
        );
        // Replaying an old queue snapshot must not upload the recovered photo again.
        backend.data[key] = [jsonEncode(old)];
        await service.flushPendingUploads();
        expect(photos.calls, ['old.jpg', 'latest.jpg']);
        expect(backend.data[key], isEmpty);
      },
    );
  }
}
