import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/services/kpi/operations_catalog_store.dart';
import 'package:webapp/views/admin/pm_fuel_ledger_dialog.dart';
import 'package:webapp/views/admin/operations_catalog_dialog.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';

class FuelStore extends PmKpiStore {
  KpiStoredData? cached;
  @override
  Future<KpiStoredData?> readCached(String id, KpiPeriod period) async =>
      cached;
  List<Map<String, dynamic>> fuel = [];
  Completer<KpiStoredData>? gate;
  @override
  bool get canReadFuel => true;
  @override
  bool get canEditFuel => false;
  @override
  Future<KpiStoredData> load(String id, KpiPeriod period) =>
      gate?.future ?? Future.value(KpiStoredData([], {}, false, fuel: fuel));
}

class CatalogStore extends OperationsCatalogStore {
  OperationsCatalog? cached;
  @override
  Future<OperationsCatalog?> readCached() async => cached;
  Completer<OperationsCatalog>? gate;
  @override
  bool get canRead => true;
  @override
  bool get canEdit => false;
  @override
  Future<OperationsCatalog> load({bool force = false}) =>
      gate?.future ??
      Future.value(
        const OperationsCatalog({'locations': [], 'matrix_versions': []}),
      );
}

void main() {
  for (final fuel in [true, false]) {
    testWidgets('persisted submodal data displays before refresh fuel=$fuel', (
      tester,
    ) async {
      final fs = FuelStore()
        ..cached = const KpiStoredData([], {}, true)
        ..gate = Completer<KpiStoredData>();
      final cs = CatalogStore()
        ..cached = const OperationsCatalog({
          'locations': [],
          'matrix_versions': [],
        })
        ..gate = Completer<OperationsCatalog>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: fuel
                ? PmFuelLedgerDialog(
                    make: const VehicleMake(id: '4', code: 'PM4'),
                    period: KpiPeriod.month(2026, 9),
                    store: fs,
                  )
                : OperationsCatalogDialog(store: cs),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppPageLoading), findsNothing);
      expect(
        find.text(fuel ? 'No fuel requests in this period.' : 'No trip rates.'),
        findsOneWidget,
      );
      if (fuel) {
        fs.gate!.complete(fs.cached!);
      } else {
        cs.gate!.complete(cs.cached!);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Fuel toolbar searches and filters existing requests', (
    tester,
  ) async {
    final store = FuelStore()
      ..fuel = [
        {
          'day': '2026-09-01',
          'reference': 'REF-A',
          'supplier': 'Station A',
          'amount': 100,
        },
        {
          'day': '2026-09-02',
          'reference': 'REF-B',
          'supplier': 'Station B',
          'amount': 200,
          'voided': true,
        },
      ];
    var wentBack = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PmFuelLedgerDialog(
            make: const VehicleMake(id: '4', code: 'PM4'),
            period: KpiPeriod.month(2026, 9),
            store: store,
            onBack: () => wentBack = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    int count() => tester
        .widget<AdminModalRecordList>(find.byType(AdminModalRecordList))
        .itemCount;
    expect(count(), 2);
    expect(find.byType(AdminListToolbar), findsOneWidget);
    expect(find.text('Add request'), findsNothing);
    final search = find.descendant(
      of: find.byType(AdminListSearchField),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'Station B');
    await tester.pumpAndSettle();
    expect(count(), 1);
    final panel = tester.widget<AdminListDynamicFiltersPanel>(
      find.byType(AdminListDynamicFiltersPanel),
    );
    (panel.filters.first as AdminListDropdownFilterConfig).onChanged('Active');
    await tester.pumpAndSettle();
    expect(count(), 0);
    expect(find.text('No matching fuel requests.'), findsOneWidget);
    panel.onClear();
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(count(), 2);
    await tester.tap(find.text('Back to KPI'));
    expect(wentBack, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final width in [375.0, 1200.0]) {
    for (final fuel in [true, false]) {
      testWidgets('KPI submodal titles visibility fuel=$fuel width=$width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: fuel
                  ? PmFuelLedgerDialog(
                      make: const VehicleMake(id: '4', code: 'PM4'),
                      period: KpiPeriod.month(2026, 9),
                      store: FuelStore(),
                    )
                  : OperationsCatalogDialog(store: CatalogStore()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(AdminListHeaderBar),
          width < 900 ? findsNothing : findsOneWidget,
        );
        expect(find.byType(AdminListStateText), findsOneWidget);
        if (fuel) {
          await tester.tap(find.byType(AdminListFiltersButton));
          await tester.pumpAndSettle();
          final popup = find
              .ancestor(
                of: find.text('Clear'),
                matching: find.byType(DecoratedBox),
              )
              .first;
          final toolbar = find.byType(AdminListToolbar);
          expect(
            tester.getRect(popup).right,
            closeTo(tester.getRect(toolbar).right, 0.01),
          );
        }

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('known empty fuel renders immediately during a stalled refresh', (
    tester,
  ) async {
    final store = FuelStore()..gate = Completer<KpiStoredData>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PmFuelLedgerDialog(
            make: const VehicleMake(id: '4', code: 'PM4'),
            period: KpiPeriod.month(2026, 9),
            store: store,
            initialData: const KpiStoredData([], {}, true),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AppPageLoading), findsNothing);
    expect(find.text('No fuel requests in this period.'), findsOneWidget);
    store.gate!.complete(const KpiStoredData([], {}, false));
    await tester.pumpAndSettle();
    expect(find.byType(AppPageLoading), findsNothing);
    expect(find.text('No fuel requests in this period.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final fuel in [true, false]) {
    for (final hangs in [false, true]) {
      testWidgets(
        '${fuel ? 'fuel' : 'trip rates'} settles empty or stalled read; hangs=$hangs',
        (tester) async {
          tester.view.physicalSize = const Size(1400, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final fs = FuelStore();
          final cs = CatalogStore();
          if (hangs) {
            fs.gate = Completer<KpiStoredData>();
            cs.gate = Completer<OperationsCatalog>();
          }
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: fuel
                    ? PmFuelLedgerDialog(
                        make: const VehicleMake(id: '4', code: 'PM4'),
                        period: KpiPeriod.month(2026, 9),
                        store: fs,
                      )
                    : OperationsCatalogDialog(store: cs),
              ),
            ),
          );
          if (hangs) {
            expect(find.byType(AppPageLoading), findsOneWidget);
            await tester.pump(const Duration(seconds: 16));
            await tester.pumpAndSettle();
            expect(find.byType(AppPageLoading), findsNothing);
            expect(find.text('Retry'), findsOneWidget);
            fs.gate = null;
            cs.gate = null;
            await tester.tap(find.text('Retry'));
          }
          await tester.pumpAndSettle();
          expect(find.byType(AppPageLoading), findsNothing);
          expect(find.byType(AdminListStateText), findsOneWidget);
          expect(
            find.text(
              fuel ? 'No fuel requests in this period.' : 'No trip rates.',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
