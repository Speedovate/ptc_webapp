import 'package:flutter/material.dart';

/// Selection must live inside Dialog, not around its full-screen route, so
/// taps outside the surface reach the modal barrier.
class AppSelectableDialog extends Dialog {
  AppSelectableDialog({
    super.key,
    super.backgroundColor,
    super.surfaceTintColor,
    super.elevation,
    super.insetPadding,
    super.shape,
    super.clipBehavior,
    required Widget child,
  }) : super(child: SelectionArea(child: child));
}
