import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/booking_pm_assignment.dart';
import 'dart:convert';

import 'package:webapp/models/booking.dart';
import 'operations_catalog.dart';
import 'pm_kpi.dart';

/// Generated only on request, using the same loaded data as the KPI.
String kpiSalaryDiagnostics({
  required String makeId,
  required List<Booking> bookings,
  required OperationsCatalog catalog,
  required PmKpi result,
  required bool verified,
  List<VehicleMake> makes = const [],
}) {
  return const JsonEncoder.withIndent('  ').convert({
    'report': 'KPI salary diagnostics',
    'pm_id': makeId,
    'period_start': kpiDayKey(result.period.start),
    'period_end': kpiDayKey(result.period.end),
    'bookings_verified': verified,
    'loaded_bookings': bookings.length,
    'driver_salary': result.driverSalary,
    'helper_salary': result.helperSalary,
    'issues': result.issues.toList(),
    'bookings': bookings.map((booking) {
      final pm = resolveBookingPm(booking, makes);
      final delivered = kpiDeliveredAt(booking);
      final day = delivered == null ? null : kpiDate(delivered);
      final included =
          pm?.id == makeId && day != null && result.period.contains(day);
      final matrix = day == null ? null : catalog.matrixFor(day);
      final trip = KpiTrip(booking, day ?? result.period.start);
      final match = matrix == null
          ? null
          : matchKpiTripRate(trip, matrix.rates);
      return {
        'booking_id': booking.id,
        'submission_key': booking.submissionKey,
        'pm_id': booking.vehicleMake?.id,
        'resolved_pm_id': pm?.id,
        'pm_assignment_issue': bookingPmAssignmentIssue(booking, makes),
        'pm_source': booking.vehicleMake?.id != null
            ? 'booking'
            : confirmedLegacyBookingPm(booking, makes) != null
            ? 'confirmed historical driver assignment'
            : pm != null
            ? 'unique fixed crew bundle'
            : 'unresolved',
        'driver_id': booking.driver?.id,
        'helper_id': booking.helper?.id,
        'status': booking.clientStatus,
        'status_events': (booking.statusOutputs ?? <String, dynamic>{}).entries
            .map((entry) {
              final raw = entry.value;
              if (raw is! Map) {
                return {'key': entry.key, 'invalid_type': '${raw.runtimeType}'};
              }
              final form = raw['status_form'];
              return {
                'key': entry.key,
                'status_key': '${raw['status_key'] ?? ''}',
                'next_status_key': form is Map
                    ? '${form['next_status_key'] ?? ''}'
                    : '',
                'submitted_at': '${raw['submitted_at'] ?? ''}',
                'created_at': '${raw['created_at'] ?? ''}',
              };
            })
            .toList(),
        'created_at': booking.createdAt?.toIso8601String(),
        'delivered_at': delivered?.toIso8601String(),
        'delivery_date_source': booking.deliveredAt != null
            ? 'delivered_at'
            : delivered != null
            ? 'status_outputs'
            : 'missing',
        'destination': trip.destination,
        'destination_barangay': trip.destinationBarangay,
        'matrix_id': matrix?.id,
        'matched_rate': match?.rate?.name,
        'rate_issue': match?.issue,
        'eligibility': included
            ? 'PM and delivery date match; see daily calculation'
            : pm?.id != makeId
            ? 'Different or missing PM'
            : day == null
            ? 'Missing delivery date'
            : 'Outside selected dates',
      };
    }).toList(),
    'days': result.days
        .map(
          (day) => {
            'date': kpiDayKey(day.date),
            'bookings': day.trips.map((trip) => trip.booking.id).toList(),
            'driver_salary': day.driverSalary,
            'helper_salary': day.helperSalary,
            'calculation_complete': day.salaryCalculated,
            'confirmed_snapshot': day.salaryComplete,
            'calculated_rates': day.estimate?.rates,
          },
        )
        .toList(),
  });
}
