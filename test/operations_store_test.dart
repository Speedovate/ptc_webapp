import 'dart:convert';
import 'package:webapp/models/booking.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/kpi/location_option_registry.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/services/kpi/operations_catalog_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';

const boxedError =
    'Dart exception thrown from converted Future. '
    "Use the properties 'error' to fetch the boxed error and 'stack' to recover the stack trace.";

class BoxingFirestore extends FakeFirebaseFirestore {
  Completer<void>? transactionStarted;
  Completer<void>? resumeTransaction;
  bool failBeforeCallback = false;
  int transactionCalls = 0;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactionCalls++;
    final started = transactionStarted;
    final resume = resumeTransaction;
    transactionStarted = null;
    resumeTransaction = null;
    started?.complete();
    if (resume != null) {
      await resume.future;
    }
    if (failBeforeCallback) {
      throw StateError(boxedError);
    }
    try {
      return await super.runTransaction(
        transactionHandler,
        timeout: timeout,
        maxAttempts: maxAttempts,
      );
    } catch (_) {
      // Reproduce Flutter Web obscuring a Dart callback failure.
      throw StateError(boxedError);
    }
  }
}

class MemoryQueue implements BookingStorageBackend {
  final values = <String, List<String>>{};
  @override
  Future<void> initialize() async {}
  @override
  Future<List<String>> readStringList(String key) async => [...?values[key]];
  @override
  Future<void> writeStringList(String key, List<String> items) async {
    values[key] = [...items];
  }
}

