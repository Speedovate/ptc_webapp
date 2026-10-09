import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_text_input_focus_policy.dart';

/// Display-text selection must not take focus from a touch-edited text field.
/// Keep normal display selection when no editor is active, and for a mouse.
class AppSelectionArea extends StatefulWidget {
  const AppSelectionArea({
    super.key,
    required this.child,
    this.contextMenuBuilder,
  });

  final Widget child;
  final SelectableRegionContextMenuBuilder? contextMenuBuilder;

  @override
  State<AppSelectionArea> createState() => _AppSelectionAreaState();
}

class _AppSelectionAreaState extends State<AppSelectionArea> {
  final _focusNode = FocusNode(debugLabel: 'Display text selection');
  bool _touchInteraction = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_updateFocusability);
  }

  void _updateFocusability() {
    _focusNode.canRequestFocus = !(_touchInteraction && isTextInputFocused);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_updateFocusability);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      _touchInteraction = event.kind == PointerDeviceKind.touch;
      _updateFocusability();
    },
    child: SelectionArea(
      focusNode: _focusNode,
      contextMenuBuilder:
          widget.contextMenuBuilder ??
          (context, state) => AdaptiveTextSelectionToolbar.selectableRegion(
            selectableRegionState: state,
          ),
      child: widget.child,
    ),
  );
}
