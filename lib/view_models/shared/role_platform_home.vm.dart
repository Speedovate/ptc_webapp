import 'package:stacked/stacked.dart';

enum RolePlatformSection {
  home('Home'),
  history('History'),
  members('Members'),
  support('Support'),
  profile('Profile');

  const RolePlatformSection(this.title);

  final String title;
}

class RolePlatformHomeViewModel extends BaseViewModel {
  bool showDrawer = true;
  RolePlatformSection selectedSection = RolePlatformSection.home;

  void toggleDrawer() {
    showDrawer = !showDrawer;
    notifyListeners();
  }

  void selectSection(RolePlatformSection section) {
    if (selectedSection == section) {
      return;
    }
    selectedSection = section;
    notifyListeners();
  }
}
