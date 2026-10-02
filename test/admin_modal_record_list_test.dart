import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';

void main() {
  testWidgets(
    'modal records batch values by 15 and retain access to later rows',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final measured = <int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: AdminModalRecordList(
                scrollController: controller,
                titles: const ['Name'],
                itemCount: 60,
                valuesAt: (i) {
                  measured.add(i);
                  return ['Record $i'];
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(measured.length, 15);
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(measured.length, greaterThan(15));
      // A long drag can cross more than one threshold, but each batch is 15.
      expect(measured.length % 15, 0);
      expect(measured.length, lessThan(60));
      await tester.scrollUntilVisible(
        find.text('Record 59'),
        350,
        scrollable: find.byType(Scrollable).last,
        maxScrolls: 40,
      );
      expect(find.text('Record 59'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('large expanded groups build only viewport rows', (tester) async {
    final built = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: AdminModalRecordList(
              titles: const ['Name'],
              itemCount: 200,
              pageSize: null,
              virtualizeGroups: true,
              rowGroupKey: (_) => 'user',
              valuesAt: (i) => ['Error $i'],
              cellBuilder: (i, col) {
                built.add(i);
                return SizedBox(height: 80, child: Text('Error $i'));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(built.length, lessThan(20));
    expect(built.contains(199), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header sections build lazily in the same viewport as rows', (
    tester,
  ) async {
    final built = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: AdminModalRecordList(
              titles: const ['Name'],
              itemCount: 1,
              valuesAt: (_) => ['Transaction'],
              scrollHeaderItems: [
                for (var i = 0; i < 30; i++)
                  Builder(
                    builder: (_) {
                      built.add(i);
                      return SizedBox(height: 250, child: Text('Crew $i'));
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(built.contains(0), isTrue);
    expect(built.contains(29), isFalse);
    expect(built.length, lessThan(8));
    expect(find.byType(ListView), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Crew 29'),
      500,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 30,
    );
    expect(built.contains(29), isTrue);
    await tester.scrollUntilVisible(
      find.text('Transaction'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Transaction'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selectable titles reenter viewport without editor scrolling', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: AdminModalRecordList(
              titles: const ['Name', 'Status'],
              selectableCells: true,
              scrollHeader: const SizedBox.shrink(),
              scrollController: controller,
              itemCount: 50,
              valuesAt: (i) => ['Record $i', 'Active'],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final header = find.byType(AdminListHeaderBar);
    final title = find.descendant(of: header, matching: find.text('Name'));
    expect(
      find.descendant(of: header, matching: find.byType(EditableText)),
      findsNothing,
    );
    final initial = tester.getTopLeft(title) - tester.getTopLeft(header);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    controller.jumpTo(0);
    await tester.pump();
    expect(tester.getTopLeft(title) - tester.getTopLeft(header), initial);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getTopLeft(title) - tester.getTopLeft(header), initial);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title) - tester.getTopLeft(header), initial);
    final rich = tester.widget<RichText>(
      find.descendant(of: title, matching: find.byType(RichText)),
    );
    expect(rich.selectionRegistrar, isNotNull);
    expect(tester.takeException(), isNull);
  });

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
