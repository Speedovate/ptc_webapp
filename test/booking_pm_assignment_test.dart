import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/booking_pm_assignment.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';

void main() {
  test(
    'confirmed historical trucks preserve original helpers and explicit PMs',
    () {
      const makes = [
        VehicleMake(id: '2', code: 'PM5'),
        VehicleMake(id: '3', code: 'PM6'),
      ];
      for (final pair in [('17', '14', '2'), ('12', '19', '3')]) {
        final legacy = Booking(
          driver: UserModel(id: pair.$1),
          helper: UserModel(id: pair.$2),
          createdAt: DateTime.utc(2026, 9, 1),
        );
        expect(resolveBookingPm(legacy, makes)?.id, pair.$3);
        expect(legacy.helper?.id, pair.$2);
        expect(legacy.vehicleMake, isNull);
        expect(
          resolveBookingPm(
            legacy.copyWith(vehicleMake: const VehicleMake(id: 'other')),
            makes,
          )?.id,
          'other',
        );
        expect(
          resolveBookingPm(
            legacy.copyWith(createdAt: DateTime.utc(2026, 9, 23)),
            makes,
          ),
          isNull,
        );
      }
    },
  );
  const driver = UserModel(id: '13');
  const helper = UserModel(id: '18');
  const make = VehicleMake(
    id: '4',
    code: 'PM7',
    driver: driver,
    helper: helper,
  );
  final booking = Booking(
    id: '104',
    driver: driver,
    helper: helper,
    createdAt: DateTime.utc(2026, 9, 18),
    deliveredAt: DateTime.utc(2026, 9, 19, 10, 37),
    clientStatus: 'check',
    statusOutputs: {
      'pending': {
        'fields': {
          'destination': 'Puerto Princesa City',
          'destination_barangay': 'Sicsican',
          'amount': '1000',
        },
      },
    },
  );
  test(
    'legacy fixed pair contributes to correct PM without changing booking',
    () {
      final result = PmKpi.calculate(
        makeId: '4',
        period: KpiPeriod.month(2026, 9),
        bookings: [booking],
        records: [],
        makes: [make],
        resolveSalary: const OperationsCatalog({}).resolveSalary,
      );
      expect(result.bookingCount, 1);
      expect(result.revenue, 1000);
      expect(result.driverSalary, 555);
      expect(result.helperSalary, 505);
      expect(booking.vehicleMake, isNull);
      expect(result.issues, isEmpty);
    },
  );
  test(
    'assignment issues distinguish missing crew, no match and duplicates',
    () {
      expect(
        bookingPmAssignmentIssue(const Booking(), [make]),
        'No PM assigned; driver and helper missing',
      );
      expect(bookingPmAssignmentIssue(booking, [make]), isNull);
      expect(
        bookingPmAssignmentIssue(booking, [
          make.copyWith(helper: const UserModel(id: '99')),
        ]),
        contains('Current assignments: PM7 (ID 4): Driver 13, Helper 99'),
      );
      expect(
        bookingPmAssignmentIssue(booking, [
          make,
          make.copyWith(id: '5', code: 'PM8'),
        ]),
        contains('multiple PMs: PM7 (ID 4), PM8 (ID 5)'),
      );
    },
  );
  test('explicit PM wins; ambiguous and incomplete pairs never assign', () {
    expect(
      resolveBookingPm(
        booking.copyWith(vehicleMake: const VehicleMake(id: '99')),
        [make],
      )?.id,
      '99',
    );
    expect(resolveBookingPm(booking, [make, make.copyWith(id: '5')]), isNull);
    expect(resolveBookingPm(booking.copyWith(helper: null), [make]), isNull);
    expect(resolveBookingPm(booking, []), isNull);
  });
  test('missing PM is visible instead of silently presenting zero', () {
    final result = PmKpi.calculate(
      makeId: '4',
      period: KpiPeriod.month(2026, 9),
      bookings: [booking],
      records: [],
    );
    expect(
      result.issues.single,
      contains('Booking 104: No PM assigned; no PM records loaded'),
    );
    expect(result.complete, isFalse);
  });
}
