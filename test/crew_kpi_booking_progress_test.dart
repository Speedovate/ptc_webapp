import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

KpiPeriod _september() => KpiPeriod.month(2026, 9);

String _day(int day, {int hour = 10}) =>
    DateTime.utc(2026, 9, day, hour).toIso8601String();

Map<String, dynamic> _booking({
  required String id,
  String? driverId = '12',
  String? helperId = '23',
  String status = 'delivered',
  String? deliveredAt,
  String? createdAt,
}) => {
  'id': id,
  'driver_id': driverId,
  'helper_id': helperId,
  'client_status': status,
  'delivered_at': ?deliveredAt,
  'created_at': createdAt ?? _day(1),
};

void main() {
  group('kpiBookingProgress', () {
    test('reports delivered out of assigned', () {
      final result = kpiBookingProgress(
        [
          _booking(id: '1', deliveredAt: _day(3)),
          _booking(id: '2', deliveredAt: _day(4)),
          _booking(id: '3', deliveredAt: _day(5)),
          _booking(id: '4', status: 'ongoing', createdAt: _day(6)),
        ],
        period: _september(),
        now: DateTime.utc(2026, 9, 30),
      );

      expect(result.delivered, 3);
      expect(result.total, 4);
    });

    test('counts a trip that reached a later workflow stage as delivered', () {
      // check/empty/return/confirm all mean the trip was delivered and has moved
      // on, so they must count as delivered rather than as outstanding work.
      for (final status in [
        'delivered',
        'check',
        'empty',
        'return',
        'confirm',
      ]) {
        final result = kpiBookingProgress(
          [_booking(id: '1', status: status, createdAt: _day(2))],
          period: _september(),
          now: DateTime.utc(2026, 9, 30),
        );
        expect(result.delivered, 1, reason: '$status is a delivered trip');
      }
    });

    test('an undelivered trip is counted but not as delivered', () {
      for (final status in ['pending', 'assigned', 'ongoing', 'book']) {
        final result = kpiBookingProgress(
          [_booking(id: '1', status: status, createdAt: _day(2))],
          period: _september(),
          now: DateTime.utc(2026, 9, 30),
        );
        expect(result.total, 1);
        expect(result.delivered, 0, reason: '$status is not delivered yet');
      }
    });

    test('a cancelled trip is not treated as delivered work', () {
      final result = kpiBookingProgress(
        [_booking(id: '1', status: 'cancelled', createdAt: _day(2))],
        period: _september(),
        now: DateTime.utc(2026, 9, 30),
      );
      expect(result.total, 1);
      expect(result.delivered, 0);
    });

    test('delivered can never exceed total', () {
      // Both sides share one anchor date, so a booking delivered in a later
      // month than it was created cannot inflate the delivered side.
      final result = kpiBookingProgress(
        [
          _booking(id: '1', createdAt: _day(28), deliveredAt: _day(29)),
          _booking(id: '2', createdAt: _day(30), deliveredAt: _day(30)),
          _booking(id: '3', status: 'ongoing', createdAt: _day(30)),
        ],
        period: _september(),
        now: DateTime.utc(2026, 9, 30),
      );
      expect(result.delivered, lessThanOrEqualTo(result.total));
      expect(result.total, 3);
      expect(result.delivered, 2);
    });

    test('a delivered trip is counted in the month it was delivered', () {
      // Created in August, delivered in September: the period anchor is the
      // delivery date, so September is the month that owns this trip.
      final result = kpiBookingProgress(
        [
          _booking(
            id: '1',
            deliveredAt: _day(2),
            createdAt: DateTime.utc(2026, 8, 28).toIso8601String(),
          ),
        ],
        period: _september(),
        now: DateTime.utc(2026, 9, 30),
      );
      expect(result.total, 1);
      expect(result.delivered, 1);
    });

    test('trips outside the period are ignored', () {
      final result = kpiBookingProgress(
        [
          _booking(
            id: '1',
            createdAt: DateTime.utc(2026, 8, 10).toIso8601String(),
          ),
          _booking(
            id: '2',
            createdAt: DateTime.utc(2026, 10, 2).toIso8601String(),
          ),
        ],
        period: _september(),
        now: DateTime.utc(2026, 9, 30),
      );
      expect(result.total, 0);
      expect(result.delivered, 0);
    });

    test('a future-dated trip is not counted yet', () {
      final result = kpiBookingProgress(
        [
          _booking(
            id: '1',
            createdAt: DateTime.utc(2026, 9, 28).toIso8601String(),
          ),
        ],
        period: _september(),
        now: DateTime.utc(2026, 9, 10),
      );
      expect(
        result.total,
        0,
        reason: 'today is the 10th; the 28th has not happened',
      );
    });

    test('never counts another crew member trip', () {
      // Defence in depth: even if a stale snapshot handed us somebody else's
      // booking, the driver must not see it in their own numbers.
      final result = kpiBookingProgress(
        [
          _booking(id: '1', driverId: '12', deliveredAt: _day(3)),
          _booking(id: '2', driverId: '13', deliveredAt: _day(4)),
          _booking(
            id: '3',
            driverId: null,
            helperId: '23',
            deliveredAt: _day(5),
          ),
        ],
        period: _september(),
        role: 'driver',
        userId: '12',
        now: DateTime.utc(2026, 9, 30),
      );
      expect(result.total, 1);
      expect(result.delivered, 1);
    });

    test('scopes to the helper when the subject is a helper', () {
      final result = kpiBookingProgress(
        [
          _booking(
            id: '1',
            driverId: '12',
            helperId: '23',
            deliveredAt: _day(3),
          ),
          _booking(
            id: '2',
            driverId: '12',
            helperId: '24',
            deliveredAt: _day(4),
          ),
        ],
        period: _september(),
        role: 'helper',
        userId: '23',
        now: DateTime.utc(2026, 9, 30),
      );
      expect(result.total, 1);
      expect(result.delivered, 1);
    });

    test('an empty snapshot is zero, not a crash', () {
      final result = kpiBookingProgress(const [], period: _september());
      expect(result.total, 0);
      expect(result.delivered, 0);
    });

    test('a booking with no dates at all cannot break the count', () {
      final result = kpiBookingProgress(
        [
          <String, dynamic>{'id': 'broken', 'client_status': 'ongoing'},
        ],
        period: _september(),
        now: DateTime.utc(2026, 9, 30),
      );
      expect(result.total, 0);
    });
  });
}
