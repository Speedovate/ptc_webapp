import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/app_selectable_text.dart';

void main() {
  for (final inherited in [false, true]) {
    testWidgets('static text copies with inherited selection=$inherited', (
      tester,
    ) async {
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.hasStrings') {
          return {'value': copied != null};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      const text = AppSelectableText('Selectable record details');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: inherited ? const SelectionArea(child: text) : text,
          ),
        ),
      );
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      await tester.longPress(find.text('Selectable record details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy').last);
      await tester.pumpAndSettle();
      expect(copied, isNotEmpty);
      expect('Selectable record details', contains(copied!));
      expect(tester.takeException(), isNull);
    });
  }
}
