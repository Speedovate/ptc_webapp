import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/view_models/admin/admin_users.vm.dart';

/// 'investor' has to exist as a role for its capability defaults to work, and
/// that list feeds two other lists the office actually uses: the role dropdown
/// in the New/Edit user modals, and the role options in the Flows screens.
/// Both leaked the role before they were guarded, so both are pinned here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AdminUsersViewModel.clearCachedState);
  tearDown(AdminUsersViewModel.clearCachedState);

  test('investor is a known role', () {
    expect(RoleAccessService().knownRoleKeys, contains('investor'));
  });

  test('investor never appears as a booking workflow role', () {
    final roles = RoleAccessService().workflowRoleKeys;
    expect(
      roles,
      isNot(contains('investor')),
      reason:
          'Paltranco advances every trip, so no status should name investor',
    );
    // The roles the Flows screens already had must all still be there.
    for (final role in [
      'client',
      'driver',
      'helper',
      'dispatcher',
      'manager',
      'admin',
    ]) {
      expect(roles, contains(role), reason: role);
    }
  });

  group('opening an investor account needs its own permission', () {
    test('a dispatcher cannot, by default', () {
      final vm = AdminUsersViewModel(
        fallbackCurrentUser: const UserModel(id: '8', role: 'dispatcher'),
      );
      expect(vm.canCreateInvestorUsers, isFalse);
    });

    test('an admin can, because admins hold every capability', () {
      final vm = AdminUsersViewModel(
        fallbackCurrentUser: const UserModel(id: '1', role: 'admin'),
      );
      expect(vm.canCreateInvestorUsers, isTrue);
    });
  });

  test('the investor capability defaults deny the money and office tools', () {
    final defaults = defaultAccessCapabilitiesForRole('investor');

    // What they get.
    for (final allowed in [
      DispatcherAccessCapability.investorPortfolioRead,
      DispatcherAccessCapability.investorTripsRead,
      DispatcherAccessCapability.investorFleetRead,
      DispatcherAccessCapability.investorEarningsRead,
      DispatcherAccessCapability.investorReportsExport,
    ]) {
      expect(defaults[allowed], isTrue, reason: allowed);
    }

    // What they must never get.
    for (final denied in [
      DispatcherAccessCapability.crewKpiRead,
      DispatcherAccessCapability.pmKpiRead,
      DispatcherAccessCapability.pmKpiUpdate,
      DispatcherAccessCapability.fuelLedgerRead,
      DispatcherAccessCapability.tripIncomeRead,
      DispatcherAccessCapability.dashboardRead,
      DispatcherAccessCapability.dashboardUpdateBilling,
      DispatcherAccessCapability.bookingsRead,
      DispatcherAccessCapability.bookingsUpdate,
      DispatcherAccessCapability.roleAccessRead,
      DispatcherAccessCapability.roleAccessUpdate,
      DispatcherAccessCapability.usersImpersonate,
      DispatcherAccessCapability.usersDelete,
      DispatcherAccessCapability.usersCreateInvestor,
      DispatcherAccessCapability.investorCommissionRateUpdate,
    ]) {
      expect(defaults[denied], isFalse, reason: denied);
    }
  });

  test('no capability is left undefined for the investor role', () {
    final defaults = defaultAccessCapabilitiesForRole('investor');
    for (final capability in DispatcherAccessCapability.values) {
      expect(
        defaults.containsKey(capability),
        isTrue,
        reason: '$capability must be decided explicitly, not defaulted',
      );
    }
  });

  test('investor defaults are unrelated to the other roles', () {
    final investor = defaultAccessCapabilitiesForRole('investor');
    final driver = defaultAccessCapabilitiesForRole('driver');
    final client = defaultAccessCapabilitiesForRole('client');

    // An investor must not inherit the crew or client toolset.
    expect(
      investor[DispatcherAccessCapability.bookingsRead],
      isNot(driver[DispatcherAccessCapability.bookingsRead]),
    );
    expect(
      investor[DispatcherAccessCapability.investorPortfolioRead],
      isNot(client[DispatcherAccessCapability.investorPortfolioRead]),
    );
  });
}
