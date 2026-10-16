import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:webapp/services/sync_error_log_service.dart';
import 'sync_error_log_service_test.dart' show MemoryLogs;

void main() {
  test(
    'same-attempt missing-source correction preserves original error and failure times',
    () async {
      final db = FakeFirebaseFirestore();
      final disk = MemoryLogs();
      var online = false;
      final logger = SyncErrorLogService(
        firestore: db,
        backend: disk,
        online: () => online,
        metadata: (_) async => {'user_id': '8'},
      );
      await logger.start();
      Future<void> capture(String error, Map<String, dynamic> evidence) =>
          logger.capture(
            source: 'booking_offline_upload_queue_service.dart',
            operation: 'bookingPhotoUpload',
            entryId: 'photo1',
            target: 'bookings/offline_booking_8_9_1_1',
            owner: '8',
            error: error,
            stack: 'Original stack',
            attempt: 2,
            failedAt: '2026-10-14T00:09:29.609Z',
            actionAt: '2026-10-13T22:06:16.112Z',
            details: {'identity_lookup': evidence},
          );
      await capture('Failed to get document because the client is offline.', {
        'stage': 'completed',
        'result': 'no_server_identity',
        'lookup_started': true,
        'old_nested_value': 'must disappear',
      });
      online = true;
      await logger.flush();
      online = false;
      await capture(
        'The original booking submission is missing. The photo remains saved.',
        {'lookup_started': false, 'result': 'deferred_or_shared_lookup'},
      );
      online = true;
      await logger.flush();
      final doc = (await db.collection(SyncErrorLogService.collection).get())
          .docs
          .single
          .data();
      expect(doc['error'], contains('original booking submission is missing'));
      expect(doc['original_failure']['error'], contains('client is offline'));
      expect(
        doc['original_failure']['last_failed_at'],
        '2026-10-14T00:09:29.609Z',
      );
      expect(doc['first_failed_at'], '2026-10-14T00:09:29.609Z');
      expect(doc['action_at'], '2026-10-13T22:06:16.112Z');
      expect(doc['occurrences'], 1);
      expect(doc['details']['identity_lookup'], {
        'lookup_started': false,
        'result': 'deferred_or_shared_lookup',
      });
      expect(jsonDecode(doc['copy_report'])['details'], doc['details']);
      logger.dispose();
    },
  );
}
