import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/investor_reporting_scope.dart';

void main() {
  final investor = UserModel(id: '30', role: 'investor');
  final own = UserModel(id: '40', role: 'driver', parentClientId: '30');
  final other = UserModel(id: '41', role: 'helper', parentClientId: '31');
  test(
    'investor reports include own crew and reject other/mixed/unresolved crew',
    () {
      final scope = InvestorReportingScope(investor, [own, other]);
      expect(scope.booking(Booking(driver: own)), true);
      expect(scope.booking(Booking(driver: own, helper: other)), false);
      expect(scope.booking(Booking(helper: other)), false);
      expect(scope.booking(const Booking()), false);
      expect(scope.booking(Booking(driver: UserModel(id: '99'))), false);
      expect(scope.make(VehicleMake(driver: own)), true);
      expect(scope.make(VehicleMake(driver: own, helper: other)), false);
    },
  );
  test(
    'refreshed ownership overrides stale embedded crew and office is unchanged',
    () {
      final scope = InvestorReportingScope(investor, [
        UserModel(id: '40', role: 'driver', parentClientId: '31'),
      ]);
      expect(scope.booking(Booking(driver: own)), false);
      final admin = InvestorReportingScope(UserModel(role: 'admin'), []);
      expect(admin.booking(Booking(driver: other)), true);
      expect(admin.make(VehicleMake(driver: other)), true);
    },
  );
}
