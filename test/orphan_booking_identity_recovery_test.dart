import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/booking_original_create_recovery.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

const mutationKey = 'offline_mutation_queue_v1::8';
const photoKey = 'booking_pending_upload_queue_v1::8';
Map<String, dynamic> fixture() => jsonDecode(
  File('test/fixtures/orphan_booking_assignment_oct13.json').readAsStringSync(),
);

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
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.writeString('paltranco_current_user_id', '8');
    await auth.writeStringList('paltranco_known_session_user_ids', ['8']);
  });

  test(
    'actual orphaned assignment recreates original submission, then drains edit and photo',
    () async {
      final row = fixture();
      final payload = Map<String, dynamic>.from(row['pending_payload']);
      final before = jsonEncode(payload);
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
      disk.data[mutationKey] = [
        jsonEncode({
          'id': row['queue_entry_id'],
          'kind': 'collectionDocumentUpsert',
          'collection_key': 'bookings',
          'target_id': row['target_id'],
          'payload': payload,
          'base_updated_at': row['base_updated_at'],
          'created_at': row['action_at'],
          'retry_count': 14,
          'is_blocked': false,
          'last_error': 'Service is temporarily unavailable. Please try again.',
        }),
      ];
      final p =
          payload['status_outputs']['book__1791856597066000']['fields']['waybill_photo'];
      disk.data[photoKey] = [
        jsonEncode({
          'id': p['pending_upload_id'],
          'booking_id': payload['id'],
          'status_key': 'book__1791856597066000',
          'field_key': 'waybill_photo',
          'file_name': p['name'],
          'mime_type': p['mime_type'],
          'size': p['size'],
          'bytes_base64': base64Encode(Uint8List(p['size'])),
          'created_at': '2026-10-13T01:56:39.284Z',
          'waiting_for_commit': true,
          'wait_reason': 'booking_mutation_pending',
          'last_error': 'Photo still waiting',
          'retry_count': 1,
        }),
      ];
      online = true;
      final photos = _Photos();
      final uploader = BookingOfflineUploadQueueService(
        firestore: db,
        backend: disk,
        mutationQueue: queue,
        photoStorageService: photos,
        flushMutations: queue.flushPendingMutations,
      );
      await uploader.flushPendingUploads();
      expect(disk.data[mutationKey], isEmpty);
      expect(disk.data[photoKey], isEmpty);
      expect(photos.uploads, 1);
      expect(jsonEncode(payload), before);
      final bookings = (await db.collection('bookings').get()).docs;
      expect(bookings, hasLength(1));
      final saved = bookings.single.data();
      expect(saved['submission_key'], payload['submission_key']);
      expect(saved['client_status'], 'assigned');
      expect(saved['vehicle_make_id'], '2');
      expect(saved['driver_id'], '17');
      expect(saved['helper_id'], '19');
      expect(saved['updated_at'], payload['updated_at']);
      expect(saved['created_at'], payload['created_at']);
      expect(
        saved['status_outputs']['pending__1791856699090000'],
        payload['status_outputs']['pending__1791856699090000'],
      );
      expect(jsonEncode(saved), isNot(contains('data:image')));
      await uploader.flushPendingUploads();
      expect((await db.collection('bookings').get()).docs, hasLength(1));
      expect(photos.uploads, 1);
    },
  );

  for (final timestamp in ['1791852980581000', '1791853133205000']) {
    test(
      'orphan photo $timestamp recovers only from complete original cache',
      () async {
        final row = fixture();
        final doc = Map<String, dynamic>.from(row['pending_payload']);
        final key = 'booking_8_9_1_$timestamp';
        final id = 'offline_$key';
        final wallTime = DateTime.fromMicrosecondsSinceEpoch(
          int.parse(timestamp),
          isUtc: true,
        ).add(const Duration(hours: 8)).toIso8601String().replaceFirst('Z', '');
        final event = Map<String, dynamic>.from(
          doc['status_outputs']['book__1791856597066000'],
        );
        final photo = event['fields']['waybill_photo'];
        photo['pending_upload_id'] = 'photo_$timestamp';
        photo['name'] = '$timestamp.jpg';
        event['submitted_at'] = wallTime;
        doc.addAll({
          'id': id,
          'submission_key': key,
          'created_at': wallTime,
          'updated_at': wallTime,
          'client_status': 'pending',
          'driver_status': 'pending',
          'helper_status': 'pending',
          'driver_id': null,
          'helper_id': null,
          'vehicle_make_id': null,
          'status_outputs': {'book__$timestamp': event},
        });
        final db = MergeAwareFirestore();
        final disk = MemoryBackend();
        final queue = OfflineMutationQueueService(
          firestore: db,
          backend: disk,
          isOnline: () => true,
        );
        addTearDown(queue.dispose);
        final photos = _Photos();
        final uploader = BookingOfflineUploadQueueService(
          firestore: db,
          backend: disk,
          mutationQueue: queue,
          photoStorageService: photos,
          flushMutations: queue.flushPendingMutations,
          cachedBookingReader: (_) async => doc,
        );
        await uploader.initialize();
        await Future<void>.delayed(Duration.zero);
        disk.data[photoKey] = [
          jsonEncode({
            'id': photo['pending_upload_id'],
            'booking_id': id,
            'status_key': 'book__$timestamp',
            'field_key': 'waybill_photo',
            'file_name': photo['name'],
            'mime_type': photo['mime_type'],
            'size': photo['size'],
            'bytes_base64': 'AQID',
            'created_at': wallTime,
            'waiting_for_commit': true,
            'last_error': 'Client is offline',
          }),
        ];
        await uploader.flushPendingUploads();
        expect(disk.data[photoKey], isEmpty);
        expect(photos.uploads, 1);
        expect((await db.collection('bookings').get()).docs, hasLength(1));
      },
    );
  }

  test(
    'fresh lookup reuses canonical booking despite an earlier missing identity',
    () async {
      final row = fixture();
      final p = Map<String, dynamic>.from(row['pending_payload']);
      final db = MergeAwareFirestore();
      final disk = MemoryBackend();
      expect(
        await BookingIdResolver(
          firestore: db,
        ).resolve(p['id'], submissionKey: p['submission_key']),
        isNull,
      );
      final server = {...p, 'id': '42', 'client_status': 'delivered'};
      await db.collection('bookings').doc('42').set(server);
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: disk,
        isOnline: () => false,
      );
      addTearDown(queue.dispose);
      expect(
        await queue.recoverOriginalBookingIdentity(
          temporaryId: p['id'],
          document: p,
          owner: '8',
          baseUpdatedAt: row['base_updated_at'],
        ),
        '42',
      );
      expect((await db.collection('bookings').get()).docs, hasLength(1));
      expect((await db.collection('bookings').doc('42').get()).data(), server);
    },
  );

  for (final scenario in [
    'deleted',
    'reservation only',
    'ambiguous',
    'repair',
    'reservation mismatch',
  ]) {
    test('unsafe identity remains preserved: $scenario', () async {
      final row = fixture();
      final p = Map<String, dynamic>.from(row['pending_payload']);
      final db = MergeAwareFirestore();
      final disk = MemoryBackend();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: disk,
        isOnline: () => false,
      );
      addTearDown(queue.dispose);
      final reservation = db
          .collection('manage_id')
          .doc(BookingIdResolver.reservationId(p['submission_key']));
      if (scenario == 'deleted') {
        await reservation.set({
          'resource_key': 'bookings',
          'submission_key': p['submission_key'],
          'document_id': '42',
          'source_document': p,
        });
      }
      if (scenario == 'reservation only') {
        await reservation.set({
          'resource_key': 'bookings',
          'submission_key': p['submission_key'],
          'document_id': '42',
        });
      }
      if (scenario == 'reservation mismatch') {
        await reservation.set({
          'resource_key': 'bookings',
          'submission_key': 'other',
          'document_id': '42',
        });
      }
      if (scenario == 'repair') {
        await db.collection('booking_id_repairs').doc(p['id']).set({
          'resolution': 'pending',
        });
      }
      if (scenario == 'ambiguous') {
        await db.collection('bookings').doc('42').set({...p, 'id': '42'});
        await db.collection('bookings').doc('43').set({...p, 'id': '43'});
      }
      final before = jsonEncode(p);
      await expectLater(
        queue.recoverOriginalBookingIdentity(
          temporaryId: p['id'],
          document: p,
          owner: '8',
          baseUpdatedAt: row['base_updated_at'],
        ),
        throwsStateError,
      );
      expect(jsonEncode(p), before);
      expect(
        (await db.collection('bookings').get()).docs,
        hasLength(scenario == 'ambiguous' ? 2 : 0),
      );
    });
  }

  test(
    'a queued create cannot resurrect a previously committed missing booking',
    () async {
      final row = fixture();
      final p = Map<String, dynamic>.from(row['pending_payload']);
      final db = MergeAwareFirestore();
      final disk = MemoryBackend();
      await db
          .collection('manage_id')
          .doc(BookingIdResolver.reservationId(p['submission_key']))
          .set({
            'resource_key': 'bookings',
            'submission_key': p['submission_key'],
            'document_id': '42',
            'source_document': p,
          });
      var online = false;
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: disk,
        isOnline: () => online,
      );
      addTearDown(queue.dispose);
      await queue.initialize();
      await Future<void>.delayed(Duration.zero);
      disk.data[mutationKey] = [
        jsonEncode({
          'id': 'original-create',
          'kind': 'bookingCreate',
          'collection_key': 'bookings',
          'target_id': p['id'],
          'payload': p,
          'created_at': row['action_at'],
          'retry_count': 0,
        }),
      ];
      online = true;
      await queue.flushPendingMutations();
      final retained = jsonDecode(disk.data[mutationKey]!.single);
      expect(retained['payload'], p);
      expect(retained['is_blocked'], true);
      expect(retained['last_error'], contains('Pending create was preserved'));
      expect((await db.collection('bookings').get()).docs, isEmpty);
    },
  );

  test(
    'missing source proof cannot turn a temporary edit into a booking create',
    () {
      for (final scenario in [
        'owner',
        'client',
        'time',
        'form',
        'missing book',
        'base',
        'unknown field',
        'photo only',
        'event key',
      ]) {
        final row = fixture();
        final p = Map<String, dynamic>.from(row['pending_payload']);
        var base = row['base_updated_at'] as String;
        var owner = '8';
        switch (scenario) {
          case 'owner':
            owner = '19';
          case 'client':
            p['client_id'] = 'other';
          case 'time':
            p['created_at'] = '2020-01-01T00:00:00Z';
          case 'form':
            p['status_outputs']['book__1791856597066000']['status_form']['next_status_key'] =
                'delivered';
          case 'missing book':
            p['status_outputs'].remove('book__1791856597066000');
          case 'base':
            base = '2020-01-01T00:00:00Z';
          case 'unknown field':
            p['unknown'] = 'value';
          case 'photo only':
            p['status_outputs']['book__1791856597066000']['fields'] = {
              'waybill_photo':
                  p['status_outputs']['book__1791856597066000']['fields']['waybill_photo'],
            };
          case 'event key':
            final event = p['status_outputs'].remove('book__1791856597066000');
            p['status_outputs']['book__123'] = event;
        }
        expect(
          originalBookingCreateForRecovery(
            document: p,
            temporaryId: p['id'],
            owner: owner,
            baseUpdatedAt: base,
          ),
          isNull,
          reason: scenario,
        );
      }
    },
  );
  test(
    'original event timestamp remains the base when submission took a millisecond',
    () {
      final p = Map<String, dynamic>.from(fixture()['pending_payload']);
      final event = p['status_outputs'].remove('book__1791856597066000');
      event['submitted_at'] = '2026-10-13T09:56:37.067';
      p['status_outputs']['book__1791856597067000'] = event;
      final original = originalBookingCreateForRecovery(
        document: p,
        temporaryId: p['id'],
        owner: '8',
        baseUpdatedAt: event['submitted_at'],
      );
      expect(original, isNotNull);
      expect(original!['created_at'], p['created_at']);
      expect(original['updated_at'], event['submitted_at']);
      expect(original['client_status'], 'pending');
    },
  );
}
