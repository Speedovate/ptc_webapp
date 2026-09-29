import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/utils/functions.dart';

class InvestorReportingScope {
  InvestorReportingScope(this.viewer, Iterable<UserModel> users)
    : users = {
        for (final user in users)
          if (normalizeId(user.id) != null) normalizeId(user.id)!: user,
      };
  final UserModel? viewer;
  final Map<String, UserModel> users;
  bool get scoped => normalizeRoleKey(viewer?.role) == 'investor';
  bool _crew(UserModel? driver, UserModel? helper) {
    if (!scoped) return true;
    final owner = normalizeId(viewer?.id);
    final crew = [
      driver,
      helper,
    ].where((u) => normalizeId(u?.id) != null).toList();
    return owner != null &&
        crew.isNotEmpty &&
        crew.every((u) {
          final resolved = users[normalizeId(u?.id)] ?? u;
          return const {
                'driver',
                'helper',
              }.contains(normalizeRoleKey(resolved?.role)) &&
              normalizeId(resolved?.parentClientId) == owner;
        });
  }

  bool booking(Booking booking) => _crew(booking.driver, booking.helper);
  bool make(VehicleMake make) => _crew(make.driver, make.helper);
}
