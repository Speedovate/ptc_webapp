import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/services/kpi/operations_catalog_store.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/views/admin/operations_catalog_dialog.dart';
import 'package:webapp/views/admin/pm_fuel_ledger_dialog.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';

class CatalogStub extends OperationsCatalogStore {
  @override
  bool get canRead => true;
  @override
  bool get canEdit => true;
  @override
  Future<OperationsCatalog> load({bool force = false}) async => current;
  @override
  Future<void> save(
    Map<String, dynamic> next,
    Map<String, dynamic> previous,
  ) async {
    current = OperationsCatalog(next);
  }
}

class FuelStub extends PmKpiStore {
  @override
  Future<KpiStoredData> load(String makeId, KpiPeriod period) async =>
      const KpiStoredData(
        [],
        {},
        true,
        fuel: [
          {
            'id': 'fuel1',
            'day': '2026-01-02',
            'reference': 'PO123',
            'supplier': 'Fuel Station',
            'amount': 1100,
            'liters': 20,
            'voided': false,
          },
        ],
      );
  @override
  bool get canReadFuel => true;
  @override
  bool get canEditFuel => true;
  Map<String, dynamic>? saved;
  @override
  bool get canEdit => true;
  @override
  Future<void> saveFuel({
    required String makeId,
    required Map<String, dynamic> data,
    required Map<String, dynamic> previous,
    Map<String, dynamic> legacyDay = const {},
  }) async {
    saved = {...data, 'make_id': makeId};
  }
}

Future<void> open(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppDialog<void>(
              context: context,
              modalKey: child.hashCode.toString(),
              builder: (_) => child,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  for (final width in [375.0, 1200.0]) {
    testWidgets('catalog add option and dismiss at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CatalogStub();
      await open(tester, OperationsCatalogDialog(store: store));
      await tester.tap(find.text('Add location'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Name'), 'Test route');
      if (width >= 1200) {
        await tester.enterText(field('Driver amount (optional)'), '500');
        await tester.enterText(field('Helper amount (optional)'), '250');
      }
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        store.current.options['origin'],
        width >= 1200 ? contains('Test route') : isNot(contains('Test route')),
      );
      expect(
        store.current.options['destination'],
        width >= 1200 ? contains('Test route') : isNot(contains('Test route')),
      );
      final rate = store.current
          .matrixFor(kpiDate(DateTime.now()))
          .rates
          .where((r) => r.name == 'Test route')
          .firstOrNull;
      if (width >= 1200) {
        expect(rate?.driver, 500);
        expect(rate?.helper, 250);
      } else {
        expect(rate, isNull);
      }
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(OperationsCatalogDialog), findsNothing);
    });
    testWidgets(
      'matrix and fuel use existing responsive record lists at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await open(tester, OperationsCatalogDialog(store: CatalogStub()));
        expect(find.text('Origin options'), findsNothing);
        expect(find.text('Destination options'), findsNothing);
        expect(find.byType(AdminModalRecordList), findsOneWidget);
        final list = tester.widget<AdminModalRecordList>(
          find.byType(AdminModalRecordList),
        );
        expect(list.valuesAt(0).first, 'San Manuel');
        expect(
          List.generate(list.itemCount, (i) => list.valuesAt(i).first),
          isNot(contains('City Proper')),
        );
        final unsetIndex = List.generate(
          list.itemCount,
          (i) => i,
        ).firstWhere((i) => list.valuesAt(i).first == 'Agutaya');
        expect(list.valuesAt(unsetIndex)[5], 'Inactive');
        final actions =
            list.cellBuilder!(unsetIndex, list.titles.indexOf('Actions'))!
                as Row;
        final activate =
            (actions.children.last as Tooltip).child as AdminListActionButton;
        expect(activate.onTap, isNull);
        final edit =
            (actions.children.first as Tooltip).child as AdminListActionButton;
        expect(edit.onTap, isNotNull);
        expect(find.text('Location'), findsWidgets);
        expect(find.text('Driver'), findsWidgets);
        expect(find.text('Helper'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        await open(
          tester,
          PmFuelLedgerDialog(
            make: const VehicleMake(id: '4', code: 'PM 4'),
            period: KpiPeriod.month(2026, 1),
            store: FuelStub(),
          ),
        );
        expect(find.byType(AdminModalRecordList), findsOneWidget);
        expect(find.text('PO123'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byIcon(Icons.visibility_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.visibility_outlined));
        await tester.pumpAndSettle();
        expect(find.text('Fuel Entry'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Close').last);
        await tester.pumpAndSettle();
      },
    );
    testWidgets('fuel liters times price saves original date at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FuelStub();
      await open(
        tester,
        FuelEntryDialog(
          makeId: '4',
          entry: const {},
          store: store,
          days: const [],
          initialDate: DateTime.utc(2026, 1, 2),
        ),
      );
      await tester.enterText(field('PO / receipt reference'), 'PO123');
      await tester.enterText(field('Liters (optional)'), '20');
      await tester.enterText(field('Price per liter (optional)'), '55');
      expect(
        tester.widget<TextField>(field('Amount')).controller!.text,
        '1100.00',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.saved?['amount'], 1100);
      expect(store.saved?['day'], '2026-01-02');
      expect(store.saved?['reference'], 'PO123');
      expect(store.saved?['make_id'], '4');
      expect(find.byType(FuelEntryDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
