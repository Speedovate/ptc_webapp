import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';

void main() {
  testWidgets(
    'filter overlay text copies and controls still apply and dismiss',
    (tester) async {
      String? copied;
      var applied = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': copied != null};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: Column(
                children: [
                  const Text('Background page contents'),
                  AdminListFiltersButton(
                    controlHeight: 48,
                    surfaceRadius: 12,
                    iconOnly: false,
                    rightGap: 0,
                    menuChildren: [
                      const Text('Filter information'),
                      TextButton(
                        onPressed: () => applied = true,
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Filter information'));
      await tester.pumpAndSettle();
      final p = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text('Filter information'),
          matching: find.byType(RichText),
        ),
      );
      expect(p.selections.any((s) => !s.isCollapsed), isTrue);
      await tester.tap(find.text('Copy').last);
      await tester.pumpAndSettle();
      expect(copied, isNotEmpty);
      expect('Filter information', contains(copied!));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(applied, isTrue);
      await tester.tapAt(const Offset(5, 500));
      await tester.pumpAndSettle();
      expect(find.text('Filter information'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
