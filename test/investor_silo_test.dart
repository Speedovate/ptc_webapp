import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_scope.dart';

/// The silo, and the two ideas it rests on: an investor is a user account with
/// that role, and a truck has no owner field of its own - it reads its owner off
/// whoever is crewed on it.
void main() {
  const inv1 = UserModel(id: '20', role: 'investor', name: 'Dela Cruz');
  const inv2 = UserModel(id: '21', role: 'investor', name: 'Reyes');
  const client = UserModel(id: '30', role: 'client', name: 'Bianca');
  const benInv1 = UserModel(
    id: '8',
    role: 'driver',
    name: 'Ben',
    parentClientId: '20',
  );
  const anaInv1 = UserModel(
    id: '9',
    role: 'helper',
    name: 'Ana',
    parentClientId: '20',
  );
  const rafInv2 = UserModel(
    id: '11',
    role: 'driver',
    name: 'Raf',
    parentClientId: '21',
  );
  const paltrancoBen = UserModel(id: '12', role: 'driver', name: 'Pio');
  const paltrancoAna = UserModel(id: '13', role: 'helper', name: 'Liza');

  final users = [
    inv1,
    inv2,
    client,
    benInv1,
    anaInv1,
    rafInv2,
    paltrancoBen,
    paltrancoAna,
  ];
  final byId = {
    for (final user in users)
      if (user.id != null) user.id!: user,
  };

  VehicleMake truck(String id, {UserModel? driver, UserModel? helper}) =>
      VehicleMake(id: id, code: 'PM$id', driver: driver, helper: helper);

  group('an investor is an account with that role', () {
    test('the list is the accounts, not anything typed', () {
      final investors = InvestorScope.investorsById(users);
      expect(investors.keys, ['20', '21']);
      expect(investors['20']?.name, 'Dela Cruz');
    });

    test('nobody else is an investor', () {
      for (final user in [client, benInv1, paltrancoBen]) {
        expect(
          InvestorScope.isInvestorRole(user.role),
          isFalse,
          reason: '$user',
        );
      }
    });
  });

  group('whose crew is this', () {
    test('a crew member under an investor is theirs', () {
      expect(InvestorScope.investorForCrew(benInv1, byId), '20');
      expect(InvestorScope.investorForCrew(anaInv1, byId), '20');
    });

    test('a crew member with no parent is Paltranco', () {
      expect(InvestorScope.investorForCrew(paltrancoBen, byId), isNull);
    });

    test('a crew member under a client is not an investor fleet', () {
      // The parent field is shared with the client hierarchy. A client is not a
      // fleet, and mistaking one for the other would put a client's driver on
      // an investor's truck.
      const underClient = UserModel(
        id: '40',
        role: 'driver',
        parentClientId: '30',
      );
      expect(InvestorScope.investorForCrew(underClient, byId), isNull);
    });
  });

  group('whose truck is this', () {
    test('a truck crewed by an investor crew is that investor\'s', () {
      expect(
        InvestorScope.investorForMake(
          truck('4', driver: benInv1, helper: anaInv1),
          byId,
        ),
        '20',
      );
    });

    test('a truck crewed by Paltranco is the company\'s', () {
      expect(
        InvestorScope.investorForMake(
          truck('7', driver: paltrancoBen, helper: paltrancoAna),
          byId,
        ),
        isNull,
      );
    });

    test('an uncrewed truck is the company\'s until crew is assigned', () {
      expect(InvestorScope.investorForMake(truck('8'), byId), isNull);
    });

    test('no truck at all is nobody\'s', () {
      expect(InvestorScope.investorForMake(null, byId), isNull);
    });

    test('a half-crewed truck still resolves from whoever is on it', () {
      // A helper on its own is enough to place the truck. The alternative is a
      // truck that reads as company-owned while an investor pays for it.
      expect(
        InvestorScope.investorForMake(truck('4', helper: anaInv1), byId),
        '20',
      );
    });
  });

  group('the silo: never mixed', () {
    bool allowed(UserModel? crew, VehicleMake vehicle) =>
        InvestorScope.canCrewWorkVehicle(
          crew: crew,
          usersById: byId,
          vehicle: vehicle,
        );

    test('Paltranco truck takes Paltranco crew', () {
      final vehicle = truck('7', driver: paltrancoBen, helper: paltrancoAna);
      expect(allowed(paltrancoBen, vehicle), isTrue);
      expect(allowed(paltrancoAna, vehicle), isTrue);
    });

    test('an investor\'s truck takes that investor\'s crew', () {
      final vehicle = truck('4', driver: benInv1, helper: anaInv1);
      expect(allowed(benInv1, vehicle), isTrue);
      expect(allowed(anaInv1, vehicle), isTrue);
    });

    test('an investor\'s crew is refused on another investor\'s truck', () {
      final vehicle = truck('9', driver: rafInv2);
      expect(allowed(benInv1, vehicle), isFalse);
      expect(allowed(anaInv1, vehicle), isFalse);
    });

    test('Paltranco crew is refused on an investor\'s truck', () {
      // The direction people forget. It is still a breach: the investor pays
      // the crew share, so the driver has to be theirs.
      final vehicle = truck('4', driver: benInv1);
      expect(allowed(paltrancoBen, vehicle), isFalse);
      expect(allowed(paltrancoAna, vehicle), isFalse);
    });

    test('Paltranco crew is refused on an uncrewed company truck', () {
      expect(allowed(paltrancoBen, truck('8')), isTrue);
      // ...and an investor's crew is too, because that truck is the company's.
      expect(allowed(benInv1, truck('8')), isFalse);
    });

    test('a crew member with no parent cannot be placed anywhere else', () {
      expect(allowed(paltrancoBen, truck('8')), isTrue);
      expect(allowed(paltrancoBen, truck('4', driver: benInv1)), isFalse);
    });
  });
}
