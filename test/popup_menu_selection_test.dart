import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/app_selectable_popup_menu_item.dart';

void main() {
  testWidgets('popup labels copy without choosing; single tap still selects', (
    tester,
  ) async {
    String? copied;
    String? selected;
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
          body: PopupMenuButton<String>(
            onSelected: (value) => selected = value,
            itemBuilder: (_) => const [
              AppSelectablePopupMenuItem(
                value: 'rates',
                child: Text('Trip rates'),
              ),
            ],
            child: const Text('Open menu'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Trip rates'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('Copy').last);
    await tester.pumpAndSettle();
    expect(copied, isNotEmpty);
    expect('Trip rates', contains(copied!));
    await tester.tap(find.text('Trip rates'));
    await tester.pumpAndSettle();
    expect(selected, 'rates');
    expect(find.text('Trip rates'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
