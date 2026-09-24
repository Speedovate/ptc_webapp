import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/booking_pm_assignment.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/role_access_service.dart';
import 'operations_catalog.dart';
import 'pm_kpi.dart';

/// Read-only personal projection. No fleet permission or write API is granted.
class CrewKpiStore {
  CrewKpiStore({
    FirebaseFirestore? firestore,
    FirestoreCacheStore? cache,
    Future<UserModel?> Function()? currentUser,
    bool Function(UserModel)? allowed,
    bool Function()? online,
    Future<List<Map<String, dynamic>>> Function()? pending,
  }) : _db = firestore,
       _cache = cache ?? FirestoreCacheStore.instance,
       _currentUser = currentUser ?? AuthRequest.instance.getCurrentUser,
       _allowed = allowed ?? canView,
       _online = online ?? currentNetworkStatus,
       _pending =
           pending ??
           (() => OfflineMutationQueueService.instance
               .readQueuedCollectionDocuments(collectionKey: 'bookings'));
  final FirebaseFirestore? _db;
  final FirestoreCacheStore _cache;
  final Future<UserModel?> Function() _currentUser;
  final bool Function(UserModel) _allowed;
  final bool Function() _online;
  final Future<List<Map<String, dynamic>>> Function() _pending;
  FirebaseFirestore get db => _db ?? FirebaseFirestore.instance;
  static bool canView(UserModel user) =>
      {'driver', 'helper'}.contains(user.role) &&
      user.id?.isNotEmpty == true &&
      RoleAccessService.instance.canAccess(
        DispatcherAccessCapability.ownKpiRead,
        role: user.role,
      );
  Future<void> _check(UserModel user) async {
    final current = await _currentUser();
    if (current?.id != user.id ||
        current?.role != user.role ||
        !_allowed(user)) {
      throw StateError('You do not have access to this KPI.');
    }
  }

  String _key(UserModel user) => 'crew-kpi:v1:${user.role}:${user.id}';
  Future<Map<String, dynamic>?> readCached(UserModel user) async {
    await _check(user);
    final saved = (await _cache.readDocumentMaps(_key(user)))?.firstOrNull;
    await _check(user);
    return saved == null ? null : _overlay(user, saved);
  }

