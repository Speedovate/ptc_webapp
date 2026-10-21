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
  test('photo log retains the actual pending booking action payload', () async {
    final backend = MemoryBackend();
    const bookingId = 'offline_booking_8_9_1_1791850210240000';
    const photoId = 'booking_upload_1791850220223000_21a9908';
    const photoKey = 'booking_pending_upload_queue_v1::signed_out';
    backend.data['offline_mutation_queue_v1::signed_out'] = [
      jsonEncode({
        'id': 'booking_create_1791850220275000_2a76ed4a',
        'kind': 'bookingCreate',
        'collection_key': 'bookings',
        'target_id': bookingId,
        'payload': {
          'id': bookingId,
          'client_id': '9',
          'status_outputs': {
            'book__1791850210240000': {
              'fields': {'representative_name': 'Preserved booking data'},
            },
          },
        },
        'created_at': '2026-10-13T00:10:20.275Z',
        'retry_count': 0,
      }),
    ];
    backend.data[photoKey] = [
      jsonEncode({
        'id': photoId,
        'booking_id': bookingId,
        'status_key': 'book__1791850210240000',
        'field_key': 'waybill_photo',
        'file_name': 'waybill.jpg',
        'mime_type': 'image/jpeg',
        'bytes_base64': 'AQID',
        'size': 3,
        'created_at': '2026-10-13T00:10:15.316Z',
        'waiting_for_commit': true,
        'wait_count': 5,
        'wait_reason': 'temporary_booking_id',
        'last_error': 'Still waiting for booking',
      }),
    ];
    final mutations = OfflineMutationQueueService(
      backend: backend,
      isOnline: () => false,
    );
    addTearDown(mutations.dispose);
    final service = BookingOfflineUploadQueueService(
      backend: backend,
      mutationQueue: mutations,
      flushMutations: () async {},
    );
    await service.flushPendingUploads();
    final retained = jsonDecode(backend.data[photoKey]!.single) as Map;
    final diagnostics = retained['error_diagnostics'] as String;
    final contextText = RegExp(
      r'Context:\n([^\n]+)\nRaw error:',
    ).firstMatch(diagnostics)?.group(1);
    expect(contextText, isNotNull);
    final context = jsonDecode(contextText!) as Map<String, dynamic>;
    final action = (context['pending_booking_actions'] as List).single as Map;
    expect(action['pending_payload']['client_id'], '9');
    expect(
      action['pending_payload']['status_outputs']['book__1791850210240000']['fields']['representative_name'],
      'Preserved booking data',
    );
    final inventory = context['local_inventory'] as Map;
    expect((inventory['booking_actions'] as Map)['matching_count'], 1);
    expect(
      ((inventory['booking_actions'] as Map)['entries'] as List)
          .single['full_payload_in_report_at'],
      'details.pending_booking_actions',
    );
    expect((inventory['photo_queue'] as Map)['sha256'], isNotEmpty);
    expect(diagnostics, isNot(contains('AQID')));
    expect(retained['bytes_base64'], 'AQID');
  });

  test(
    'legacy missing delivery action enriches diagnostics without inventing history or deleting photo',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      const key = 'booking_pending_upload_queue_v1::signed_out';
      const at = '2026-09-25T07:04:33.425Z';
      const statusKey = 'ongoing__1790319873403000';
      final server = <String, dynamic>{
        'id': '146',
        'submission_key': 'booking_8_9_1_1790305482086000',
        'updated_at': '2026-09-30T08:11:25.185',
        'client_status': 'ongoing',
        'delivered_at': null,
        'status_outputs': {
          'ongoing__1790727085179000': {
            'submitted_at': '2026-09-30T08:11:25.179',
            'status_key': 'ongoing',
            'fields': {'amount': '4100'},
          },
        },
      };
      await db.collection('bookings').doc('146').set(server);
      backend.data[key] = [
        jsonEncode({
          'id': 'booking_upload_1790319873451000_6be87a2a',
          'booking_id': '146',
          'status_key': statusKey,
          'field_key': 'delivery_form_photo',
          'file_name': 'camera_1790319853329.jpg',
          'mime_type': 'image/jpeg',
          'bytes_base64': 'AQID',
          'size': 3,
          'created_at': at,
          'waiting_for_commit': true,
          'wait_count': 14,
          'wait_reason': 'photo_field_missing',
          'last_error': 'This photo is still waiting',
          'error_diagnostics': '{"diagnostic_schema":"server_photo_state_v1"}',
        }),
      ];
      final photos = SlowPhotos();
      var now = DateTime.utc(2026, 10, 2);
      var reads = 0;
      final service = BookingOfflineUploadQueueService(
        backend: backend,
        firestore: db,
        photoStorageService: photos,
        flushMutations: () async {},
        now: () => now,
        bookingReader: (_) async {
          reads++;
          return server;
        },
        mutationQueue: OfflineMutationQueueService(
          backend: backend,
          firestore: db,
          isOnline: () => false,
        ),
      );
      await service.flushPendingUploads();
      await service.flushPendingUploads();
      final retained = jsonDecode(backend.data[key]!.single);
      expect(retained['bytes_base64'], 'AQID');
      expect(retained['created_at'], at);
      expect(retained['status_key'], statusKey);
      expect(retained['waiting_for_commit'], true);
      expect(
        retained['error_diagnostics'],
        contains('photo_dependency_state_v2'),
      );
      expect(
        retained['error_diagnostics'],
        contains('pending_booking_actions'),
      );
      expect(retained['error_diagnostics'], contains('server_document'));
      expect(photos.started.isCompleted, false);
      expect((await db.collection('bookings').doc('146').get()).data(), server);
      final snapshot = backend.data[key]!.single;
      await service.flushPendingUploads();
      expect(
        backend.data[key]!.single,
        snapshot,
        reason:
            'An unchanged missing action must not rewrite photo bytes or diagnostics each cycle',
      );
      final beforeBackground = reads;
      for (var i = 0; i < 10; i++) {
        await service.flushPendingUploads(background: true);
      }
      expect(reads, beforeBackground);
      expect(backend.data[key]!.single, snapshot);
      now = now.add(const Duration(minutes: 5));
      await service.flushPendingUploads(background: true);
      expect(reads, beforeBackground + 1);
      await service.flushPendingUploads();
      expect(
        reads,
        beforeBackground + 2,
        reason: 'Explicit retry bypasses cooldown',
      );
      expect(backend.data[key]!.single, snapshot);
    },
  );
}
