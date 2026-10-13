import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_status_continuation.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class _Photos extends PhotoStorageService {
  bool fail = true;
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
    if (fail) {
      throw FirebaseException(plugin: 'firebase_storage', code: 'unavailable');
    }
    return {
      'name': fileName,
      'size': size,
      'mime_type': mimeType,
      'storage_path':
          'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/photo.jpg',
      'download_url': 'https://example.test/recovered',
    };
  }
}

Map<String, dynamic> fixture() => jsonDecode(
  File('test/fixtures/booking23_oct13_history.json').readAsStringSync(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'booking 23 archives start and older photo while preserving delivered booking',
    () async {
      final row = fixture();
      final server = Map<String, dynamic>.from(row['server_document']);
      final q = row['queue_snapshot'];
      final pending = Map<String, dynamic>.from(q['pending_payload']);
      final db = MergeAwareFirestore();
      final disk = MemoryBackend();
      const mutationKey = 'offline_mutation_queue_v1::signed_out';
      const photoKey = 'booking_pending_upload_queue_v1::signed_out';
      final mutation = {
        'id': q['queue_entry_id'],
        'kind': 'collectionDocumentUpsert',
        'collection_key': 'bookings',
        'target_id': '23',
        'payload': pending,
        'base_updated_at': q['base_updated_at'],
        'created_at': q['action_at'],
        'is_blocked': true,
        'retry_count': 1,
        'last_error':
            'Sync conflict: booking changed remotely before applying this edit.',
        'conflict_recovery_attempted': true,
        'booking_start_archive_rechecked': true,
        'booking_photo_rechecked': true,
        'booking_metadata_rechecked': true,
        'booking_history_rechecked': true,
        'booking_edit_archive_rechecked': true,
      };
      disk.data[mutationKey] = [jsonEncode(mutation)];
      final snap = row['photo_snapshot'];
      final photo = snap['photo_upload'];
      final encoded = base64Encode(Uint8List(photo['size']));
      disk.data[photoKey] = [
        jsonEncode({
          ...photo,
          'id': snap['queue_entry_id'],
          'created_at': snap['action_at'],
          'bytes_base64': encoded,
          'last_error': 'Photo waiting for booking changes',
        }),
      ];
      final ref = db.collection('bookings').doc('23');
      await ref.set(server);
      final queue = OfflineMutationQueueService(
        backend: disk,
        firestore: db,
        isOnline: () => true,
      );
      addTearDown(queue.dispose);
      final photos = _Photos();
      final uploader = BookingOfflineUploadQueueService(
        backend: disk,
        firestore: db,
        photoStorageService: photos,
        mutationQueue: queue,
        flushMutations: queue.flushPendingMutations,
      );
      await uploader.flushPendingUploads();
      expect(disk.data[mutationKey], isEmpty);
      expect(jsonDecode(disk.data[photoKey]!.single)['bytes_base64'], encoded);
      photos.fail = false;
      await uploader.flushPendingUploads();
      expect(disk.data[photoKey], isEmpty);
      final actual = (await ref.get()).data()!;
      for (final key in server.keys.where((k) => k != 'status_outputs')) {
        expect(actual[key], server[key], reason: key);
      }
      for (final event in (server['status_outputs'] as Map).entries) {
        expect(actual['status_outputs'][event.key], event.value);
      }
      expect(
        actual['status_outputs']['assigned__1789814545358000'],
        pending['status_outputs']['assigned__1789814545358000'],
      );
      expect(
        actual['status_outputs']['photo__${snap['queue_entry_id']}']['submitted_at'],
        snap['action_at'],
      );
      expect(
        actual['status_outputs']['photo__${snap['queue_entry_id']}']['fields']['delivery_form_photo']['size'],
        photo['size'],
      );
      // Restart/retry cannot duplicate either historical action or restore live fields.
      disk.data[mutationKey] = [
        jsonEncode({...mutation, 'is_blocked': false}),
      ];
      await queue.flushPendingMutations();
      expect(disk.data[mutationKey], isEmpty);
      expect((await ref.get()).data(), actual);
    },
  );

  test('recovered photos do not loosen identity, history or workflow checks', () {
    for (final scenario in [
      'crew',
      'identity',
      'existing history',
      'extra action',
      'photo path',
      'photo marker',
      'photo time',
    ]) {
      final row = fixture();
      final server = Map<String, dynamic>.from(row['server_document']);
      final q = row['queue_snapshot'];
      final pending = Map<String, dynamic>.from(q['pending_payload']);
      final outputs = server['status_outputs'] as Map;
      final audit = outputs.entries
          .singleWhere((e) => '${e.key}'.startsWith('photo__'))
          .value;
      switch (scenario) {
        case 'crew':
          pending['helper_id'] = 'other';
        case 'identity':
          pending['submission_key'] = 'other';
        case 'existing history':
          pending['status_outputs']['assigned__1788762432291000']['fields']['amount'] =
              '9999';
        case 'extra action':
          outputs['unrelated'] = {'status_key': 'pending', 'fields': {}};
        case 'photo path':
          audit['fields']['delivery_form_photo']['storage_path'] =
              'bookings/other/photo.jpg';
        case 'photo marker':
          audit['upload_id'] = 'wrong';
        case 'photo time':
          audit['submitted_at'] = '2027-01-01T00:00:00Z';
      }
      expect(
        reconcileBookingHistory(
          server,
          pending,
          baseUpdatedAt: q['base_updated_at'],
        ),
        isNull,
        reason: scenario,
      );
    }
  });
}
