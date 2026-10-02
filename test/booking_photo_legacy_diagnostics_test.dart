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
