import 'package:webapp/view_models/admin/admin_bookings.vm.dart';
import 'package:webapp/view_models/admin/admin_dashboard.vm.dart';
import 'package:webapp/view_models/admin/admin_flow.vm.dart';
import 'package:webapp/view_models/admin/admin_users.vm.dart';
import 'package:webapp/view_models/admin/admin_vehicle_makes.vm.dart';
import 'package:webapp/view_models/admin/admin_vehicle_sizes.vm.dart';
import 'package:webapp/view_models/admin/admin_vehicle_types.vm.dart';
import 'package:webapp/view_models/client/client_booking_history.vm.dart';
import 'package:webapp/view_models/client/client_booking_home.vm.dart';
import 'package:webapp/view_models/client/client_members.vm.dart';
import 'package:webapp/view_models/shared/booking_workflow.vm.dart';
import 'package:webapp/view_models/shared/role_assigned_home.vm.dart';

class AppSessionReset {
  AppSessionReset._();

  static void clearUserScopedState() {
    AdminBookingsViewModel.clearCachedState();
    AdminDashboardViewModel.clearCachedState();
    AdminFlowViewModel.clearCachedState();
    AdminUsersViewModel.clearCachedState();
    AdminVehicleMakesViewModel.clearCachedState();
    AdminVehicleSizesViewModel.clearCachedState();
    AdminVehicleTypesViewModel.clearCachedState();
    ClientBookingHistoryViewModel.clearCachedState();
    ClientBookingHomeViewModel.clearCachedState();
    ClientMembersViewModel.clearCachedState();
    BookingWorkflowViewModel.clearCachedState();
    RoleAssignedHomeViewModel.clearCachedState();
  }
}
