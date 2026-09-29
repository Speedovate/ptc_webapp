import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/sync_error_log_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final realConflict in [false, true]) {
    test(
      'blocked metadata retry acknowledges only matching business data: $realConflict',
      () async {
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        final payload = {
          'id': '153',
          'submission_key': 'original',
          'client_status': 'assigned',
          'updated_at': '2026-09-29T15:30:03.460',
          'chassis_id': '3',
        };
        final server = {
          ...payload,
          'photo_cleanup_paths': ['old-photo'],
          'photo_cleanup_claims': [],
          'media_synced_at': '2026-09-29T08:00:00Z',
          if (realConflict) 'chassis_id': '4',
        };
        await db.collection('bookings').doc('153').set(server);
        await db.collection('chassis').doc('3').set({
          'current_booking_id': 999,
        });
        backend.data[storageKey] = [
          jsonEncode({
            'id': 'retry1',
            'kind': 'collectionDocumentUpsert',
            'collection_key': 'bookings',
            'target_id': '153',
            'payload': payload,
            'base_updated_at': '2026-09-29T15:26:10.693',
            'created_at': '2026-09-29T07:30:08.473Z',
            'is_blocked': true,
            'retry_count': 1,
            'booking_history_rechecked': true,
            'conflict_recovery_attempted': true,
            'last_error':
                'Sync conflict: booking changed remotely before applying this edit.',
          }),
        ];
        final queue = OfflineMutationQueueService(
          firestore: db,
          backend: backend,
          isOnline: () => true,
        );
        await queue.flushPendingMutations();
        expect(
          (await db.collection('bookings').doc('153').get()).data(),
          server,
        );
        expect((await db.collection('chassis').doc('3').get()).data(), {
          'current_booking_id': 999,
        });
        final rows = backend.data[storageKey]!;
        expect(rows, hasLength(realConflict ? 1 : 0));
        if (realConflict) {
          final saved = jsonDecode(rows.single);
          expect(saved['is_blocked'], true);
          expect(saved['booking_metadata_rechecked'], true);
          expect(saved['error_diagnostics'], contains('server_document'));
          expect(
            saved['error_diagnostics'],
            contains('same_action_version_different_contents'),
          );
          expect(saved['created_at'], '2026-09-29T07:30:08.473Z');
          await queue.flushPendingMutations();
          expect(backend.data[storageKey], rows);
        }
      },
    );
  }
  test(
    'diagnostics include original data when retained and photo metadata without bytes',
    () {
      final snapshot = SyncErrorLogService.pendingMutationSnapshot({
        'id': 'photo1',
        'booking_id': '146',
        'status_key': 'ongoing__1',
        'field_key': 'delivery_form_photo',
        'bytes_base64': 'AQID',
        'base_payload': {'updated_at': 'original'},
      });
      expect(snapshot['original_document_available'], true);
      expect(snapshot['original_document'], {'updated_at': 'original'});
      expect(snapshot['collection'], 'bookings');
      expect(snapshot['target_id'], '146');
      expect(snapshot['operation'], 'bookingPhotoUpload');
      expect(snapshot['photo_upload']['local_bytes_present'], true);
      expect(jsonEncode(snapshot), isNot(contains('AQID')));
    },
  );
}
