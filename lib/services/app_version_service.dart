import 'package:package_info_plus/package_info_plus.dart';

class AppVersionService {
  AppVersionService._();

  static final Future<String> sidebarVersionLabel = _loadSidebarVersionLabel();

  static Future<String> _loadSidebarVersionLabel() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version.trim();
    final buildNumber = packageInfo.buildNumber.trim();

    if (version.isEmpty && buildNumber.isEmpty) {
      return 'Version';
    }
    if (buildNumber.isEmpty) {
      return 'Version $version';
    }
    if (version.isEmpty) {
      return 'Version ($buildNumber)';
    }
    return 'Version $version ($buildNumber)';
  }
}
