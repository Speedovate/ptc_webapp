import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/services/kpi/operations_catalog_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'pm_kpi_queue_test.dart' show MemoryStorage;

class SlowCatalog extends OperationsCatalogStore {
  final gate = Completer<OperationsCatalog>();
  bool started = false;
  @override
  Future<OperationsCatalog> load({bool force = false}) {
    started = true;
    return gate.future;
  }
}

class Store extends PmKpiStore {
  Store(SlowCatalog catalog, FakeFirebaseFirestore db)
    : super(
        firestore: db,
        cache: FirestoreCacheStore(),
        catalogStore: catalog,
        accountProvider: () async => 'test',
        online: () => false,
        queue: OfflineMutationQueueService(
          firestore: db,
          backend: MemoryStorage(),
          isOnline: () => false,
        ),
      );
  final started = Completer<void>();
  final rules = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> loadFleetRules({bool localOnly = false}) {
    if (!started.isCompleted) started.complete();
    return rules.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'fleet rules start while catalog is pending; results remain joined',
    () async {
      SharedPreferences.setMockInitialValues({});
      final catalog = SlowCatalog();
      final store = Store(catalog, FakeFirebaseFirestore());
      final load = store.load('1', KpiPeriod.month(2026, 10));
      await store.started.future.timeout(const Duration(seconds: 2));
      expect(catalog.started, true);
      expect(catalog.gate.isCompleted, false);
      store.rules.complete({
        'rating_rules': {'target_percent': 45},
      });
      catalog.gate.complete(const OperationsCatalog({}));
      final result = await load;
      expect(result.settings['rating_rules']['target_percent'], 45);
      expect(result.records, isEmpty);
      expect(result.fromCache, true);
    },
  );
}
