import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_commission.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

const investorA = 'inv-1';

final ownedMake = VehicleMake(id: '4', code: 'PM4', investorId: investorA);

/// A delivered City Proper run with a driver and a helper, which is a
/// trip share of 100 + 50 on the office rate card.
KpiTrip cityTrip({String id = '900', String destination = 'Bancao-Bancao'}) =>
    KpiTrip(
      Booking(
        id: id,
        clientStatus: 'delivered',
        driver: const UserModel(id: '8', role: 'driver'),
        helper: const UserModel(id: '9', role: 'helper'),
        vehicleMake: ownedMake,
        deliveredAt: DateTime.utc(2026, 9, 15),
        statusOutputs: {
          'delivered__1': {
            'status_key': 'delivered',
            'fields': {'amount': '10000', 'destination': destination},
          },
        },
      ),
      DateTime.utc(2026, 9, 15),
    );

InvestorCommission build(List<KpiTrip> trips, Map<String, String> routes) =>
    InvestorCommission.calculate(
      investorId: investorA,
      periodKey: '2026-09',
      rate: 0.10,
      trips: trips,
      routes: routes,
      makes: [ownedMake],
    );

void main() {
  group('resolveKpiTripRoutes', () {
    test('a rate the office already confirmed wins', () {
      final trip = cityTrip();
      // The card would match this trip to something else; the confirmed rate
      // for that exact trip is the authority, not the guess.
      final resolution = resolveKpiTripRoutes(
        [trip],
        rates: KpiRate.matrix,
        savedTripRates: [
          {'signature': trip.signature, 'route': 'El Nido'},
        ],
      );
      expect(resolution.routes[trip.identity], 'El Nido');
      expect(resolution.unresolved, isEmpty);
      expect(resolution.complete, isTrue);
    });

    test('a confirmed rate that is no longer on the card is not used', () {
      final trip = cityTrip(destination: 'Quezon');
      final resolution = resolveKpiTripRoutes(
        [trip],
        rates: KpiRate.matrix,
        savedTripRates: [
          {
            'signature': trip.signature,
            'route': 'Destination That Was Retired',
          },
        ],
      );
      // Falls back to the card rather than pricing on a name that no longer
      // means anything.
      expect(
        resolution.routes[trip.identity],
        isNot('Destination That Was Retired'),
      );
      expect(resolution.unresolved, isEmpty);
    });

    test('an unmatched drop-off is reported, never guessed', () {
      final trip = cityTrip(destination: 'Bancao-Bancao');
      expect(matchKpiTripRate(trip, KpiRate.matrix).rate, isNull);
      final resolution = resolveKpiTripRoutes([trip], rates: KpiRate.matrix);
      expect(resolution.routes, isEmpty);
      expect(resolution.unresolved, [trip]);
      expect(resolution.complete, isFalse);
    });

    test('one good trip and one bad trip reports only the bad one', () {
      final good = cityTrip(id: '900', destination: 'Quezon');
      final bad = cityTrip(id: '901', destination: 'Bancao-Bancao');
      final resolution = resolveKpiTripRoutes([
        good,
        bad,
      ], rates: KpiRate.matrix);
      expect(resolution.routes[good.identity], 'Quezon');
      expect(resolution.unresolved, [bad]);
    });
  });

  group('a statement refuses to price a trip it cannot price', () {
    // The whole reason this exists. Without the guard the crew's trip share
    // silently became zero and the investor was overpaid, with the
    // reconciliation check certifying it.
    test('a trip with no route is refused', () {
      final trip = cityTrip(destination: 'Bancao-Bancao');
      expect(
        () => build([trip], const {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('Cannot price'), contains('Bancao-Bancao')),
          ),
        ),
      );
    });

    test('a route that is not on the card is refused', () {
      final trip = cityTrip();
      expect(
        () => build([trip], {trip.identity: 'Somewhere Off Card'}),
        throwsA(isA<StateError>()),
      );
    });

    test('a blank route is refused rather than treated as free', () {
      final trip = cityTrip();
      expect(
        () => build([trip], {trip.identity: '   '}),
        throwsA(isA<StateError>()),
      );
    });

    test('one unpriced trip among priced ones is still refused', () {
      final priced = cityTrip(id: '900', destination: 'Quezon');
      final unpriced = cityTrip(id: '901', destination: 'Bancao-Bancao');
      expect(
        () => build([priced, unpriced], {priced.identity: 'Quezon'}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('1 of 2'),
          ),
        ),
      );
    });

    test('an empty period is not an error', () {
      final statement = build(const [], const {});
      expect(statement.tripCount, 0);
      expect(statement.grossBillings, 0);
      expect(statement.netDue, 0);
    });

    test('a trip belonging to another investor is not this investor problem', () {
      final otherMake = VehicleMake(id: '9', code: 'PM9', investorId: 'inv-2');
      final otherTrip = KpiTrip(
        Booking(
          id: '950',
          clientStatus: 'delivered',
          driver: const UserModel(id: '8', role: 'driver'),
          helper: const UserModel(id: '9', role: 'helper'),
          vehicleMake: otherMake,
          deliveredAt: DateTime.utc(2026, 9, 15),
          statusOutputs: const {},
        ),
        DateTime.utc(2026, 9, 15),
      );
      // Unpriceable, but not this statement's: it is not this investor's truck.
      final statement = build([otherTrip], const {});
      expect(statement.tripCount, 0);
    });
  });

  group('a priced trip is unaffected', () {
    test('the crew trip share is what the rate card says', () {
      final trip = cityTrip(destination: 'Quezon');
      final statement = build([trip], {trip.identity: 'Quezon'});
      expect(statement.grossBillings, 10000);
      expect(statement.crewTripShare, greaterThan(0));
      expect(statement.netDue, lessThan(statement.investorPool));
    });

    test('the resolver feeds the statement directly', () {
      // The intended path: resolve, then calculate. No hand-built map.
      final trip = cityTrip(destination: 'Quezon');
      final resolution = resolveKpiTripRoutes([trip], rates: KpiRate.matrix);
      expect(resolution.complete, isTrue);
      final statement = build([trip], resolution.routes);
      expect(statement.crewTripShare, greaterThan(0));
    });

    test('resolution and the guard agree on what is priceable', () {
      final priced = cityTrip(id: '900', destination: 'Quezon');
      final unpriced = cityTrip(id: '901', destination: 'Bancao-Bancao');
      final resolution = resolveKpiTripRoutes([
        priced,
        unpriced,
      ], rates: KpiRate.matrix);
      // Whatever the resolver calls unresolved is exactly what the statement
      // refuses, so a caller cannot resolve its way past the guard by building
      // the map itself.
      expect(resolution.unresolved, hasLength(1));
      expect(
        () => build([priced, unpriced], resolution.routes),
        throwsA(isA<StateError>()),
      );
    });
  });
}
