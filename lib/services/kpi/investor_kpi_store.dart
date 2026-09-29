import 'package:webapp/models/user.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/services/investor_reporting_scope.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';

/// Reuses the regular account-scoped persistence and permission checks.
class InvestorKpiStore extends PmKpiStore {
  InvestorKpiStore(this.viewer);
  final UserModel viewer;
  InvestorReportingScope get scope =>
      InvestorReportingScope(viewer, AuthRequest.hydratedUsersSnapshot);
  @override
  List<VehicleMake> get makes => super.makes.where(scope.make).toList();
  @override
  Future<List<VehicleMake>> exportMakes() async {
    await AuthRequest.instance.getUsers();
    return (await super.exportMakes()).where(scope.make).toList();
  }

  @override
  List<Booking>? get cachedBookings =>
      super.cachedBookings?.where(scope.booking).toList();
  @override
  Future<List<Booking>> bookings() async =>
      (await super.bookings()).where(scope.booking).toList();
  @override
  Stream<List<Booking>> watchBookings() =>
      super.watchBookings().map((rows) => rows.where(scope.booking).toList());
  @override
  List<UserModel> get incidentUsers => super.incidentUsers
      .where((user) => user.parentClientId == viewer.id)
      .toList();
}
