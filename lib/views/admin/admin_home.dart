import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/view_models/admin/admin_home.vm.dart';
import 'package:webapp/views/admin/admin_bookings.dart';
import 'package:webapp/views/admin/admin_dashboard.dart';
import 'package:webapp/views/admin/admin_fields.dart';
import 'package:webapp/views/admin/admin_forms.dart';
import 'package:webapp/views/admin/admin_statuses.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/views/admin/admin_vehicle_makes.dart';
import 'package:webapp/views/admin/admin_vehicle_sizes.dart';
import 'package:webapp/views/admin/admin_vehicle_types.dart';
import 'package:webapp/views/shared/profile_view.dart';
import 'package:webapp/widgets/shared/admin_shell_layout_scope.dart';
import 'package:webapp/widgets/shared/platform_shell.dart';
import 'package:webapp/widgets/sidebar_menu_item.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({
    super.key,
    required this.user,
    required this.onLogout,
    required this.onUserUpdated,
    this.isQuickLoggedIn = false,
  });

  final UserModel user;
  final VoidCallback onLogout;
  final Future<void> Function() onUserUpdated;
  final bool isQuickLoggedIn;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final AdminHomeViewModel _viewModel = AdminHomeViewModel();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AdminHomeViewModel>.reactive(
      viewModelBuilder: () => _viewModel,
      builder: (context, vm, _) {
        final width = MediaQuery.of(context).size.width;
        final isCompact = width < 1100;
        final showRail = !isCompact && vm.showDrawer;

        return PlatformShell(
          scaffoldKey: _scaffoldKey,
          user: widget.user,
          title: _selectedSectionTitle(vm),
          isCompact: isCompact,
          showRail: showRail,
          onToggleNavigation: vm.toggleDrawer,
          onProfile: () => vm.selectSection(AdminSection.profile),
          onLogout: widget.onLogout,
          logoutLabel: widget.isQuickLoggedIn ? 'Go Back' : 'Logout',
          sidebar: _buildSidebar(vm, isCompact: isCompact),
          body: KeyedSubtree(
            key: ValueKey('${vm.selectedSection}:${vm.selectedSettingsSection}'),
            child: AdminShellLayoutScope(
              filtersRightGap: showRail ? 44 : 24,
              child: _buildSelectedSection(vm.selectedSection),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar(
    AdminHomeViewModel vm, {
    required bool isCompact,
  }) {
    return PlatformSidebarContainer(
      onBrandTap: () {
        vm.selectSection(AdminSection.dashboard);
        if (isCompact && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      children: [
        SidebarMenuItem(
          label: AdminSection.dashboard.title,
          icon: _menuIcon(AdminSection.dashboard),
          isSelected: vm.selectedSection == AdminSection.dashboard,
          onTap: () {
            vm.selectSection(AdminSection.dashboard);
            if (isCompact) {
              Navigator.of(context).pop();
            }
          },
        ),
        SidebarMenuItem(
          label: AdminSection.bookings.title,
          icon: _menuIcon(AdminSection.bookings),
          isSelected: vm.selectedSection == AdminSection.bookings,
          onTap: () {
            vm.selectSection(AdminSection.bookings);
            if (isCompact) {
              Navigator.of(context).pop();
            }
          },
        ),
        SidebarMenuItem(
          label: AdminSection.vehicles.title,
          icon: _menuIcon(AdminSection.vehicles),
          isSelected: false,
          trailing: Icon(
            vm.isVehiclesExpanded
                ? Icons.keyboard_arrow_down_rounded
                : Icons.chevron_right_rounded,
            color: Colors.white,
            size: 18,
          ),
          onTap: vm.toggleVehiclesExpanded,
          children: vm.isVehiclesExpanded
              ? [
                  SidebarMenuItem(
                    label: AdminVehiclesSection.makes.title,
                    icon: Icons.precision_manufacturing_outlined,
                    isChild: true,
                    isSelected:
                        vm.selectedSection == AdminSection.vehicles &&
                        vm.selectedVehiclesSection == AdminVehiclesSection.makes,
                    onTap: () {
                      vm.selectVehiclesSection(AdminVehiclesSection.makes);
                      if (isCompact) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  SidebarMenuItem(
                    label: AdminVehiclesSection.types.title,
                    icon: Icons.category_outlined,
                    isChild: true,
                    isSelected:
                        vm.selectedSection == AdminSection.vehicles &&
                        vm.selectedVehiclesSection == AdminVehiclesSection.types,
                    onTap: () {
                      vm.selectVehiclesSection(AdminVehiclesSection.types);
                      if (isCompact) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  SidebarMenuItem(
                    label: AdminVehiclesSection.sizes.title,
                    icon: Icons.straighten_outlined,
                    isChild: true,
                    isSelected:
                        vm.selectedSection == AdminSection.vehicles &&
                        vm.selectedVehiclesSection == AdminVehiclesSection.sizes,
                    onTap: () {
                      vm.selectVehiclesSection(AdminVehiclesSection.sizes);
                      if (isCompact) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ]
              : const [],
        ),
        SidebarMenuItem(
          label: AdminSection.settings.title,
          icon: _menuIcon(AdminSection.settings),
          isSelected: false,
          trailing: Icon(
            vm.isSettingsExpanded
                ? Icons.keyboard_arrow_down_rounded
                : Icons.chevron_right_rounded,
            color: Colors.white,
            size: 18,
          ),
          onTap: vm.toggleSettingsExpanded,
          children: vm.isSettingsExpanded
              ? [
                  SidebarMenuItem(
                    label: AdminSettingsSection.forms.title,
                    icon: Icons.description_outlined,
                    isChild: true,
                    isSelected:
                        vm.selectedSection == AdminSection.settings &&
                        vm.selectedSettingsSection == AdminSettingsSection.forms,
                    onTap: () {
                      vm.selectSettingsSection(AdminSettingsSection.forms);
                      if (isCompact) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  SidebarMenuItem(
                    label: AdminSettingsSection.fields.title,
                    icon: Icons.view_stream_outlined,
                    isChild: true,
                    isSelected:
                        vm.selectedSection == AdminSection.settings &&
                        vm.selectedSettingsSection == AdminSettingsSection.fields,
                    onTap: () {
                      vm.selectSettingsSection(AdminSettingsSection.fields);
                      if (isCompact) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  SidebarMenuItem(
                    label: AdminSettingsSection.statuses.title,
                    icon: Icons.flag_outlined,
                    isChild: true,
                    isSelected:
                        vm.selectedSection == AdminSection.settings &&
                        vm.selectedSettingsSection ==
                            AdminSettingsSection.statuses,
                    onTap: () {
                      vm.selectSettingsSection(AdminSettingsSection.statuses);
                      if (isCompact) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ]
              : const [],
        ),
        SidebarMenuItem(
          label: AdminSection.profile.title,
          icon: _menuIcon(AdminSection.profile),
          isSelected: vm.selectedSection == AdminSection.profile,
          onTap: () {
            vm.selectSection(AdminSection.profile);
            if (isCompact) {
              Navigator.of(context).pop();
            }
          },
        ),
        SidebarMenuItem(
          label: AdminSection.users.title,
          icon: _menuIcon(AdminSection.users),
          isSelected: vm.selectedSection == AdminSection.users,
          onTap: () {
            vm.selectSection(AdminSection.users);
            if (isCompact) {
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }

  Widget _buildSelectedSection(AdminSection section) {
    return switch (section) {
      AdminSection.dashboard => const AdminDashboardView(),
      AdminSection.bookings => AdminBookingsView(user: widget.user),
      AdminSection.vehicles => switch (_viewModel.selectedVehiclesSection) {
          AdminVehiclesSection.makes => const AdminVehicleMakesView(),
          AdminVehiclesSection.sizes => const AdminVehicleSizesView(),
          AdminVehiclesSection.types => const AdminVehicleTypesView(),
        },
      AdminSection.settings => switch (_viewModel.selectedSettingsSection) {
          AdminSettingsSection.forms => const AdminFormsView(),
          AdminSettingsSection.fields => const AdminFieldsView(),
          AdminSettingsSection.statuses => const AdminStatusesView(),
        },
      AdminSection.users => AdminUsersView(
          user: widget.user,
          onCurrentUserUpdated: widget.onUserUpdated,
          onLogout: widget.onLogout,
          isQuickLoggedIn: widget.isQuickLoggedIn,
          initialEditUserId: _viewModel.pendingEditUserId,
          onInitialEditHandled: _viewModel.clearPendingEditUser,
        ),
      AdminSection.profile => ProfileView(
          user: widget.user,
          isCurrentUserView: true,
          onLogout: widget.onLogout,
          logoutLabel: widget.isQuickLoggedIn ? 'Go Back' : 'Logout',
          onEditPressed: () {
            _viewModel.openUsersForEdit(widget.user.id);
          },
        ),
    };
  }

  String _selectedSectionTitle(AdminHomeViewModel vm) {
    if (vm.selectedSection == AdminSection.settings) {
      return vm.selectedSettingsSection.title;
    }
    if (vm.selectedSection == AdminSection.vehicles) {
      return vm.selectedVehiclesSection.title;
    }
    return vm.selectedSection.title;
  }

  IconData _menuIcon(AdminSection section) {
    return switch (section) {
      AdminSection.dashboard => Icons.dashboard_rounded,
      AdminSection.bookings => Icons.calendar_month_rounded,
      AdminSection.vehicles => Icons.local_shipping_outlined,
      AdminSection.settings => Icons.settings_rounded,
      AdminSection.users => Icons.people_alt_rounded,
      AdminSection.profile => Icons.account_circle_rounded,
    };
  }
}
