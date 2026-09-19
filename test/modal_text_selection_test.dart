import 'package:webapp/widgets/shared/app_selectable_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';

void main() {
  for (final sheet in [false, true]) {
    testWidgets(
      '${sheet ? 'bottom sheet' : 'dialog'} supports copying text and using controls',
      (tester) async {
        String? clipboard;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': clipboard != null};
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    Widget content(BuildContext modalContext) => Material(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Copyable modal text'),
                            TextField(controller: controller),
                            TextButton(
                              onPressed: () => Navigator.of(modalContext).pop(),
                              child: const Text('Done'),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (sheet) {
                      showAppModalBottomSheet<void>(
                        context: context,
                        modalKey: 'selection-sheet',
                        builder: content,
                      );
                    } else {
                      showAppDialog<void>(
                        context: context,
                        modalKey: 'selection-dialog',
                        builder: (context) =>
                            AppSelectableDialog(child: content(context)),
                      );
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Copyable modal text'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy').last);
        await tester.pumpAndSettle();
        expect(clipboard, isNotEmpty);
        expect('Copyable modal text', contains(clipboard!));
        await tester.enterText(find.byType(TextField), 'draft preserved');
        expect(controller.text, 'draft preserved');
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Copyable modal text'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
