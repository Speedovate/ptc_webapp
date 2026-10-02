import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/kpi/kpi_fleet_rating.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/kpi_rating_rules.dart';

PmKpi report(double revenue, {KpiRatingRules rules = const KpiRatingRules()}) =>
    PmKpi(
      period: KpiPeriod.month(2026, 9),
      days: [],
      revenue: revenue,
      bookingCount: 1,
      issues: {},
      threshold: 10000,
      ratingRules: rules,
    );
void main() {
  test('equal truck weights rather than revenue weighted fleet margin', () {
    // Fixed expenses 108,000: these trucks have margins 10% and 70%.
    expect(
      averageFleetRating([report(120000), report(360000)]),
      'Satisfactory',
    );
    expect(averageFleetRating([report(360000)]), 'Excellent');
    expect(averageFleetRating([report(120000)]), 'Failed');
  });
  test('editable rules apply to the average', () {
    const rules = KpiRatingRules(
      grossSatisfactoryMin: 30,
      grossExcellentMin: 40,
    );
    expect(
      averageFleetRating([
        report(120000, rules: rules),
        report(360000, rules: rules),
      ]),
      'Excellent',
    );
  });
  test(
    'cannot invent an average for missing revenue or inconsistent rules',
    () {
      expect(averageFleetRating([]), 'Not rated');
      expect(averageFleetRating([report(0), report(360000)]), 'Not rated');
      expect(
        averageFleetRating([
          report(360000),
          report(360000, rules: const KpiRatingRules(grossExcellentMin: 60)),
        ]),
        'Not rated',
      );
    },
  );
}
