import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/booking_remote_document.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';

import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

const _mutationKey = 'offline_mutation_queue_v1::signed_out';
const _photoKey = 'booking_pending_upload_queue_v1::signed_out';

class _Photos extends PhotoStorageService {
  final uploads = <String>[];
  final deleted = <String?>[];
  Future<void> Function()? duringUpload;

  @override
  Future<void> deleteByPath(String? path) async => deleted.add(path);
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
    uploads.add('$bookingId/$statusKey/$fieldKey');
    await duringUpload?.call();
    return {
      'name': fileName.replaceAll(' ', '_'),
      'size': bytes.length,
      'mime_type': mimeType,
      'storage_path':
          'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/new.jpg',
      'download_url': 'https://example.test/photo',
    };
  }
}

Map<String, dynamic> _queuedPhoto({
  required String id,
  required String booking,
  required String status,
  required String field,
  required String name,
  required int size,
  required String mime,
  String bytes = 'AQID',
}) => {
  'id': id,
  'booking_id': booking,
  'status_key': status,
  'field_key': field,
  'bytes_base64': bytes,
  'file_name': name,
  'size': size,
  'mime_type': mime,
  'waiting_for_commit': true,
  'created_at': '2026-10-08T06:15:59.375Z',
  'retry_count': 1,
  'last_error': 'Photo is still waiting',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scenario in [
    'same image',
    'different image',
    'marker race',
    'image race',
  ]) {
    test('booking 210 duplicate staging: $scenario', () async {
      final db = MergeAwareFirestore();
      final disk = MemoryBackend();
      final photos = _Photos();
      const status = 'ongoing__1791439298101000';
      const field = 'delivery_form_photo';
      const name = 'Screenshot 2026-10-08 140111.png';
      final bytes = Uint8List(558406);
      final encoded = base64Encode(bytes);
      final different = Uint8List.fromList(bytes)..[0] = 1;
      final originalPhoto = {
        'name': name,
        'size': bytes.length,
        'mime_type': 'image/png',
        'pending_upload': true,
        'pending_upload_id': 'booking_upload_1791439298178000_4c064c3b',
        'download_url':
            'data:image/png;base64,${scenario == 'different image' ? base64Encode(different) : encoded}',
      };
      final server = {
        'id': '210',
        'client_status': 'delivered',
        'billing_status': 'billed',
        'updated_at': '2026-10-08T14:21:02.599',
        'status_outputs': {
          status: {
            'fields': {field: originalPhoto},
          },
        },
      };
      final ref = db.collection('bookings').doc('210');
      await ref.set(server);
      disk.data[_photoKey] = [
        jsonEncode(
          _queuedPhoto(
            id: 'booking_upload_1791440311547000_2df6ffa6',
            booking: '210',
            status: status,
            field: field,
            name: name,
            size: bytes.length,
            mime: 'image/png',
            bytes: encoded,
          ),
        ),
      ];
      if (scenario.endsWith('race')) {
        photos.duringUpload = () async {
          await ref.update({
            if (scenario == 'marker race')
              'status_outputs.$status.fields.$field.pending_upload_id':
                  'newer-marker',
            if (scenario == 'image race')
              'status_outputs.$status.fields.$field.download_url':
                  'data:image/png;base64,${base64Encode(different)}',
          });
        };
      }
      final mutations = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryBackend(),
        isOnline: () => false,
      );
      addTearDown(mutations.dispose);
      final uploader = BookingOfflineUploadQueueService(
        firestore: db,
        backend: disk,
        mutationQueue: mutations,
        photoStorageService: photos,
        flushMutations: () async {},
      );
      await uploader.flushPendingUploads();
      final saved = (await ref.get()).data()!;
      expect(saved['client_status'], server['client_status']);
      expect(saved['billing_status'], server['billing_status']);
      expect(saved['updated_at'], server['updated_at']);
      final photo =
          ((saved['status_outputs'] as Map)[status]['fields'] as Map)[field];
      if (scenario == 'same image') {
        expect(disk.data[_photoKey], isEmpty);
        expect(photos.uploads, hasLength(1));
        expect(photo['download_url'], 'https://example.test/photo');
        expect(photo['pending_upload_id'], isNull);
        expect(photo['pending_upload'], isNull);
      } else {
        final retained = jsonDecode(disk.data[_photoKey]!.single);
        expect(retained['bytes_base64'], encoded);
        expect(retained['waiting_for_commit'], true);
        expect(photo['pending_upload'], true);
        if (scenario == 'different image') {
          expect(photos.uploads, isEmpty);
          expect(saved, server);
        } else {
          expect(photos.deleted, hasLength(1));
          expect(
            photo['pending_upload_id'],
            scenario == 'marker race'
                ? 'newer-marker'
                : originalPhoto['pending_upload_id'],
          );
          expect(
            photo['download_url'],
            scenario == 'image race'
                ? 'data:image/png;base64,${base64Encode(different)}'
                : originalPhoto['download_url'],
          );
        }
      }
    });
  }

  test(
    'queued create keeps inline bytes local and retries without duplicate booking',
    () async {
      final db = MergeAwareFirestore();
      final disk = MemoryBackend();
      final document = {
        'id': 'offline_create-photo',
        'submission_key': 'create-photo',
        'created_at': '2026-10-09T06:08:17Z',
        'updated_at': '2026-10-09T06:08:17Z',
        'client_status': 'pending',
        'status_outputs': {
          'book': {
            'fields': {
              'waybill_photo': {
                'download_url': 'data:image/jpeg;base64,AQID',
                'name': 'photo.jpg',
                'pending_upload': true,
                'pending_upload_id': 'upload',
              },
            },
          },
        },
      };
      final entry = jsonEncode({
        'id': 'create1',
        'kind': 'bookingCreate',
        'target_id': 'offline_create-photo',
        'collection_key': 'bookings',
        'payload': document,
        'created_at': '2026-10-09T06:08:17Z',
        'retry_count': 0,
      });
      final mutations = OfflineMutationQueueService(
        firestore: db,
        backend: disk,
        isOnline: () => true,
      );
      addTearDown(mutations.dispose);
      for (var attempt = 0; attempt < 2; attempt++) {
        disk.data[_mutationKey] = [entry];
        await mutations.flushPendingMutations();
        expect(disk.data[_mutationKey], isEmpty);
        final bookings = await db.collection('bookings').get();
        expect(bookings.docs, hasLength(1));
        expect(
          jsonEncode(bookings.docs.single.data()),
          isNot(contains('data:image')),
        );
        final identities = await db.collection('manage_id').get();
        expect(
          jsonEncode(identities.docs.map((d) => d.data()).toList()),
          isNot(contains('data:image')),
        );
      }
      expect(jsonEncode(document), contains('data:image'));
    },
  );

  test(
    'size recovery keeps original payload and version protection on conflict',
    () async {
      final db = MergeAwareFirestore();
      final disk = MemoryBackend();
      final original = {
        'id': '203',
        'submission_key': 'original',
        'updated_at': '2026-10-09T06:08:17Z',
        'status_outputs': {
          'book': {
            'fields': {
              'waybill_photo': {
                'download_url': 'data:image/jpeg;base64,AQID',
                'pending_upload': true,
                'pending_upload_id': 'upload',
              },
            },
          },
        },
      };
      await db.collection('bookings').doc('203').set({
        'id': '203',
        'submission_key': 'other',
        'updated_at': '2026-10-08T00:00:00Z',
      });
      disk.data[_mutationKey] = [
        jsonEncode({
          'id': 'entry203',
          'kind': 'collectionDocumentUpsert',
          'collection_key': 'bookings',
          'target_id': '203',
          'payload': original,
          'base_updated_at': '2026-10-08T00:00:00Z',
          'created_at': '2026-10-09T06:08:48.224Z',
          'is_blocked': true,
          'retry_count': 1,
          'last_error': 'Document exceeds the maximum allowed size',
        }),
      ];
      final mutations = OfflineMutationQueueService(
        firestore: db,
        backend: disk,
        isOnline: () => true,
      );
      addTearDown(mutations.dispose);
      await mutations.flushPendingMutations();
      final retained = jsonDecode(disk.data[_mutationKey]!.single);
      expect(retained['is_blocked'], true);
      expect(retained['booking_inline_preview_rechecked'], true);
      expect(retained['payload'], original);
      expect(retained['created_at'], '2026-10-09T06:08:48.224Z');
      expect(retained['base_updated_at'], '2026-10-08T00:00:00Z');
      expect(
        (await db.collection('bookings').doc('203').get())
            .data()!['submission_key'],
        'other',
      );
      final previous = disk.data[_mutationKey]!.single;
      await mutations.flushPendingMutations();
      expect(disk.data[_mutationKey]!.single, previous);
    },
  );

  test(
    'booking 203 size failure recovers its mutation and all three photos',
    () async {
      final db = MergeAwareFirestore();
      final disk = MemoryBackend();
      final photos = _Photos();
      const base = '2026-10-08T15:39:14.602Z';
      const action = '2026-10-09T14:08:17.014Z';
      final bytes = base64Encode(Uint8List(292272));
      final outputs = <String, dynamic>{};
      final uploads = <String>[];
      for (var i = 0; i < 3; i++) {
        final status = ['book__1', 'assigned__2', 'assigned__3'][i];
        outputs[status] = {
          'fields': {
            'waybill_photo': {
              'name': '1000141986.jpg',
              'mime_type': 'image/jpeg',
              'size': 292272,
              'download_url': 'data:image/jpeg;base64,$bytes',
              'pending_upload': true,
              'pending_upload_id': 'upload$i',
            },
          },
        };
        uploads.add(
          jsonEncode(
            _queuedPhoto(
              id: 'upload$i',
              booking: '203',
              status: status,
              field: 'waybill_photo',
              name: '1000141986.jpg',
              size: 292272,
              mime: 'image/jpeg',
              bytes: bytes,
            ),
          ),
        );
      }
      final document = {
        'id': '203',
        'client_status': 'ongoing',
        'updated_at': action,
        'status_outputs': outputs,
      };
      expect(utf8.encode(jsonEncode(document)).length, greaterThan(1048576));
      expect(
        utf8.encode(jsonEncode(bookingRemoteDocument(document))).length,
        lessThan(2000),
      );
      // Local preview is not modified by preparing the server payload.
      expect(jsonEncode(document), contains('data:image/jpeg;base64,'));
      await db.collection('bookings').doc('203').set({
        'id': '203',
        'client_status': 'assigned',
        'updated_at': base,
      });
      disk.data[_mutationKey] = [
        jsonEncode({
          'id': 'entry203',
          'kind': 'collectionDocumentUpsert',
          'collection_key': 'bookings',
          'target_id': '203',
          'payload': document,
          'base_updated_at': base,
          'created_at': '2026-10-09T06:08:48.224Z',
          'is_blocked': true,
          'retry_count': 1,
          'last_error':
              'Document size (1,171,674 bytes) exceeds the maximum allowed size of 1,048,576 bytes.',
        }),
      ];
      disk.data[_photoKey] = uploads;
      final mutations = OfflineMutationQueueService(
        firestore: db,
        backend: disk,
        isOnline: () => true,
      );
      addTearDown(mutations.dispose);
      await mutations.flushPendingMutations();
      expect(disk.data[_mutationKey], isEmpty);
      final saved = (await db.collection('bookings').doc('203').get()).data()!;
      expect(jsonEncode(saved), isNot(contains('data:image')));
      expect(saved['updated_at'], action);
      expect(
        disk.data[_photoKey],
        uploads,
        reason: 'durable photo bytes remain intact',
      );
      final uploader = BookingOfflineUploadQueueService(
        firestore: db,
        backend: disk,
        mutationQueue: mutations,
        photoStorageService: photos,
        flushMutations: mutations.flushPendingMutations,
      );
      await uploader.flushPendingUploads();
      expect(disk.data[_photoKey], isEmpty);
      expect(photos.uploads, hasLength(3));
      final completed = (await db.collection('bookings').doc('203').get())
          .data()!;
      expect(completed['updated_at'], action);
      expect(completed['client_status'], 'ongoing');
    },
  );

  for (final sample in [
    (
      '147',
      'delivered__1791431216630000',
      'delivered__1791431204922000',
      'delivery_form_photo',
      'Screenshot 2026-10-08 114633.png',
      691171,
      'image/png',
    ),
    (
      '213',
      'ongoing__1791440159165000',
      'assigned__1791440138612000',
      'waybill_photo',
      'camera_1791439936334.jpg',
      91869,
      'image/jpeg',
    ),
    (
      '168',
      'delivered__1791436539913000',
      'delivered__1791436539913000',
      'delivery_form_photo',
      'Screenshot 2026-10-08 131529.png',
      555652,
      'image/png',
    ),
  ]) {
    test(
      'booking ${sample.$1} recognizes the existing uploaded photo without a write',
      () async {
        final db = MergeAwareFirestore();
        final disk = MemoryBackend();
        final photos = _Photos();
        final (booking, oldStatus, newStatus, field, name, size, mime) = sample;
        final server = {
          'id': booking,
          'client_status': 'delivered',
          'updated_at': '2026-10-08T15:20:29.051Z',
          'status_outputs': {
            newStatus: {
              'fields': {
                field: {
                  'name': name.replaceAll(' ', '_'),
                  'size': size,
                  'mime_type': mime,
                  'storage_path':
                      'bookings/$booking/status_outputs/$newStatus/$field/existing.png',
                  'download_url': 'https://example.test/existing',
                },
              },
            },
          },
        };
        await db.collection('bookings').doc(booking).set(server);
        disk.data[_photoKey] = [
          jsonEncode(
            _queuedPhoto(
              id: 'upload$booking',
              booking: booking,
              status: oldStatus,
              field: field,
              name: name,
              size: size,
              mime: mime,
            ),
          ),
        ];
        final mutations = OfflineMutationQueueService(
          firestore: db,
          backend: MemoryBackend(),
          isOnline: () => false,
        );
        addTearDown(mutations.dispose);
        final uploader = BookingOfflineUploadQueueService(
          firestore: db,
          backend: disk,
          mutationQueue: mutations,
          photoStorageService: photos,
          flushMutations: () async {},
        );
        await uploader.flushPendingUploads();
        expect(disk.data[_photoKey], isEmpty);
        expect(photos.uploads, isEmpty);
        expect(
          (await db.collection('bookings').doc(booking).get()).data(),
          server,
        );
      },
    );
  }
}
