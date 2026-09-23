import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/kpi/kpi_incident_summary.dart';
import 'package:webapp/services/kpi/kpi_rating_rules.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

void main() {
  test('per-user records never inherit partner or legacy counts', () {
    final settings = <String, dynamic>{
      'incident_counts': {
        '2026-09-01': {'complaints': 10, 'accidents': 3},
      },
      'user_incident_counts': {
        '13': {
          '2026-09-01': {'complaints': 1, 'accidents': 0},
        },
        '18': {
          '2026-09-01': {'complaints': 0, 'accidents': 1},
        },
      },
    };
    final period = KpiPeriod(
      DateTime.utc(2026, 9, 1),
      DateTime.utc(2026, 9, 1),
    );
    final driver = KpiIncidentSummary.forUser(
      settings,
      '13',
      period,
      period.end,
    );
    final helper = KpiIncidentSummary.forUser(
      settings,
      '18',
      period,
      period.end,
    );
    final replacement = KpiIncidentSummary.forUser(
      settings,
      '22',
      period,
      period.end,
    );
    expect(driver.confirmedComplaints, 1);
    expect(driver.confirmedAccidents, 0);
    expect(helper.confirmedComplaints, 0);
    expect(helper.confirmedAccidents, 1);
    expect(replacement.complaints, 0);
    expect(replacement.confirmedComplaints, isNull);
  });

  test('date counts sum once across weekly monthly and custom views', () {
    final settings = {
      'incident_counts': {
        for (var d = 1; d <= 30; d++)
          kpiDayKey(DateTime.utc(2026, 9, d)): {
            'complaints': d == 8 ? 1 : 0,
            'accidents': d == 15 ? 1 : 0,
          },
      },
    };
    final month = KpiIncidentSummary(
      settings,
      KpiPeriod.month(2026, 9),
      DateTime.utc(2026, 9, 30),
    );
    expect(month.confirmedComplaints, 1);
    expect(month.confirmedAccidents, 1);
    final week = KpiIncidentSummary(
      settings,
      KpiPeriod.week(2026, 9, 2),
      DateTime.utc(2026, 9, 30),
    );
    expect(week.confirmedComplaints, 1);
    expect(week.confirmedAccidents, 0);
    final custom = KpiIncidentSummary(
      settings,
      KpiPeriod(DateTime.utc(2026, 9, 8), DateTime.utc(2026, 9, 15)),
      DateTime.utc(2026, 9, 30),
    );
    expect(custom.confirmedComplaints, 1);
    expect(custom.confirmedAccidents, 1);
  });
  test('unknown days remain unrated; future days are not treated as zero', () {
    final summary = KpiIncidentSummary(
      {
        'incident_counts': {
          '2026-09-01': {'complaints': 0, 'accidents': 0},
        },
      },
      KpiPeriod.month(2026, 9),
      DateTime.utc(2026, 9, 2),
    );
    expect(summary.days, 2);
    expect(summary.missingComplaints, 1);
    expect(summary.confirmedComplaints, isNull);
    final future = KpiIncidentSummary(
      {},
      KpiPeriod.month(2026, 10),
      DateTime.utc(2026, 9, 2),
    );
    expect(future.days, 0);
    expect(future.confirmedAccidents, isNull);
  });
  test('target defaults to 40 percent and can be edited separately', () {
    final monthly = PmKpi(
      period: KpiPeriod.month(2026, 9),
      days: [],
      revenue: 100000,
      bookingCount: 1,
      issues: {},
      threshold: 10000,
    );
    expect(monthly.profitTarget, closeTo(140000, .001));
    expect(monthly.marginTarget, 40000);
    final edited = PmKpi(
      period: monthly.period,
      days: [],
      revenue: 100000,
      bookingCount: 1,
      issues: {},
      threshold: 10000,
      ratingRules: const KpiRatingRules(targetPercent: 42.5),
    );
    expect(edited.profitTarget, closeTo(148750, .001));
    expect(edited.marginTarget, 42500);
  });
}