  Future<Map<String, dynamic>?> load(UserModel user) async {
    await _check(user);
    if (!_online()) return readCached(user);
    Future<QuerySnapshot<Map<String, dynamic>>> query(
      Query<Map<String, dynamic>> q,
    ) => q
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));
    final result = await Future.wait([
      query(
        db.collection('bookings').where('${user.role}_id', isEqualTo: user.id),
      ),
      query(
        db
            .collection('vehicle_makes')
            .where('${user.role}_id', isEqualTo: user.id),
      ),
    ]);
    final bookings = result[0].docs
        .map((d) => {...d.data(), 'id': d.id})
        .toList();
    final makes = {
      for (final d in result[1].docs) d.id: {...d.data(), 'id': d.id},
    };
    // Fuel is visible only for trucks currently assigned to this crew member.
    final assignedMakeIds = result[1].docs.map((d) => d.id).toSet();
    final fuel = <Map<String, dynamic>>[];
    for (final id in assignedMakeIds) {
      final prefix = '${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}_';
      final docs = await query(db.collection('pm_fuel_entries')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: prefix)
          .where(FieldPath.documentId, isLessThan: '$prefix~'));
      for (final doc in docs.docs) {
        final row = doc.data();
        if (row['make_id']?.toString() != id) continue;
        fuel.add({
          'id': doc.id, 'make_id': id, 'pm': makes[id]?['code'] ?? id,
          for (final key in ['day', 'reference', 'supplier', 'liters',
            'price_per_liter', 'amount', 'notes', 'status', 'created_at', 'updated_at'])
            key: row[key],
        });
      }
    }
    // Explicit historical PMs may no longer have this crew member assigned.
    final ids = bookings
        .map((b) => b['vehicle_make_id']?.toString())
        .whereType<String>()
        .toSet();
    // Previously confirmed legacy assignments retain their historical PM.
    for (final b in bookings) {
      final created = DateTime.tryParse('${b['created_at']}');
      if (created != null && created.isBefore(DateTime.utc(2026, 9, 22))) {
        if ('${b['driver_id']}' == '17') ids.add('2');
        if ('${b['driver_id']}' == '12') ids.add('3');
      }
    }
    for (final id in ids.where(
      (id) => id.isNotEmpty && !makes.containsKey(id),
    )) {
      final doc = await db
          .collection('vehicle_makes')
          .doc(id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      if (doc.exists) makes[id] = {...doc.data()!, 'id': id};
    }
    final records = <Map<String, dynamic>>[];
    final incidents = <Map<String, dynamic>>[];
    for (final id in makes.keys) {
      final prefix =
          '${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}_';
      final docs = await query(
        db
            .collection('pm_kpi_records')
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: prefix)
            .where(FieldPath.documentId, isLessThan: '$prefix~'),
      );
      for (final doc in docs.docs) {
        final data = doc.data();
        if (data['kind'] == 'settings' || doc.id.endsWith('_settings')) {
          final users = data['user_incident_counts'];
          final own = users is Map ? users[user.id] : null;
          if (own is Map) {
            for (final day in own.entries) {
              if (day.value is Map) {
                incidents.add({
                  'day': day.key,
                  'complaints': day.value['complaints'],
                  'accidents': day.value['accidents'],
                });
              }
            }
          }
        } else {
          // Never persist someone else's pay or PM revenue in this cache.
          final allRates = (data['trip_rates'] as List? ?? [])
              .whereType<Map>()
              .toList();
          final owners = allRates
              .map((r) => r['${user.role}_id']?.toString())
              .whereType<String>()
              .toSet();
          final ownRates = allRates
              .where((r) => '${r['${user.role}_id']}' == user.id)
              .toList();
          final exclusive = owners.length == 1 && owners.contains(user.id);
          records.add({
            'make_id': id,
            'day': data['day'],
            'salary_confirmed': data['salary_confirmed'],
            'trip_rates': [
              for (final r in ownRates)
                {
                  'signature': r['signature'],
                  'route': r['route'],
                  'amount': r[user.role],
                  'booking_id': r['booking_id'],
                },
            ],
            'daily_rate': data['daily_rate'],
            'exclusive': exclusive,
            if (exclusive) 'salary_total': data['${user.role}_salary'],
            if (exclusive)
              'shares_total': ownRates.fold<double>(
                0,
                (total, r) => total + (kpiMoney(r[user.role]) ?? 0),
              ),
            if (exclusive) 'hustling_fulls': data['hustling_fulls'],
            if (exclusive) 'hustling_empties': data['hustling_empties'],
          });
        }
      }
    }
    final catalog = await db
        .collection('operations_catalog')
        .doc('settings')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));
    final catalogData = <String, dynamic>{...?catalog.data()};
    final published = await Future.wait([
      for (final id in (catalogData['matrix_version_ids'] as List? ?? []).toSet())
        db.collection('operations_catalog').doc('matrix_$id')
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 12)),
    ]);
    if (published.any((doc) => !doc.exists)) {
      throw StateError('Trip matrix version is unavailable.');
    }
    catalogData['matrix_versions'] = [
      ...(catalogData['matrix_versions'] as List? ?? []),
      ...published.map((doc) => doc.data()!),
    ];
    final rules = await db
        .collection('pm_kpi_records')
        .doc('ZmxlZXQ_settings')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));
    final snapshot = <String, dynamic>{
      'bookings': bookings.map(_bookingData).toList(),
      'makes': makes.values
          .map(
            (m) => {
              'id': m['id'],
              'code': m['code'],
              'driver_id': m['driver_id'],
              'helper_id': m['helper_id'],
            },
          )
          .toList(),
      'records': records,
      'incidents': incidents,
      'catalog': catalogData,
      'fuel': fuel,
      'assigned_make_ids': assignedMakeIds.toList(),
      'rating_rules': rules.data()?['rating_rules'] ?? {},
    };
    await _check(user);
    await _cache.writeDocumentMaps(_key(user), [snapshot]);
    await _check(user);
    return _overlay(user, snapshot);
  }

  Future<Map<String, dynamic>> _overlay(
    UserModel user,
    Map<String, dynamic> source,
  ) async {
    final byId = {
      for (final b in (source['bookings'] as List).cast<Map>())
        '${b['id']}': Map<String, dynamic>.from(b),
    };
    for (final pending in await _pending()) {
      if (byId.containsKey('${pending['id']}') ||
          '${pending['${user.role}_id']}' == user.id) {
        byId['${pending['id']}'] = _bookingData(pending);
      }
    }
    await _check(user);
    return {
      ...source,
      'bookings': byId.values
          .where((b) => '${b['${user.role}_id']}' == user.id)
          .toList(),
    };
  }
}

