import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/kpi/kpi_salary_diagnostics.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';

Booking trip(String destination, {String barangay = '', DateTime? delivered}) =>
    Booking(
      id: '42',
      vehicleMake: const VehicleMake(id: '4'),
      clientStatus: 'delivered',
      driver: const UserModel(id: '8'),
      helper: const UserModel(id: '9'),
      createdAt: DateTime.utc(2026, 9, 1),
      deliveredAt: delivered ?? DateTime.utc(2026, 9, 1, 4),
      statusOutputs: {
        'pending': {
          'fields': {
            'destination': destination,
            'destination_barangay': barangay,
            'amount': '1000',
          },
        },
      },
    );

void main() {
  test(
    'later booking location edit replaces pending location for KPI matching',
    () {
      final booking = trip('Puerto Princesa City', barangay: 'Princesa');
      final outputs = {
        ...booking.statusOutputs!,
        'delivered__1790022027033000': {
          'status_key': 'delivered',
          'submitted_at': '2026-09-22T04:20:27.033',
          'fields': {'destination_barangay': 'Bagong Pag-asa'},
        },
      };
      final edited = booking.copyWith(statusOutputs: outputs);
      final item = KpiTrip(edited, kpiDate(edited.deliveredAt!));
      expect(item.destinationBarangay, 'Bagong Pag-asa');
      expect(item.destination, 'Puerto Princesa City');
      expect(
        matchKpiTripRate(
          item,
          const OperationsCatalog({}).matrixFor(item.day).rates,
        ).rate?.name,
        'Bagong Pag-asa',
      );
      expect(KpiTrip(booking, item.day).destinationBarangay, 'Princesa');
      expect(edited.deliveredAt, booking.deliveredAt);
    },
  );
  test(
    'confirmed Bagong Pag-asa matches City Proper without manual selection',
    () {
      const catalog = OperationsCatalog({});
      final booking = trip('Puerto Princesa City', barangay: 'Bagong Pag-asa');
      final day = kpiDate(booking.deliveredAt!);
      final rate = matchKpiTripRate(
        KpiTrip(booking, day),
        catalog.matrixFor(day).rates,
      ).rate!;
      expect(rate.name, 'Bagong Pag-asa');
      expect(rate.driver, 100);
      expect(rate.helper, 50);
      expect(rate.usesCityPremium, true);
      final issues = <String>{};
      final resolved = catalog.resolveSalary(
        KpiDay(day, [KpiTrip(booking, day)], {}),
        issues,
      );
      expect(resolved.driverSalary, 555);
      expect(resolved.helperSalary, 505);
      expect(issues, isEmpty);
    },
  );
  test(
    'saved manual rate resolves pending trip without confirming the day',
    () {
      const catalog = OperationsCatalog({});
      final booking = trip('Unknown place');
      final date = kpiDate(booking.deliveredAt!);
      final item = KpiTrip(booking, date);
      final record = <String, dynamic>{
        'salary_confirmed': false,
        'trip_rates': [
          {
            'signature': item.signature,
            'route': 'City Proper',
            'driver': 9999,
            'helper': 9999,
          },
        ],
      };
      final issues = <String>{};
      final resolved = catalog.resolveSalary(
        KpiDay(date, [item], record),
        issues,
      );
      expect(resolved.salaryComplete, isFalse);
      expect(resolved.salaryCalculated, isTrue);
      expect(resolved.driverSalary, 555);
      expect(resolved.helperSalary, 505);
      expect(resolved.estimate!.rates.single['route'], 'City Proper');
      expect(issues, isEmpty);
      final changed = KpiTrip(
        booking.copyWith(driver: const UserModel(id: '77')),
        date,
      );
      final changedIssues = <String>{};
      final stale = catalog.resolveSalary(
        KpiDay(date, [changed], record),
        changedIssues,
      );
      expect(stale.driverSalary, 455);
      expect(stale.estimate!.rates, isEmpty);
      expect(
        changedIssues.single,
        contains('No active trip rate for drop-off'),
      );
    },
  );

  test('unmatched trip keeps earned daily pay and other matched trip pay', () {
    const catalog = OperationsCatalog({});
    final date = DateTime.utc(2026, 9, 1);
    final known = trip('Narra');
    final unknown = Booking(
      id: '43',
      vehicleMake: const VehicleMake(id: '4'),
      driver: const UserModel(id: '8'),
      helper: const UserModel(id: '9'),
      deliveredAt: DateTime.utc(2026, 9, 1, 5),
    );
    final result = PmKpi.calculate(
      makeId: '4',
      period: KpiPeriod(date, date),
      bookings: [known, unknown],
      records: [],
      resolveSalary: catalog.resolveSalary,
    );
    expect(result.driverSalary, 955);
    expect(result.helperSalary, 705);
    expect(result.days.single.salaryCalculated, isFalse);
    expect(result.issues.any((issue) => issue.contains('Booking 43')), isTrue);
    final report = kpiSalaryDiagnostics(
      makeId: '4',
      bookings: [known, unknown],
      catalog: catalog,
      result: result,
      verified: false,
    );
    expect(report, contains('No active trip rate for drop-off'));
    expect(report, contains('"driver_salary": 955.0'));
  });
  test(
    'calculated salary needs no manual confirmation when fuel is complete',
    () {
      const catalog = OperationsCatalog({});
      final date = DateTime.utc(2026, 9, 1);
      final result = PmKpi.calculate(
        makeId: '4',
        period: KpiPeriod(date, date),
        bookings: [trip('Narra')],
        records: [
          {
            'make_id': '4',
            'day': '2026-09-01',
            'fuel_confirmed': true,
            'fuel': 0,
          },
        ],
        resolveSalary: catalog.resolveSalary,
      );
      expect(result.days.single.salaryCalculated, isTrue);
      expect(result.days.single.salaryComplete, isFalse);
      expect(result.complete, isTrue);
    },
  );

  test(
    'known legacy spellings and suffixes match without changing stored fields',
    () {
      for (final pair in [
        ('STA LOURDES', 'Sta. Lourdes'),
        ('Santa Lourdes | OT', 'Sta. Lourdes'),
        ('Brgy. Santa Monica', 'Sta. Monica'),
        ('ELNIDO', 'El Nido'),
        ('BROOKES POINT', "Brooke's Point"),
        ('RIOTUBA', 'Rio Tuba'),
        ('Sofronio Española', 'Española'),
      ]) {
        final b = trip(pair.$1);
        final result = matchKpiTripRate(
          KpiTrip(b, DateTime.utc(2026, 9, 1)),
          KpiRate.matrix,
        );
        expect(result.rate?.name, pair.$2);
        expect(bookingRecordValue(b), pair.$1);
      }
    },
  );
  test(
    'Puerto Princesa uses the barangay; city alone and ambiguous names remain unresolved',
    () {
      final date = DateTime.utc(2026, 9, 1);
      expect(
        matchKpiTripRate(
          KpiTrip(
            trip('Puerto Princesa City', barangay: 'SAN MANUEL | OT'),
            date,
          ),
          KpiRate.matrix,
        ).rate?.name,
        'San Manuel',
      );
      expect(
        matchKpiTripRate(
          KpiTrip(trip('Puerto Princesa City'), date),
          KpiRate.matrix,
        ).rate,
        isNull,
      );
      expect(
        matchKpiTripRate(
          KpiTrip(trip('Roxas', barangay: 'San Manuel'), date),
          KpiRate.matrix,
        ).issue,
        contains('Multiple active trip rates'),
      );
      expect(
        matchKpiTripRate(KpiTrip(trip('Narra'), date), const [
          KpiRate('Narra', 100, 50),
          KpiRate('Other', 200, 100, aliases: ['Narra']),
        ]).rate,
        isNull,
      );
    },
  );
  test(
    'matched delivered trips appear as estimates while confirmed snapshots remain authoritative',
    () {
      const catalog = OperationsCatalog({});
      final b = trip('Puerto Princesa City', barangay: 'STA LOURDES');
      final period = KpiPeriod(
        DateTime.utc(2026, 9, 1),
        DateTime.utc(2026, 9, 1),
      );
      PmKpi calculate(List<Map<String, dynamic>> records) => PmKpi.calculate(
        makeId: '4',
        period: period,
        bookings: [b],
        records: records,
        resolveSalary: catalog.resolveSalary,
      );
      final estimate = calculate([]);
      expect(estimate.driverSalary, 555);
      expect(estimate.helperSalary, 505);
      expect(estimate.days.single.salaryEstimated, isTrue);
      expect(estimate.complete, isFalse);
      final confirmed = calculate([
        {
          'make_id': '4',
          'day': '2026-09-01',
          'salary_confirmed': true,
          'trip_signature': estimate.days.single.signature,
          'driver_salary': 999,
          'helper_salary': 888,
        },
      ]);
      expect(confirmed.driverSalary, 999);
      expect(confirmed.helperSalary, 888);
      expect(confirmed.days.single.salaryEstimated, isFalse);
    },
  );
  test(
    'estimates use the matrix effective on delivery date and report unmatched routes',
    () {
      final catalog = OperationsCatalog({
        'matrix_versions': [
          TripMatrixVersion(
            id: 'future',
            effectiveFrom: DateTime.utc(2026, 10),
            rates: const [KpiRate('Narra', 900, 450)],
          ).toMap(),
        ],
      });
      KpiDay day(Booking b) => KpiDay(kpiDate(b.deliveredAt!), [
        KpiTrip(b, kpiDate(b.deliveredAt!)),
      ], {});
      expect(catalog.resolveSalary(day(trip('Narra')), {}).driverSalary, 955);
      expect(
        catalog
            .resolveSalary(
              day(trip('Narra', delivered: DateTime.utc(2026, 10, 1, 4))),
              {},
            )
            .driverSalary,
        1355,
      );
      final issues = <String>{};
      final unknown = catalog.resolveSalary(day(trip('Unknown place')), issues);
      expect(unknown.salaryCalculated, isFalse);
      expect(unknown.driverSalary, 455);
      expect(unknown.helperSalary, 455);
      expect(
        issues.single,
        contains('Booking 42: No active trip rate for drop-off'),
      );
    },
  );
}

String bookingRecordValue(Booking booking) =>
    booking.statusOutputs!['pending']['fields']['destination'] as String;
