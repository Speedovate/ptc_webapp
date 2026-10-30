import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_create_photo_restage.dart';

void main() {
  final first = <String, dynamic>{
    'status_key': 'book',
    'submitted_by': '8',
    'submitted_at': '2026-10-30T10:31:38.309',
    'fields': {
      'representative_name': 'New Panay',
      'waybill_photo': {
        'name': 'waybill.jpg',
        'size': 5,
        'mime_type': 'image/jpeg',
        'pending_upload': true,
        'pending_upload_id': 'old',
      },
    },
  };
  final assignment = <String, dynamic>{
    'status_key': 'pending',
    'submitted_by': '8',
    'submitted_at': '2026-10-30T10:33:11.180',
    'status_form': {
      'is_main_form': true,
      'current_status_key': 'pending',
      'next_status_key': 'assigned',
    },
    'fields': {'driver_id': '13', 'helper_id': '18'},
  };
  final server = <String, dynamic>{
    'id': '352',
    'submission_key': 'booking_8_9_1_1793327498308000',
    'created_at': '2026-10-30T10:31:38.308',
    'updated_at': '2026-10-30T10:31:38.309',
    'client_status': 'pending',
    'driver_status': 'pending',
    'helper_status': 'pending',
    'driver_id': null,
    'helper_id': null,
    'vehicle_make_id': null,
    'chassis_id': null,
    'delivered_at': null,
    'status_outputs': {'book__1793327498309000': first},
    'photo_cleanup_paths': <String>[],
    'photo_cleanup_claims': <String>[],
  };
  final pending = <String, dynamic>{
    ...server,
    'updated_at': '2026-10-30T10:33:11.180',
    'client_status': 'assigned',
    'driver_status': 'assigned',
    'helper_status': 'assigned',
    'driver_id': '13',
    'helper_id': '18',
    'status_outputs': {
      'book__1793327498309000': {
        ...first,
        'fields': {
          ...(first['fields'] as Map),
          'waybill_photo': {
            ...((first['fields'] as Map)['waybill_photo'] as Map),
            'pending_upload_id': 'new',
          },
        },
      },
      'pending__1793327591180000': assignment,
    },
  };
  bool safe(Map<String, dynamic> next) => canContinueRestagedBookingCreate(
    server,
    next,
    baseUpdatedAt: server['created_at'] as String,
  );

  test('accepts assignment when only initial photo marker was restaged', () {
    expect(safe(pending), isTrue);
  });

  test(
    'rejects changed first event, changed metadata, and remote progress',
    () {
      final status = Map<String, dynamic>.from(
        pending['status_outputs'] as Map,
      );
      final firstCopy = Map<String, dynamic>.from(status.values.first as Map);
      status[status.keys.first] = {...firstCopy, 'submitted_by': 'another'};
      expect(safe({...pending, 'status_outputs': status}), isFalse);
      final fields = Map<String, dynamic>.from(firstCopy['fields'] as Map);
      fields['waybill_photo'] = {
        ...(fields['waybill_photo'] as Map),
        'name': 'other.jpg',
      };
      status[status.keys.first] = {...firstCopy, 'fields': fields};
      expect(safe({...pending, 'status_outputs': status}), isFalse);
      expect(
        canContinueRestagedBookingCreate(
          {...server, 'client_status': 'assigned'},
          pending,
          baseUpdatedAt: server['created_at'] as String,
        ),
        isFalse,
      );
    },
  );
}
