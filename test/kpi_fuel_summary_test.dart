import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

void main() {
  test('summary fuel totals come from the selected PM ledger and period', () {
    final fuel = <Map<String, dynamic>>[
      {'id': 'a', 'make_id': '4', 'day': '2026-09-01', 'amount': 1200},
      {'id': 'b', 'make_id': '4', 'day': '2026-09-08', 'amount': 800},
      {
        'id': 'c',
        'make_id': '4',
        'day': '2026-09-15',
        'amount': 500,
        'local_sync_status': 'pending',
      },
      {'id': 'd', 'make_id': '4', 'day': '2026-09-30', 'amount': 300},
      {
        'id': 'void',
        'make_id': '4',
        'day': '2026-09-01',
        'amount': 9000,
        'voided': true,
      },
      {'id': 'other', 'make_id': '7', 'day': '2026-09-01', 'amount': 9999},
      {'id': 'oct', 'make_id': '4', 'day': '2026-10-01', 'amount': 7777},
    ];
    PmKpi report(KpiPeriod period) => PmKpi.calculate(
      makeId: '4',
      period: period,
      bookings: [],
      // Existing daily totals must not be added again over fuel entries.
      records: [
        {'make_id': '4', 'day': '2026-09-01', 'fuel': 1200},
      ],
      fuelEntries: fuel,
    );
    final month = report(KpiPeriod.month(2026, 9));
    expect(month.fuel, 2800);
    expect(
      [
        for (var week = 1; week <= 4; week++)
          report(KpiPeriod.week(2026, 9, week)).fuel,
      ],
      [1200, 800, 500, 300],
    );
    expect(
      report(
        KpiPeriod(DateTime.utc(2026, 9, 8), DateTime.utc(2026, 9, 15)),
      ).fuel,
      1300,
    );
    expect(
      month.expenses,
      month.fuel +
          month.driverSalary +
          month.helperSalary +
          month.depreciation +
          month.maintenance,
    );
    fuel[0] = {...fuel[0], 'amount': 1500};
    expect(report(KpiPeriod.month(2026, 9)).fuel, 3100);
    fuel[0] = {...fuel[0], 'voided': true};
    expect(report(KpiPeriod.month(2026, 9)).fuel, 1600);
  });
}
