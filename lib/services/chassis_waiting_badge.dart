import 'package:webapp/models/booking.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/models/chassis_action_history.dart';

/// One threshold per active waiting chassis, using the same history as its list.
List<DateTime> chassisWaitingBadgeThresholds(
  Iterable<Chassis> chassis,
  Iterable<Booking> bookings,
) {
  final byId = {for (final booking in bookings) booking.id: booking};
  final byChassis = <String, Set<Booking>>{};
  for (final booking in byId.values) {
    if (booking.chassisId != null) {
      byChassis.putIfAbsent(booking.chassisId!, () => {}).add(booking);
    }
  }
  final thresholds = <DateTime>[];
  for (final item in {for (final item in chassis) item.id: item}.values) {
    if (!item.isActive) continue;
    final history = ChassisActionHistory.fromBookings(item, {
      ...?byChassis['${item.id}'],
      if (byId[item.bookingReferenceId] case final Booking booking) booking,
    });
    if (history.waiting && history.deliveredAt != null) {
      thresholds.add(history.deliveredAt!.add(const Duration(hours: 4)));
    }
  }
  return thresholds..sort();
}
