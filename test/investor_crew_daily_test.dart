import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/investor_commission.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

import 'support/investor_fixtures.dart';

const inv = 'inv-1';
final make = InvestorFixtures.ownedMake('4', 'PM4', inv);

Booking trip({
  required String id,
  required int day,
  String driver = '8',
  String helper = '9',
  String amount = '3000',
}) => Booking(
  id: id,
  clientStatus: 'delivered',
  driver: UserModel(id: driver, role: 'driver'),
  helper: UserModel(id: helper, role: 'helper'),
  vehicleMake: make,
  deliveredAt: DateTime.utc(2026, 9, day),
  statusOutputs: {
    'delivered__1': {
      'status_key': 'delivered',
      'fields': {'amount': amount, 'destination': 'City Proper'},
    },
  },
);

InvestorCommission build(List<KpiTrip> trips) {
  final routes = {for (final t in trips) t.identity: 'City Proper'};
  return InvestorCommission.calculate(
    investorId: inv,
    periodKey: '2026-09',
    rate: 0.10,
    trips: trips,
    routes: routes,
    makes: [make],
    users: InvestorFixtures.usersFor([make]),
  );
}

/// The daily is owed per person *per day they turned up*, which is not the
/// same as per person in the period. Handing kpiSalary a whole month counts a
/// driver who worked twenty days as one person, so the crew is short-paid and
/// the shortfall becomes the investor's - silently, and with every total still
/// reconciling. These pin the day-at-a-time rule that prevents it.
void main() {
  test('the same driver over four days is paid four dailies', () {
    // One crew, four separate working days, one trip each.
    final trips = [
      for (final day in [5, 9, 16, 19])
        KpiTrip(trip(id: 'b$day', day: day), DateTime.utc(2026, 9, day)),
    ];
    final statement = build(trips);
    // ignore: avoid_print
    print(
      '4 DAYS: crewDaily=${statement.crewDaily} tripShare=${statement.crewTripShare}',
    );
    // Four days x 2 crew x 455
    expect(statement.crewDaily, 4 * 2 * 455);
  });

  test('two drivers on the same day each get a daily', () {
    final trips = [
      KpiTrip(
        trip(id: 'a', day: 5, driver: '8', helper: '9'),
        DateTime.utc(2026, 9, 5),
      ),
      KpiTrip(
        trip(id: 'b', day: 5, driver: '10', helper: '11'),
        DateTime.utc(2026, 9, 5),
      ),
    ];
    final statement = build(trips);
    // ignore: avoid_print
    print('1 DAY 2 CREWS: crewDaily=${statement.crewDaily}');
    expect(statement.crewDaily, 4 * 455);
  });

  test('a helper who works two days is paid two dailies', () {
    // Only the helper repeats: a different driver each day, so the expected
    // figure is the helper's two dailies plus two one-off driver dailies.
    final trips = [
      KpiTrip(
        trip(id: 'a', day: 5, driver: '8', helper: '9'),
        DateTime.utc(2026, 9, 5),
      ),
      KpiTrip(
        trip(id: 'b', day: 6, driver: '10', helper: '9'),
        DateTime.utc(2026, 9, 6),
      ),
    ];
    final statement = build(trips);
    // ignore: avoid_print
    print('SAME HELPER 2 DAYS: crewDaily=${statement.crewDaily}');
    expect(statement.crewDaily, 4 * 455);
  });

  test('a day with no booking pays no daily', () {
    final trips = [KpiTrip(trip(id: 'a', day: 5), DateTime.utc(2026, 9, 5))];
    final statement = build(trips);
    // ignore: avoid_print
    print('1 DAY: crewDaily=${statement.crewDaily}');
    expect(statement.crewDaily, 2 * 455);
  });

  test('two trips on one day still pay one daily', () {
    final trips = [
      KpiTrip(trip(id: 'a', day: 5), DateTime.utc(2026, 9, 5)),
      KpiTrip(trip(id: 'b', day: 5), DateTime.utc(2026, 9, 5)),
    ];
    final statement = build(trips);
    // ignore: avoid_print
    print(
      '1 DAY 2 TRIPS: crewDaily=${statement.crewDaily} tripShare=${statement.crewTripShare}',
    );
    expect(statement.crewDaily, 2 * 455);
    expect(statement.crewTripShare, 2 * (100 + 50));
  });
}
