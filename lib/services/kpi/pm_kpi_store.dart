import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/services/kpi/operations_catalog_store.dart';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/role_access_service.dart';

class KpiStoredData {
  const KpiStoredData(
    this.records,
    this.settings,
    this.fromCache, {
    this.fuel = const [],
    this.catalog = const OperationsCatalog({}),
  });
  final List<Map<String, dynamic>> fuel;
  final OperationsCatalog catalog;
  final List<Map<String, dynamic>> records;
  final Map<String, dynamic> settings;
  final bool fromCache;
}

/// On-demand reads only. Uses the existing account-scoped, versioned offline
/// mutation queue; does not introduce a listener, timer, or numeric ID counter.
class PmKpiStore {
  static final instance = PmKpiStore();
  final Map<String, Future<KpiStoredData>> _inFlight = {};
  final Map<String, DateTime> _refreshedAt = {};

  PmKpiStore({
    FirebaseFirestore? firestore,
    OfflineMutationQueueService? queue,
    FirestoreCacheStore? cache,
    Future<String> Function()? accountProvider,
    bool Function()? editPermission,
    OperationsCatalogStore? catalogStore,
    bool Function()? online,
  }) : _providedFirestore = firestore,
       _queue = queue ?? OfflineMutationQueueService.instance,
       _cache = cache ?? FirestoreCacheStore.instance,
       _accountProvider = accountProvider,
       _editPermission = editPermission,
       _catalogStore = catalogStore ?? OperationsCatalogStore.instance,
       _online = online ?? currentNetworkStatus;
  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final Future<String> Function()? _accountProvider;
  final bool Function()? _editPermission;
  final bool Function() _online;
  final OperationsCatalogStore _catalogStore;

  static const collection = 'pm_kpi_records';
  bool get canRead => RoleAccessService.instance.canAccess(
    DispatcherAccessCapability.pmKpiRead,
  );
  bool get canReadFuel => RoleAccessService.instance.canAccess(
    DispatcherAccessCapability.fuelLedgerRead,
  );
  bool get canEditFuel =>
      _editPermission?.call() ??
      (canReadFuel &&
          RoleAccessService.instance.canAccess(
            DispatcherAccessCapability.fuelLedgerUpdate,
          ));
  bool get canReadIncome => RoleAccessService.instance.canAccess(
    DispatcherAccessCapability.tripIncomeRead,
  );
  bool get canReadCatalog => RoleAccessService.instance.canAccess(
    DispatcherAccessCapability.operationsCatalogRead,
  );
  bool get canReadBookings => RoleAccessService.instance.canAccess(
    DispatcherAccessCapability.bookingsRead,
  );
  bool get canEdit =>
      _editPermission?.call() ??
      RoleAccessService.instance.canAccess(
        DispatcherAccessCapability.pmKpiUpdate,
      );
  bool get canOpenUsers => RoleAccessService.instance.canAccess(
    DispatcherAccessCapability.usersRead,
  );
  bool get bookingsVerified =>
      BookingRequest.hasAuthoritativeBookings &&
      !BookingRequest.isAuthoritativeSyncInFlight;
  Future<UserModel?> currentUser() => AuthRequest.instance.getCurrentUser();
  List<VehicleMake> get makes => VehicleRequest.hydratedMakesSnapshot;
  Future<List<VehicleMake>> exportMakes() => VehicleRequest.instance.getMakes();
  List<UserModel> get incidentUsers => AuthRequest.hydratedUsersSnapshot;

  /// Reuse bookings already hydrated by the shell instead of waiting for a
  /// second cache inflation or an in-flight server request on modal open.
  List<Booking>? get cachedBookings => BookingRequest.hasResolvedBookings
      ? BookingRequest.hydratedBookingsSnapshot
      : null;
  Future<List<Booking>> bookings() => BookingRequest.instance.getBookings();
  Stream<List<Booking>> watchBookings() =>
      BookingRequest.instance.watchBookings();

  final OfflineMutationQueueService _queue;
  final FirestoreCacheStore _cache;
  String _prefix(String makeId) =>
      '${base64Url.encode(utf8.encode(makeId)).replaceAll('=', '')}_';
  Future<String> _account() async {
    if (_accountProvider != null) {
      return _accountProvider();
    }
    final user = await AuthRequest.instance.getCurrentUser();
    if (user?.id == null ||
        !canRead ||
        !RoleAccessService.instance.canAccess(
          DispatcherAccessCapability.vehicleMakesRead,
        ) ||
        !RoleAccessService.instance.canAccess(
          DispatcherAccessCapability.bookingsRead,
        )) {
      throw StateError('You do not have access to PM KPIs.');
    }
    return user!.id!;
  }

