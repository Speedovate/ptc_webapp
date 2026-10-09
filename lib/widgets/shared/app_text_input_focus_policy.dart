import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Touch editing must keep focus while mobile browser selection controls are
/// active. Explicit form actions and keyboard completion still dismiss input.
bool shouldDismissTextInputForPointer(PointerDownEvent event) =>
    shouldDismissTextInputForDevice(event.kind);

bool shouldDismissTextInputForDevice(PointerDeviceKind? kind) =>
    kind != PointerDeviceKind.touch;

bool get isTextInputFocused =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>() !=
    null;

class AppTextInputFocusPolicy extends StatelessWidget {
  const AppTextInputFocusPolicy({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      EditableTextTapOutsideIntent:
          CallbackAction<EditableTextTapOutsideIntent>(
            onInvoke: (intent) {
              if (shouldDismissTextInputForPointer(intent.pointerDownEvent)) {
                intent.focusNode.unfocus();
              }
              return null;
            },
          ),
    },
    child: child,
  );
}
