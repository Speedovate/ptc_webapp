import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/kpi/location_option_registry.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/widgets/admin_form_controls.dart';

void main() {
  tearDown(() => LocationOptionRegistry.apply({}, {}));
  test(
    'distance labels preserve location values and barangay classification',
    () {
      const catalog = OperationsCatalog({});
      final labels = catalog.labelsFor(DateTime.utc(2026));
      expect(labels['Santa Monica'], 'Santa Monica | CP');
      expect(labels['San Manuel'], 'San Manuel | OT');
      expect(labels['Santa Lourdes'], 'Santa Lourdes | OT');
      expect(labels['Narra'], 'Narra | OT');
      expect(labels['Puerto Princesa City'], 'Puerto Princesa City');
      expect(labels['Agutaya'], 'Agutaya');
      expect(catalog.options['origin_barangay'], contains('San Manuel'));
      expect(
        catalog.options['origin_barangay'],
        isNot(contains('San Manuel | OT')),
      );
    },
  );
  testWidgets('picker displays suffix but returns the original location name', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminSearchSelectFormField(
            options: const ['San Manuel'],
            locationOptionKey: 'origin_barangay',
            onChanged: (value) => selected = value,
            decoration: const InputDecoration(labelText: 'Barangay'),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AdminSearchSelectFormField));
    await tester.pumpAndSettle();
    expect(find.text('San Manuel | OT'), findsOneWidget);
    expect(find.text('Santa Monica | CP'), findsOneWidget);
    await tester.tap(find.text('San Manuel | OT'));
    await tester.pumpAndSettle();
    expect(selected, 'San Manuel');
    expect(find.text('San Manuel | OT'), findsNothing);
    expect(find.text('San Manuel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
