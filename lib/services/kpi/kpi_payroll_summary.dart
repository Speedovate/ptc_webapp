import 'pm_kpi.dart';

class KpiPayrollSummary {
  static List<List<Object?>> rows(PmKpi result) {
    final groups = <String, List<KpiDay>>{};
    for (final day in result.days) {
      if (day.trips.isEmpty && day.record.isEmpty) continue;
      final week = ((day.date.day - 1) ~/ 7 + 1).clamp(1, 4);
      final key =
          '${day.date.year}-${day.date.month.toString().padLeft(2, '0')}:$week';
      groups.putIfAbsent(key, () => []).add(day);
    }
    return [
      for (final group in groups.entries)
        _row(group.key, group.value, result.period),
    ];
  }

  static List<Object?> _row(String key, List<KpiDay> days, KpiPeriod selected) {
    final period = KpiPeriod.week(
      days.first.date.year,
      days.first.date.month,
      int.parse(key.split(':').last),
    );
    final start = period.start.isBefore(selected.start)
        ? selected.start
        : period.start;
    final end = period.end.isAfter(selected.end) ? selected.end : period.end;
    var driver = 0.0, helper = 0.0, driverShares = 0.0, helperShares = 0.0;
    for (final day in days) {
      driver += day.driverSalary;
      helper += day.helperSalary;
      final rates =
          (day.estimate?.rates ?? day.record['trip_rates'] as List? ?? const [])
              .whereType<Map>();
      for (final rate in rates) {
        driverShares += kpiMoney(rate['driver']) ?? 0;
        helperShares += kpiMoney(rate['helper']) ?? 0;
      }
    }
    return [
      '${kpiDayKey(start)} – ${kpiDayKey(end)}',
      driverShares,
      driver - driverShares,
      helperShares,
      helper - helperShares,
      driver + helper,
      days.every((d) => d.salaryComplete) ? 'Confirmed' : 'Pending',
    ];
  }
}
