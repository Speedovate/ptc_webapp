import 'package:webapp/models/booking.dart';
import 'package:webapp/models/vehicle_make.dart';

/// Owner-confirmed historical assignments for legacy bookings created before
/// confirmation on 22 Sep 2026. This does not infer future driver assignments.
VehicleMake? confirmedLegacyBookingPm(
  Booking booking,
  Iterable<VehicleMake> makes,
) {
  if (booking.vehicleMake?.id?.trim().isNotEmpty == true ||
      booking.createdAt == null ||
      !booking.createdAt!.isBefore(DateTime.utc(2026, 9, 22))) {
    return null;
  }
  final expected = switch (booking.driver?.id) {
    '17' => ('2', 'PM5'),
    '12' => ('3', 'PM6'),
    _ => null,
  };
  if (expected == null) return null;
  return makes
      .where(
        (make) =>
            make.id == expected.$1 &&
            make.code?.trim().toUpperCase() == expected.$2,
      )
      .firstOrNull;
}

/// PALTRANCO's fixed truck/driver/helper bundle. Never override an explicit
/// booking PM or choose between multiple trucks assigned to the same pair.
VehicleMake? resolveBookingPm(Booking booking, Iterable<VehicleMake> makes) {
  if (booking.vehicleMake?.id?.trim().isNotEmpty == true) {
    return booking.vehicleMake;
  }
  final historical = confirmedLegacyBookingPm(booking, makes);
  if (historical != null) return historical;
  final driver = booking.driver?.id;
  final helper = booking.helper?.id;
  if (driver == null || driver.isEmpty || helper == null || helper.isEmpty) {
    return null;
  }
  final matches = <String, VehicleMake>{
    for (final make in makes)
      if (make.id?.isNotEmpty == true &&
          make.driver?.id == driver &&
          make.helper?.id == helper)
        make.id!: make,
  };
  return matches.length == 1 ? matches.values.single : null;
}

/// Explain the failed assignment using the same exact-pair rule as the resolver.
String? bookingPmAssignmentIssue(Booking booking, Iterable<VehicleMake> makes) {
  final available = makes.toList();
  if (resolveBookingPm(booking, available) != null) return null;
  final driver = booking.driver?.id;
  final helper = booking.helper?.id;
  final missing = [
    if (driver == null || driver.isEmpty) 'driver',
    if (helper == null || helper.isEmpty) 'helper',
  ];
  if (missing.isNotEmpty) {
    return 'No PM assigned; ${missing.join(' and ')} missing';
  }
  String label(VehicleMake make) => '${make.code ?? 'PM'} (ID ${make.id})';
  final matches = {
    for (final make in available)
      if (make.id?.isNotEmpty == true &&
          make.driver?.id == driver &&
          make.helper?.id == helper)
        make.id!: make,
  };
  if (matches.length > 1) {
    return 'No PM assigned; Driver $driver + Helper $helper match multiple PMs: '
        '${matches.values.map(label).join(', ')}';
  }
  if (available.isEmpty) {
    return 'No PM assigned; no PM records loaded to match Driver $driver + Helper $helper';
  }
  final candidates = available.where(
    (make) => make.driver?.id == driver || make.helper?.id == helper,
  );
  final details = candidates
      .map(
        (make) =>
            '${label(make)}: Driver ${make.driver?.id ?? 'not assigned'}, Helper ${make.helper?.id ?? 'not assigned'}',
      )
      .join('; ');
  return 'No PM assigned; no PM has Driver $driver + Helper $helper'
      '${details.isEmpty ? '' : '. Current assignments: $details'}';
}
