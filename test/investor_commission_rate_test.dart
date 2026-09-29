import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/investor_commission.dart';
import 'package:webapp/services/investor_commission_rate_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';

import 'support/investor_fixtures.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';

import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

InvestorCommissionRateStore _store({
  FakeFirebaseFirestore? db,
  OfflineMutationQueueService? queue,
  bool online = true,
  bool canEdit = true,
  FirestoreCacheStore? cache,
}) {
  final firestore = db ?? MergeAwareFirestore();
  return InvestorCommissionRateStore(
    firestore: firestore,
    queue:
        queue ??
        OfflineMutationQueueService(
          firestore: firestore,
          backend: MemoryBackend(),
          isOnline: () => online,
        ),
    cache: cache ?? FirestoreCacheStore(),
    accountProvider: () async => 'admin',
    editPermission: () => canEdit,
    online: () => online,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('reading a stored rate', () {
    test('an absent rate is the default, so production is unchanged', () async {
      expect(
        await _store().loadRate(),
        InvestorCommissionRateStore.defaultRate,
      );
      expect(InvestorCommissionRateStore.defaultRate, 0.10);
    });

    test('a saved rate is read back', () async {
      final store = _store();
      await store.saveRate(0.15);
      expect(await store.loadRate(), 0.15);
    });

    test('a rate set offline is not lost', () async {
      final db = MergeAwareFirestore();
      final store = _store(db: db, online: false);
      await store.saveRate(0.12);
      // A fresh store over the same fake, still offline, sees the queued edit
      // rather than the default.
      final reread = _store(db: db, online: false);
      expect(await reread.loadRate(), 0.12);
    });
  });

  group('recovering from a bad stored value', () {
    // A rate of 0 or 1 would be silently catastrophic in either direction, so
    // anything unusable resolves to the default and never to a wrong number.
    for (final bad in [
      null,
      0,
      1,
      0.0,
      1.0,
      -0.2,
      1.5,
      'abc',
      '',
      '  ',
      true,
      double.nan,
      double.infinity,
      <String, dynamic>{},
    ]) {
      test('${bad.runtimeType} "$bad" falls back to the default', () {
        expect(InvestorCommissionRateStore.rateFrom(bad), 0.10);
      });
    }

    test('a rate written as a string is accepted', () {
      expect(InvestorCommissionRateStore.rateFrom('0.07'), 0.07);
      expect(InvestorCommissionRateStore.rateFrom(' 0.07 '), 0.07);
      // A bare number is read as a rate, never as a percentage: 7 is not a
      // 700% share, it is simply an unusable value.
      expect(InvestorCommissionRateStore.rateFrom(7), 0.10);
      expect(InvestorCommissionRateStore.rateFrom(0.07), 0.07);
    });
  });

  group('validating an entered percentage', () {
    test('accepts a real share', () {
      expect(
        InvestorCommissionRateStore.validatePercent(10),
        closeTo(0.10, 1e-9),
      );
      expect(
        InvestorCommissionRateStore.validatePercent(0.5),
        closeTo(0.005, 1e-9),
      );
      expect(
        InvestorCommissionRateStore.validatePercent(99.9),
        closeTo(0.999, 1e-9),
      );
    });

    // Rejected, not clamped: a typo must surface rather than become a silent
    // 10% on a document an investor is being asked to trust.
    for (final bad in [0.0, 100.0, -5.0, 150.0, double.nan, double.infinity]) {
      test('rejects $bad', () {
        expect(
          () => InvestorCommissionRateStore.validatePercent(bad),
          throwsA(isA<StateError>()),
        );
      });
    }

    test('a bad rate cannot be saved', () async {
      final store = _store();
      for (final bad in [0.0, 1.0, -1.0, 2.0, double.nan]) {
        expect(() => store.saveRate(bad), throwsA(isA<StateError>()));
      }
      // And nothing was written by the rejected attempts.
      expect(await store.loadRate(), 0.10);
    });
  });

  group('permission', () {
    test('a store without the capability cannot change the rate', () async {
      final store = _store(canEdit: false);
      expect(
        () => store.saveRate(0.2),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('platform share'),
          ),
        ),
      );
      expect(await store.loadRate(), 0.10);
    });
  });

  group('the rate reaches the money', () {
    // The whole point of storing it: what the office sets is what the investor
    // is actually charged. A setting nothing reads is a setting that lies.
    const investorA = 'inv-1';
    final make = InvestorFixtures.ownedMake('4', 'PM4', investorA);
    // A priceable drop-off, resolved through the shared resolver, so this test
    // measures the rate and nothing else.
    final trip = KpiTrip(
      Booking(
        id: '900',
        clientStatus: 'delivered',
        driver: const UserModel(id: '8', role: 'driver'),
        helper: const UserModel(id: '9', role: 'helper'),
        vehicleMake: make,
        deliveredAt: DateTime.utc(2026, 9, 15),
        statusOutputs: {
          'delivered__1': {
            'status_key': 'delivered',
            'fields': {'amount': '10000', 'destination': 'Quezon'},
          },
        },
      ),
      DateTime.utc(2026, 9, 15),
    );
    final routes = resolveKpiTripRoutes([trip], rates: KpiRate.matrix).routes;

    Future<InvestorCommission> statementFor(
      InvestorCommissionRateStore store,
    ) async => InvestorCommission.calculate(
      investorId: investorA,
      periodKey: '2026-09',
      rate: await store.loadRate(),
      trips: [trip],
      routes: routes,
      makes: [make],
      users: InvestorFixtures.usersFor([make]),
    );

    test('the default rate takes 10% of a trip', () async {
      final statement = await statementFor(_store());
      expect(statement.grossBillings, 10000);
      expect(statement.platformFee, 1000);
    });

    test('a stored rate is what gets taken', () async {
      final store = _store();
      await store.saveRate(0.25);
      final statement = await statementFor(store);
      expect(statement.platformFee, 2500);
    });

    test('changing the rate moves the investor, not the gross', () async {
      final store = _store();
      final atTen = await statementFor(store);
      await store.saveRate(0.30);
      final atThirty = await statementFor(store);
      expect(atThirty.grossBillings, atTen.grossBillings);
      expect(atThirty.platformFee, 3000);
      expect(atThirty.netDue, closeTo(atTen.netDue - 2000, 0.01));
      // And the line the investor reads states the rate that was applied.
      expect(
        atThirty.statement.map((line) => line.$1),
        contains('Paltranco share (30%)'),
      );
    });

    test('a broken stored rate still bills 10%, not 0% or 100%', () async {
      final store = _store();
      await store.saveRate(0.20);
      // Corrupt the document behind the store's back, as a bad migration or a
      // hand-edited field would.
      final cache = FirestoreCacheStore();
      final cacheKey = 'investor:admin:commission';
      final document = (await cache.readDocumentMaps(cacheKey))!.single;
      await cache.writeDocumentMaps(cacheKey, [
        {...document, 'commission_rate': 1},
      ]);
      final reread = _store(cache: cache);
      final statement = await statementFor(reread);
      expect(statement.platformFee, 1000);
    });
  });

  group('the stored document', () {
    test('records who set it and when, and is a settings doc', () async {
      final store = _store();
      await store.saveRate(0.14);
      final documentId = '${InvestorCommissionRateStore.reservedId}_settings';
      final cacheKey = 'investor:admin:commission';
      final cache = FirestoreCacheStore();
      final document = (await cache.readDocumentMaps(cacheKey))!.single;
      expect(document['commission_rate'], 0.14);
      expect(document['kind'], 'settings');
      expect(document['updated_by'], 'admin');
      expect(document['updated_at'], isNotEmpty);
      // The reserved id must not look like a vehicle document, or the KPI
      // record range would read it as a trip.
      expect(documentId, isNot(contains(' ')));
    });
  });
}
