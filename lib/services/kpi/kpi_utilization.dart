import 'package:webapp/models/booking.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/booking_pm_assignment.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

enum KpiUtilizationMode { daily, weekly, monthly }

/// Counts unique completed trips using their original delivery date.
/// Callers supply the same authorized bookings and makes as the KPI overview.
class KpiUtilization {
  KpiUtilization({
    required this.counts,
    required this.columns,
    required this.unresolved,
    required this.totalDays,
    this.trips = const {},
  });
  final Map<String, List<int>> counts;
  final int columns;
  final int unresolved;
  final Map<String, int> totalDays;
  final Map<String, List<List<Booking>>> trips;

  factory KpiUtilization.calculate({
    required List<Booking> bookings,
    required List<VehicleMake> makes,
    required KpiUtilizationMode mode,
    required int year,
    required int month,
  }) {
    final columns = switch (mode) {
      KpiUtilizationMode.daily => DateTime.utc(year, month + 1, 0).day,
      KpiUtilizationMode.weekly => 4,
      KpiUtilizationMode.monthly => 12,
    };
    final counts = <String, List<int>>{
      for (final make in makes)
        if (make.id != null) make.id!: List.filled(columns, 0),
    };
    final unique = <String, Booking>{};
    final trips = <String, List<List<Booking>>>{
      for (final id in counts.keys)
        id: List.generate(columns, (_) => <Booking>[]),
    };
    final activeDays = <String, Set<DateTime>>{};
    for (final booking in bookings) {
      final key = (booking.submissionKey?.isNotEmpty ?? false)
          ? booking.submissionKey
          : booking.id;
      if (key == null || key.isEmpty) {
        continue;
      }
      final previous = unique[key];
      if (previous == null ||
          (booking.updatedAt ?? DateTime(1900)).isAfter(
            previous.updatedAt ?? DateTime(1900),
          )) {
        unique[key] = booking;
      }
    }
    var unresolved = 0;
    for (final booking in unique.values) {
      if (!Booking.isDeliveredWorkflowStatus(booking.clientStatus)) {
        continue;
      }
      final delivered = kpiDeliveredAt(booking);
      if (delivered == null) {
        unresolved++;
        continue;
      }
      final day = kpiDate(delivered);
      if (day.year != year ||
          (mode != KpiUtilizationMode.monthly && day.month != month)) {
        continue;
      }
      final pm = resolveBookingPm(booking, makes);
      final row = counts[pm?.id];
      if (row == null) {
        unresolved++;
        continue;
      }
      final column = switch (mode) {
        KpiUtilizationMode.daily => day.day - 1,
        KpiUtilizationMode.weekly => ((day.day - 1) ~/ 7).clamp(0, 3),
        KpiUtilizationMode.monthly => day.month - 1,
      };
      row[column]++;
      trips[pm!.id]![column].add(booking);
      activeDays.putIfAbsent(pm.id!, () => <DateTime>{}).add(day);
    }
    return KpiUtilization(
      counts: counts,
      columns: columns,
      unresolved: unresolved,
      trips: trips,
      totalDays: {
        for (final id in counts.keys) id: activeDays[id]?.length ?? 0,
      },
    );
  }
}
