import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/type_history_input.dart';

void main() {
  testWidgets(
    'filters on typing and refocus, ranks exact first, hides unrelated and empty results',
    (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TypeHistoryInput(
                  controller: controller,
                  historyKey: null,
                  browseOptionsOnFocus: true,
                  matchInputOnly: true,
                  includeExactMatch: true,
                  options: const [
                    'Beyond San Pedro',
                    'San Manuel',
                    'San Pedro City Proper',
                    'San Pedro',
                    'Tiniguiban',
                  ],
                  child: TextField(controller: controller),
                ),
                const TextField(),
              ],
            ),
          ),
        ),
      );
      final input = find.byType(TextField).first;
      await tester.tap(input);
      await tester.pump();
      expect(find.byType(TextButton), findsNothing);
      await tester.enterText(input, '  sAn  Pedro ');
      await tester.pump();
      final rows = tester
          .widgetList<TextButton>(find.byType(TextButton))
          .map(
            (button) =>
                (find
                            .descendant(
                              of: find.byWidget(button),
                              matching: find.byType(Text),
                            )
                            .evaluate()
                            .single
                            .widget
                        as Text)
                    .data,
          )
          .toList();
      expect(rows, ['San Pedro', 'San Pedro City Proper', 'Beyond San Pedro']);
      expect(find.text('San Manuel'), findsNothing);
      expect(find.text('Tiniguiban'), findsNothing);
      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      await tester.tap(input);
      await tester.pump();
      expect(find.widgetWithText(TextButton, 'San Pedro'), findsOneWidget);
      expect(find.text('Tiniguiban'), findsNothing);
      await tester.enterText(input, 'zzz');
      await tester.pump();
      expect(find.byType(TextButton), findsNothing);
      await tester.enterText(input, '');
      await tester.pump();
      expect(find.byType(TextButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
