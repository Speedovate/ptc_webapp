import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';

void main() {
  for (final desktop in [false, true]) {
    testWidgets('border-width boundary fits grouped rows, desktop=$desktop', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> show(double width) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 700,
                child: AdminModalRecordList(
                  titles: const ['Name', 'Status'],
                  itemCount: 2,
                  valuesAt: (_) => ['Example user', 'Unconfirmed'],
                  rowGroupKey: (_) => 'group',
                  horizontalOnDesktop: desktop,
                ),
              ),
            ),
          ),
        ),
      );

      await show(1300);
      final header = find.byType(AdminListHeaderBar);
      final slots = tester.widgetList<AdminListFixedSlot>(
        find.descendant(of: header, matching: find.byType(AdminListFixedSlot)),
      );
      final cellsWidth = slots.fold<double>(0, (sum, slot) => sum + slot.width);
      expect(slots.length, 2);
      // The old fit calculation chose a horizontal row at these widths,
      // although the card border left the body 1–2 pixels too narrow.
      for (final insets in [32.0, 33.0, 34.0, 35.0]) {
        await show(cellsWidth + insets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Example user'), findsNWidgets(2));
      }
    });
  }
}
