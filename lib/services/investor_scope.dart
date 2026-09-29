import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/utils/functions.dart';

/// Who an investor is allowed to see and touch.
///
/// An investor brings trucks and their own crew, but Paltranco does the
/// booking, dispatching and billing. So an investor reads their own operation
/// and nothing else. Every capability check in the investor screens has to be
/// paired with one of these - a capability on its own is not a boundary,
/// because the same capability lets an admin see the whole company.
class InvestorScope {
  const InvestorScope._();

  /// Roles that see the whole operation and are never scoped.
  static const Set<String> officeRoles = {'admin', 'manager', 'dispatcher'};

  static bool isOfficeRole(String? role) =>
      officeRoles.contains(normalizeRoleKey(role));

  static bool isInvestorRole(String? role) =>
      normalizeRoleKey(role) == 'investor';

  /// The investors on file, keyed by user id. These are the accounts an
  /// investor's fleet can belong to, and the only values the office can pick
  /// from - there is nothing to type and so nothing to mistype.
  static Map<String, UserModel> investorsById(Iterable<UserModel> users) {
    final map = <String, UserModel>{};
    for (final user in users) {
      if (!isInvestorRole(user.role)) continue;
      final id = normalizeId(user.id);
      if (id != null) map[id] = user;
    }
    return map;
  }

  /// Whether [viewer] may act on a row owned by [ownerInvestorId].
  ///
  /// A null owner means Paltranco owns the row, so only the office reaches it.
  /// An investor therefore never sees a company truck or a company crew member,
  /// which is what stops their Portfolio from quietly including the whole fleet.
  static bool ownsRow({
    required String? viewerRole,
    required String? viewerId,
    required String? ownerInvestorId,
  }) {
    if (isOfficeRole(viewerRole)) {
      return true;
    }
    if (!isInvestorRole(viewerRole)) {
      return false;
    }
    final owner = normalizeId(ownerInvestorId);
    final viewer = normalizeId(viewerId);
    if (owner == null || viewer == null) {
      return false;
    }
    return owner == viewer;
  }

  /// Whether [viewer] may hand out [role].
  ///
  /// Investor is the one role that cannot be granted without a dedicated
  /// permission. Admins hold everything by default; anyone else needs
  /// `users.create_investor` granted to their role.
  static bool canGrantRole({
    required String? viewerRole,
    required String role,
    required bool canCreateInvestorUsers,
  }) {
    if (normalizeRoleKey(role) != 'investor') {
      return true;
    }
    if (isOfficeRole(viewerRole)) {
      return canCreateInvestorUsers;
    }
    return false;
  }

  /// The investor a crew member works for, as that investor's user id.
  ///
  /// Read from the crew member's `parent_client_id`, but only honoured when
  /// that parent is actually an investor account. A crew member under a client
  /// is a client relationship, not an investor one, and must not be mistaken
  /// for a fleet.
  static String? investorForCrew(
    UserModel? crew,
    Map<String, UserModel> usersById,
  ) {
    final parentId = normalizeId(crew?.parentClientId);
    if (parentId == null) return null;
    return isInvestorRole(usersById[parentId]?.role) ? parentId : null;
  }

  /// The investor who owns a truck, as that investor's user id.
  ///
  /// Derived from whoever is crewed on it, because a truck carries no owner
  /// field of its own. A driver or helper whose `parent_client_id` names an
  /// investor account puts the truck in that investor's fleet; a Paltranco crew
  /// member leaves it a company truck.
  ///
  /// The driver is asked first, then the helper. A truck can only ever belong to
  /// one investor, and a mixed crew is not something to resolve here - the silo
  /// check rejects that pairing before it can be saved.
  static String? investorForMake(
    VehicleMake? make,
    Map<String, UserModel> usersById,
  ) {
    if (make == null) return null;
    for (final crew in [make.driver, make.helper]) {
      final owner = investorForCrew(crew, usersById);
      if (owner != null) return owner;
    }
    return null;
  }

  /// The one dispatch rule the whole model rests on: a crew only ever works an
  /// investor's own trucks, so an investor's fleet is a closed silo.
  ///
  ///   Paltranco truck <-> Paltranco crew
  ///   inv-1 truck     <-> inv-1's crew
  ///   inv-1 truck     <-> inv-2's crew   never
  ///
  /// Both sides are resolved the same way, so a company crew member cannot be
  /// put on an investor's truck and an investor's crew cannot be put on a
  /// company truck.
  static bool canCrewWorkVehicle({
    required UserModel? crew,
    required Map<String, UserModel> usersById,
    required VehicleMake? vehicle,
  }) {
    final crewOwner = investorForCrew(crew, usersById);
    final vehicleOwner = investorForMake(vehicle, usersById);
    return crewOwner == vehicleOwner;
  }
}
