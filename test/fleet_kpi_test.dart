import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/kpi/fleet_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/kpi_rating_rules.dart';

void main() {
  test('fleet sums PM costs and targets and merges daily earnings once', () {
    final period = KpiPeriod.month(2026, 9);
    PmKpi report(double revenue, double driver, double helper, double target) =>
        PmKpi(
          period: period,
          days: [
            KpiDay(
              DateTime.utc(2026, 9, 9),
              [],
              {'fuel': 100},
              estimate: KpiSalaryEstimate(
                driver: driver,
                helper: helper,
                dailyRate: 455,
                rates: [
                  {'signature': '$revenue', 'driver': 100, 'helper': 50},
                ],
              ),
            ),
          ],
          revenue: revenue,
          bookingCount: 1,
          issues: {},
          threshold: 0,
          ratingRules: KpiRatingRules(targetPercent: target),
        );
    final first = report(10000, 555, 505, 40);
    final second = report(20000, 655, 555, 45);
    final total = FleetKpi(period, [first, second]);
    expect(total.revenue, 30000);
    expect(total.days, hasLength(1));
    expect(total.days.single.estimate!.rates, hasLength(2));
    expect(total.driverSalary, 1210);
    expect(total.helperSalary, 1060);
    expect(total.fuel, 200);
    expect(total.depreciation, closeTo(100000, 0.001));
    expect(total.maintenance, closeTo(116000, 0.001));
    expect(total.expenses, first.expenses + second.expenses);
    expect(total.gross, first.gross + second.gross);
    expect(total.marginTarget, 13000);
    expect(total.profitTarget, first.profitTarget + second.profitTarget);
    expect(total.revenueTarget, closeTo(700000, 0.001));
    expect(total.days.single.salaryComplete, isFalse);
  });
}
