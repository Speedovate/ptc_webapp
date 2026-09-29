import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_commission.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

import 'support/investor_fixtures.dart';

/// The money split, checked against the numbers the office already uses: a
/// City Proper crew share of 100/50 plus 455 a day each, and the 10% platform
/// fee taken on the delivery amount before anything else comes out.
void main() {
  // An investor is an account with that role, and a truck belongs to whoever
  // is crewed on it. The fixtures keep those two facts in step.
  const investorA = 'inv-1';
  const investorB = 'inv-2';

  final cityMake = InvestorFixtures.ownedMake('4', 'PM1', investorA);
  final otherInvestorMake = InvestorFixtures.ownedMake('9', 'PM9', investorB);
  final companyMake = InvestorFixtures.companyMake('5', 'PM5');
  final makes = [cityMake, otherInvestorMake, companyMake];

  Booking trip({
    required String id,
    required String makeId,
    required String driverId,
    required String helperId,
    String amount = '3000',
    String destination = 'Bancao-Bancao',
  }) {
    return Booking(
      id: id,
      clientStatus: 'delivered',
      driver: UserModel(id: driverId, role: 'driver'),
      helper: UserModel(id: helperId, role: 'helper'),
      vehicleMake: VehicleMake(id: makeId, code: makeId),
      deliveredAt: DateTime.utc(2026, 9, 15),
      statusOutputs: {
        'delivered__1': {
          'status_key': 'delivered',
          'fields': {'amount': amount, 'destination': destination},
        },
      },
    );
  }

  KpiTrip wrap(Booking b) => KpiTrip(b, DateTime.utc(2026, 9, 15));

  /// Routes are keyed by trip identity, which is what the rate card looks up.
  /// Everything here is a city run unless a test says otherwise.
  InvestorCommission statementFor({
    required List<KpiTrip> trips,
    String investor = investorA,
    double rate = 0.10,
    List<InvestorExpense> expenses = const [],
    String route = 'City Proper',
  }) => InvestorCommission.calculate(
    investorId: investor,
    periodKey: '2026-09',
    rate: rate,
    trips: trips,
    routes: {for (final trip in trips) trip.identity: route},
    makes: makes,
    users: InvestorFixtures.usersFor(makes),
    expenses: expenses,
  );

  group('only the investor own trucks count', () {
    test('a trip on another investor truck is not on this statement', () {
      final statement = statementFor(
        trips: [
          wrap(trip(id: '1', makeId: '4', driverId: '13', helperId: '18')),
          wrap(trip(id: '2', makeId: '9', driverId: '20', helperId: '21')),
        ],
      );
      expect(statement.tripCount, 1);
      expect(statement.grossBillings, 3000);
    });

    test('a company trip is not on any investor statement', () {
      final statement = statementFor(
        trips: [
          wrap(trip(id: '3', makeId: '5', driverId: '16', helperId: '15')),
        ],
        investor: investorB,
      );
      expect(statement.tripCount, 0);
      expect(statement.netDue, 0);
    });
  });

  group('the split', () {
    final oneTrip = [
      wrap(trip(id: '1', makeId: '4', driverId: '13', helperId: '18')),
    ];

    test('Paltranco takes its rate off the top, unconditionally', () {
      final statement = statementFor(trips: oneTrip);
      expect(statement.grossBillings, 3000);
      expect(statement.platformFee, 300);
      expect(statement.investorPool, 2700);
    });

    test('crew is the daily plus the trip share, shown separately', () {
      final statement = statementFor(trips: oneTrip);
      // 455 x 2 people for the day, plus the city trip share of 100 + 50.
      expect(statement.crewDaily, 910);
      expect(statement.crewTripShare, 150);
    });

    test('the investor nets the remainder', () {
      final statement = statementFor(trips: oneTrip);
      expect(statement.netDue, 2700 - 910 - 150);
      expect(statement.netDue, 1640);
    });

    test('a different rate is honoured and nothing else moves', () {
      final at5 = statementFor(trips: oneTrip, rate: 0.05);
      final at15 = statementFor(trips: oneTrip, rate: 0.15);
      expect(at5.platformFee, 150);
      expect(at15.platformFee, 450);
      expect(at5.crewDaily, at15.crewDaily);
      // 15% of 3,000 is 450, so the pool is 2,550 before crew.
      expect(at15.netDue, 2550 - 910 - 150);
      expect(at15.netDue, 1490);
    });
  });

  group('expenses', () {
    final oneTrip = [
      wrap(trip(id: '1', makeId: '4', driverId: '13', helperId: '18')),
    ];

    test('an approved cost comes out of the investor share', () {
      final statement = statementFor(
        trips: oneTrip,
        expenses: const [
          InvestorExpense(
            amount: 1200,
            category: 'fuel',
            approved: true,
            reference: 'PO-2026-01',
            description: 'Diesel, Roxas run',
          ),
        ],
      );
      expect(statement.approvedExpensesTotal, 1200);
      expect(statement.netDue, 1640 - 1200);
    });

    test('a cost the investor has not approved does not move their money', () {
      final statement = statementFor(
        trips: oneTrip,
        expenses: const [
          InvestorExpense(
            amount: 50000,
            category: 'maintenance',
            approved: false,
          ),
        ],
      );
      expect(statement.approvedExpensesTotal, 0);
      expect(statement.netDue, 1640, reason: 'pending costs must not deduct');
      expect(
        statement.pendingExpenses,
        hasLength(1),
        reason: 'but it must still be visible',
      );
    });
  });

  group('the statement reads top to bottom', () {
    test('and the lines add up to the net', () {
      final statement = statementFor(
        trips: [
          wrap(trip(id: '1', makeId: '4', driverId: '13', helperId: '18')),
        ],
        expenses: const [
          InvestorExpense(amount: 300, category: 'fuel', approved: true),
        ],
      );

      final lines = statement.statement;
      expect(lines.first.$1, 'Gross billings');
      expect(lines.last.$1, 'Net due');
      final running = lines
          .take(lines.length - 1)
          .fold<double>(0, (sum, line) => sum + line.$2);
      expect(running, closeTo(statement.netDue, 0.005));
    });
  });

  group('more volume, same per-trip economics', () {
    test('a second trip on the same day shares the daily wage', () {
      final statement = statementFor(
        trips: [
          wrap(trip(id: '1', makeId: '4', driverId: '13', helperId: '18')),
          wrap(trip(id: '2', makeId: '4', driverId: '13', helperId: '18')),
        ],
      );
      expect(statement.tripCount, 2);
      expect(statement.grossBillings, 6000);
      expect(statement.platformFee, 600);
      // The daily is charged once, which is the whole point of daily pay.
      expect(statement.crewDaily, 910);
      expect(statement.crewTripShare, 300, reason: '150 per trip');
      expect(statement.netDue, 6000 - 600 - 910 - 300);
    });

    test('a second crew adds its own daily wage', () {
      final statement = statementFor(
        trips: [
          wrap(trip(id: '1', makeId: '4', driverId: '13', helperId: '18')),
          wrap(trip(id: '2', makeId: '4', driverId: '16', helperId: '15')),
        ],
      );
      expect(statement.crewDaily, 1820, reason: 'four people, one day');
    });
  });
}
