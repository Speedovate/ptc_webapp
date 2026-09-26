import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_scope.dart';

/// The investor model only holds if two things are true: an investor can never
/// reach another investor's rows, and a crew member can never be put on a truck
/// its own investor does not own. Both are pure functions here on purpose, so
/// every screen that touches money or dispatch can be checked against them.
void main() {
  group('scoping an investor to their own rows', () {
    test('the office is never scoped', () {
      for (final role in ['admin', 'manager', 'dispatcher']) {
        expect(
          InvestorScope.ownsRow(
            viewerRole: role,
            viewerId: '1',
            ownerInvestorId: '99',
          ),
          isTrue,
          reason: role,
        );
        expect(
          InvestorScope.ownsRow(
            viewerRole: role,
            viewerId: '1',
            ownerInvestorId: null,
          ),
          isTrue,
          reason: role,
        );
      }
    });

    test('an investor sees exactly their own rows', () {
      expect(
        InvestorScope.ownsRow(
          viewerRole: 'investor',
          viewerId: '8',
          ownerInvestorId: '8',
        ),
        isTrue,
      );
      expect(
        InvestorScope.ownsRow(
          viewerRole: 'investor',
          viewerId: '8',
          ownerInvestorId: '9',
        ),
        isFalse,
        reason: 'another investor is off limits',
      );
    });

    test('an investor never sees company-owned rows', () {
      // A Paltranco truck is not an investor's, so it must stay out of their
      // Portfolio and Fleet even though the company is running it.
      expect(
        InvestorScope.ownsRow(
          viewerRole: 'investor',
          viewerId: '8',
          ownerInvestorId: null,
        ),
        isFalse,
      );
    });

    test('an unidentified viewer reaches nothing', () {
      expect(
        InvestorScope.ownsRow(
          viewerRole: 'investor',
          viewerId: null,
          ownerInvestorId: '8',
        ),
        isFalse,
      );
      expect(
        InvestorScope.ownsRow(
          viewerRole: 'driver',
          viewerId: '13',
          ownerInvestorId: '8',
        ),
        isFalse,
        reason: 'crew are not investors',
      );
    });
  });

  group('granting the investor role', () {
    test('it needs an explicit permission, even for the office', () {
      expect(
        InvestorScope.canGrantRole(
          viewerRole: 'admin',
          role: 'investor',
          canCreateInvestorUsers: false,
        ),
        isFalse,
      );
      expect(
        InvestorScope.canGrantRole(
          viewerRole: 'admin',
          role: 'investor',
          canCreateInvestorUsers: true,
        ),
        isTrue,
      );
      expect(
        InvestorScope.canGrantRole(
          viewerRole: 'manager',
          role: 'investor',
          canCreateInvestorUsers: true,
        ),
        isTrue,
        reason: 'a granted manager may create one',
      );
    });

    test('no other role can hand it out', () {
      expect(
        InvestorScope.canGrantRole(
          viewerRole: 'driver',
          role: 'investor',
          canCreateInvestorUsers: true,
        ),
        isFalse,
      );
      expect(
        InvestorScope.canGrantRole(
          viewerRole: 'dispatcher',
          role: 'investor',
          canCreateInvestorUsers: false,
        ),
        isFalse,
      );
    });

    test('ordinary roles stay open to anyone who may edit users', () {
      expect(
        InvestorScope.canGrantRole(
          viewerRole: 'dispatcher',
          role: 'driver',
          canCreateInvestorUsers: false,
        ),
        isTrue,
      );
    });
  });

  group('a crew only ever works its own investor trucks', () {
    test('matching owners are allowed', () {
      expect(
        InvestorScope.canCrewWorkVehicle(
          crewInvestorId: '8',
          vehicleInvestorId: '8',
        ),
        isTrue,
      );
    });

    test('a mismatch is refused in both directions', () {
      expect(
        InvestorScope.canCrewWorkVehicle(
          crewInvestorId: '8',
          vehicleInvestorId: '9',
        ),
        isFalse,
      );
      expect(
        InvestorScope.canCrewWorkVehicle(
          crewInvestorId: '9',
          vehicleInvestorId: '8',
        ),
        isFalse,
      );
    });

    test('an investor crew can never be put on a company truck', () {
      expect(
        InvestorScope.canCrewWorkVehicle(
          crewInvestorId: '8',
          vehicleInvestorId: null,
        ),
        isFalse,
      );
    });

    test('company crews still crew company trucks', () {
      expect(
        InvestorScope.canCrewWorkVehicle(
          crewInvestorId: null,
          vehicleInvestorId: null,
        ),
        isTrue,
      );
    });

    test('an unowned crew member is never a free pass', () {
      // A crew member with no investor recorded must not be usable on an
      // investor's truck just because the id is missing on one side.
      expect(
        InvestorScope.canCrewWorkVehicle(
          crewInvestorId: null,
          vehicleInvestorId: '8',
        ),
        isFalse,
      );
    });
  });

  group('trip ownership comes from the truck', () {
    test('an investor-owned make resolves to its investor', () {
      expect(
        InvestorScope.investorForMake(
          const VehicleMake(id: '1', code: 'PM1', investorId: '8'),
        ),
        '8',
      );
    });

    test('a company make resolves to nobody', () {
      expect(
        InvestorScope.investorForMake(const VehicleMake(id: '1', code: 'PM1')),
        isNull,
      );
    });

    test('the driver on the make never implies ownership', () {
      // Same truck, driver changed. Ownership must not move with the shift.
      const make = VehicleMake(id: '1', code: 'PM1', investorId: '8');
      final afterShiftChange = make.copyWith(
        driver: const VehicleMake(id: '1', code: 'PM1', investorId: '8').driver,
      );
      expect(InvestorScope.investorForMake(afterShiftChange), '8');
    });
  });
}
