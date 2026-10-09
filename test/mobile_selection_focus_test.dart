import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/app_selectable_dialog.dart';
import 'package:webapp/widgets/shared/app_selection_area.dart';
import 'package:webapp/widgets/shared/app_text_input_focus_policy.dart';

void main() {
  for (final surface in ['page', 'dialog', 'admin modal', 'nested']) {
    testWidgets(
      '$surface protects touch editing and restores display selection',
      (tester) async {
        final editorFocus = FocusNode();
        final controller = TextEditingController(text: 'Draft');
        addTearDown(editorFocus.dispose);
        addTearDown(controller.dispose);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            if (call.method == 'Clipboard.getData') return {'text': 'Pasted'};
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller, focusNode: editorFocus),
            const SizedBox(height: 80),
            const Text('Selectable display label'),
          ],
        );
        final Widget body = switch (surface) {
          'dialog' => AppSelectableDialog(child: content),
          'admin modal' => AdminModalShell(title: 'Form', child: content),
          'nested' => AppSelectionArea(child: AppSelectionArea(child: content)),
          _ => AppSelectionArea(child: content),
        };
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => AppTextInputFocusPolicy(child: child!),
            home: Scaffold(body: body),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(isTextInputFocused, isTrue);
        await tester.longPress(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(editorFocus.hasFocus, isTrue);

        // Even a long press claimed by an ancestor display selection region
        // must not replace the editor's focus during mobile selection controls.
        final label = find.text('Selectable display label');
        await tester.longPress(label);
        await tester.pumpAndSettle();
        expect(editorFocus.hasFocus, isTrue);
        for (final area in tester.widgetList<SelectionArea>(
          find.byType(SelectionArea),
        )) {
          expect(area.focusNode!.canRequestFocus, isFalse);
        }
        await tester
            .state<EditableTextState>(find.byType(EditableText))
            .pasteText(SelectionChangedCause.toolbar);
        await tester.pumpAndSettle();
        expect(controller.text, contains('Pasted'));
        expect(editorFocus.hasFocus, isTrue);

        // Mouse selection still behaves normally, including on a hybrid device.
        await tester.tap(label, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(editorFocus.hasFocus, isFalse);
        await tester.longPress(label);
        await tester.pumpAndSettle();
        expect(find.byType(EditableText), findsOneWidget);
        expect(isTextInputFocused, isFalse);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'Display text selection',
        );
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  for (final sheet in [false, true]) {
    testWidgets(
      '${sheet ? 'bottom sheet' : 'filter popup'} keeps touch paste focus',
      (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        Widget editor(BuildContext context) => Material(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(focusNode: focus),
              const Text('Display text beside input'),
              const SizedBox(height: 40),
            ],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => AppTextInputFocusPolicy(child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => sheet
                    ? TextButton(
                        onPressed: () => showAppModalBottomSheet<void>(
                          context: context,
                          modalKey:
                              'touch-paste-sheet-${Theme.of(context).platform.name}',
                          builder: editor,
                        ),
                        child: const Text('Open'),
                      )
                    : AdminListFiltersButton(
                        controlHeight: 48,
                        surfaceRadius: 12,
                        iconOnly: false,
                        rightGap: 0,
                        menuChildren: [
                          SizedBox(width: 200, child: editor(context)),
                        ],
                      ),
              ),
            ),
          ),
        );
        await tester.tap(find.text(sheet ? 'Open' : 'Filters'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Draft');
        await tester.longPress(find.text('Display text beside input'));
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        if (!sheet) {
          // Text selection overlays can dispatch touch outside the popup.
          await tester.tapAt(const Offset(10, 550));
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          expect(find.byType(TextField), findsOneWidget);
          await tester.tapAt(
            const Offset(10, 550),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          expect(find.byType(TextField), findsNothing);
        } else {
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          expect(find.byType(TextField), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }
}
