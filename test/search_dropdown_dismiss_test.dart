import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/admin_form_controls.dart';

void main() {
  for (final width in [375.0, 1200.0]) {
    testWidgets('search picker outside tap dismisses only picker at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final changes = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: AdminSearchSelectFormField(
                        initialValue: 'Garage',
                        dialogTitle: 'Select destination',
                        options: const ['Garage', 'Port'],
                        onChanged: changes.add,
                      ),
                    ),
                  ),
                ),
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Garage'));
      await tester.pumpAndSettle();
      expect(find.text('Select destination'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Po');
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Select destination'), findsNothing);
      expect(find.text('Garage'), findsOneWidget);
      expect(changes, isEmpty);
      await tester.tap(find.text('Garage'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Po');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Port'));
      await tester.pumpAndSettle();
      expect(changes, ['Port']);
      expect(find.text('Select destination'), findsNothing);
      expect(find.text('Port'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
