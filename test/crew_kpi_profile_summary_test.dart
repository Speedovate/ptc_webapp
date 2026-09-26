import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/services/kpi/crew_kpi_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/views/shared/crew_kpi_profile_summary.dart';
import 'package:webapp/views/shared/profile_view.dart';

class _SummaryStore extends CrewKpiStore {
  _SummaryStore(this.snapshot);

  final Map<String, dynamic> snapshot;
  bool failCache = false;
  int cachedCalls = 0;
  int loadCalls = 0;

  @override
  Future<Map<String, dynamic>?> readCached(UserModel user) async {
    cachedCalls++;
    if (failCache) {
      throw StateError('cache unavailable');
    }
    return snapshot;
  }

  @override
  Future<Map<String, dynamic>?> load(UserModel user) async {
    loadCalls++;
    return snapshot;
  }
}

Map<String, dynamic> _summaryData(DateTime day) => {
  'bookings': [
    {
      'id': 'summary-booking',
      'driver_id': 'summary-driver',
      'helper_id': 'summary-helper',
      'vehicle_make_id': 'summary-make',
      'client_status': 'delivered',
      'delivered_at': day.toIso8601String(),
      'created_at': day.toIso8601String(),
    },
  ],
  'makes': <Map<String, dynamic>>[],
  'records': <Map<String, dynamic>>[],
  'catalog': <String, dynamic>{},
  'incidents': [
    {'day': kpiDayKey(day), 'complaints': 1, 'accidents': 0},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => RoleAccessService.instance.setCurrentUser(null));

  testWidgets('profile summary loads the current user KPI through the store', (
    tester,
  ) async {
    const user = UserModel(id: 'summary-driver', role: 'driver');
    final day = kpiDate(DateTime.now());
    final store = _SummaryStore(_summaryData(day));
    var opened = false;
    RoleAccessService.instance.setCurrentUser(user);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileView(
              user: user,
              scrollable: false,
              padding: EdgeInsets.zero,
              isCurrentUserView: true,
              kpiStore: store,
              vehicleCatalogRepository: _EmptyMakesRepository(),
              onOpenKpiTracking: () => opened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-kpi-summary')), findsOneWidget);
    expect(find.text('KPI summary'), findsOneWidget);
    expect(find.text('Complaints'), findsOneWidget);
    expect(find.text('Accidents'), findsOneWidget);
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('Shares'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(store.cachedCalls, 1);
    expect(store.loadCalls, 1);

    await tester.tap(find.text('View full KPI'));
    expect(opened, isTrue);
  });

  testWidgets(
    'profile summary falls back to a fresh KPI load when cache fails',
    (tester) async {
      const user = UserModel(id: 'summary-driver', role: 'driver');
      final store = _SummaryStore(_summaryData(kpiDate(DateTime.now())))
        ..failCache = true;
      RoleAccessService.instance.setCurrentUser(user);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileView(
                user: user,
                scrollable: false,
                padding: EdgeInsets.zero,
                isCurrentUserView: true,
                kpiStore: store,
                vehicleCatalogRepository: _EmptyMakesRepository(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('profile-kpi-summary')), findsOneWidget);
      expect(find.text('KPI summary'), findsOneWidget);
      expect(store.cachedCalls, 1);
      expect(store.loadCalls, 1);
    },
  );

  testWidgets('profile summary loads for a crew member viewed by admin', (
    tester,
  ) async {
    // Admin holds the cross-crew KPI permission by default, so the office can
    // audit a crew member's record from their profile. Every other role stays
    // off until it is granted.
    const user = UserModel(id: 'other-driver', role: 'driver');
    final store = _SummaryStore(_summaryData(kpiDate(DateTime.now())));
    RoleAccessService.instance.setCurrentUser(
      const UserModel(id: 'admin-id', role: 'admin'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileView(
              user: user,
              scrollable: false,
              padding: EdgeInsets.zero,
              isCurrentUserView: false,
              kpiStore: store,
              vehicleCatalogRepository: _EmptyMakesRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profile-kpi-summary')), findsOneWidget);
    expect(find.text('Bookings'), findsOneWidget);
    expect(store.cachedCalls + store.loadCalls, greaterThan(0));
  });

  testWidgets(
    'profile summary does not load for a crew member viewed by a role without '
    'the cross-crew KPI permission',
    (tester) async {
      const user = UserModel(id: 'other-driver', role: 'driver');
      final store = _SummaryStore(_summaryData(kpiDate(DateTime.now())));
      RoleAccessService.instance.setCurrentUser(
        const UserModel(id: 'manager-id', role: 'manager'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfileView(
                user: user,
                scrollable: false,
                padding: EdgeInsets.zero,
                isCurrentUserView: false,
                kpiStore: store,
                vehicleCatalogRepository: _EmptyMakesRepository(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('profile-kpi-summary')), findsNothing);
      expect(store.cachedCalls, 0);
      expect(store.loadCalls, 0);
    },
  );

  testWidgets(
    'summary respects a revoked KPI permission without loading data',
    (tester) async {
      const user = UserModel(id: 'blocked-driver', role: 'driver');
      final store = _SummaryStore(_summaryData(kpiDate(DateTime.now())));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CrewKpiProfileSummary(
              user: user,
              store: store,
              network: const Stream<bool>.empty(),
              allowed: () => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have access to KPI Tracking.'),
        findsOneWidget,
      );
      expect(store.cachedCalls, 0);
      expect(store.loadCalls, 0);
    },
  );
}

class _EmptyMakesRepository implements VehicleCatalogRepository {
  @override
  Future<List<VehicleMake>> getMakes() async => const [];

  @override
  Future<List<VehicleCatalogItem>> getSizes() async => const [];

  @override
  Future<List<VehicleCatalogItem>> getTypes() async => const [];

  @override
  Future<VehicleMake> saveMake(VehicleMake make) async => make;

  @override
  Future<void> deleteMake(String makeId) async {}

  @override
  Future<VehicleCatalogItem> saveSize(VehicleCatalogItem size) async => size;

  @override
  Future<void> deleteSize(String sizeId) async {}

  @override
  Future<VehicleCatalogItem> saveType(VehicleCatalogItem type) async => type;

  @override
  Future<void> deleteType(String typeId) async {}
}
