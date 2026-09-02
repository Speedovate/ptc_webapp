import 'package:flutter/widgets.dart';

class AdminShellLayoutScope extends InheritedWidget {
  const AdminShellLayoutScope({
    super.key,
    required this.filtersRightGap,
    required this.alignFiltersToToolbarAction,
    required super.child,
  });

  final double filtersRightGap;
  final bool alignFiltersToToolbarAction;

  static AdminShellLayoutScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AdminShellLayoutScope>();
  }

  @override
  bool updateShouldNotify(AdminShellLayoutScope oldWidget) {
    return filtersRightGap != oldWidget.filtersRightGap ||
        alignFiltersToToolbarAction != oldWidget.alignFiltersToToolbarAction;
  }
}
