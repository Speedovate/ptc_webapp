import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_text_input_focus_policy.dart';
import 'package:webapp/widgets/status_form/status_form_runtime_fields.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final input in ['chat', 'booking', 'empty booking']) {
    final booking = input != 'chat';
    final initialText = input == 'empty booking' ? '' : 'Draft';
    testWidgets(
      '$input touch selection keeps focus '
      'and accepts paste; mouse outside still dismisses',
      (tester) async {
        final focus = FocusNode();
        final controller = TextEditingController(text: initialText);
        addTearDown(focus.dispose);
        addTearDown(controller.dispose);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            if (call.method == 'Clipboard.getData') {
              return {'text': 'Pasted text'};
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
            builder: (context, child) => AppTextInputFocusPolicy(child: child!),
            home: Scaffold(
              body: booking
                  ? AdminModalShell(
                      title: 'New Booking',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusFormRuntimeFieldCard(
                            field: const StatusField(
                              key: 'remarks',
                              title: 'Remarks',
                              type: 'text',
                            ),
                            initialValue: initialText,
                            focusNode: focus,
                            onChanged: (_) {},
                          ),
                          const SizedBox(
                            height: 160,
                            width: double.infinity,
                            key: ValueKey('outside'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        TextField(controller: controller, focusNode: focus),
                        const Expanded(
                          child: SizedBox.expand(key: ValueKey('outside')),
                        ),
                      ],
                    ),
            ),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        await tester.longPress(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        // Selection/menu interaction can deliver touch outside the field bounds.
        final outside = tester.getCenter(find.byKey(const ValueKey('outside')));
        await tester.tapAt(outside, kind: PointerDeviceKind.touch);
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        await editable.pasteText(SelectionChangedCause.toolbar);
        await tester.pumpAndSettle();
        expect(editable.widget.controller.text, contains('Pasted text'));
        expect(focus.hasFocus, isTrue);
        await tester.tapAt(outside, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isFalse);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets('web tap-outside intent preserves touch focus', (tester) async {
    final focus = FocusNode();
    late BuildContext actionContext;
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppTextInputFocusPolicy(
          child: Builder(
            builder: (context) {
              actionContext = context;
              return Scaffold(body: TextField(focusNode: focus));
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    Actions.invoke(
      actionContext,
      EditableTextTapOutsideIntent(
        focusNode: focus,
        pointerDownEvent: const PointerDownEvent(kind: PointerDeviceKind.touch),
      ),
    );
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
  });
}
