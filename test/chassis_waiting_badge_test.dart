import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/services/chassis_waiting_badge.dart';

void main() {
  final delivered = DateTime.utc(2026, 10, 2, 1);
  Chassis chassis(int id, {bool active = true}) => Chassis(
    id: id,
    name: '$id',
    isActive: active,
    currentStatus: Chassis.loaded,
    currentBookingId: id,
  );
  Booking booking(int id, {String status = 'delivered', DateTime? at}) =>
      Booking(
        id: '$id',
        chassisId: '$id',
        clientStatus: status,
        deliveredAt: at,
      );
  test(
    'counts one waiting chassis at four hours, not claims or missing dates',
    () {
      final thresholds = chassisWaitingBadgeThresholds(
        [
          chassis(1),
          chassis(1),
          chassis(2),
          chassis(3),
          chassis(4, active: false),
          chassis(5),
        ],
        [
          booking(1, at: delivered),
          booking(1, at: delivered),
          booking(2, at: delivered, status: 'return'),
          booking(3),
          booking(4, at: delivered),
          booking(
            5,
            at: delivered.add(const Duration(hours: 1)),
            status: 'check',
          ),
        ],
      );
      expect(thresholds, [
        delivered.add(const Duration(hours: 4)),
        delivered.add(const Duration(hours: 5)),
      ]);
      int count(DateTime now) =>
          thresholds.where((at) => !at.isAfter(now)).length;
      expect(count(delivered.add(const Duration(hours: 4))..toUtc()), 1);
      expect(count(delivered.add(const Duration(hours: 3, minutes: 59))), 0);
      expect(count(delivered.add(const Duration(hours: 5))), 2);
    },
  );
  test(
    'current chassis booking reference works even without reverse chassis id',
    () {
      expect(
        chassisWaitingBadgeThresholds(
          [chassis(1)],
          [Booking(id: '1', clientStatus: 'empty', deliveredAt: delivered)],
        ),
        [delivered.add(const Duration(hours: 4))],
      );
    },
  );
}
