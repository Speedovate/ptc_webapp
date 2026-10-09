import 'package:webapp/widgets/shared/app_selection_area.dart';
import 'package:flutter/material.dart';

/// Keep selection inside the popup surface, outside its normal tap handler.
/// Long-press/drag can select the label while a single tap still chooses it.
class AppSelectablePopupMenuItem<T> extends PopupMenuItem<T> {
  const AppSelectablePopupMenuItem({
    super.key,
    super.value,
    super.enabled,
    super.height,
    super.padding,
    super.child,
  });

  @override
  PopupMenuItemState<T, AppSelectablePopupMenuItem<T>> createState() =>
      _AppSelectablePopupMenuItemState<T>();
}

class _AppSelectablePopupMenuItemState<T>
    extends PopupMenuItemState<T, AppSelectablePopupMenuItem<T>> {
  @override
  Widget build(BuildContext context) =>
      AppSelectionArea(child: super.build(context));
}