Map<String, dynamic> _bookingData(Map<String, dynamic> b) => {
  for (final key in [
    'id',
    'driver_id',
    'helper_id',
    'vehicle_make_id',
    'client_status',
    'delivered_at',
    'created_at',
    'updated_at',
    'submission_key',
    'chassis_id',
    'local_sync_status',
  ])
    key: b[key],
  'status_outputs': {
    for (final entry
        in (b['status_outputs'] is Map ? b['status_outputs'] as Map : {})
            .entries)
      if (entry.value is Map)
        '${entry.key}': {
          'status_key': entry.value['status_key'],
          'submitted_at': entry.value['submitted_at'],
          'status_form': entry.value['status_form'],
          'fields': {
            for (final key in [
              'origin',
              'destination',
              'origin_barangay',
              'destination_barangay',
            ])
              key: (entry.value['fields'] is Map
                  ? entry.value['fields'] as Map
                  : {})[key],
          },
        },
  },
};

/// Calculations run only on data/filter changes, never on expand/collapse.
List<Map<String, dynamic>> crewKpiTransactions(
  UserModel user,
  Map<String, dynamic> data,
) {
  final role = user.role!;
  final catalog = OperationsCatalog(
    Map<String, dynamic>.from(data['catalog'] as Map? ?? {}),
  );
  final makes = [
    for (final m in (data['makes'] as List? ?? []).whereType<Map>())
      VehicleMake(
        id: '${m['id']}',
        code: m['code']?.toString(),
        driver: UserModel(id: m['driver_id']?.toString()),
        helper: UserModel(id: m['helper_id']?.toString()),
      ),
  ];
  final grouped = <String, List<KpiTrip>>{};
  final seen = <String>{};
  for (final raw in (data['bookings'] as List? ?? []).whereType<Map>()) {
    if ('${raw['${role}_id']}' != user.id ||
        !Booking.isDeliveredWorkflowStatus(raw['client_status']?.toString())) {
      continue;
    }
    final b = Booking.fromMap({
      ...Map<String, dynamic>.from(raw),
      'driver': {'id': raw['driver_id']},
      'helper': {'id': raw['helper_id']},
      'vehicle_make': raw['vehicle_make_id'] == null
          ? null
          : {'id': raw['vehicle_make_id']},
    });
    final delivered = kpiDeliveredAt(b);
    if (delivered == null) continue;
    final trip = KpiTrip(b, kpiDate(delivered));
    if (!seen.add(trip.identity)) continue;
    grouped.putIfAbsent(kpiDayKey(trip.day), () => []).add(trip);
  }
  final rows = <Map<String, dynamic>>[];
  for (final entry in grouped.entries) {
    final trips = entry.value
      ..sort((a, b) {
        final c = kpiDeliveredAt(
          a.booking,
        )!.compareTo(kpiDeliveredAt(b.booking)!);
        return c == 0 ? a.identity.compareTo(b.identity) : c;
      });
    final day = trips.first.day;
    final matrix = catalog.matrixFor(day);
    var cityTrips = 0;
    var confirmedDay = true;
    double? confirmedDaily;
    final pmRecords = <String, Map>{};
    for (final trip in trips) {
      final pm = resolveBookingPm(trip.booking, makes)?.id;
      final record = (data['records'] as List? ?? [])
          .whereType<Map>()
          .where((r) => r['make_id'] == pm && r['day'] == entry.key)
          .firstOrNull;
      if (record != null && pm != null) pmRecords[pm] = record;
      final saved = (record?['trip_rates'] as List? ?? [])
          .whereType<Map>()
          .where((r) => r['signature'] == trip.signature)
          .firstOrNull;
      final selected = matrix.rates
          .where((r) => r.name == saved?['route'])
          .firstOrNull;
      final rate = selected ?? matchKpiTripRate(trip, matrix.rates).rate;
      final currentSignatures = trips
          .where((t) => resolveBookingPm(t.booking, makes)?.id == pm)
          .map((t) => t.signature)
          .toSet();
      final savedSignatures = (record?['trip_rates'] as List? ?? [])
          .whereType<Map>()
          .map((r) => r['signature'])
          .toSet();
      final matchingDay =
          currentSignatures.length == savedSignatures.length &&
          currentSignatures.containsAll(savedSignatures);
      final confirmed =
          matchingDay &&
          kpiMoney(saved?['amount']) != null &&
          saved != null &&
          record?['salary_confirmed'] == true &&
          trip.booking.localSyncStatus == null;
      confirmedDay = confirmedDay && confirmed;
      double? amount;
      if (rate?.usesCityPremium == true) cityTrips++;
      if (confirmed) {
        amount = kpiMoney(saved['amount']);
        confirmedDaily ??= kpiMoney(record?['daily_rate']);
      } else if (rate != null) {
        amount = role == 'driver' ? rate.driver : rate.helper;
        if (rate.usesCityPremium && cityTrips > matrix.pay.cityAfter) {
          amount = role == 'driver'
              ? matrix.pay.cityDriver
              : matrix.pay.cityHelper;
        }
      }
      rows.add({
        'day': entry.key,
        'at': kpiDeliveredAt(
          trip.booking,
        )!.toUtc().add(const Duration(hours: 8)).toIso8601String(),
        'label': 'Booking ${trip.booking.id}',
        'booking_id': trip.booking.id,
        'type': 'Share',
        'amount': amount,
        'status': amount == null
            ? 'Missing rate'
            : confirmed
            ? 'Confirmed'
            : 'Unconfirmed',
      });
    }
    // Daily pay belongs to the person, once per worked day across PMs.
    var pay = confirmedDaily ?? matrix.pay.daily;
    if (pmRecords.length == 1) {
      final record = pmRecords.values.single;
      if (confirmedDay &&
          record['exclusive'] == true &&
          kpiMoney(record['salary_total']) != null) {
        pay =
            kpiMoney(record['salary_total'])! -
            (kpiMoney(record['shares_total']) ?? 0);
      } else if (record['exclusive'] == true) {
        pay +=
            (kpiMoney(record['hustling_fulls']) ?? 0) *
            (role == 'driver' ? matrix.pay.fullDriver : matrix.pay.fullHelper);
        pay +=
            (kpiMoney(record['hustling_empties']) ?? 0) *
            (role == 'driver'
                ? matrix.pay.emptyDriver
                : matrix.pay.emptyHelper);
      }
    }
    rows.add({
      'day': entry.key,
      'at': day.add(const Duration(days: 1)).toIso8601String(),
      'label': '${entry.key} Pay',
      'type': 'Salary',
      'amount': pay,
      'status': confirmedDay ? 'Confirmed' : 'Unconfirmed',
    });
  }
  rows.sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));
  return rows;
}
