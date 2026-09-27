import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/investor_commission_rate_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/view_models/admin/investor_statement.vm.dart';

import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

const investorA = 'inv-A';
const investorB = 'inv-B';

final makes = [
  VehicleMake(id: '4', code: 'PM4', investorId: investorA),
  VehicleMake(id: '5', code: 'PM5', investorId: investorA),
  VehicleMake(id: '9', code: 'PM9', investorId: investorB),
  // A company truck, which must never appear in an investor list.
  VehicleMake(id: '7', code: 'PM7'),
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
/// so the view model's assembly is tested without a Firestore round trip.
class StubKpiStore extends PmKpiStore {
  StubKpiStore({
    required this.bookingsForPeriod,
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

({InvestorStatementViewModel vm, StubKpiStore kpi, MemoryCache rateCache})
buildVm({
  List<Booking> bookings = const [],
  Map<String, List<Map<String, dynamic>>> recordsByMake = const {},
  Map<String, List<Map<String, dynamic>>> fuelByMake = const {},
  List<VehicleMake>? ownedMakes,
  bool Function()? canEdit,
}) {
  final kpi = StubKpiStore(
    bookingsForPeriod: bookings,
    recordsByMake: recordsByMake,
    fuelByMake: fuelByMake,
  );
  final db = MergeAwareFirestore();
  final rateCache = MemoryCache();
  final rates = InvestorCommissionRateStore(
    firestore: db,
    queue: OfflineMutationQueueService(
      firestore: db,
      backend: MemoryBackend(),
      isOnline: () => false,
    ),
    cache: rateCache,
    accountProvider: () async => 'admin',
    editPermission: canEdit ?? () => true,
    online: () => false,
  );
  final vm = InvestorStatementViewModel(kpiStore: kpi, rateStore: rates)
    ..setMakes(ownedMakes ?? makes);
  return (vm: vm, kpi: kpi, rateCache: rateCache);
}

Booking delivered({
  required String id,
  required String makeId,
  String amount = '10000',
  String destination = 'Quezon',
}) => Booking(
  id: id,
  clientStatus: 'delivered',
  driver: const UserModel(id: '8', role: 'driver', name: 'Ben'),
  helper: const UserModel(id: '9', role: 'helper', name: 'Ana'),
  vehicleMake: VehicleMake(id: makeId, code: makeId),
  deliveredAt: DateTime.utc(2026, 9, 15),
  statusOutputs: {
    'delivered__1': {
      'status_key': 'delivered',
      'fields': {'amount': amount, 'destination': destination},
    },
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the investor list', () {
    test('only investors that own a truck are offered', () {
      final vm = buildVm().vm;
      expect(vm.investors, [investorA, investorB]);
      expect(vm.hasInvestors, isTrue);
    });

    test('a company truck invents nobody', () {
      final vm = buildVm(ownedMakes: [makes.last]).vm;
      expect(vm.investors, isEmpty);
      expect(vm.hasInvestors, isFalse);
    });

    test('switching investor clears the previous statement', () {
      final vm = buildVm().vm;
      vm.selectInvestor(investorA);
      vm.selectInvestor(investorB);
      expect(vm.statement, isNull);
      expect(vm.ownedMakes, isEmpty);
    });
  });

  group('the period', () {
    test('is keyed the way the workbook files it', () {
      expect(kpiMonthKey(KpiPeriod.month(2026, 9)), '2026-09');
      expect(kpiMonthKey(KpiPeriod.month(2026, 12)), '2026-12');
      expect(kpiMonthKey(KpiPeriod.month(2026, 1)), '2026-01');
    });

    test('is labelled the way a person reads it', () {
      expect(kpiMonthLabel(KpiPeriod.month(2026, 9)), 'September 2026');
      expect(kpiMonthLabel(KpiPeriod.month(2026, 12)), 'December 2026');
    });
  });

  group('generating a statement', () {
    test('reads every truck the investor owns, and no others', () async {
      final vm = buildVm(
        bookings: [delivered(id: '1', makeId: '4')],
      ).vm;
      vm.selectInvestor(investorA);
      await vm.generate();
      final loaded = buildVm(
        bookings: [delivered(id: '1', makeId: '4')],
      );
      loaded.vm.selectInvestor(investorA);
      await loaded.vm.generate();
      expect(loaded.kpi.loaded, containsAll(<String>['4', '5']));
      expect(loaded.kpi.loaded, isNot(contains('9')));
      expect(loaded.kpi.loaded, isNot(contains('7')));
      expect(vm.investorId, investorA);
    });

    test('merges the investor trucks into one statement', () async {
      final vm = buildVm(
        bookings: [
          delivered(id: '1', makeId: '4', amount: '10000'),
          delivered(id: '2', makeId: '5', amount: '5000'),
          delivered(id: '3', makeId: '9', amount: '99000'),
        ],
      ).vm;
      vm.selectInvestor(investorA);
      final statement = await vm.generate();
      expect(statement, isNotNull);
      expect(statement!.tripCount, 2);
      // The other investor's ₱99,000 is nowhere in this document.
      expect(statement.grossBillings, 15000);
      expect(statement.investorId, investorA);
    });

    test(
      'an unpriceable trip blocks the statement instead of understating it',
      () async {
        final vm = buildVm(
          bookings: [
            delivered(id: '1', makeId: '4', destination: 'Bancao-Bancao'),
          ],
        ).vm;
        vm.selectInvestor(investorA);
        final statement = await vm.generate();
        expect(statement, isNull);
        expect(vm.error, contains('Cannot price'));
      },
    );

    test('an investor with no trucks is refused, not shown as zero', () async {
      final vm = buildVm().vm;
      vm.selectInvestor('inv-NOBODY');
      expect(await vm.generate(), isNull);
      expect(vm.error, contains('does not own any trucks'));
    });

    test('generating with nothing selected is refused', () async {
      final vm = buildVm().vm;
      expect(await vm.generate(), isNull);
      expect(vm.error, contains('Choose an investor'));
    });

    test('a month with no trips is a real zero statement', () async {
      final vm = buildVm().vm;
      vm.selectInvestor(investorA);
      final statement = await vm.generate();
      expect(statement, isNotNull);
      expect(statement!.tripCount, 0);
      expect(statement.grossBillings, 0);
      expect(statement.netDue, 0);
    });

    test('the default platform share applies when none was ever set', () async {
      final vm = buildVm(
        bookings: [delivered(id: '1', makeId: '4')],
      ).vm;
      vm.selectInvestor(investorA);
      final statement = await vm.generate();
      expect(statement!.rate, 0.10);
      expect(statement.platformFee, 1000);
      expect(vm.platformShare, 10);
    });

    test('a set platform share is what the statement is priced at', () async {
      final vm = buildVm(
        bookings: [delivered(id: '1', makeId: '4')],
      ).vm;
      await vm.savePlatformShare(25);
      vm.selectInvestor(investorA);
      final statement = await vm.generate();
      expect(statement!.rate, 0.25);
      expect(statement.platformFee, 2500);
      expect(vm.platformShare, 25);
    });
  });

  group('the export files', () {
    test('one xlsx and one pdf, named for the investor and month', () async {
      final vm = buildVm(
        bookings: [delivered(id: '1', makeId: '4')],
      ).vm;
      vm.selectInvestor(investorA);
      vm.selectPeriod(KpiPeriod.month(2026, 9));
      final statement = await vm.generate();
      final files = vm.files(statement!);
      expect(files.keys.toList()..sort(), [
        'Investor-Statement-inv-A-2026-09.pdf',
        'Investor-Statement-inv-A-2026-09.xlsx',
      ]);
      for (final bytes in files.values) {
        expect(bytes.length, greaterThan(500));
      }
    });

    test(
      'the statement sheet carries the figures the office will send',
      () async {
        final vm = buildVm(
          bookings: [delivered(id: '1', makeId: '4')],
        ).vm;
        vm.selectInvestor(investorA);
        final statement = await vm.generate();
        final files = vm.files(statement!);
        // The xlsx is a zip, so the bytes are real rather than an empty shell.
        expect(files.values.first.take(2), [0x50, 0x4b]);
      },
    );
  });

  group('the platform share control', () {
    test('an invalid share is refused and the old one stands', () async {
      final vm = buildVm().vm;
      await vm.savePlatformShare(12);
      expect(() => vm.savePlatformShare(0), throwsA(isA<StateError>()));
      expect(await vm.loadPlatformShare(), 12);
    });

    test('a change drops the statement on screen', () async {
      final vm = buildVm(
        bookings: [delivered(id: '1', makeId: '4')],
      ).vm;
      vm.selectInvestor(investorA);
      expect(await vm.generate(), isNotNull);
      expect(vm.statement, isNotNull);
      await vm.savePlatformShare(15);
      // One number on screen and another in the printout is the worst outcome.
      expect(vm.statement, isNull);
    });

    test('without the capability the share cannot be changed', () async {
      final vm = buildVm(canEdit: () => false).vm;
      expect(vm.canEditRate, isFalse);
      expect(
        () => vm.savePlatformShare(15),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('platform share'),
          ),
        ),
      );
      expect(await vm.loadPlatformShare(), 10);
    });
  });
}
