import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/utils/cached_snapshot_documents.dart';

void main() {
  test(
    'server refresh retains a queued offline booking as recovery evidence',
    () {
      final pending = <String, dynamic>{
        'id': 'offline_booking_8_9_1_123',
        'submission_key': 'booking_8_9_1_123',
        'client_id': '9',
        'local_sync_status': 'queued',
        'created_at': '2026-10-14T06:00:00Z',
        'status_outputs': {
          'book__123': {
            'fields': {'representative_name': 'Original', 'waybill_photo': 'x'},
          },
        },
      };
      final remote = <Map<String, dynamic>>[
        {'id': '55', 'submission_key': 'another-booking'},
      ];
      final visible = mergeBookingSnapshotDocuments(
        remote: remote,
        cached: [
          pending,
          {'id': 'old-server-booking'},
        ],
        isFromCache: false,
        hasPendingWrites: false,
      );
      expect(visible.map((row) => row['id']), ['55', pending['id']]);
      expect(visible.last['status_outputs'], pending['status_outputs']);
      expect(remote, hasLength(1));
    },
  );

  test('confirmed submission replaces the temporary cached booking', () {
    final visible = mergeBookingSnapshotDocuments(
      remote: [
        {'id': '56', 'submission_key': 'booking_8_9_1_123'},
      ],
      cached: [
        {
          'id': 'offline_booking_8_9_1_123',
          'submission_key': 'booking_8_9_1_123',
          'local_sync_status': 'queued',
        },
      ],
      isFromCache: false,
      hasPendingWrites: false,
    );
    expect(visible.map((row) => row['id']), ['56']);
  });
}
