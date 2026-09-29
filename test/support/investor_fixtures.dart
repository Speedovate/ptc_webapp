import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_scope.dart';

/// Test fixtures for the investor model as it now stands: an investor is a
/// user account with that role, and a truck has no owner field of its own - it
/// belongs to whoever is crewed on it.
///
/// Crew is built *from* the investor id rather than from a fixed pair, so a test
/// cannot name an investor and silently get a Paltranco truck back. That failure
/// is invisible in the result: the statement comes out empty rather than wrong,
/// which reads as "no trips" instead of "wrong owner".
class InvestorFixtures {
  const InvestorFixtures._();

  /// The investor accounts used when a test does not care who they are.
  static const inv1 = UserModel(
    id: 'inv-1',
    role: 'investor',
    name: 'Dela Cruz',
  );
  static const inv2 = UserModel(id: 'inv-2', role: 'investor', name: 'Reyes');

  /// Crew with no parent, which is Paltranco's own.
  static const pioCompany = UserModel(id: 'd-pio', role: 'driver', name: 'Pio');
  static const lizaCompany = UserModel(
    id: 'h-liza',
    role: 'helper',
    name: 'Liza',
  );

  /// Crew belonging to [investorId].
  static UserModel driverFor(String investorId, {String id = 'd-ben'}) =>
      UserModel(
        id: id,
        role: 'driver',
        name: 'Ben',
        parentClientId: investorId,
      );

  static UserModel helperFor(String investorId, {String id = 'h-ana'}) =>
      UserModel(
        id: id,
        role: 'helper',
        name: 'Ana',
        parentClientId: investorId,
      );

  /// A truck owned by [investorId], because its crew works for them.
  static VehicleMake ownedMake(
    String id,
    String code,
    String investorId, {
    UserModel? driver,
    UserModel? helper,
    bool isActive = true,
  }) => VehicleMake(
    id: id,
    code: code,
    driver: driver ?? driverFor(investorId, id: 'd-$id'),
    helper: helper ?? helperFor(investorId, id: 'h-$id'),
    isActive: isActive,
  );

  /// A Paltranco truck: crewed by people with no investor.
  static VehicleMake companyMake(
    String id,
    String code, {
    bool isActive = true,
  }) => VehicleMake(
    id: id,
    code: code,
    driver: pioCompany,
    helper: lizaCompany,
    isActive: isActive,
  );

  /// The accounts a statement needs to resolve ownership: the investors, plus
  /// every crew member referenced by the makes it is given.
  ///
  /// Built from [makes] rather than from a fixed list, so a crew member can
  /// never be missing from the lookup - which would read as "no owner" and drop
  /// the truck off the statement.
  static List<UserModel> usersFor(
    List<VehicleMake> makes, {
    List<UserModel> investors = const [inv1, inv2],
  }) {
    final byId = <String, UserModel>{
      for (final investor in investors)
        if (investor.id != null) investor.id!: investor,
    };
    for (final make in makes) {
      for (final person in [make.driver, make.helper]) {
        if (person?.id == null) continue;
        byId[person!.id!] = person;
        final parent = person.parentClientId;
        if (parent == null || parent.isEmpty) continue;
        byId.putIfAbsent(parent, () => UserModel(id: parent, role: 'investor'));
      }
    }
    return byId.values.toList();
  }

  static List<UserModel> users(List<VehicleMake> makes) => usersFor(makes);

  /// The owner a make resolves to, for asserting on ownership directly.
  static String? ownerOf(VehicleMake make) {
    final resolved = usersFor([make]);
    return InvestorScope.investorForMake(make, {
      for (final user in resolved)
        if (user.id != null) user.id!: user,
    });
  }
}
