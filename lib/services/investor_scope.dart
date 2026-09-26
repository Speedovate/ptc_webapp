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

  /// The one dispatch rule the whole model rests on: a crew only ever works an
  /// investor's own trucks, so an investor's fleet is a closed silo.
  ///
  /// Ownership is compared, never inferred. The driver on a make rotates with
  /// the shift, so a crew member is not evidence of who owns the truck, and a
  /// company crew member is not evidence that a truck is company-owned.
  static bool canCrewWorkVehicle({
    required String? crewInvestorId,
    required String? vehicleInvestorId,
  }) {
    final crew = normalizeId(crewInvestorId);
    final vehicle = normalizeId(vehicleInvestorId);
    if (crew == null || vehicle == null) {
      // Unowned means Paltranco, and Paltranco crews only crew its own trucks.
      return crew == vehicle;
    }
    return crew == vehicle;
  }

  /// The investor a trip's commission belongs to, derived from the truck the
  /// trip ran on. Null means the trip was company work.
  static String? investorForMake(VehicleMake make) =>
      normalizeId(make.investorId);
}
