import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_commission.dart';
import 'package:webapp/services/kpi/investor_statement_workbook.dart';
import 'package:webapp/services/kpi/kpi_report_export.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

/// The statement is a file the office generates and sends, so the only thing
/// that has to be true is that it opens, reads correctly, and never claims a
/// figure it did not deduct.
void main() {
  const investorId = '8';

  final makes = [
    const VehicleMake(
      id: '4',
      code: 'PM1',
      investorId: investorId,
      isActive: true,
    ),
    const VehicleMake(id: '9', code: 'PM9', investorId: '77', isActive: true),
  ];
  const crew = [
    UserModel(id: '13', role: 'driver', name: 'Ben'),
    UserModel(id: '18', role: 'helper', name: 'Ana'),
  ];

  Booking trip(String id, String makeId, String amount) => Booking(
    id: id,
    clientStatus: 'delivered',
    driver: const UserModel(id: '13', role: 'driver'),
    helper: const UserModel(id: '18', role: 'helper'),
    vehicleMake: VehicleMake(id: makeId, code: makeId),
    deliveredAt: DateTime.utc(2026, 9, 15),
    statusOutputs: {
      'delivered__1': {
        'status_key': 'delivered',
        'fields': {'amount': amount, 'destination': 'Bancao-Bancao'},
      },
    },
  );

  InvestorCommission statement({
    List<InvestorExpense> expenses = const [],
    double rate = 0.10,
  }) {
    final trips = [
      KpiTrip(trip('101', '4', '3000'), DateTime.utc(2026, 9, 15)),
      KpiTrip(trip('102', '4', '2500'), DateTime.utc(2026, 9, 16)),
    ];
    return InvestorCommission.calculate(
      investorId: investorId,
      periodKey: '2026-09',
      rate: rate,
      trips: trips,
      routes: {for (final t in trips) t.identity: 'City Proper'},
      makes: makes,
      expenses: expenses,
    );
  }

  Map<String, List<List<Object?>>> build(InvestorCommission s) =>
      InvestorStatementWorkbook.build(
        statement: s,
        periodKey: '2026-09',
        investorName: 'Investor Eight',
        makes: makes,
        crew: crew,
        generatedBy: '1',
      );

  test('the summary carries every line of the statement', () {
    final sheets = build(statement());
    final rows = sheets['Statement 2026-09']!;
    final lines = rows
        .whereType<List<Object?>>()
        .map((row) => row.whereType<String>().join(' | '))
        .where((line) => line.isNotEmpty)
        .toList();

    expect(lines, contains('PALAWAN TRANSPORT CORP'));
    expect(lines, contains('INVESTOR STATEMENT'));
    // The name sits in its own column, so check the whole row.
    expect(lines.any((line) => line.contains('Investor Eight')), isTrue);
    expect(lines, contains('Gross billings'));
    expect(lines, contains('Net due'));
    // Its own truck only, so the fleet count must exclude the other investor.
    expect(rows.where((r) => r.isNotEmpty && r.first == 'TRUCKS').single[1], 1);
    expect(
      rows.where((r) => r.isNotEmpty && r.first == 'TRIPS COMPLETED').single[1],
      2,
    );
  });

  test('only this investor own trips appear in the detail sheet', () {
    final sheets = build(statement());
    final rows = sheets['Trips 2026-09']!;
    expect(rows.first, [
      'BOOKING',
      'DELIVERED',
      'ROUTE',
      'TRUCK',
      'DRIVER',
      'HELPER',
      'AMOUNT',
      'COMMISSION',
    ]);
    expect(rows, hasLength(3), reason: 'header plus two trips');

    final codes = rows.skip(1).map((row) => row[3]).toSet();
    expect(codes, {'PM1'}, reason: 'the other investor truck must not appear');
    expect(rows.skip(1).map((row) => row[6]).toList(), [3000.0, 2500.0]);
    // 10% of each delivery, matching the statement.
    expect(rows.skip(1).map((row) => row[7]).toList(), [300.0, 250.0]);
  });

  test('a pending cost is listed but not deducted', () {
    final s = statement(
      expenses: const [
        InvestorExpense(
          amount: 9000,
          category: 'repair',
          approved: false,
          reference: 'PO-77',
        ),
      ],
    );
    final rows = build(s)['Statement 2026-09']!;
    final text = rows.map((row) => row.join(' ')).join('\n');

    expect(text, contains('PENDING YOUR APPROVAL'));
    expect(text, contains('repair - PO-77'));
    // The net must not have moved.
    final net =
        rows.firstWhere((r) => r.isNotEmpty && r.first == 'Net due')[1]
            as double;
    expect(net, s.netDue);
    // 5,500 gross, less the 10% fee, less one day's crew, less two city shares.
    expect(net, closeTo(5500 - 550 - 910 - 300, 0.005));
    expect(net, 3740);
  });

  test('an approved cost is deducted and appears in the statement lines', () {
    final s = statement(
      expenses: const [
        InvestorExpense(
          amount: 1200,
          category: 'fuel',
          approved: true,
          reference: 'PO-2026-01',
          description: 'Diesel',
        ),
      ],
    );
    final text = build(
      s,
    )['Statement 2026-09']!.map((row) => row.join(' ')).join('\n');
    expect(text, contains('Approved expenses'));
    expect(text, isNot(contains('PENDING YOUR APPROVAL')));
    expect(s.netDue, closeTo(5500 - 550 - 910 - 300 - 1200, 0.005));
    expect(s.netDue, 2540);
  });

  test('a period with trips but no recorded costs is marked NOT FINAL', () {
    // The biggest cost line is simply missing, so the figure is too high. The
    // statement says so on its face rather than letting a wrong number go out.
    final sheets = InvestorStatementWorkbook.build(
      statement: statement(),
      periodKey: '2026-09',
      investorName: 'Investor Eight',
      makes: makes,
      crew: crew,
      costsRecorded: 0,
    );
    final text = sheets['Statement 2026-09']!
        .map((row) => row.join(' '))
        .join('\n');
    expect(text, contains('DRAFT - NOT FINAL'));
    expect(text, contains('COSTS RECORDED'));
    expect(text, contains('Do not send it as a final statement'));
  });

  test('once costs are recorded the draft warning is gone', () {
    final sheets = InvestorStatementWorkbook.build(
      statement: statement(),
      periodKey: '2026-09',
      makes: makes,
      crew: crew,
      costsRecorded: 8,
    );
    final text = sheets['Statement 2026-09']!
        .map((row) => row.join(' '))
        .join('\n');
    expect(text, isNot(contains('DRAFT - NOT FINAL')));
    expect(text, contains('COSTS RECORDED'));
  });

  test('the file name is stable and sortable across months', () {
    expect(
      InvestorStatementWorkbook.fileName(investorId: '8', periodKey: '2026-09'),
      'Investor-Statement-8-2026-09',
    );
    expect(
      InvestorStatementWorkbook.fileName(investorId: '', periodKey: '2026-09'),
      startsWith('Investor-Statement-investor-'),
    );
  });

  test('the export produces a real xlsx with both sheets', () {
    final bytes = KpiReportExport.excel(build(statement()), styled: true);
    expect(bytes, isNotEmpty);

    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toList();
    expect(names, contains('xl/workbook.xml'));
    expect(names, contains('xl/worksheets/sheet1.xml'));
    expect(names, contains('xl/worksheets/sheet2.xml'));

    final workbook = utf8.decode(
      archive.findFile('xl/workbook.xml')!.content as List<int>,
    );
    expect(workbook, contains('Statement 2026-09'));
    expect(workbook, contains('Trips 2026-09'));
  });

  test('the pdf export renders the same figures', () {
    final pdf = KpiReportExport.pdf(build(statement()));
    final text = utf8.decode(pdf, allowMalformed: true);
    expect(text, contains('PALTRANCO - Statement 2026-09'));
    expect(text, contains('Net due'));
    // The rate label travels with the number, so a statement is never ambiguous.
    // PDF escapes parentheses, so match the label without them.
    expect(text, contains('Paltranco share'));
  });
}
