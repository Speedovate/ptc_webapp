import 'package:webapp/models/booking.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/booking_pm_assignment.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';

/// Earliest known truck activity, not an arbitrary epoch that would invent costs.
KpiPeriod fleetTruckAllTimePeriod(
  VehicleMake make,
  List<VehicleMake> makes,
  List<Booking> bookings,
  KpiStoredData stored,
  DateTime today,
) {
  final dates = <DateTime>[
    if (make.createdAt != null) kpiDate(make.createdAt!),
    for (final booking in bookings)
      if (resolveBookingPm(booking, makes)?.id == make.id) ...[
        if (booking.createdAt != null) kpiDate(booking.createdAt!),
        if (kpiDeliveredAt(booking) != null) kpiDate(kpiDeliveredAt(booking)!),
      ],
    for (final record in [...stored.records, ...stored.fuel])
      if (DateTime.tryParse('${record['day']}') case final DateTime day)
        DateTime.utc(day.year, day.month, day.day),
  ].where((date) => !date.isAfter(today)).toList()..sort();
  return KpiPeriod(dates.isEmpty ? today : dates.first, today);
}