  void invalidateRefreshWindow() => _refreshedAt.clear();

  Future<KpiStoredData?> readCached(String makeId, KpiPeriod period) async {
    final account = await _account();
    if (await _cache.readDocumentMaps('kpi:$account:$makeId:settings') ==
            null &&
        await _cache.readDocumentMaps('kpi:$account:$makeId:days') == null) {
      return null;
    }
    return _loadData(makeId, period, account, localOnly: true);
  }

  Future<KpiStoredData> load(String makeId, KpiPeriod period) async {
    final account = await _account();
    final key = '$account:$makeId:${period.start}:${period.end}';
    final pending = _inFlight[key];
    if (pending != null) {
      return pending;
    }
    final refreshed = _refreshedAt[key];
    final recent =
        refreshed != null &&
        DateTime.now().difference(refreshed) < const Duration(seconds: 30);
    final request = _loadData(makeId, period, account, localOnly: recent);
    _inFlight[key] = request;
    try {
      final result = await request;
      if (!result.fromCache) {
        if (_refreshedAt.length >= 24) {
          _refreshedAt.remove(_refreshedAt.keys.first);
        }
        _refreshedAt[key] = DateTime.now();
      }
      return result;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<KpiStoredData> _loadData(
    String makeId,
    KpiPeriod period,
    String account, {
    required bool localOnly,
  }) async {
    final prefix = _prefix(makeId);
    final cacheKey = 'kpi:$account:$makeId:days';
    final settingsKey = 'kpi:$account:$makeId:settings';
    final fuelKey = 'kpi:$account:$makeId:fuel';
    var fuel =
        await _cache.readDocumentMaps(fuelKey) ?? <Map<String, dynamic>>[];
    if (localOnly) {
      await _catalogStore.restore();
    }
    final catalog = localOnly
        ? _catalogStore.current
        : await _catalogStore.load();
    var records =
        await _cache.readDocumentMaps(cacheKey) ?? <Map<String, dynamic>>[];
    var settings =
        (await _cache.readDocumentMaps(settingsKey))?.firstOrNull ??
        <String, dynamic>{};
    var fromCache = true;
    if (!localOnly && _online()) {
      try {
        final ref = _firestore.collection(collection);
        final results = await Future.wait([
          _firestore
              .collection('pm_fuel_entries')
              .where(
                FieldPath.documentId,
                isGreaterThanOrEqualTo: '$prefix${kpiDayKey(period.start)}_',
              )
              .where(
                FieldPath.documentId,
                isLessThanOrEqualTo: '$prefix${kpiDayKey(period.end)}~',
              )
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 10)),
          ref
              .where(
                FieldPath.documentId,
                isGreaterThanOrEqualTo: '$prefix${kpiDayKey(period.start)}',
              )
              .where(
                FieldPath.documentId,
                isLessThanOrEqualTo: '$prefix${kpiDayKey(period.end)}',
              )
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 10)),
          ref
              .doc('${prefix}settings')
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 10)),
        ]);
        final snapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
        records = [
          ...records.where((r) {
            final day = DateTime.tryParse('${r['day']}T00:00:00Z');
            return day != null && !period.contains(day);
          }),
          ...snapshot.docs.map((d) => {...d.data(), 'id': d.id}),
        ];
        final fuelSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
        fuel = [
          ...fuel.where((r) {
            final day = DateTime.tryParse('${r['day']}T00:00:00Z');
            return day != null && !period.contains(day);
          }),
          ...fuelSnapshot.docs.map((d) => {...d.data(), 'id': d.id}),
        ];
        await _cache.writeDocumentMaps(fuelKey, fuel);
        final config = results[2] as DocumentSnapshot<Map<String, dynamic>>;
        settings = config.exists ? {...config.data()!, 'id': config.id} : {};
        await _cache.writeDocumentMaps(cacheKey, records);
        await _cache.writeDocumentMaps(settingsKey, [settings]);
        fromCache = false;
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' ||
            error.code == 'unauthenticated') {
          rethrow;
        }
      } catch (_) {
        // Display the explicit cached/incomplete state; never synthesize success.
      }
    }
    final queued = await _queue.readQueuedCollectionDocuments(
      collectionKey: collection,
    );
    final merged = {
      for (final record in records) record['id'].toString(): record,
    };
    for (final record in queued.where((r) => r['make_id'] == makeId)) {
      if (record['kind'] == 'settings') {
        settings = record;
      } else {
        merged[record['id'].toString()] = record;
      }
    }
    final pendingFuel = await _queue.readQueuedCollectionDocuments(
      collectionKey: 'pm_fuel_entries',
    );
    final fuelById = {for (final r in fuel) r['id'].toString(): r};
    for (final r in pendingFuel.where((r) => r['make_id'] == makeId)) {
      fuelById[r['id'].toString()] = r;
    }
    final conflicts = await _queue.getBlockedConflicts();
    if (conflicts.any(
      (c) =>
          (const {
                'pm_kpi_records',
                'pm_fuel_entries',
              }.contains(c.collectionKey) &&
              c.targetId.startsWith(prefix)) ||
          c.collectionKey == 'operations_catalog',
    )) {
      throw StateError(
        'A KPI edit needs review in Queued Actions. Existing server data was preserved.',
      );
    }
    return KpiStoredData(
      merged.values.toList(),
      settings,
      fromCache,
      fuel: fuelById.values.toList(),
      catalog: catalog,
    );
  }

  /// Promote only explicit, signature-matched City Proper choices. Never infer
  /// a location from a missing rate or overwrite an existing matrix rate.
  Future<KpiStoredData> learnCityProperDropoffs(
    List<Booking> bookings,
    KpiStoredData stored,
  ) async {
    if (!_catalogStore.canEdit) return stored;
    final names = <String>{};
    final signatures = {
      for (final record in stored.records)
        for (final choice
            in (record['trip_rates'] as List? ?? const []).whereType<Map>())
          if (choice['route'] == 'City Proper') choice['signature'],
    };
    for (final booking in bookings) {
      final delivered = kpiDeliveredAt(booking);
      if (delivered == null) continue;
      final trip = KpiTrip(booking, kpiDate(delivered));
      if (!signatures.contains(trip.signature)) continue;
      // Barangays belong under PPC; an out-of-town destination must not be
      // reclassified because a generic City Proper rate was selected.
      if (!const [
        'puertoprincesacity',
        'puertoprincesa',
      ].contains(normalizeKpiLocation(trip.destination))) {
        continue;
      }
      final key = normalizeKpiLocation(trip.destinationBarangay);
      if (key.isEmpty) continue;
      final location = stored.catalog.locations
          .where(
            (l) =>
                l.kind == 'barangay' &&
                [
                  l.name,
                  ...l.aliases,
                ].any((n) => normalizeKpiLocation(n) == key),
          )
          .firstOrNull;
      if (location == null ||
          stored.catalog
              .matrixFor(trip.day)
              .rates
              .any(
                (r) => [
                  r.name,
                  ...r.aliases,
                ].any((n) => normalizeKpiLocation(n) == key),
              )) {
        continue;
      }
      names.add(location.name);
    }
    if (names.isEmpty) return stored;
    final current = await _catalogStore.load();
    final existing =
        (current.document['city_proper_locations'] as List? ?? const [])
            .whereType<String>()
            .toSet();
    final added = names.difference(existing);
    if (added.isEmpty) return stored;
    final classified = OperationsCatalog({
      ...current.document,
      'city_proper_locations': [...existing, ...added],
    });
    final next = classified.withLocations([
      for (final location in current.locations)
        added.contains(location.name) ? location.copyActive(true) : location,
    ]);
    await _catalogStore.save(next, current.document);
    return KpiStoredData(
      stored.records,
      stored.settings,
      stored.fromCache,
      fuel: stored.fuel,
      catalog: _catalogStore.current,
    );
  }

  Future<void> save({
    required String makeId,
    required Map<String, dynamic> data,
    required Map<String, dynamic> previous,
  }) async {
    final account = await _account();
    if (!canEdit) {
      throw StateError('You do not have access to edit PM KPIs.');
    }
    if (makeId.startsWith('offline_') ||
        makeId.startsWith('-') ||
        makeId.isEmpty) {
      throw StateError('Sync this vehicle first before recording KPIs.');
    }
    final id =
        '${_prefix(makeId)}${data['kind'] == 'settings' ? 'settings' : data['day']}';
    final document = <String, dynamic>{
      ...data,
      'revisions': [
        ...((previous['revisions'] as List?) ?? []),
        if (previous.isNotEmpty)
          {
            for (final entry in previous.entries)
              if (entry.key != 'revisions' &&
                  !entry.key.startsWith('queued_') &&
                  !entry.key.endsWith('_live'))
                entry.key: entry.value,
          },
      ],
      'id': id,
      'make_id': makeId,
      'updated_by': account,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _queue.saveCollectionDocumentOnlineFirst(
      collectionKey: collection,
      documentId: id,
      baseUpdatedAt: previous['updated_at']?.toString(),
      document: document,
    );
    // Preserve successful local saves across refresh/restart, even after the
    // queue has drained and before this range has been fetched again.
    final key =
        'kpi:$account:$makeId:${data['kind'] == 'settings' ? 'settings' : 'days'}';
    final cached = await _cache.readDocumentMaps(key) ?? [];
    await _cache.writeDocumentMaps(key, [
      ...cached.where((r) => r['id'] != id),
      document,
    ]);
  }

  Future<void> saveFuel({
    required String makeId,
    required Map<String, dynamic> data,
    required Map<String, dynamic> previous,
    Map<String, dynamic> legacyDay = const {},
  }) async {
    final account = await _account();
    if (!canEditFuel) {
      throw StateError('You do not have access to edit fuel entries.');
    }
    if (makeId.isEmpty ||
        makeId.startsWith('offline_') ||
        makeId.startsWith('-')) {
      throw StateError('Sync this vehicle first.');
    }
    final day = data['day']?.toString();
    final date = DateTime.tryParse('${day}T00:00:00Z');
    if (date == null ||
        date.isAfter(kpiDate(DateTime.now())) ||
        kpiMoney(data['amount']) == null ||
        (previous.isNotEmpty && previous['day'] != day)) {
      throw StateError(
        'Enter a valid fuel date and amount. To change a saved date, void the entry and add a new one.',
      );
    }
    final cacheKey = 'kpi:$account:$makeId:fuel';
    final cached =
        await _cache.readDocumentMaps(cacheKey) ?? <Map<String, dynamic>>[];
    final sourceKey = data['import_key'];
    if (sourceKey != null &&
        cached.any((record) => record['import_key'] == sourceKey)) {
      return;
    }
    Future<void> persist(Map<String, dynamic> document, String? base) async {
      await _queue.saveCollectionDocumentOnlineFirst(
        collectionKey: 'pm_fuel_entries',
        documentId: document['id'].toString(),
        document: document,
        baseUpdatedAt: base,
      );
      cached.removeWhere((r) => r['id'] == document['id']);
      cached.add(document);
      await _cache.writeDocumentMaps(cacheKey, cached);
    }

    final legacyId = '${_prefix(makeId)}${day}_legacy';
    if (legacyDay['fuel_source'] != 'ledger' &&
        (kpiMoney(legacyDay['fuel']) ?? 0) > 0 &&
        !cached.any((r) => r['id'] == legacyId)) {
      // Preserve the pre-ledger daily amount exactly once, with stable identity
      // and timestamp so concurrent/replayed migrations are idempotent.
      await persist({
        'id': legacyId,
        'make_id': makeId,
        'day': day,
        'kind': 'legacy',
        'amount': legacyDay['fuel'],
        'reference': legacyDay['fuel_reference'] ?? '',
        'notes': 'Existing daily fuel total',
        'voided': false,
        'created_at': legacyDay['updated_at'],
        'updated_at': legacyDay['updated_at'],
        'created_by': legacyDay['updated_by'],
        'updated_by': legacyDay['updated_by'],
      }, null);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final importKey = data['import_key']?.toString();
    if (importKey != null &&
        !RegExp(r'^[A-Za-z0-9_-]{1,1000}$').hasMatch(importKey)) {
      throw StateError('Invalid workbook source key.');
    }
    final id =
        previous['id']?.toString() ??
        (importKey != null
            ? '${_prefix(makeId)}${day}_import_$importKey'
            : '${_prefix(makeId)}${day}_${_firestore.collection('pm_fuel_entries').doc().id}');
    await persist({
      ...data,
      'id': id,
      'make_id': makeId,
      'created_at': previous['created_at'] ?? now,
      'created_by': previous['created_by'] ?? account,
      'updated_by': account,
      'updated_at': now,
      'revisions': [
        ...(previous['revisions'] as List? ?? []),
        if (previous.isNotEmpty)
          {
            for (final e in previous.entries)
              if (e.key != 'revisions' &&
                  !e.key.startsWith('queued_') &&
                  e.key != 'local_sync_status')
                e.key: e.value,
          },
      ],
    }, previous['updated_at']?.toString());
  }
}
