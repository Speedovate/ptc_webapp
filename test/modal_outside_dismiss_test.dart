import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/app_selectable_dialog.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';

void main() {
  testWidgets(
    'dismiss during confirmation does not pop parent on late completion',
    (tester) async {
      final save = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAdminActionConfirmation(
                  context,
                  title: 'Pending save',
                  message: 'Details',
                  confirmLabel: 'Save',
                  modalKey: 'pending-save',
                  onConfirmAsync: () => save.future,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Pending save'), findsNothing);
      save.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [375.0, 1200.0]) {
    for (final kind in ['form', 'custom', 'confirmation', 'sheet']) {
      testWidgets('$kind outside dismissal at $width', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var confirmed = false;
        final controller = TextEditingController(text: 'Keep draft');
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    if (kind == 'confirmation') {
                      showAdminActionConfirmation(
                        context,
                        title: 'Confirm action',
                        message: 'Details',
                        confirmLabel: 'Save',
                        modalKey: '$kind:$width',
                        onConfirmAsync: () async {
                          confirmed = true;
                          return true;
                        },
                      );
                    } else if (kind == 'sheet') {
                      showAppModalBottomSheet<void>(
                        context: context,
                        modalKey: '$kind:$width',
                        builder: (_) => SizedBox(
                          height: 180,
                          child: TextField(controller: controller),
                        ),
                      );
                    } else {
                      showAppDialog<void>(
                        context: context,
                        modalKey: '$kind:$width',
                        builder: (_) => StatefulBuilder(
                          builder: (_, setState) => kind == 'form'
                              ? AdminModalShell(
                                  title: 'Form',
                                  child: TextField(controller: controller),
                                )
                              : AppSelectableDialog(
                                  child: SizedBox(
                                    height: 180,
                                    child: TextField(controller: controller),
                                  ),
                                ),
                        ),
                      );
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        final baselineBarriers = find.byType(ModalBarrier).evaluate().length;
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(ModalBarrier), findsWidgets);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.byType(ModalBarrier).evaluate().length, baselineBarriers);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Confirm action'), findsNothing);
        expect(controller.text, 'Keep draft');
        expect(confirmed, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
