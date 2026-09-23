import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_status_continuation.dart';

Map<String, dynamic> server() => {
  'id': '7',
  'submission_key': 'booking-original',
  'client_status': 'pending',
  'driver_status': 'pending',
  'helper_status': 'pending',
  'driver_id': null,
  'helper_id': null,
  'chassis_id': null,
  'vehicle_make_id': null,
  'created_at': '2026-09-22T08:00:00',
  'updated_at': '2026-09-22T09:00:00',
  'status_outputs': {
    'existing': {
      'fields': {'amount': '3000'},
    },
  },
};
Map<String, dynamic> pending() => {
  ...server(),
  'client_status': 'assigned',
  'driver_status': 'assigned',
  'helper_status': 'assigned',
  'driver_id': '13',
  'helper_id': '18',
  'updated_at': '2026-09-22T10:00:00',
  'status_outputs': {
    ...server()['status_outputs'],
    'new': {
      'status_key': 'pending',
      'submitted_at': '2026-09-22T10:00:00',
      'submitted_by': '8',
      'fields': {'driver_id': '13', 'helper_id': '18'},
      'status_form': {
        'is_main_form': true,
        'current_status_key': 'pending',
        'next_status_key': 'assigned',
      },
    },
  },
};
void main() {
  test('permits evidenced assignment without changing either input', () {
    final a = server();
    final b = pending();
    final originals = jsonEncode([a, b]);
    expect(isSafeBookingStatusContinuation(a, b), true);
    expect(jsonEncode([a, b]), originals);
  });
  test(
    'ongoing continuation preserves crew and rejects an unexplained crew edit',
    () {
      final a = pending();
      final b = jsonDecode(jsonEncode(a)) as Map<String, dynamic>;
      b['client_status'] = b['driver_status'] = b['helper_status'] = 'ongoing';
      b['updated_at'] = '2026-09-22T11:00:00';
      b['status_outputs']['start'] = {
        'status_key': 'assigned',
        'submitted_at': b['updated_at'],
        'submitted_by': '13',
        'fields': {},
        'status_form': {
          'is_main_form': true,
          'current_status_key': 'assigned',
          'next_status_key': 'ongoing',
        },
      };
      expect(isSafeBookingStatusContinuation(a, b), true);
      b['helper_id'] = '99';
      expect(isSafeBookingStatusContinuation(a, b), false);
    },
  );

  test('make inference needs transaction-verified crew', () {
    final b = pending()..['vehicle_make_id'] = '4';
    expect(isSafeBookingStatusContinuation(server(), b), false);
    expect(
      isSafeBookingStatusContinuation(
        server(),
        b,
        verifiedMake: {'driver_id': '13', 'helper_id': '18'},
      ),
      true,
    );
    expect(
      isSafeBookingStatusContinuation(
        server(),
        b,
        verifiedMake: {'driver_id': '13', 'helper_id': '99'},
      ),
      false,
    );
  });
  for (final scenario in [
    'changed history',
    'missing history',
    'amount',
    'identity',
    'time',
    'crew',
    'regression',
    'missing event',
    'extra event',
    'server crew',
  ]) {
    test('rejects $scenario', () {
      final a = server();
      final b = pending();
      switch (scenario) {
        case 'changed history':
          b['status_outputs']['existing']['fields']['amount'] = '4000';
        case 'missing history':
          b['status_outputs'].remove('existing');
        case 'amount':
          b['amount'] = 900;
        case 'identity':
          b['submission_key'] = 'another';
        case 'time':
          b['updated_at'] = '2026-09-23T10:00:00';
        case 'crew':
          b['driver_id'] = '99';
        case 'regression':
          a['client_status'] = 'delivered';
        case 'missing event':
          b['status_outputs'].remove('new');
        case 'extra event':
          b['status_outputs']['another'] = {};
        case 'server crew':
          a['driver_id'] = '17';
      }
      expect(isSafeBookingStatusContinuation(a, b), false);
    });
  }
}
