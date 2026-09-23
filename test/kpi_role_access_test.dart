import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/kpi/operations_catalog_store.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/services/role_access_service.dart';

const operationsCapabilities = [
  DispatcherAccessCapability.pmKpiRead,
  DispatcherAccessCapability.pmKpiUpdate,
  DispatcherAccessCapability.fuelLedgerRead,
  DispatcherAccessCapability.fuelLedgerUpdate,
  DispatcherAccessCapability.tripIncomeRead,
  DispatcherAccessCapability.operationsCatalogRead,
  DispatcherAccessCapability.operationsCatalogUpdate,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => RoleAccessService.instance.setCurrentUser(null));
  test(
    'new capabilities default only to admin, including legacy documents',
    () {
      for (final role in [...builtInRoleKeys, 'custom-role']) {
        final config = DispatcherAccessConfig.fromMap({
          'role': role,
          'capabilities': {
            'vehicle_makes.read': true,
            'vehicle_makes.update': true,
          },
        });
        for (final capability in operationsCapabilities) {
          expect(
            config.isEnabled(capability),
            role == 'admin',
            reason: '$role $capability',
          );
        }
        expect(
          config.isEnabled(DispatcherAccessCapability.vehicleMakesUpdate),
          isTrue,
        );
        RoleAccessService.instance.setCurrentUser(
          UserModel(id: 'test', role: role),
        );
        final store = PmKpiStore();
        expect(store.canRead, role == 'admin');
        expect(store.canEdit, role == 'admin');
        expect(store.canReadFuel, role == 'admin');
        expect(store.canEditFuel, role == 'admin');
        expect(store.canReadIncome, role == 'admin');
        expect(OperationsCatalogStore().canEdit, role == 'admin');
      }
    },
  );
  test(
    'explicit role overrides survive fresh persistent cache instance',
    () async {
      SharedPreferences.setMockInitialValues({});
      final config = DispatcherAccessConfig.defaults(roleKey: 'manager');
      final changed = config.copyWith(
        capabilities: {
          ...config.capabilities,
          for (final capability in operationsCapabilities) capability: true,
          DispatcherAccessCapability.fuelLedgerUpdate: false,
        },
      );
      final cache = FirestoreCacheStore();
      await cache.writeDocumentMaps('kpi-role-access-test', [changed.toMap()]);
      final restored = DispatcherAccessConfig.fromMap(
        (await FirestoreCacheStore().readDocumentMaps(
          'kpi-role-access-test',
        ))!.single,
      );
      expect(restored.isEnabled(DispatcherAccessCapability.pmKpiRead), isTrue);
      expect(
        restored.isEnabled(DispatcherAccessCapability.operationsCatalogUpdate),
        isTrue,
      );
      expect(
        restored.isEnabled(DispatcherAccessCapability.fuelLedgerUpdate),
        isFalse,
      );
      expect(
        restored.isEnabled(DispatcherAccessCapability.bookingsRead),
        isTrue,
      );
    },
  );
  test('non-admin direct settings and ledger mutations are denied', () async {
    RoleAccessService.instance.setCurrentUser(
      const UserModel(id: 'm', role: 'manager'),
    );
    final store = PmKpiStore(accountProvider: () async => 'm');
    await expectLater(
      store.saveFuel(
        makeId: '4',
        data: {'day': '2026-01-01', 'amount': 100},
        previous: {},
      ),
      throwsStateError,
    );
    await expectLater(
      OperationsCatalogStore(owner: () async => 'm').save({}, {}),
      throwsStateError,
    );
  });
}
