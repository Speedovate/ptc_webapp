import 'dart:async';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/kpi/operations_catalog_store.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/views/admin/operations_catalog_dialog.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'pm_kpi_queue_test.dart' show MemoryStorage;

class AllowedCatalog extends OperationsCatalogStore {
  AllowedCatalog(
    FakeFirebaseFirestore superArgsDb,
    OfflineMutationQueueService superArgsQueue,
    bool Function() online,
  ) : super(
        firestore: superArgsDb,
        queue: superArgsQueue,
        cache: FirestoreCacheStore(),
        owner: () async => 'manager',
        editPermission: () => true,
        online: online,
      );
  @override
  bool get canRead => true;
}

// Drive retries explicitly in widget tests; use the real save/replay methods.
class ManualQueue extends OfflineMutationQueueService {
  ManualQueue({
    required super.firestore,
    required super.backend,
    required super.isOnline,
  });
  @override
  Future<void> initialize() async {}
}

class HeldCache extends FirestoreCacheStore {
  bool hold = false;
  final captured = Completer<void>();
  final release = Completer<void>();
  @override
  Future<List<Map<String, dynamic>>?> readDocumentMaps(String key) async {
    final result = await super.readDocumentMaps(key);
    if (hold) {
      hold = false;
      captured.complete();
      await release.future;
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'late cached refresh cannot undo a successfully saved activation',
    () async {
      SharedPreferences.setMockInitialValues({});
      final auth = createAuthStorageBackend();
      await auth.initialize();
      await auth.writeString('paltranco_current_user_id', 'manager');
      final db = FakeFirebaseFirestore();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryStorage(),
        isOnline: () => true,
      );
      final cache = HeldCache();
      final store = OperationsCatalogStore(
        firestore: db,
        queue: queue,
        cache: cache,
        owner: () async => 'manager',
        editPermission: () => true,
        online: () => false,
      );
      await store.save({}, {});
      final previous = store.current;
      cache.hold = true;
      final refresh = store.load(force: true);
      await cache.captured.future;
      final matrix = previous.matrixFor(kpiDate(DateTime.now()));
      final next = {
        ...previous.withLocations([
          for (final l in previous.locations)
            l.name == 'San Manuel' ? l.copyActive(false) : l,
        ]),
        'matrix_versions': [
          TripMatrixVersion(
            id: 'new-version',
            effectiveFrom: kpiDate(DateTime.now()),
            rates: [
              for (final r in matrix.rates)
                r.name == 'San Manuel'
                    ? KpiRate(r.name, r.driver, r.helper, active: false)
                    : r,
            ],
          ).toMap(),
        ],
      };
      await store.save(next, previous.document);
      cache.release.complete();
      await refresh;
      expect(
        store.current.locations
            .firstWhere((l) => l.name == 'San Manuel')
            .active,
        false,
      );
    },
  );
  for (final initiallyOnline in [true, false]) {
    testWidgets('rate toggles persist and restore online=$initiallyOnline', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final auth = createAuthStorageBackend();
      await auth.initialize();
      await auth.writeString('paltranco_current_user_id', 'manager');
      final db = FakeFirebaseFirestore();
      var online = initiallyOnline;
      final queue = ManualQueue(
        firestore: db,
        backend: MemoryStorage(),
        isOnline: () => online,
      );
      final store = AllowedCatalog(db, queue, () => online);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OperationsCatalogDialog(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> toggle(String expected) async {
        final list = tester.widget<AdminModalRecordList>(
          find.byType(AdminModalRecordList),
        );
        final i = List.generate(
          list.itemCount,
          (i) => i,
        ).firstWhere((i) => list.valuesAt(i).first == 'San Manuel');
        final action =
            ((list.cellBuilder!(i, 6) as Row).children.last as Tooltip).child
                as AdminListActionButton;
        expect(action.onTap, isNotNull);
        action.onTap!();
        await tester.pumpAndSettle();
        final updated = tester.widget<AdminModalRecordList>(
          find.byType(AdminModalRecordList),
        );
        final j = List.generate(
          updated.itemCount,
          (i) => i,
        ).firstWhere((i) => updated.valuesAt(i).first == 'San Manuel');
        expect(updated.valuesAt(j)[5], expected);
      }

      await toggle('Inactive');
      await toggle('Active');
      await toggle('Inactive');
      online = true;
      await queue.flushPendingMutations();
      final reopened = AllowedCatalog(db, queue, () => online);
      final value = await reopened.load(force: true);
      final location = value.locations.firstWhere(
        (l) => l.name == 'San Manuel',
      );
      expect(location.active, false);
      expect(
        value
            .matrixFor(kpiDate(DateTime.now()))
            .rates
            .firstWhere((r) => r.name == 'San Manuel')
            .active,
        false,
      );
      expect(
        (await db.collection('operations_catalog').doc('settings').get())
            .exists,
        true,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
