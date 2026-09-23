import 'package:flutter/rendering.dart';
import 'package:webapp/views/admin/pm_fuel_ledger_dialog.dart';
import 'package:webapp/services/kpi/kpi_all_time_period.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/views/admin/admin_kpi_tracking.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'pm_kpi_dialog_test.dart' show TestStore;

class FleetStore extends TestStore {
  bool allowed = true;
  bool fail = false;
  final periods = <KpiPeriod>[];
  @override
  bool get canRead => allowed;
  @override
  List<Booking>? get cachedBookings => [];
  @override
  Future<List<VehicleMake>> exportMakes() async => [
    VehicleMake(
      id: '1',
      code: 'PM4',
      driver: const UserModel(id: '13', name: 'Jonami Mainar'),
      helper: const UserModel(id: '18', name: 'Orlando Bania'),
      createdAt: DateTime.utc(2026, 9, 1),
    ),
    VehicleMake(id: '2', code: 'PM5', createdAt: DateTime.utc(2026, 9, 10)),
  ];
  @override
  Future<KpiStoredData?> readCached(String makeId, KpiPeriod period) async =>
      const KpiStoredData([], {}, true);
  @override
  Future<KpiStoredData> load(String makeId, KpiPeriod period) async {
    periods.add(period);
    if (fail) throw StateError('offline');
    return const KpiStoredData([], {}, false);
  }
}

void main() {
  test(
    'all time begins with each truck history, including older recorded expenses',
    () {
      final truck = VehicleMake(id: '1', createdAt: DateTime.utc(2026, 9, 10));
      final period = fleetTruckAllTimePeriod(
        truck,
        [truck],
        [],
        const KpiStoredData(
          [
            {'day': '2026-08-02'},
          ],
          {},
          true,
        ),
        DateTime.utc(2026, 9, 24),
      );
      expect(period.start, DateTime.utc(2026, 8, 2));
      expect(period.end, DateTime.utc(2026, 9, 24));
    },
  );
  for (final width in [375.0, 1400.0]) {
    testWidgets('fleet overview and monthly filter at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FleetStore();
      addTearDown(store.updates.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdminKpiTrackingView(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('All Time'), findsNothing);
      expect(
        tester
            .widget<AdminListToolbar>(find.byType(AdminListToolbar))
            .buttonLabel,
        'Actions',
      );
      expect(store.periods.first.start, DateTime.utc(1900));
      var list = tester.widget<AdminModalRecordList>(
        find.byType(AdminModalRecordList),
      );
      expect(list.itemCount, 3);
      expect(list.valuesAt(0).first, 'Total');
      expect(list.valuesAt(1).first, 'PM4');
      final panel = tester.widget<AdminListDynamicFiltersPanel>(
        find.byType(AdminListDynamicFiltersPanel),
      );
      final dropdown = panel.filters.first as AdminListDropdownFilterConfig;
      expect(dropdown.value, 'All Time');
      expect(dropdown.items, ['Range', 'Weekly', 'Monthly', 'All Time']);
      dropdown.onChanged('Monthly');
      await tester.pumpAndSettle();
      expect(store.periods.last.start.day, 1);
      expect(store.periods.last.start.year, DateTime.now().year);
      expect(tester.takeException(), isNull);
      store.fail = true;
      dropdown.onChanged('Weekly');
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      list = tester.widget<AdminModalRecordList>(
        find.byType(AdminModalRecordList),
      );
      expect(
        list.itemCount,
        3,
      ); // Cached fleet remains visible on failed refresh.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('search matches crew and Actions Fuel selects a PM', (
    tester,
  ) async {
    final store = FleetStore();
    addTearDown(store.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminKpiTrackingView(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    final searches = tester.widget<AdminListSearchField>(
      find.byType(AdminListSearchField),
    );
    for (final search in ['Mainar', 'Orlando', '18', 'PM4']) {
      searches.onChanged(search);
      await tester.pumpAndSettle();
      final list = tester.widget<AdminModalRecordList>(
        find.byType(AdminModalRecordList),
      );
      expect(list.itemCount, 2);
      expect(list.valuesAt(1).first, 'PM4');
    }
    searches.onChanged('no match');
    await tester.pumpAndSettle();
    expect(find.text('No matching trucks.'), findsOneWidget);
    searches.onChanged('');
    await tester.pumpAndSettle();
    final actionsText = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.text('Actions'),
        matching: find.byType(RichText),
      ),
    );
    expect(
      actionsText.size.width + 0.01,
      greaterThanOrEqualTo(actionsText.getMaxIntrinsicWidth(double.infinity)),
    );
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(3));
    final surfaces = tester.widgetList<Material>(
      find.ancestor(
        of: find.byType(PopupMenuItem<String>).first,
        matching: find.byType(Material),
      ),
    );
    expect(
      surfaces.any(
        (m) =>
            m.color == Colors.white && m.surfaceTintColor == Colors.transparent,
      ),
      isTrue,
    );
    await tester.tap(find.text('Fuel').last);
    await tester.pumpAndSettle();
    expect(find.text('Fuel · Select PM'), findsOneWidget);
    await tester.tap(find.text('Orlando Bania').last);
    await tester.pumpAndSettle();
    expect(find.byType(PmFuelLedgerDialog), findsOneWidget);
    expect(
      tester
          .widget<PmFuelLedgerDialog>(find.byType(PmFuelLedgerDialog))
          .make
          .id,
      '1',
    );
    expect(find.text('Go Back'), findsOneWidget);
    await tester.tap(find.text('Go Back'));
    await tester.pumpAndSettle();
    expect(find.text('Fuel · Select PM'), findsOneWidget);
    expect(find.byType(PmFuelLedgerDialog), findsNothing);
    await tester.tap(find.text('PM5').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PmFuelLedgerDialog>(find.byType(PmFuelLedgerDialog))
          .make
          .id,
      '2',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Rules opens shared editor without selecting a PM', (
    tester,
  ) async {
    final store = FleetStore();
    addTearDown(store.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminKpiTrackingView(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    expect(find.text('Rules · Select PM'), findsNothing);
    expect(find.text('Rules'), findsOneWidget);
    expect(find.byKey(const ValueKey('kpi-rule-edit-0')), findsOneWidget);
    await tester.tap(find.text('Go Back'));
    await tester.pumpAndSettle();
    expect(find.text('Actions'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('denied KPI access makes no fleet reads', (tester) async {
    final store = FleetStore()..allowed = false;
    addTearDown(store.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminKpiTrackingView(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('You do not have access to KPI Tracking.'),
      findsOneWidget,
    );
    expect(store.periods, isEmpty);
  });
}
