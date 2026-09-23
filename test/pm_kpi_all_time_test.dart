import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/views/admin/pm_kpi_dialog.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'pm_kpi_dialog_test.dart' show TestStore, TestDiagnostics;

class AllTimeStore extends TestStore {
  KpiPeriod? requested;
  @override
  Future<KpiStoredData> load(String makeId, KpiPeriod period) async {
    requested = period;
    return super.load(makeId, period);
  }
}

void main() {
  testWidgets('Rules entry opens selected PM rules after loading', (
    tester,
  ) async {
    final store = AllTimeStore();
    addTearDown(store.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PmKpiDialog(
            make: const VehicleMake(id: '4', code: 'PM4'),
            store: store,
            diagnostics: TestDiagnostics(),
            openRules: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rules'), findsOneWidget);
    expect(find.text('Back to KPI'), findsOneWidget);
    final rules = tester.widget<AdminModalRecordList>(
      find.byType(AdminModalRecordList),
    );
    expect(rules.itemCount, 6);
    expect(rules.valuesAt(5), contains('Gross income target (%)'));
    await tester.tap(find.text('Back to KPI'));
    await tester.pumpAndSettle();
    expect(find.text('PM4 KPI'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final width in [375.0, 1200.0]) {
    testWidgets('All Time is last and fetches full PM history at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AllTimeStore();
      addTearDown(store.updates.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PmKpiDialog(
              make: VehicleMake(
                id: '4',
                code: 'PM4',
                createdAt: DateTime.utc(2026, 1, 1),
              ),
              store: store,
              diagnostics: TestDiagnostics(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<AdminDropdownFormField<String>>(
        find.byType(AdminDropdownFormField<String>).first,
      );
      expect(field.items!.map((e) => e.value), [
        'Range',
        'Weekly',
        'Monthly',
        'All Time',
      ]);
      expect(field.initialValue, 'Monthly');
      field.onChanged!('All Time');
      await tester.pumpAndSettle();
      expect(store.requested!.start, DateTime.utc(1900));
      expect(find.byKey(const ValueKey('kpi-period-date-field')), findsNothing);
      expect(tester.takeException(), isNull);
      field.onChanged!('Monthly');
      await tester.pumpAndSettle();
      expect(store.requested!.start.day, 1);
      expect(store.requested!.start.year, DateTime.now().year);
      expect(
        find.byKey(const ValueKey('kpi-period-date-field')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
