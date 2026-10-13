import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class _Photos extends PhotoStorageService {
  int uploads = 0;
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
    uploads++;
    return {
      'name': fileName,
      'size': size,
      'mime_type': mimeType,
      'download_url': 'https://example.test/photo',
      'storage_path':
          'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/photo.jpg',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Dispatcher 8 reconnect drains creates, assignments and all local photos',
    () async {
      final auth = createAuthStorageBackend();
      await auth.writeString('paltranco_current_user_id', '8');
      await auth.writeStringList('paltranco_known_session_user_ids', ['8']);
      final disk = MemoryBackend();
      final db = MergeAwareFirestore();
      var online = false;
      const mutationKey = 'offline_mutation_queue_v1::8';
      const photoKey = 'booking_pending_upload_queue_v1::8';
      final mutations = <String>[];
      final photos = <String>[];
      final documents = <Map<String, dynamic>>[];
      for (final timestamp in [
        '1791850210240000',
        '1791852980581000',
        '1791853133205000',
        '1791856597066000',
      ]) {
        final key = 'booking_8_9_1_$timestamp';
        final id = 'offline_$key';
        final upload = 'photo_$timestamp';
        final status = 'book__$timestamp';
        final doc = <String, dynamic>{
          'id': id,
          'submission_key': key,
          'client_id': '9',
          'created_at': '2026-10-13T08:10:10.240',
          'updated_at': '2026-10-13T08:10:10.240',
          'client_status': 'pending',
          'driver_status': 'pending',
          'helper_status': 'pending',
          'billing_status': 'unbilled',
          'delivered_at': null,
          'status_outputs': {
            status: {
              'fields': {
                'waybill_photo': {
                  'name': '$timestamp.jpg',
                  'size': 3,
                  'mime_type': 'image/jpeg',
                  'download_url': 'data:image/jpeg;base64,AQID',
                  'pending_upload': true,
                  'pending_upload_id': upload,
                },
              },
            },
          },
        };
        documents.add(doc);
        mutations.add(
          jsonEncode({
            'id': 'create_$timestamp',
            'kind': 'bookingCreate',
            'collection_key': 'bookings',
            'target_id': id,
            'payload': doc,
            'created_at': '2026-10-13T00:10:20.275Z',
            'is_blocked': true,
            'retry_count': 1,
            'last_error':
                'Failed to get document because the client is offline.',
            'error_diagnostics': 'Original offline stack',
            'booking_inline_preview_rechecked': true,
            'booking_start_photo_history_rechecked': true,
          }),
        );
        photos.add(
          jsonEncode({
            'id': upload,
            'booking_id': id,
            'status_key': status,
            'field_key': 'waybill_photo',
            'bytes_base64': 'AQID',
            'file_name': '$timestamp.jpg',
            'mime_type': 'image/jpeg',
            'size': 3,
            'created_at': '2026-10-13T00:10:15.316Z',
            'waiting_for_commit': true,
            'wait_reason': 'temporary_booking_id',
            'retry_count': 1,
            'last_error':
                'Failed to get document because the client is offline.',
          }),
        );
      }
      disk.data[mutationKey] = mutations;
      disk.data[photoKey] = photos;
      final queue = OfflineMutationQueueService(
        backend: disk,
        firestore: db,
        isOnline: () => online,
      );
      addTearDown(queue.dispose);
      await queue.initialize();
      expect(queue.currentStatus.failedCount, 4);
      for (final original in [documents.first, documents.last]) {
        await queue.queueCollectionDocumentUpsert(
          collectionKey: 'bookings',
          documentId: original['id'],
          baseUpdatedAt: original['updated_at'],
          document: {
            ...original,
            'client_status': 'assigned',
            'driver_status': 'assigned',
            'helper_status': 'assigned',
            'driver_id': '17',
            'helper_id': '19',
            'updated_at': '2026-10-13T08:12:24.931',
          },
        );
      }
      // Edits retain the original create action and all recovery evidence.
      for (final raw in disk.data[mutationKey]!) {
        final entry = jsonDecode(raw);
        expect(entry['error_diagnostics'], 'Original offline stack');
        expect(entry['booking_inline_preview_rechecked'], true);
        expect(entry['booking_start_photo_history_rechecked'], true);
        expect(entry['created_at'], '2026-10-13T00:10:20.275Z');
      }
      final storage = _Photos();
      final uploader = BookingOfflineUploadQueueService(
        backend: disk,
        firestore: db,
        mutationQueue: queue,
        photoStorageService: storage,
        flushMutations: queue.flushPendingMutations,
      );
      online = true;
      await uploader.flushPendingUploads();
      expect(disk.data[mutationKey], isEmpty);
      expect(disk.data[photoKey], isEmpty);
      expect(queue.currentStatus.pendingCount, 0);
      expect(queue.currentStatus.failedCount, 0);
      expect(uploader.currentStatus.pendingCount, 0);
      expect(storage.uploads, 4);
      final saved = (await db.collection('bookings').get()).docs;
      expect(saved, hasLength(4));
      expect(
        saved.map((d) => d.data()['submission_key']).toSet(),
        hasLength(4),
      );
      for (final booking in saved) {
        expect(booking.id, isNot(startsWith('offline_')));
        final data = booking.data();
        expect(jsonEncode(data), isNot(contains('data:image')));
        final assigned =
            data['submission_key'] == documents.first['submission_key'] ||
            data['submission_key'] == documents.last['submission_key'];
        expect(data['client_status'], assigned ? 'assigned' : 'pending');
        if (assigned) {
          expect(data['driver_id'], '17');
          expect(data['helper_id'], '19');
          expect(data['updated_at'], '2026-10-13T08:12:24.931');
        }
      }
      await uploader.flushPendingUploads();
      expect(storage.uploads, 4);
      expect((await db.collection('bookings').get()).docs, hasLength(4));
    },
  );
}
