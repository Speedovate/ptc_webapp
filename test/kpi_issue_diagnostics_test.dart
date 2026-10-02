import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/services/kpi/kpi_salary_diagnostics.dart';
import 'package:webapp/services/booking_pm_assignment.dart';

void main() {
  test(
    'large fleet diagnostic retains affected bookings instead of unrelated rows',
    () {
      const makes = [
        VehicleMake(
          id: '1',
          code: 'PM4',
          driver: UserModel(id: '16'),
          helper: UserModel(id: '15'),
        ),
        VehicleMake(
          id: '2',
          code: 'PM5',
          driver: UserModel(id: '17'),
          helper: UserModel(id: '19'),
        ),
      ];
      final affected = ['124', '114', '112', '109']
          .map(
            (id) => Booking(
              id: id,
              driver: const UserModel(id: '16'),
              helper: const UserModel(id: '19'),
              clientStatus: 'delivered',
              createdAt: DateTime.utc(2026, 10, 1),
              deliveredAt: DateTime.utc(2026, 10, 2),
            ),
          )
          .toList();
      final bookings = [
        for (var i = 200; i < 390; i++)
          Booking(id: '$i', clientStatus: 'pending'),
        ...affected,
      ];
      final result = PmKpi.calculate(
        makeId: '3',
        period: KpiPeriod.month(2026, 10),
        bookings: bookings,
        records: [],
        makes: makes,
      );
      final json = kpiSalaryDiagnostics(
        makeId: '3',
        bookings: bookings,
        catalog: const OperationsCatalog({}),
        result: result,
        verified: true,
        makes: makes,
        issuesOnly: true,
      );
      final report = jsonDecode(json);
      expect(report['loaded_bookings'], 194);
      expect(report['reported_bookings'], 4);
      expect((report['bookings'] as List).map((b) => b['booking_id']), [
        '124',
        '114',
        '112',
        '109',
      ]);
      expect(report['current_pm_assignments'], hasLength(2));
      expect(json.length, lessThan(16000));
      for (final booking in affected) {
        expect(
          resolveBookingPm(booking, makes),
          isNull,
          reason: 'Do not guess the historical truck',
        );
        expect(
          bookingPmAssignmentIssue(booking, makes),
          contains('Select the truck used for this booking'),
        );
      }
    },
  );
}
