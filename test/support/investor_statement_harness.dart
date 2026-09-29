import 'package:webapp/models/booking.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/investor_commission_rate_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/view_models/admin/investor_statement.vm.dart';

import '../booking_id_resolver_test.dart' show MemoryBackend;
import 'investor_fixtures.dart';
import 'merge_aware_firestore.dart';

/// The two investor fleets the tests share: one investor with two trucks, one
/// with a single truck, and a company truck that must never look like an
/// investor.
const String investorA = 'inv-1';
const String investorB = 'inv-2';

final investorTestMakes = [
  InvestorFixtures.ownedMake('4', 'PM4', investorA),
  InvestorFixtures.ownedMake('5', 'PM5', investorA),
  InvestorFixtures.ownedMake('9', 'PM9', investorB),
  // A company truck: it must never show up as an investor.
  InvestorFixtures.companyMake('7', 'PM7'),
];

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

/// A KPI store that answers from a fixed set of bookings and per-make records,
/// so a statement can be assembled without a Firestore round trip.
class StubKpiStore extends PmKpiStore {
  StubKpiStore({
    this.bookingsForPeriod = const [],
    this.recordsByMake = const {},
    this.fuelByMake = const {},
  }) : super(
         accountProvider: () async => 'admin',
         editPermission: () => true,
         online: () => false,
         cache: MemoryCache(),
       );

  final List<Booking> bookingsForPeriod;
  final Map<String, List<Map<String, dynamic>>> recordsByMake;
  final Map<String, List<Map<String, dynamic>>> fuelByMake;
  final loaded = <String>[];

  @override
  Future<List<Booking>> bookings() async => bookingsForPeriod;

  @override
  Future<KpiStoredData> load(String makeId, KpiPeriod period) async {
    loaded.add(makeId);
    return KpiStoredData(
      recordsByMake[makeId] ?? const [],
      const {},
      true,
      fuel: fuelByMake[makeId] ?? const [],
    );
  }
}

/// Tears down the queue a statement read started, so its retry timer does not
/// outlive the test.
void disposeInvestorStatementVm(
  ({
    InvestorStatementViewModel vm,
    StubKpiStore kpi,
    MemoryCache rateCache,
    OfflineMutationQueueService rateQueue,
  })
  h,
) {
  h.vm.dispose();
  h.rateQueue.dispose();
}

({
  InvestorStatementViewModel vm,
  StubKpiStore kpi,
  MemoryCache rateCache,
  OfflineMutationQueueService rateQueue,
})
buildInvestorStatementVm({
  List<Booking> bookings = const [],
  Map<String, List<Map<String, dynamic>>> recordsByMake = const {},
  Map<String, List<Map<String, dynamic>>> fuelByMake = const {},
  List<VehicleMake>? makes,
  bool Function()? canEditRate,
}) {
  final kpi = StubKpiStore(
    bookingsForPeriod: bookings,
    recordsByMake: recordsByMake,
    fuelByMake: fuelByMake,
  );
  final db = MergeAwareFirestore();
  final rateCache = MemoryCache();
  final rateQueue = OfflineMutationQueueService(
    firestore: db,
    backend: MemoryBackend(),
    isOnline: () => false,
  );
  final rates = InvestorCommissionRateStore(
    firestore: db,
    queue: rateQueue,
    cache: rateCache,
    accountProvider: () async => 'admin',
    editPermission: canEditRate,
    online: () => false,
  );
  final vm = InvestorStatementViewModel(kpiStore: kpi, rateStore: rates)
    ..setUsers(InvestorFixtures.usersFor(makes ?? investorTestMakes))
    ..setMakes(makes ?? investorTestMakes);
  return (vm: vm, kpi: kpi, rateCache: rateCache, rateQueue: rateQueue);
}

/// A builder the dialog can be opened with, sharing nothing between calls.
InvestorStatementViewModel Function() investorVmFactory({
  bool Function()? canEditRate,
}) =>
    () => buildInvestorStatementVm(canEditRate: canEditRate).vm;