class MemoryCache extends FirestoreCacheStore {
  final values = <String, List<Map<String, dynamic>>>{};
  @override
  Future<List<Map<String, dynamic>>?> readDocumentMaps(String key) async =>
      values[key]?.map((r) => {...r}).toList();
  @override
  Future<void> writeDocumentMaps(
    String key,
    List<Map<String, dynamic>> documents,
  ) async {
    values[key] = documents.map((r) => {...r}).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BoxingFirestore db;
  late MemoryQueue backend;
  late OfflineMutationQueueService queue;
  late OperationsCatalogStore catalog;
  late PmKpiStore store;
  late MemoryCache cache;
  late bool online;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.writeString('paltranco_current_user_id', 'manager');
    await auth.remove('paltranco_known_session_user_ids');
    db = BoxingFirestore();
    backend = MemoryQueue();
    online = false;
    cache = MemoryCache();
    queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => online,
    );
    catalog = OperationsCatalogStore(
      firestore: db,
      queue: queue,
      cache: cache,
      owner: () async => 'manager',
      editPermission: () => true,
      online: () => online,
    );
    store = PmKpiStore(
      firestore: db,
      queue: queue,
      cache: cache,
      accountProvider: () async => 'manager',
      editPermission: () => true,
      catalogStore: catalog,
      online: () => online,
    );
  });
  tearDown(() async {
    LocationOptionRegistry.apply({}, {});
    await createAuthStorageBackend().remove('paltranco_current_user_id');
  });
  test(
    'repeated offline fuel import keeps one stable record and source date',
    () async {
      final data = <String, dynamic>{
        'day': '2026-01-02',
        'amount': 1100,
        'liters': 20,
        'import_key': 'source_A',
        'reference': 'PO123',
      };
      await store.saveFuel(makeId: '4', data: data, previous: {});
      await store.saveFuel(makeId: '4', data: data, previous: {});
      final pending = await queue.readQueuedCollectionDocuments(
        collectionKey: 'pm_fuel_entries',
      );
      expect(pending, hasLength(1));
      expect(pending.single['id'], 'NA_2026-01-02_import_source_A');
      expect(pending.single['day'], '2026-01-02');
      online = true;
      await queue.flushPendingMutations();
      expect((await db.collection('pm_fuel_entries').get()).docs, hasLength(1));
    },
  );
  test(
    'saved City Proper dropoff becomes a shared offline rate once',
    () async {
      final booking = Booking(
        id: '12',
        deliveredAt: DateTime.utc(2026, 9, 2, 4),
        statusOutputs: {
          'pending': {
            'fields': {
              'destination': 'Puerto Princesa City',
              'destination_barangay': 'Tiniguiban',
            },
          },
        },
      );
      final trip = KpiTrip(booking, kpiDate(kpiDeliveredAt(booking)!));
      final stored = KpiStoredData(
        [
          {
            'trip_rates': [
              {'signature': trip.signature, 'route': 'City Proper'},
            ],
          },
        ],
        {},
        true,
      );
      final learned = await store.learnCityProperDropoffs([booking], stored);
      final rate = matchKpiTripRate(
        trip,
        learned.catalog.matrixFor(trip.day).rates,
      ).rate;
      expect(rate?.name, 'Tiniguiban');
      expect(rate?.driver, 100);
      expect(rate?.helper, 50);
      expect(rate?.usesCityPremium, true);
      expect(
        learned.catalog.options['destination_barangay'],
        contains('Tiniguiban'),
      );
      final before = await queue.readPendingItems('manager');
      await store.learnCityProperDropoffs([booking], learned);
      expect((await queue.readPendingItems('manager')).length, before.length);
      expect(
        learned.catalog
            .matrixFor(trip.day)
            .rates
            .singleWhere((r) => r.name == 'Roxas')
            .driver,
        600,
      );
    },
  );
  test(
    'KPI cache reuse and explicit refresh preserve local-first reads',
    () async {
      online = true;
      final period = KpiPeriod.month(2026, 9);
      final ref = db.collection('pm_kpi_records').doc('NA_settings');
      await ref.set({'marker': 'first'});
      expect((await store.load('4', period)).settings['marker'], 'first');
      await ref.set({'marker': 'remote update'});
      expect(
        (await store.readCached('4', period))!.settings['marker'],
        'first',
      );
      expect((await store.load('4', period)).settings['marker'], 'first');
      store.invalidateRefreshWindow();
      expect(
        (await store.load('4', period)).settings['marker'],
        'remote update',
      );
      expect(await store.readCached('other-pm', period), isNull);
    },
  );
  test(
    'fresh stores restore persisted catalog and fuel while offline',
    () async {
      final persistent = FirestoreCacheStore();
      final writerCatalog = OperationsCatalogStore(
        firestore: db,
        queue: queue,
        cache: persistent,
        owner: () async => 'manager',
        editPermission: () => true,
        online: () => false,
      );
      await writerCatalog.save(
        const OperationsCatalog({}).changeOptions('origin', ['Persisted port']),
        {},
      );
      final writer = PmKpiStore(
        firestore: db,
        queue: queue,
        cache: persistent,
        accountProvider: () async => 'manager',
        editPermission: () => true,
        catalogStore: writerCatalog,
        online: () => false,
      );
      await writer.saveFuel(
        makeId: '4',
        data: {'day': '2026-01-02', 'amount': 1234},
        previous: {},
      );
      // Flush the queue so reopening cannot obtain the values from its overlay.
      online = true;
      await queue.flushPendingMutations();
      online = false;
      final readerCatalog = OperationsCatalogStore(
        firestore: db,
        queue: queue,
        cache: FirestoreCacheStore(),
        owner: () async => 'manager',
        online: () => false,
      );
      final reader = PmKpiStore(
        firestore: db,
        queue: queue,
        cache: FirestoreCacheStore(),
        accountProvider: () async => 'manager',
        catalogStore: readerCatalog,
        online: () => false,
      );
      final loaded = await reader.load('4', KpiPeriod.month(2026, 1));
      expect(loaded.fromCache, isTrue);
      expect(
        loaded.catalog.locations.map((l) => l.name),
        contains('Persisted port'),
      );
      expect(loaded.catalog.options['origin'], isEmpty);
      expect(loaded.fuel.single['amount'], 1234);
      final otherCatalog = OperationsCatalogStore(
        firestore: db,
        queue: queue,
        cache: FirestoreCacheStore(),
        owner: () async => 'other',
        online: () => false,
      );
      await otherCatalog.restore();
      expect(otherCatalog.current.options['origin'], isNot(['Persisted port']));
    },
  );
  test(
    'catalog versions and settings publish atomically; immutable history survives refresh',
    () async {
      final base = await catalog.load();
      final version = TripMatrixVersion(
        id: 'v1',
        effectiveFrom: DateTime.utc(2026, 10),
        rates: const [KpiRate('New route', 300, 150)],
      );
      await catalog.save({
        ...base.changeOptions('origin', ['New origin']),
        'matrix_versions': [version.toMap()],
      }, base.document);
      expect(
        (await catalog.load(force: true)).locations.map((l) => l.name),
        contains('New origin'),
      );
      expect(catalog.current.options['origin'], isEmpty);
      expect((await db.collection('operations_catalog').get()).docs, isEmpty);
      online = true;
      await queue.flushPendingMutations();
      final settings =
          (await db.collection('operations_catalog').doc('settings').get())
              .data()!;
      expect(settings['matrix_versions'], isNull);
      expect(settings['matrix_version_ids'], ['v1']);
      expect(
        (await db.collection('operations_catalog').doc('matrix_v1').get())
            .data(),
        version.toMap(),
      );
      final loaded = await catalog.load(force: true);
      expect(loaded.matrixFor(DateTime.utc(2026, 10)).rates.single.driver, 300);
      expect(loaded.locations.map((l) => l.name), contains('New origin'));
      expect(loaded.options['origin'], isEmpty);
      expect(await queue.readPendingItems('manager'), isEmpty);
    },
  );
  test(
    'a second catalog save during sync follows its own committed predecessor',
    () async {
      const base = {'updated_at': '2026-09-19T17:31:05.969Z'};
      await db.collection('operations_catalog').doc('settings').set(base);
      await catalog.save({'change': 'first'}, base);
      final started = Completer<void>();
      final resume = Completer<void>();
      db.transactionStarted = started;
      db.resumeTransaction = resume;
      online = true;
      final syncing = queue.flushPendingMutations();
      await started.future;
      await catalog.save({'change': 'second'}, catalog.current.document);
      resume.complete();
      await syncing;
      await queue.flushPendingMutations();
      expect(await queue.readPendingItems('manager'), isEmpty);
      expect(
        (await db.collection('operations_catalog').doc('settings').get())
            .data()!['change'],
        'second',
      );
    },
  );
  test(
    'rebasing an in-flight catalog successor still protects a later remote edit',
    () async {
      const base = {'updated_at': '2026-09-19T17:31:05.969Z'};
      await db.collection('operations_catalog').doc('settings').set(base);
      await catalog.save({'change': 'first'}, base);
      final started = Completer<void>();
      final resume = Completer<void>();
      db.transactionStarted = started;
      db.resumeTransaction = resume;
      online = true;
      final syncing = queue.flushPendingMutations();
      await started.future;
      await catalog.save({'change': 'second'}, catalog.current.document);
      await catalog.save({'change': 'third'}, catalog.current.document);
      resume.complete();
      await syncing;
      await db.collection('operations_catalog').doc('settings').set({
        'change': 'another device',
        'updated_at': '2099-01-01T00:00:00Z',
      });
      await queue.flushPendingMutations();
      expect(
        (await queue.readPendingItems('manager')).single.isBlocked,
        isTrue,
      );
      expect(
        (await db.collection('operations_catalog').doc('settings').get())
            .data()!['change'],
        'another device',
      );
    },
  );
  test(
    'successive offline rate edits publish every pending snapshot',
    () async {
      final first = TripMatrixVersion(
        id: 'first',
        effectiveFrom: DateTime.utc(2026, 10),
        rates: const [KpiRate('Narra', 600, 300)],
      );
      final second = TripMatrixVersion(
        id: 'second',
        effectiveFrom: DateTime.utc(2026, 11),
        rates: const [KpiRate('Narra', 700, 350)],
      );
      await catalog.save({
        'matrix_versions': [first.toMap()],
      }, {});
      final previous = catalog.current.document;
      await catalog.save({
        ...previous,
        'matrix_versions': [first.toMap(), second.toMap()],
      }, previous);
      online = true;
      await queue.flushPendingMutations();
      expect(await queue.readPendingItems('manager'), isEmpty);
      final loaded = await catalog.load(force: true);
      expect(
        loaded.matrixFor(DateTime.utc(2026, 10, 3)).rates.single.driver,
        600,
      );
      expect(
        loaded.matrixFor(DateTime.utc(2026, 11, 3)).rates.single.driver,
        700,
      );
      expect(
        (await db.collection('operations_catalog').get()).docs,
        hasLength(3),
      );
    },
  );
  test(
    'reviewed legacy conflict applies explicitly and retains server matrix history',
    () async {
      final serverVersion = TripMatrixVersion(
        id: 'server',
        effectiveFrom: DateTime.utc(2025),
        rates: const [KpiRate('Narra', 500, 250)],
      );
      final pendingVersion = TripMatrixVersion(
        id: 'pending',
        effectiveFrom: DateTime.utc(2026),
        rates: const [KpiRate('Narra', 600, 300)],
      );
      await db
          .collection('operations_catalog')
          .doc('matrix_server')
          .set(serverVersion.toMap());
      await db.collection('operations_catalog').doc('settings').set({
        'updated_at': '2026-09-20T07:46:59.085Z',
        'matrix_version_ids': ['server'],
      });
      await catalog.save(
        {
          'matrix_versions': [pendingVersion.toMap()],
        },
        {'updated_at': '2026-09-19T17:31:05.969Z'},
      );
      online = true;
      await queue.flushPendingMutations();
      final id = (await queue.readPendingItems('manager')).single.conflictId!;
      final review = await queue.reviewCatalogConflict(id);
      expect(
        review.proposed['matrix_version_ids'],
        containsAll(['server', 'pending']),
      );
      expect(
        (await queue.readPendingItems('manager')).single.isBlocked,
        isTrue,
      );
      await queue.applyReviewedCatalogConflict(review);
      expect(await queue.readPendingItems('manager'), isEmpty);
      expect(
        (await db.collection('operations_catalog').doc('settings').get())
            .data()!['matrix_version_ids'],
        containsAll(['server', 'pending']),
      );
      expect(
        (await db.collection('operations_catalog').doc('matrix_server').get())
            .data(),
        serverVersion.toMap(),
      );
    },
  );
  test(
    'reviewed conflict refuses a server change made after comparison',
    () async {
      await db.collection('operations_catalog').doc('settings').set({
        'updated_at': '2026-09-20T07:46:59.085Z',
      });
      await catalog.save(
        {'locations': []},
        {'updated_at': '2026-09-19T17:31:05.969Z'},
      );
      online = true;
      await queue.flushPendingMutations();
      final id = (await queue.readPendingItems('manager')).single.conflictId!;
      final review = await queue.reviewCatalogConflict(id);
      await db.collection('operations_catalog').doc('settings').update({
        'new_value': 'do not overwrite',
      });
      await expectLater(
        queue.applyReviewedCatalogConflict(review),
        throwsStateError,
      );
      expect(
        (await queue.readPendingItems('manager')).single.isBlocked,
        isTrue,
      );
      expect(
        (await db.collection('operations_catalog').doc('settings').get())
            .data()!['new_value'],
        'do not overwrite',
      );
    },
  );
  test('a stale matrix change cannot publish orphan/new rates', () async {
    await db.collection('operations_catalog').doc('settings').set({
      'updated_at': '2026-09-20T00:00:00Z',
      'matrix_version_ids': [],
    });
    final v = TripMatrixVersion(
      id: 'conflict',
      effectiveFrom: DateTime.utc(2026, 10),
      rates: const [KpiRate('Narra', 999, 999)],
    );
    await catalog.save(
      {
        'matrix_versions': [v.toMap()],
      },
      {'updated_at': '2026-09-01T00:00:00Z'},
    );
    online = true;
    await queue.flushPendingMutations();
    expect(
      (await db.collection('operations_catalog').doc('matrix_conflict').get())
          .exists,
      isFalse,
    );
    final item = (await queue.readPendingItems('manager')).single;
    expect(item.isBlocked, isTrue);
    expect(
      item.errorMessage,
      contains('operations_catalog/settings changed remotely'),
    );
    expect(item.errorMessage, contains('2026-09-01T00:00:00Z'));
    expect(item.errorMessage, isNot(contains('converted Future')));
    expect(item.diagnostics, contains('Raw error:\nBad state: Sync conflict:'));
    expect(item.diagnostics, contains('Target: operations_catalog/settings'));
    expect(item.diagnostics, contains('Stack trace:\n'));
    expect(item.diagnostics, contains('offline_mutation_queue_service.dart:'));
    final savedFailure = backend.values.values
        .expand((v) => v)
        .map((v) => jsonDecode(v) as Map<String, dynamic>)
        .firstWhere((v) => v['target_id'] == 'settings');
    expect(savedFailure['error_diagnostics'], item.diagnostics);
  });
  test(
    'old boxed catalog error rechecks once without clearing its base version',
    () async {
      await db.collection('operations_catalog').doc('settings').set({
        'updated_at': '2026-09-20T00:00:00Z',
        'protected': true,
      });
      await catalog.save(
        {'locations': []},
        {'updated_at': '2026-09-01T00:00:00Z'},
      );
      final key = backend.values.keys.singleWhere(
        (k) => k.startsWith('offline_mutation_queue_v1::'),
      );
      final entry =
          jsonDecode(backend.values[key]!.single) as Map<String, dynamic>;
      backend.values[key] = [
        jsonEncode({...entry, 'is_blocked': true, 'last_error': boxedError}),
      ];
      online = true;
      await queue.flushPendingMutations();
      final item = (await queue.readPendingItems('manager')).single;
      expect(item.errorMessage, contains('changed remotely'));
      expect(
        (await db.collection('operations_catalog').doc('settings').get())
            .data()!['protected'],
        isTrue,
      );
      final calls = db.transactionCalls;
      await queue.flushPendingMutations();
      expect(db.transactionCalls, calls);
      expect(
        jsonDecode(backend.values[key]!.single)['boxed_error_rechecked'],
        isTrue,
      );
    },
  );
  test(
    'a persistent boxed transport failure does not recheck indefinitely',
    () async {
      await catalog.save({'locations': []}, {});
      db.failBeforeCallback = true;
      online = true;
      await queue.flushPendingMutations();
      expect(
        (await queue.readPendingItems('manager')).single.isBlocked,
        isTrue,
      );
      await queue.flushPendingMutations();
      final calls = db.transactionCalls;
      await queue.flushPendingMutations();
      await queue.flushPendingMutations();
      expect(db.transactionCalls, calls);
      expect(
        (await db.collection('operations_catalog').doc('settings').get())
            .exists,
        isFalse,
      );
    },
  );
  test(
    'a recovered catalog action publishes its matrix and leaves the queue',
    () async {
      final version = TripMatrixVersion(
        id: 'recovered',
        effectiveFrom: DateTime.utc(2026),
        rates: const [KpiRate('Narra', 500, 250)],
      );
      await catalog.save({
        'matrix_versions': [version.toMap()],
      }, {});
      final key = backend.values.keys.singleWhere(
        (k) => k.startsWith('offline_mutation_queue_v1::'),
      );
      final entry =
          jsonDecode(backend.values[key]!.single) as Map<String, dynamic>;
      backend.values[key] = [
        jsonEncode({...entry, 'is_blocked': true, 'last_error': boxedError}),
      ];
      online = true;
      await queue.flushPendingMutations();
      expect(await queue.readPendingItems('manager'), isEmpty);
      expect(
        (await db
                .collection('operations_catalog')
                .doc('matrix_recovered')
                .get())
            .data(),
        version.toMap(),
      );
      expect(
        (await db.collection('operations_catalog').doc('settings').get())
            .data()!['matrix_version_ids'],
        ['recovered'],
      );
    },
  );
  test(
    'offline fuel migration preserves existing amount once across two entries and reconnect',
    () async {
      final old = {
        'make_id': '4',
        'day': '2026-09-01',
        'fuel': 500,
        'fuel_confirmed': true,
        'updated_at': '2026-09-01T01:00:00Z',
        'updated_by': 'manager',
      };
      await store.saveFuel(
        makeId: '4',
        data: {
          'day': '2026-09-01',
          'amount': 1000,
          'reference': 'PO1',
          'voided': false,
        },
        previous: {},
        legacyDay: old,
      );
      await store.saveFuel(
        makeId: '4',
        data: {
          'day': '2026-09-01',
          'amount': 2000,
          'reference': 'PO2',
          'voided': false,
        },
        previous: {},
        legacyDay: old,
      );
      final period = KpiPeriod.week(2026, 9, 1);
      var data = await store.load('4', period);
      expect(data.fuel, hasLength(3));
      expect(data.fuel.where((r) => r['kind'] == 'legacy'), hasLength(1));
      expect(
        PmKpi.calculate(
          makeId: '4',
          period: period,
          bookings: [],
          records: [old],
          fuelEntries: data.fuel,
        ).fuel,
        3500,
      );
      online = true;
      await queue.flushPendingMutations();
      data = await store.load('4', period);
      expect(data.fuel, hasLength(3));
      expect((await db.collection('pm_fuel_entries').get()).docs, hasLength(3));
      expect((await db.collection('bookings').get()).docs, isEmpty);
      expect((await db.collection('manage_id').get()).docs, isEmpty);
    },
  );
  test(
    'fuel edit and void retain prior versions and original entry date',
    () async {
      await store.saveFuel(
        makeId: '4',
        data: {
          'day': '2026-09-01',
          'amount': 1000,
          'reference': 'PO1',
          'voided': false,
        },
        previous: {},
      );
      online = true;
      await queue.flushPendingMutations();
      var data = await store.load('4', KpiPeriod.week(2026, 9, 1));
      var entry = data.fuel.single;
      online = false;
      await store.saveFuel(
        makeId: '4',
        data: {...entry, 'amount': 1200},
        previous: entry,
      );
      online = true;
      await queue.flushPendingMutations();
      data = await store.load('4', KpiPeriod.week(2026, 9, 1));
      entry = data.fuel.single;
      expect((entry['revisions'] as List).single['amount'], 1000);
      online = false;
      await store.saveFuel(
        makeId: '4',
        data: {...entry, 'voided': true},
        previous: entry,
      );
      online = true;
      await queue.flushPendingMutations();
      data = await store.load('4', KpiPeriod.week(2026, 9, 1));
      expect((data.fuel.single['revisions'] as List), hasLength(2));
      expect(data.fuel.single['day'], '2026-09-01');
      expect(
        PmKpi.calculate(
          makeId: '4',
          period: KpiPeriod.week(2026, 9, 1),
          bookings: [],
          records: [],
          fuelEntries: data.fuel,
        ).fuel,
        0,
      );
    },
  );
}
