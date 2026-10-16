import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_status_continuation.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

Map<String, dynamic> fixture() => jsonDecode(
  File('test/fixtures/booking254_assignment_oct15.json').readAsStringSync(),
);

class Photos extends PhotoStorageService {
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
      'download_url': 'https://example.test/upload',
      'storage_path':
          'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/upload.jpg',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final committed in [false, true]) {
    test(
      'booking254 blocked assignment and photo drain; already committed=$committed',
      () async {
        final row = committed
            ? jsonDecode(
                File(
                  'test/fixtures/booking254_committed_oct16.json',
                ).readAsStringSync(),
              )
            : fixture();
        final snapshot = row['queue_snapshot'];
        final pending = snapshot['pending_payload'];
        final original = jsonEncode(pending);
        final server = Map<String, dynamic>.from(row['server_document']);
        final db = MergeAwareFirestore();
        final disk = MemoryBackend();
        var online = false;
        final queue = OfflineMutationQueueService(
          firestore: db,
          backend: disk,
          isOnline: () => online,
        );
        addTearDown(queue.dispose);
        await queue.initialize();
        await Future<void>.delayed(Duration.zero);
        await db.collection('bookings').doc('254').set(server);
        await db.collection('vehicle_makes').doc('4').set({
          'id': '4',
          'driver_id': '13',
          'helper_id': '18',
        });
        const mutationKey = 'offline_mutation_queue_v1::signed_out';
        const photoKey = 'booking_pending_upload_queue_v1::signed_out';
        disk.data[mutationKey] = [
          jsonEncode({
            'id': snapshot['queue_entry_id'],
            'kind': 'collectionDocumentUpsert',
            'collection_key': 'bookings',
            'target_id': '254',
            'payload': pending,
            'base_updated_at': row['base_updated_at'],
            'created_at': snapshot['action_at'],
            'retry_count': 2,
            'is_blocked': true,
            'last_error':
                'Bad state: Sync conflict: booking changed remotely before applying this edit.',
            for (final flag in [
              'boxed_error_rechecked',
              'booking_conflict_rechecked',
              'booking_continuation_rechecked',
              'booking_history_rechecked',
              'conflict_recovery_attempted',
              'booking_metadata_rechecked',
              'booking_photo_rechecked',
              'booking_edit_archive_rechecked',
              'booking_delivery_history_rechecked',
              'booking_repeated_delivery_rechecked',
              'booking_committed_delivery_rechecked',
              'booking_start_archive_rechecked',
              'booking_start_photo_history_rechecked',
              'booking_queued_history_preservation_rechecked',
              'booking_inline_preview_rechecked',
              'booking_pending_preview_rechecked',
            ])
              flag: true,
          }),
        ];
        final p =
            pending['status_outputs']['book__1792024716308000']['fields']['waybill_photo'];
        disk.data[photoKey] = [
          jsonEncode({
            'id': p['pending_upload_id'],
            'booking_id': '254',
            'status_key': 'book__1792024716308000',
            'field_key': 'waybill_photo',
            'file_name': p['name'],
            'size': p['size'],
            'mime_type': p['mime_type'],
            'bytes_base64': base64Encode(Uint8List(p['size'])),
            'created_at': '2026-10-15T00:38:37.959Z',
            'waiting_for_commit': true,
            'wait_reason': 'booking_mutation_pending',
            'retry_count': 1,
            'last_error': 'Photo still waiting',
          }),
        ];
        online = true;
        final photos = Photos();
        final uploader = BookingOfflineUploadQueueService(
          firestore: db,
          backend: disk,
          mutationQueue: queue,
          photoStorageService: photos,
          flushMutations: queue.flushPendingMutations,
        );
        await uploader.flushPendingUploads();
        expect(
          disk.data[mutationKey]?.length,
          0,
          reason: disk.data[mutationKey]?.isNotEmpty == true
              ? '${jsonDecode(disk.data[mutationKey]!.first)['last_error']}'
              : null,
        );
        expect(disk.data[photoKey]?.length, 0);
        expect(photos.uploads, 1);
        final saved = (await db.collection('bookings').doc('254').get())
            .data()!;
        expect(saved['client_status'], 'assigned');
        expect(saved['driver_id'], '13');
        expect(saved['helper_id'], '18');
        expect(saved['vehicle_make_id'], '4');
        expect(
          saved['updated_at'],
          committed ? server['updated_at'] : pending['updated_at'],
        );
        if (committed) {
          expect(
            saved['status_outputs']['assigned__1792024797328000'],
            server['status_outputs']['assigned__1792024797328000'],
          );
        }
        expect(
          saved['status_outputs']['pending__1792024759350000'],
          pending['status_outputs']['pending__1792024759350000'],
        );
        expect(jsonEncode(saved), isNot(contains('data:image')));
        expect(jsonEncode(pending), original);
        await uploader.flushPendingUploads();
        expect(photos.uploads, 1);
      },
    );
  }
  for (final scenario in [
    'marker',
    'metadata',
    'changed history',
    'different previews',
    'https preview',
    'crew',
  ]) {
    test('booking254 rejects unrelated differences: $scenario', () {
      final row = fixture();
      final server = Map<String, dynamic>.from(row['server_document']);
      final pending = Map<String, dynamic>.from(
        row['queue_snapshot']['pending_payload'],
      );
      final local =
          pending['status_outputs']['book__1792024716308000']['fields']['waybill_photo'];
      final remote =
          server['status_outputs']['book__1792024716308000']['fields']['waybill_photo'];
      switch (scenario) {
        case 'marker':
          local['pending_upload_id'] = 'other';
        case 'metadata':
          local['size'] = 1;
        case 'changed history':
          pending['status_outputs']['book__1792024716308000']['fields']['origin'] =
              'Other';
        case 'different previews':
          remote['download_url'] = 'data:image/jpeg;base64,DIFFERENT';
        case 'https preview':
          local['download_url'] = 'https://example.test/other';
        case 'crew':
          pending['driver_id'] = '99';
      }
      expect(
        reconcileBookingHistory(
          server,
          pending,
          baseUpdatedAt: row['base_updated_at'],
          verifiedMake: {'driver_id': '13', 'helper_id': '18'},
        ),
        isNull,
      );
    });
  }
}
