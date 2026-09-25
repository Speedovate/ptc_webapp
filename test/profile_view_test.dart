import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/views/shared/profile_view.dart';

class _MakesRepository implements VehicleCatalogRepository {
  _MakesRepository(this.makes);

  final List<VehicleMake> makes;

  @override
  Future<List<VehicleMake>> getMakes() async => makes;

  @override
  Future<List<VehicleCatalogItem>> getSizes() async => const [];

  @override
  Future<List<VehicleCatalogItem>> getTypes() async => const [];

  @override
  Future<VehicleMake> saveMake(VehicleMake make) async => make;

  @override
  Future<void> deleteMake(String makeId) async {}

  @override
  Future<VehicleCatalogItem> saveSize(VehicleCatalogItem size) async => size;

  @override
  Future<void> deleteSize(String sizeId) async {}

  @override
  Future<VehicleCatalogItem> saveType(VehicleCatalogItem type) async => type;

  @override
  Future<void> deleteType(String typeId) async {}
}

Widget _profile(UserModel user, VehicleCatalogRepository repository) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfileView(
            user: user,
            scrollable: false,
            padding: EdgeInsets.zero,
            vehicleCatalogRepository: repository,
            showKpiSummary: false,
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => RoleAccessService.instance.setCurrentUser(null));

  testWidgets('driver profile shows every assigned vehicle make and type', (
    tester,
  ) async {
    const user = DriverModel(
      id: 'profile-driver-1',
      role: 'driver',
      name: 'Driver One',
    );
    final repository = _MakesRepository([
      const VehicleMake(
        id: 'make-a',
        code: 'TRUCK-A',
        type: VehicleCatalogItem(id: 'type-a', name: '6-Wheeler'),
        driver: UserModel(id: 'profile-driver-1'),
      ),
      const VehicleMake(
        id: 'make-b',
        code: 'TRUCK-B',
        type: VehicleCatalogItem(id: 'type-b', name: '10-Wheeler'),
        driver: UserModel(id: 'profile-driver-1'),
      ),
      const VehicleMake(
        id: 'inactive',
        code: 'INACTIVE',
        isActive: false,
        driver: UserModel(id: 'profile-driver-1'),
      ),
      const VehicleMake(
        id: 'other',
        code: 'OTHER',
        driver: UserModel(id: 'someone-else'),
      ),
    ]);

    await tester.pumpWidget(_profile(user, repository));
    await tester.pumpAndSettle();

    expect(find.text('Vehicle assignment'), findsOneWidget);
    expect(find.textContaining('TRUCK-A'), findsOneWidget);
    expect(find.textContaining('TRUCK-B'), findsOneWidget);
    expect(find.textContaining('6-Wheeler'), findsOneWidget);
    expect(find.textContaining('10-Wheeler'), findsOneWidget);
    expect(find.text('INACTIVE'), findsNothing);
    expect(find.text('OTHER'), findsNothing);
  });

  testWidgets('helper profile resolves assignment through helper reference', (
    tester,
  ) async {
    const user = UserModel(
      id: 'profile-helper-1',
      role: 'helper',
      name: 'Helper One',
    );
    final repository = _MakesRepository([
      const VehicleMake(
        id: 'helper-make',
        code: 'HELPER-TRUCK',
        type: VehicleCatalogItem(id: 'type-h', name: 'Mitsubishi Canter'),
        driver: UserModel(id: 'another-driver'),
        helper: user,
      ),
      const VehicleMake(
        id: 'helper-other',
        code: 'NOT-MINE',
        helper: UserModel(id: 'another-helper'),
      ),
    ]);

    await tester.pumpWidget(_profile(user, repository));
    await tester.pumpAndSettle();

    expect(find.text('Vehicle make code'), findsOneWidget);
    expect(find.text('HELPER-TRUCK'), findsOneWidget);
    expect(find.text('Mitsubishi Canter'), findsOneWidget);
    expect(find.text('NOT-MINE'), findsNothing);
  });
}
