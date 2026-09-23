import 'dart:typed_data';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'kpi_rating_rules.dart';
import 'kpi_report_export.dart';
import 'kpi_template_workbook.dart';
import 'pm_kpi.dart';
import 'pm_kpi_store.dart';

/// Workbook structure follows PALTRANCO's monthly ledgers, Monthly summary,
/// and weekly PM blocks. All values come from the selected dates in the app.
class KpiFleetWorkbook {
  static const months = [
    'Jan',
    'Feb',
    'March',
    'April',
    'May',
    'June',
    'July',
    'Aug',
    'Sept',
    'Oct',
    'Nov',
    'Dec',
  ];

  static KpiPeriod? overlap(KpiPeriod a, KpiPeriod b) {
    final start = a.start.isAfter(b.start) ? a.start : b.start;
    final end = a.end.isBefore(b.end) ? a.end : b.end;
    return end.isBefore(start) ? null : KpiPeriod(start, end);
  }

  static Future<Uint8List> export({
    required PmKpiStore store,
    required KpiPeriod period,
  }) async {
    if (!store.canRead ||
        !store.canReadBookings ||
        !store.canReadFuel ||
        !store.canReadIncome) {
      throw StateError(
        'KPI, bookings, fuel and trip income read access required for fleet export.',
      );
    }
    final makes =
        (await store.exportMakes())
            .where((m) => m.id?.isNotEmpty == true)
            .toList()
          ..sort((a, b) => (a.code ?? a.id!).compareTo(b.code ?? b.id!));
    if (makes.isEmpty) {
      throw StateError('No fleet records available to export.');
    }
    final bookings = await store.bookings();
    final data = <FleetMonth>[];
    for (
      var month = DateTime.utc(period.start.year, period.start.month);
      !month.isAfter(period.end);
      month = DateTime.utc(month.year, month.month + 1)
    ) {
      final dates = overlap(period, KpiPeriod.month(month.year, month.month))!;
      for (final make in makes) {
        // Sequential on-demand reads: no background listeners or fleet-wide
        // fan-out on modal open. Store supplies account-scoped cached data offline.
        final stored = await store.load(make.id!, dates);
        data.add(FleetMonth(make, month, dates, stored, bookings, makes));
      }
    }
    return KpiTemplateWorkbook.export(data, period);
  }

