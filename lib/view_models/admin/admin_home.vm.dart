import 'package:stacked/stacked.dart';
import 'package:webapp/utils/performance_trace.dart';

enum AdminSection {
  dashboard('Dashboard'),
  bookings('Bookings'),
  vehicles('Vehicles'),
  settings('Flows'),
  users('Users'),
  access('Roles'),
  support('Support'),
  profile('Profile'),
  analytics('Analytics');

  const AdminSection(this.title);

  final String title;
}

enum AdminSettingsSection {
  statuses('Statuses'),
  forms('Forms'),
  fields('Fields');

  const AdminSettingsSection(this.title);

  final String title;
}

enum AdminVehiclesSection {
  makes('Makes'),
  types('Types'),
  sizes('Sizes'),
  chassis('Chassis');

  const AdminVehiclesSection(this.title);

  final String title;
}

class AdminHomeViewModel extends BaseViewModel {
  bool showDrawer = true;
  AdminSection selectedSection = AdminSection.dashboard;
  AdminSettingsSection selectedSettingsSection = AdminSettingsSection.statuses;
  AdminVehiclesSection selectedVehiclesSection = AdminVehiclesSection.makes;
  bool isSettingsExpanded = false;
  bool isVehiclesExpanded = false;
  String? pendingEditUserId;

  void toggleDrawer() {
    showDrawer = !showDrawer;
    notifyListeners();
  }

  void selectSection(AdminSection section) {
    if (selectedSection == section) {
      PerformanceTrace.event(
        'admin-nav',
        'select ignored section=${section.name}',
      );
      return;
    }
    PerformanceTrace.event(
      'admin-nav',
      'select from=${selectedSection.name} to=${section.name}',
    );
    selectedSection = section;
    notifyListeners();
  }

  void openUsersForEdit(String? userId) {
    pendingEditUserId = userId;
    selectedSection = AdminSection.users;
    notifyListeners();
  }

  void clearPendingEditUser() {
    if (pendingEditUserId == null) {
      return;
    }
    pendingEditUserId = null;
    notifyListeners();
  }

  void toggleSettingsExpanded() {
    isSettingsExpanded = !isSettingsExpanded;
    notifyListeners();
  }

  void toggleVehiclesExpanded() {
    isVehiclesExpanded = !isVehiclesExpanded;
    notifyListeners();
  }

  void selectSettingsSection(AdminSettingsSection section) {
    PerformanceTrace.event('admin-nav', 'select flow section=${section.name}');
    selectedSection = AdminSection.settings;
    selectedSettingsSection = section;
    isSettingsExpanded = true;
    notifyListeners();
  }

  void selectVehiclesSection(AdminVehiclesSection section) {
    PerformanceTrace.event(
      'admin-nav',
      'select vehicle section=${section.name}',
    );
    selectedSection = AdminSection.vehicles;
    selectedVehiclesSection = section;
    isVehiclesExpanded = true;
    notifyListeners();
  }
}
