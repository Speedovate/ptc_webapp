import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/firestore_offline_service.dart';
import 'package:webapp/services/firebase_console_diagnostic.dart';
import 'package:webapp/services/booking_photo_marker_match.dart';
import 'package:webapp/services/sync_error_log_service.dart';
import 'sync_error_log_service_test.dart' show MemoryLogs, reports;

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform mobile web keeps durable persistence with compatible transport',
      () {
        final settings = FirestoreOfflineService.settingsForPlatform(
          web: true,
          platform: platform,
        );
        expect(settings.persistenceEnabled, true);
        expect(settings.webExperimentalForceLongPolling, true);
        expect(settings.webExperimentalAutoDetectLongPolling, false);
        expect(
          settings.webExperimentalLongPollingOptions?.timeoutDuration,
          const Duration(seconds: 25),
        );
      },
    );
  }
  for (final platform in TargetPlatform.values) {
    test('$platform native transport retains SDK defaults and persistence', () {
      final settings = FirestoreOfflineService.settingsForPlatform(
        web: false,
        platform: platform,
      );
      expect(settings.persistenceEnabled, true);
      expect(settings.webExperimentalForceLongPolling, isNull);
      expect(settings.webExperimentalLongPollingOptions, isNull);
    });
  }
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    test('$platform desktop web retains SDK transport defaults', () {
      final settings = FirestoreOfflineService.settingsForPlatform(
        web: true,
        platform: platform,
      );
      expect(settings.persistenceEnabled, true);
      expect(settings.webExperimentalForceLongPolling, isNull);
    });
  }
  final rows =
      jsonDecode(
            File(
              'test/fixtures/oct21_build57_mobile_data.json',
            ).readAsStringSync(),
          )
          as List;
  test('actual +57 reservation timeout is not proof of a missing booking', () {
    final row = rows.first;
    final result = firebaseConsoleDiagnostic({
      'error': row['error'],
      'details': {'identity_lookup': row['identity_lookup']},
    });
    expect(result['category'], 'connection_or_service_availability');
    expect(result['reason'], contains('did not confirm'));
    expect(result['evidence']['firebase_code'], isNull);
    expect(result['evidence']['console_state_verified'], false);
  });
  for (final row in rows.where((r) => r['server_document'] != null)) {
    test(
      'historical build46 booking ${row['booking_id']} has an exact uploaded photo',
      () {
        final photo = row['photo_upload'];
        expect(
          bookingPhotoAlreadyUploadedInHistory(
            booking: Map<String, dynamic>.from(row['server_document']),
            bookingId: row['booking_id'],
            fieldKey: photo['field_key'],
            fileName: photo['file_name'],
            size: photo['size'],
            mimeType: photo['mime_type'],
          ),
          true,
        );
      },
    );
  }
  for (final attempt in [14, 15]) {
    test(
      'timeout correction preserves original evidence; attempt=$attempt',
      () async {
        final disk = MemoryLogs();
        final logger = SyncErrorLogService(
          backend: disk,
          online: () => false,
          metadata: (_) async => {'user_id': '8'},
        );
        addTearDown(logger.dispose);
        final row = rows.first;
        Future<void> capture(
          String error,
          int n,
          Map<String, dynamic> lookup,
        ) => logger.capture(
          source: 'booking_offline_upload_queue_service.dart',
          operation: 'bookingPhotoUpload',
          owner: '8',
          entryId: row['queue_entry_id'],
          target: 'bookings/pending',
          error: error,
          stack: 'Original evidence',
          attempt: n,
          actionAt: row['action_at'],
          failedAt: row['last_failed_at'],
          details: {'identity_lookup': lookup},
        );
        await capture(row['error'], 14, {});
        await capture(
          'TimeoutException: The server booking identity check timed out.',
          attempt,
          Map<String, dynamic>.from(row['identity_lookup']),
        );
        final pending = jsonDecode(reports(disk).single);
        expect(pending['error'], startsWith('TimeoutException'));
        expect(pending['original_failure']['error'], row['error']);
        expect(pending['action_at'], row['action_at']);
        expect(pending['first_failed_at'], row['last_failed_at']);
      },
    );
  }
}