  static Map<String, List<List<Object?>>> build(
    List<FleetMonth> data,
    KpiPeriod period,
  ) {
    final sheets = <String, List<List<Object?>>>{};
    final monthKeys = data.map((d) => d.month).toSet().toList()..sort();
    final makeIds = data.map((d) => d.make.id).toSet();
    final issues = <List<Object?>>[
      ['UNIT', 'PERIOD', 'DATA STATUS', 'ISSUE'],
    ];
    final summary = <List<Object?>>[
      ['PALAWAN TRANSPORT CORP'],
      ['MONTHLY KPI'],
      ['SELECTED PERIOD', kpiDayKey(period.start), kpiDayKey(period.end)],
      ['REVENUE TARGET / PM / MONTH', 350000],
      [],
      [
        'UNIT',
        'ITEM',
        for (final month in monthKeys) ...[
          '${months[month.month - 1]} ${month.year}',
          '%',
        ],
      ],
    ];
    for (final id in makeIds) {
      final reports = [
        for (final month in monthKeys)
          data.firstWhere((d) => d.make.id == id && d.month == month),
      ];
      for (var i = 0; i < 9; i++) {
        summary.add([
          i == 0 ? reports.first.label : '',
          labels(reports.first.report.ratingRules.targetLabel)[i],
          for (final d in reports) ...[
            values(d.report)[i],
            d.report.revenue == 0
                ? null
                : ExcelReportCell(
                    values(d.report)[i] / d.report.revenue,
                    style: 3,
                  ),
          ],
        ]);
      }
      summary.add([]);
    }
    for (final month in monthKeys) {
      final entries = data.where((d) => d.month == month).toList();
      final key = '${months[month.month - 1]} ${month.year}';
      final ledger = <List<Object?>>[
        ['PALAWAN TRANSPORT CORP'],
        [key],
        [
          'SELECTED PERIOD',
          kpiDayKey(entries.first.period.start),
          kpiDayKey(entries.first.period.end),
        ],
        [],
      ];
      final weekly = <List<Object?>>[
        ['', 'PALAWAN TRANSPORT CORP'],
        ['', 'KPI'],
        ['', 'MONTH OF $key'],
        ['', 'REVENUE TARGET / PM / MONTH', 350000],
        [
          '',
          'SELECTED PERIOD',
          kpiDayKey(entries.first.period.start),
          kpiDayKey(entries.first.period.end),
        ],
        [],
        [
          '',
          'UNIT',
          'ITEM',
          key,
          '%',
          'Week 1',
          '',
          'Week 2',
          '',
          'Week 3',
          'Week 4',
        ],
      ];
      for (final d in entries) {
        final weeks = [
          for (var w = 1; w <= 4; w++)
            overlap(d.period, KpiPeriod.week(month.year, month.month, w)),
        ];
        final reports = [
          for (final w in weeks) w == null ? null : d.calculate(w),
        ];
        for (var i = 0; i < 9; i++) {
          final r = weekly.length + 1;
          final nums = [
            for (final report in reports)
              report == null ? null : values(report)[i],
          ];
          weekly.add([
            '',
            i == 0 ? d.label : '',
            labels(d.report.ratingRules.targetLabel)[i],
            ExcelReportCell(
              values(d.report)[i],
              formula: 'SUM(F$r,H$r,J$r:K$r)',
              style: 2,
            ),
            d.report.revenue == 0
                ? null
                : ExcelReportCell(
                    values(d.report)[i] / d.report.revenue,
                    style: 3,
                  ),
            nums[0],
            '',
            nums[1],
            '',
            nums[2],
            nums[3],
          ]);
        }
        weekly.add([]);
        ledger.add([
          '',
          'FUEL',
          '',
          '',
          '',
          '',
          '',
          'Salary',
          '',
          'Maintenance',
          '',
          '',
        ]);
        ledger.add([
          d.label,
          'PO No. / Ref',
          'DATE',
          'Amount',
          'Liter',
          'PRICE/LITER',
          'Notes / Route',
          'Date',
          'Amount',
          'Ref',
          'Description',
          'Amount',
        ]);
        final fuel = d.stored.fuel.where((f) {
          final date = DateTime.tryParse('${f['day']}T00:00:00Z');
          return f['voided'] != true && date != null && d.period.contains(date);
        }).toList()..sort((a, b) => '${a['day']}'.compareTo('${b['day']}'));
        final count = fuel.length > 4 ? fuel.length : 4;
        final start = ledger.length + 1;
        for (var i = 0; i < count; i++) {
          final f = i < fuel.length ? fuel[i] : <String, dynamic>{};
          final w = i < 4 ? weeks[i] : null;
          final report = i < 4 ? reports[i] : null;
          ledger.add([
            w == null ? '' : 'Week ${i + 1}',
            f['reference'],
            f['day'],
            kpiMoney(f['amount']),
            kpiMoney(f['liters']),
            kpiMoney(f['price_per_liter']),
            f['notes'],
            w == null ? '' : '${kpiDayKey(w.start)} – ${kpiDayKey(w.end)}',
            report == null ? null : report.driverSalary + report.helperSalary,
            '',
            report == null ? '' : 'Fixed allocation',
            report?.maintenance,
          ]);
        }
        final end = ledger.length;
        ledger.add([
          'Total',
          '',
          '',
          ExcelReportCell(
            fuel.fold<double>(0, (s, f) => s + (kpiMoney(f['amount']) ?? 0)),
            formula: 'SUM(D$start:D$end)',
            style: 2,
          ),
          ExcelReportCell(
            fuel.fold<double>(0, (s, f) => s + (kpiMoney(f['liters']) ?? 0)),
            formula: 'SUM(E$start:E$end)',
            style: 2,
          ),
          '',
          '',
          '',
          ExcelReportCell(
            d.report.driverSalary + d.report.helperSalary,
            formula: 'SUM(I$start:I$end)',
            style: 2,
          ),
          '',
          '',
          ExcelReportCell(
            d.report.maintenance,
            formula: 'SUM(L$start:L$end)',
            style: 2,
          ),
        ]);
        ledger.add([]);
        issues.add([
          d.label,
          key,
          d.stored.fromCache ? 'Cached data' : 'Loaded data',
          d.report.complete ? 'Complete' : 'Incomplete',
        ]);
        for (final issue in d.report.issues) {
          issues.add([d.label, key, '', issue]);
        }
      }
      sheets[key] = ledger;
      sheets['Weekly-$key'] = weekly;
    }
    // Match the reference's ledger → Monthly → Weekly sheet grouping.
    return {
      for (final e in sheets.entries.where((e) => !e.key.startsWith('Weekly-')))
        e.key: e.value,
      'Monthly': summary,
      for (final e in sheets.entries.where((e) => e.key.startsWith('Weekly-')))
        e.key: e.value,
      'Data Checks': issues,
    };
  }

  static List<String> labels(String target) => [
    'REVENUE',
    'FUEL',
    'SALARY',
    'TRUCK DEPRECIATION',
    'MAINTENANCE',
    'TOTAL EXPENSES',
    'TOTAL GROSS INCOME (Actual)',
    'TARGET GROSS INCOME (TARGET- $target%)',
    'FAVORABLE (UNFAVORABLE)',
  ];
  static List<double> values(PmKpi r) => [
    r.revenue,
    r.fuel,
    r.driverSalary + r.helperSalary,
    r.depreciation,
    r.maintenance,
    r.expenses,
    r.gross,
    r.marginTarget,
    r.marginVariance,
  ];
}

class FleetMonth {
  FleetMonth(
    this.make,
    this.month,
    this.period,
    this.stored,
    this.bookings,
    this.makes,
  );
  final VehicleMake make;
  final DateTime month;
  final KpiPeriod period;
  final KpiStoredData stored;
  final List<Booking> bookings;
  final List<VehicleMake> makes;
  String get label => make.code ?? make.id!;
  late final PmKpi report = calculate(period);
  final _reports = <(DateTime, DateTime), PmKpi>{};
  PmKpi calculate(KpiPeriod dates) => _reports.putIfAbsent(
    (dates.start, dates.end),
    () => PmKpi.calculate(
      makeId: make.id!,
      period: dates,
      bookings: bookings,
      makes: makes,
      records: stored.records,
      fuelEntries: stored.fuel,
      resolveSalary: stored.catalog.resolveSalary,
      ratingRules: KpiRatingRules.fromMap(stored.settings),
    ),
  );
}
