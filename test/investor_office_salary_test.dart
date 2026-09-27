import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_commission.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

const inv = 'inv-A';
final make = VehicleMake(id: '4', code: 'PM4', investorId: inv);

Booking trip({required String id, String destination = 'Bancao-Bancao'}) =>
    Booking(
      id: id,
      clientStatus: 'delivered',
      driver: const UserModel(id: '8', role: 'driver'),
      helper: const UserModel(id: '9', role: 'helper'),
      vehicleMake: make,
      deliveredAt: DateTime.utc(2026, 9, 5),
      statusOutputs: {
        'delivered__1': {
          'status_key': 'delivered',
          'fields': {'amount': '3000', 'destination': destination},
        },
      },
    );

/// Production reality: the office prices the day themselves, on routes the
/// rate card does not carry. Those are the routes that appear in the four
/// pm_kpi_records documents in ptc-mvp - Bancao-Bancao, San Pedro, Maunlad.
KpiDay officeDay({
  double driver = 1355,
  double helper = 905,
  bool confirmed = false,
  List<KpiTrip>? trips,
  bool signatureMatches = true,
}) {
  final day = DateTime.utc(2026, 9, 5);
  final withTrips = trips ?? [KpiTrip(trip(id: '900'), day)];
  // The office's own notion of settled: ticked *and* still describing these
  // exact trips. A figure whose trips changed underneath it is not settled, and
  // the statement says so rather than presenting it as final.
  final signature = signatureMatches
      ? jsonEncode(withTrips.map((t) => t.signature).toList()..sort())
      : 'a signature from a different set of trips';
  return KpiDay(day, withTrips, {
    'day': '2026-09-05',
    'driver_salary': driver,
    'helper_salary': helper,
    'salary_confirmed': confirmed,
    'trip_signature': signature,
  });
}

void main() {
  InvestorCommission build({
    List<KpiTrip>? trips,
    Map<String, KpiDay> officeDays = const {},
    Map<String, String>? routes,
  }) {
    final list = trips ?? [KpiTrip(trip(id: '900'), DateTime.utc(2026, 9, 5))];
    return InvestorCommission.calculate(
      investorId: inv,
      periodKey: '2026-09',
      rate: 0.10,
      trips: list,
      routes: routes ?? {for (final t in list) t.identity: 'Bancao-Bancao'},
      makes: [make],
      officeDays: officeDays,
    );
  }

  group('a day the office priced itself', () {
    test('is not blocked by a route the rate card does not carry', () {
      // Without the office figure this throws. Bancao-Bancao matches nothing.
      expect(
        () => build(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Cannot price'),
          ),
        ),
      );
      // With it, the statement is produced.
      final statement = build(officeDays: {'2026-09-05': officeDay()});
      expect(statement.crewCost, 2260);
    });

    test('uses the office figure, not anything the card derives', () {
      final statement = build(officeDays: {'2026-09-05': officeDay()});
      // 1355 + 905 exactly. Nothing recomputed, nothing rounded away.
      expect(statement.crewCost, 1355 + 905);
      expect(statement.officeDayCount, 1);
    });

    test('reports an unconfirmed figure rather than hiding it', () {
      final statement = build(
        officeDays: {'2026-09-05': officeDay(confirmed: false)},
      );
      expect(statement.unconfirmedDays, 1);
    });

    test('a confirmed, still-matching figure is not outstanding', () {
      final statement = build(
        officeDays: {'2026-09-05': officeDay(confirmed: true)},
      );
      expect(statement.unconfirmedDays, 0);
    });

    test('a figure whose trips have changed underneath it is outstanding', () {
      // The office priced a different set of trips and never came back. The
      // number is still theirs, but the statement must not call it settled.
      final statement = build(
        officeDays: {
          '2026-09-05': officeDay(confirmed: true, signatureMatches: false),
        },
      );
      expect(statement.unconfirmedDays, 1);
    });

    test('one honest line replaces a split nobody can substantiate', () {
      final statement = build(officeDays: {'2026-09-05': officeDay()});
      final labels = statement.statement.map((line) => line.$1).toList();
      expect(labels, contains('Crew cost (1 day per office KPI)'));
      expect(labels, isNot(contains('Crew daily salary')));
      expect(labels, isNot(contains('Crew trip share')));
    });
  });

  group('a day with no office figure still derives and still blocks', () {
    test('an unpriceable day is refused', () {
      expect(() => build(), throwsA(isA<StateError>()));
    });

    test('a priceable day keeps the daily and trip share split', () {
      final t = KpiTrip(
        trip(id: '900', destination: 'Quezon'),
        DateTime.utc(2026, 9, 5),
      );
      final statement = build(trips: [t], routes: {t.identity: 'Quezon'});
      final labels = statement.statement.map((line) => line.$1).toList();
      expect(labels, contains('Crew daily salary'));
      expect(labels, contains('Crew trip share'));
      expect(statement.officeDayCount, 0);
      // Daily is still counted per person-day.
      expect(statement.crewDaily, 2 * 455);
    });
  });

  group('a mixed period', () {
    test('adds the office days to the derived ones', () {
      final priced = KpiTrip(
        trip(id: '901', destination: 'Quezon'),
        DateTime.utc(2026, 9, 6),
      );
      final statement = build(
        trips: [
          KpiTrip(trip(id: '900'), DateTime.utc(2026, 9, 5)),
          priced,
        ],
        routes: {
          for (final t in [
            KpiTrip(trip(id: '900'), DateTime.utc(2026, 9, 5)),
            priced,
          ])
            t.identity: t.identity == priced.identity
                ? 'Quezon'
                : 'Bancao-Bancao',
        },
        officeDays: {'2026-09-05': officeDay()},
      );
      // Office day 2,260 plus one derived day of 2 crew.
      expect(statement.officeDayCount, 1);
      expect(statement.crewCost, greaterThan(2260));
      expect(statement.netDue, lessThan(statement.investorPool));
    });
  });
}
