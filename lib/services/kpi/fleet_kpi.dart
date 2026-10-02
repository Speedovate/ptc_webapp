import 'kpi_fleet_rating.dart';
import 'pm_kpi.dart';

/// Sum already scoped PM reports, retaining their own costs and targets.
class FleetKpi extends PmKpi {
  FleetKpi(KpiPeriod period, this.reports)
    : super(
        period: period,
        days: _days(reports),
        revenue: reports.fold(0, (sum, r) => sum + r.revenue),
        bookingCount: reports.fold(0, (sum, r) => sum + r.bookingCount),
        issues: {for (final r in reports) ...r.issues},
        threshold: 0,
        ratingRules: reports.first.ratingRules,
      );

  final List<PmKpi> reports;
  double sum(double Function(PmKpi) value) =>
      reports.fold(0, (total, report) => total + value(report));
  @override
  double get depreciation => sum((r) => r.depreciation);
  @override
  double get maintenance => sum((r) => r.maintenance);
  @override
  double get revenueTarget => sum((r) => r.revenueTarget);
  @override
  double get profitTarget => sum((r) => r.profitTarget);
  @override
  double get marginTarget => sum((r) => r.marginTarget);
  @override
  bool get depreciationEstimated => reports.any((r) => r.depreciationEstimated);
  @override
  bool get maintenanceEstimated => reports.any((r) => r.maintenanceEstimated);
  @override
  String get rating => averageFleetRating(reports);

  static List<KpiDay> _days(List<PmKpi> reports) {
    final groups = <String, List<KpiDay>>{};
    for (final r in reports) {
      for (final d in r.days) {
        groups.putIfAbsent(kpiDayKey(d.date), () => []).add(d);
      }
    }
    return [for (final days in groups.values) _FleetDay(days)];
  }
}

class _FleetDay extends KpiDay {
  _FleetDay(this.sources)
    : super(
        sources.first.date,
        [for (final d in sources) ...d.trips],
        {if (sources.any((d) => d.record.isNotEmpty)) 'fleet_summary': true},
        estimate: KpiSalaryEstimate(
          driver: sources.fold(0, (sum, d) => sum + d.driverSalary),
          helper: sources.fold(0, (sum, d) => sum + d.helperSalary),
          dailyRate: 0,
          complete: sources.every((d) => d.salaryCalculated),
          rates: [
            for (final d in sources)
              for (final rate
                  in (d.estimate?.rates ??
                          d.record['trip_rates'] as List? ??
                          [])
                      .whereType<Map>())
                Map<String, dynamic>.from(rate),
          ],
        ),
      );
  final List<KpiDay> sources;
  @override
  double get fuel => sources.fold(0, (sum, d) => sum + d.fuel);
  @override
  double get driverSalary => sources.fold(0, (sum, d) => sum + d.driverSalary);
  @override
  double get helperSalary => sources.fold(0, (sum, d) => sum + d.helperSalary);
  @override
  bool get salaryComplete => sources.every((d) => d.salaryComplete);
  @override
  bool get fuelComplete => sources.every((d) => d.fuelComplete);
}
