import 'package:webapp/services/kpi/kpi_rating_rules.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/kpi/operations_catalog_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'pm_kpi_queue_test.dart' show MemoryStorage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.writeString('paltranco_current_user_id', 'manager');
  });
  test(
    'offline KPI, fuel and rates survive fresh stores then sync original values',
    () async {
      var online = false;
      final db = FakeFirebaseFirestore();
      final backend = MemoryStorage();
      OfflineMutationQueueService queue() => OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      OperationsCatalogStore catalog(OfflineMutationQueueService q) =>
          OperationsCatalogStore(
            firestore: db,
            queue: q,
            cache: FirestoreCacheStore(),
            owner: () async => 'manager',
            editPermission: () => true,
            online: () => online,
          );
      PmKpiStore store(OfflineMutationQueueService q) => PmKpiStore(
        firestore: db,
        queue: q,
        cache: FirestoreCacheStore(),
        accountProvider: () async => 'manager',
        editPermission: () => true,
        catalogStore: catalog(q),
        online: () => online,
      );
      final firstQueue = queue();
      final first = store(firstQueue);
      await first.saveFuel(
        makeId: '4',
        data: {
          'day': '2026-09-01',
          'amount': 200,
          'liters': 4,
          'price_per_liter': 50,
          'reference': 'PO-1',
        },
        previous: {},
      );
      final fuelOnly = await store(
        queue(),
      ).readCached('4', KpiPeriod.month(2026, 9));
      expect(fuelOnly, isNotNull);
      expect(fuelOnly!.fuel.single['liters'], 4);
      await first.save(
        makeId: '4',
        data: {
          'kind': 'settings',
          'rating_rules': {'target_percent': 40},
          'user_incident_counts': {
            '13': {
              '2026-09-01': {'complaints': 1},
            },
          },
        },
        previous: {},
      );
      await first.save(
        makeId: '4',
        data: {
          'day': '2026-09-01',
          'driver_salary': 455,
          'helper_salary': 455,
          'salary_confirmed': true,
        },
        previous: {},
      );
      await catalog(firstQueue).save({
        'locations': [],
        'matrix_versions': [],
        'pay_rules': {'daily': 455},
      }, {});
      final restoredQueue = queue();
      final restored = await store(
        restoredQueue,
      ).readCached('4', KpiPeriod.month(2026, 9));
      expect(restored!.settings['rating_rules']['target_percent'], 40);
      expect(
        restored
            .settings['user_incident_counts']['13']['2026-09-01']['complaints'],
        1,
      );
      expect(restored.records.single['driver_salary'], 455);
      expect(restored.fuel.single['amount'], 200);
      expect(
        (await catalog(
          restoredQueue,
        ).readCached())!.document['pay_rules']['daily'],
        455,
      );
      final actionTime = restored.settings['updated_at'];
      await first.saveFleetRules(const KpiRatingRules(targetPercent: 35), {});
      await first.save(
        makeId: '2',
        data: {
          'kind': 'settings',
          'rating_rules': {'target_percent': 55},
        },
        previous: {},
      );
      for (final pm in ['4', '2']) {
        final data = await store(
          queue(),
        ).readCached(pm, KpiPeriod.month(2026, 9));
        expect(data!.settings['rating_rules']['target_percent'], 35);
      }
      final fleetActionTime = (await store(
        queue(),
      ).loadFleetRules(localOnly: true))['updated_at'];
      online = true;
      await restoredQueue.flushPendingMutations();
      await restoredQueue.flushPendingMutations();
      expect(await restoredQueue.readPendingItems('manager'), isEmpty);
      final settings =
          (await db.collection('pm_kpi_records').doc('NA_settings').get())
              .data()!;
      expect(settings['updated_at'], actionTime);
      expect(
        settings['rating_rules']['target_percent'],
        40,
      ); // Legacy PM document preserved.
      final shared =
          (await db.collection('pm_kpi_records').doc('ZmxlZXQ_settings').get())
              .data()!;
      expect(shared['rating_rules']['target_percent'], 35);
      expect(shared['updated_at'], fleetActionTime);
      expect((await db.collection('pm_fuel_entries').get()).docs, hasLength(1));
      expect(
        (await db.collection('operations_catalog').doc('settings').get())
            .exists,
        isTrue,
      );
    },
  );
  test(
    'cached catalog restores without claiming a server refresh or sharing accounts',
    () async {
      var owner = 'manager';
      final db = FakeFirebaseFirestore();
      final cache = FirestoreCacheStore();
      await cache.writeDocumentMaps('operations_catalog:manager', [
        {
          'pay_rules': {'daily': 455},
        },
      ]);
      await db.collection('operations_catalog').doc('settings').set({
        'pay_rules': {'daily': 500},
      });
      final q = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryStorage(),
        isOnline: () => false,
      );
      final store = OperationsCatalogStore(
        firestore: db,
        cache: FirestoreCacheStore(),
        queue: q,
        owner: () async => owner,
        online: () => true,
      );
      expect((await store.readCached())!.document['pay_rules']['daily'], 455);
      expect((await store.load()).document['pay_rules']['daily'], 500);
      owner = 'another-user';
      expect(await store.readCached(), isNull);
    },
  );
}
