import 'package:flutter/widgets.dart';

class AdminShellLayoutScope extends InheritedWidget {
  const AdminShellLayoutScope({
    super.key,
    required this.filtersRightGap,
    required super.child,
  });

  final double filtersRightGap;

  static AdminShellLayoutScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AdminShellLayoutScope>();
  }

  @override
  bool updateShouldNotify(AdminShellLayoutScope oldWidget) {
    return filtersRightGap != oldWidget.filtersRightGap;
  }
}
