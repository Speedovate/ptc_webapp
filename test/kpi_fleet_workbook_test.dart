import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/kpi_fleet_workbook.dart';
import 'package:webapp/services/kpi/kpi_report_export.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';

const fleet = [
  VehicleMake(id: '1', code: 'PM4'),
  VehicleMake(id: '2', code: 'PM5', isActive: false),
];
final fleetBookings = <Booking>[
  for (var i = 0; i < 20; i++)
    Booking(
      id: '$i',
      vehicleMake: fleet[i % 2],
      clientStatus: 'delivered',
      statusOutputs: {
        'pending': {
          'fields': {'amount': '1000'},
        },
      },
      createdAt: DateTime.utc(2026, 9, 9),
      deliveredAt: DateTime.utc(2026, 9, 9),
    ),
];
KpiStoredData data(String id) => KpiStoredData(
  [],
  {},
  true,
  fuel: [
    {
      'id': 'f-$id',
      'make_id': id,
      'day': '2026-09-09',
      'liters': 10,
      'price_per_liter': 60,
      'amount': 600,
      'reference': '=SAFE & <ref>',
    },
    {
      'id': 'void-$id',
      'make_id': id,
      'day': '2026-09-09',
      'amount': 500,
      'voided': true,
    },
    {'id': 'outside-$id', 'make_id': id, 'day': '2026-08-31', 'amount': 999},
  ],
);

class FleetStore extends PmKpiStore {
  final loads = <String>[];
  bool fuelAccess = true;
  @override
  bool get canRead => true;
  @override
  bool get canReadBookings => true;
  @override
  bool get canReadFuel => fuelAccess;
  @override
  bool get canReadIncome => true;
  @override
  Future<List<VehicleMake>> exportMakes() async => fleet;
  @override
  Future<List<Booking>> bookings() async => bookingsForTest;
  final bookingsForTest = fleetBookings;
  @override
  Future<KpiStoredData> load(String makeId, KpiPeriod period) async {
    loads.add(makeId);
    return data(makeId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'fleet workbook uses all PMs and full data, proper ledger columns and weekly totals',
    () async {
      final store = FleetStore();
      final bytes = await KpiFleetWorkbook.export(
        store: store,
        period: KpiPeriod.month(2026, 9),
      );
      expect(store.loads, ['1', '2']);
      final zip = ZipDecoder().decodeBytes(bytes);
      XmlDocument doc(String p) =>
          XmlDocument.parse(utf8.decode(zip.findFile(p)!.content));
      expect(
        doc(
          'xl/workbook.xml',
        ).findAllElements('sheet').map((s) => s.getAttribute('name')),
        ['SEPT', 'Monthly', 'Weekly-Sept'],
      );
      for (final f in zip.files.where((f) => f.name.endsWith('.xml'))) {
        XmlDocument.parse(utf8.decode(f.content));
      }
      final ledger = doc('xl/worksheets/sheet1.xml');
      final texts = ledger
          .findAllElements('t')
          .map((e) => e.innerText)
          .toList();
      expect(
        texts,
        containsAll([
          'PM4',
          'PM5',
          'Liter',
          'PRICE/LITER',
          'Salary',
          'Maintenance',
          '=SAFE & <ref>',
        ]),
      );
      expect(texts, isNot(contains('2026-08-31')));
      expect(
        ledger
            .findAllElements('v')
            .where((v) => v.innerText == '500' || v.innerText == '999'),
        isEmpty,
      );
      final weekly = doc('xl/worksheets/sheet3.xml');
      final revenues = weekly
          .findAllElements('row')
          .where(
            (r) => r.findAllElements('t').any((t) => t.innerText == 'REVENUE'),
          );
      expect(revenues.length, 4);
      for (final row in revenues.take(2)) {
        final total = row
            .findElements('c')
            .firstWhere((c) => c.getAttribute('r')!.startsWith('D'));
        expect(total.findElements('v').single.innerText, '10000.0');
        expect(total.findElements('f').single.innerText, startsWith('SUM('));
      }
      expect(zip.findFile('xl/styles.xml'), isNotNull);
      expect(zip.files.any((f) => f.name.contains('externalLink')), isFalse);
      File('/private/tmp/paltranco-fleet-test.xlsx').writeAsBytesSync(bytes);
    },
  );
  test('custom range crosses months without including unselected weeks', () {
    final period = KpiPeriod(
      DateTime.utc(2026, 9, 22),
      DateTime.utc(2026, 10, 7),
    );
    final entries = [
      for (final m in [9, 10])
        for (final make in fleet)
          FleetMonth(
            make,
            DateTime.utc(2026, m),
            KpiFleetWorkbook.overlap(period, KpiPeriod.month(2026, m))!,
            data(make.id!),
            fleetBookings,
            fleet,
          ),
    ];
    final sheets = KpiFleetWorkbook.build(entries, period);
    expect(
      sheets.keys,
      containsAll([
        'Sept 2026',
        'Oct 2026',
        'Monthly',
        'Weekly-Sept 2026',
        'Weekly-Oct 2026',
      ]),
    );
    final rows = sheets['Weekly-Sept 2026']!.where(
      (r) => r.length > 2 && r[2] == 'TRUCK DEPRECIATION',
    );
    for (final row in rows) {
      expect(row[5], isNull);
      expect(row[7], isNull);
      expect(row[9], isNull);
      expect(row[10], closeTo(12500, 0.001));
      expect((row[3] as ExcelReportCell).value, closeTo(12500, 0.001));
    }
  });
  test(
    'fleet export respects fuel read access before loading records',
    () async {
      final store = FleetStore()..fuelAccess = false;
      await expectLater(
        KpiFleetWorkbook.export(store: store, period: KpiPeriod.month(2026, 9)),
        throwsStateError,
      );
      expect(store.loads, isEmpty);
    },
  );
}
