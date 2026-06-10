import 'package:stacked/stacked.dart';

enum AdminSection {
  dashboard('Dashboard'),
  bookings('Bookings'),
  vehicles('Vehicles'),
  settings('Settings'),
  users('Users'),
  profile('Profile');

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
  sizes('Sizes');

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
      return;
    }

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
    selectedSection = AdminSection.settings;
    selectedSettingsSection = section;
    isSettingsExpanded = true;
    notifyListeners();
  }

  void selectVehiclesSection(AdminVehiclesSection section) {
    selectedSection = AdminSection.vehicles;
    selectedVehiclesSection = section;
    isVehiclesExpanded = true;
    notifyListeners();
  }
}
