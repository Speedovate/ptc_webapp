import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

Booking booking({
  String id = '1',
  String? submission,
  String status = 'delivered',
  DateTime? created,
  DateTime? delivered,
  String make = '4',
  String amount = '70,000',
}) => Booking(
  id: id,
  submissionKey: submission,
  clientStatus: status,
  vehicleMake: VehicleMake(id: make),
  driver: const UserModel(id: '8', role: 'driver'),
  helper: const UserModel(id: '9', role: 'helper'),
  createdAt: created ?? DateTime.utc(2026, 9, 1),
  deliveredAt: delivered,
  statusOutputs: {
    'pending': {
      'fields': {'amount': amount, 'destination': 'City Proper'},
    },
  },
);

void main() {
  test(
    'only delivered onward contributes bookings revenue and transactions',
    () {
      final result = PmKpi.calculate(
        makeId: '4',
        period: KpiPeriod.month(2026, 9),
        records: [],
        bookings: [
          for (final status in [
            'pending',
            'assigned',
            'ongoing',
            'delivered',
            'check',
            'empty',
            'return',
            'confirm',
          ])
            booking(
              id: status,
              status: status,
              amount: '100',
              delivered: DateTime.utc(2026, 9, 2),
            ),
        ],
      );
      expect(result.bookingCount, 5);
      expect(result.revenue, 500);
      expect(
        result.days.expand((day) => day.trips).map((trip) => trip.booking.id),
        unorderedEquals(['delivered', 'check', 'empty', 'return', 'confirm']),
      );
    },
  );
  test(
    'pre-delivery bookings without crew do not produce PM warnings or trips',
    () {
      final result = PmKpi.calculate(
        makeId: '4',
        period: KpiPeriod.month(2026, 9),
        records: [],
        bookings: [
          for (final status in ['pending', 'assigned', 'ongoing'])
            Booking(
              id: status,
              clientStatus: status,
              createdAt: DateTime.utc(2026, 9, 1),
            ),
          Booking(
            id: 'delivered',
            clientStatus: 'delivered',
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        ],
      );
      expect(result.days.expand((day) => day.trips), isEmpty);
      expect(result.issues.where((issue) => issue.contains('No PM assigned')), [
        'Booking delivered: No PM assigned; driver and helper missing [Status: Delivered]',
      ]);
    },
  );
  test(
    'four periods partition every month including leap year without loss',
    () {
      for (final year in [2024, 2026]) {
        for (var month = 1; month <= 12; month++) {
          final full = KpiPeriod.month(year, month);
          final days = [
            for (var w = 1; w <= 4; w++) ...KpiPeriod.week(year, month, w).days,
          ];
          expect(days, full.days.toList());
          expect(full.weeks, closeTo(4, 1e-10));
          expect(days.toSet().length, days.length);
          for (var w = 1; w <= 4; w++) {
            expect(KpiPeriod.week(year, month, w).weeks, closeTo(1, 1e-10));
          }
        }
      }
    },
  );
  test('range allocations add to monthly totals across months', () {
    final first = KpiPeriod(
      DateTime.utc(2026, 9, 22),
      DateTime.utc(2026, 9, 25),
    );
    final rest = KpiPeriod(
      DateTime.utc(2026, 9, 26),
      DateTime.utc(2026, 10, 7),
    );
    expect(first.weeks + rest.weeks, closeTo(2, 1e-10));
  });
  test('Manila date uses original offline action instant, not sync date', () {
    expect(kpiDayKey(kpiDate(DateTime.utc(2026, 8, 31, 16, 30))), '2026-09-01');
    expect(kpiDayKey(kpiDate(DateTime.utc(2026, 9, 1, 15, 59))), '2026-09-01');
  });
  test(
    'Created revenue and Delivered salary can belong to different months',
    () {
      final b = booking(
        created: DateTime.utc(2026, 8, 31, 5),
        delivered: DateTime.utc(2026, 9, 2),
      );
      final august = PmKpi.calculate(
        makeId: '4',
        period: KpiPeriod.month(2026, 8),
        bookings: [b],
        records: [],
      );
      final september = PmKpi.calculate(
        makeId: '4',
        period: KpiPeriod.month(2026, 9),
        bookings: [b],
        records: [],
      );
      expect(august.revenue, 70000);
      expect(august.days.expand((d) => d.trips), isEmpty);
      expect(september.revenue, 0);
      expect(september.days.expand((d) => d.trips), hasLength(1));
    },
  );
  test(
    'cancellation, other PM and duplicate submission do not inflate revenue',
    () {
      final b = booking(submission: 'stable');
      final result = PmKpi.calculate(
        makeId: '4',
        period: KpiPeriod.month(2026, 9),
        bookings: [
          b,
          b.copyWith(id: '107'),
          booking(id: '2', status: 'cancelled'),
          booking(id: '3', make: '5'),
        ],
        records: [],
      );
      expect(result.revenue, 70000);
      expect(result.depreciation, closeTo(50000, .001));
      expect(result.maintenance, closeTo(58000, .001));
      expect(result.revenueTarget, closeTo(350000, .001));
      expect(result.profitTarget, closeTo(140000, .001));
    },
  );
  test(
    'daily salary once per person; City Proper premium starts at fifth trip',
    () {
      final trips = [
        for (var i = 0; i < 6; i++)
          KpiTrip(
            booking(id: '$i', delivered: DateTime.utc(2026, 9, 1, i)),
            DateTime.utc(2026, 9, 1),
          ),
      ];
      final salary = kpiSalary(trips, {
        for (final t in trips) t.identity: 'City Proper',
      });
      expect(salary.driver, 455 + 4 * 100 + 2 * 150);
      expect(salary.helper, 455 + 4 * 50 + 2 * 75);
      expect(salary.rates, hasLength(6));
    },
  );
  test(
    'matrix correction and additive hustling are separate from daily pay',
    () {
      final trip = KpiTrip(
        booking(delivered: DateTime.utc(2026, 9, 1)),
        DateTime.utc(2026, 9, 1),
      );
      final salary = kpiSalary(
        [trip],
        {trip.identity: 'Narra'},
        fulls: 1,
        empties: 1,
      );
      expect(salary.driver, 455 + 500 + 100 + 50);
      expect(salary.helper, 455 + 250 + 50 + 25);
    },
  );
  test(
    'confirmed zero differs from unencoded expense; trip changes invalidate salary',
    () {
      final date = DateTime.utc(2026, 9, 1);
      final blank = KpiDay(date, [], {});
      expect(blank.fuelComplete, isFalse);
      expect(blank.salaryComplete, isFalse);
      final record = {
        'fuel': 0,
        'fuel_confirmed': true,
        'driver_salary': 0,
        'helper_salary': 0,
        'salary_confirmed': true,
        'trip_signature': blank.signature,
      };
      expect(KpiDay(date, [], record).salaryComplete, isTrue);
      expect(KpiDay(date, [], record).fuelComplete, isTrue);
      expect(
        KpiDay(date, [KpiTrip(booking(), date)], record).salaryComplete,
        isFalse,
      );
    },
  );
  test('rating uses current gross margin even with unresolved data checks', () {
    final period = KpiPeriod.week(2026, 9, 1);
    for (final example in [
      (18000.0, 'Satisfactory'),
      (28000.0, 'Satisfactory'),
      (17000.0, 'Failed'),
      (29000.0, 'Excellent'),
    ]) {
      final result = PmKpi(
        period: period,
        days: [],
        revenue: example.$1 + 27000,
        bookingCount: 1,
        issues: {},
        threshold: 10000,
      );
      expect(result.rating, example.$2);
      result.issues.add('Missing expense');
      expect(result.rating, example.$2);
      expect(result.complete, isFalse);
    }
  });
  test(
    'legacy delivery output follows next status, never Updated timestamp',
    () {
      final b = booking().copyWith(
        deliveredAt: null,
        updatedAt: DateTime.utc(2026, 10, 1),
        statusOutputs: {
          'ongoing__1': {
            'status_key': 'ongoing',
            'status_form': {'next_status_key': 'delivered'},
            'submitted_at': '2026-09-01T05:00:00Z',
          },
        },
      );
      expect(kpiDeliveredAt(b), DateTime.utc(2026, 9, 1, 5));
    },
  );
  test('cancelled delivered trip does not silently erase earned pay', () {
    final b = booking(status: 'cancelled', delivered: DateTime.utc(2026, 9, 1));
    final result = PmKpi.calculate(
      makeId: '4',
      period: KpiPeriod.month(2026, 9),
      bookings: [b],
      records: [],
    );
    expect(result.revenue, 0);
    expect(result.days.expand((d) => d.trips), hasLength(1));
    expect(
      result.issues,
      contains(
        'Booking 1: cancelled after delivery; review earned salary [Status: Cancelled]',
      ),
    );
  });
  test('conflicting copies cannot produce a final rating', () {
    final result = PmKpi.calculate(
      makeId: '4',
      period: KpiPeriod.month(2026, 9),
      bookings: [
        booking(id: '71', submission: 'collision', amount: '100'),
        booking(id: '107', submission: 'collision', amount: '200'),
      ],
      records: [],
    );
    expect(result.issues, contains('Booking identity conflict: collision'));
    expect(result.bookingCount, 1);
    expect(result.complete, false);
  });
}
