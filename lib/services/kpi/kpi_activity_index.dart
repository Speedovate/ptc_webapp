import 'pm_kpi.dart';

/// Cached ordering and day lookup for presentation-only rebuilds.
class KpiActivityIndex {
  KpiActivityIndex(PmKpi result) {
    activeDays = result.days
        .where((day) => day.trips.isNotEmpty || day.record.isNotEmpty)
        .toList();

    for (final day in activeDays) {
      final trips = [...day.trips]
        ..sort((a, b) {
          final order = kpiDeliveredAt(
            a.booking,
          )!.compareTo(kpiDeliveredAt(b.booking)!);
          return order == 0 ? a.identity.compareTo(b.identity) : order;
        });
      for (final trip in trips) {
        activityRows.add((day: day, trip: trip, showDailyTotals: false));
      }
      activityRows.add((day: day, trip: null, showDailyTotals: true));
    }
    activityRows.sort((a, b) {
      final aTime = a.trip == null
          ? a.day.date.add(const Duration(days: 1))
          : kpiDeliveredAt(
              a.trip!.booking,
            )!.toUtc().add(const Duration(hours: 8));
      final bTime = b.trip == null
          ? b.day.date.add(const Duration(days: 1))
          : kpiDeliveredAt(
              b.trip!.booking,
            )!.toUtc().add(const Duration(hours: 8));
      final order = bTime.compareTo(aTime);
      return order != 0
          ? order
          : (b.trip?.identity ?? '').compareTo(a.trip?.identity ?? '');
    });
    activeDays.sort((a, b) => b.date.compareTo(a.date));

    for (var i = 0; i < activityRows.length; i++) {
      transactionsByDay
          .putIfAbsent(kpiDayKey(activityRows[i].day.date), () => [])
          .add(i);
    }
  }
  late final List<KpiDay> activeDays;
  final activityRows = <({KpiDay day, KpiTrip? trip, bool showDailyTotals})>[];
  final transactionsByDay = <String, List<int>>{};
}
