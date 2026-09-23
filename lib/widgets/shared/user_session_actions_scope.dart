import 'package:flutter/widgets.dart';

/// Keeps related user details connected to the shell's account lifecycle.
class UserSessionActionsScope extends InheritedWidget {
  const UserSessionActionsScope({
    super.key,
    required this.onUserUpdated,
    required this.onLogout,
    required this.isQuickLoggedIn,
    required super.child,
  });
  final Future<void> Function() onUserUpdated;
  final VoidCallback onLogout;
  final bool isQuickLoggedIn;

  static UserSessionActionsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UserSessionActionsScope>();

  @override
  bool updateShouldNotify(UserSessionActionsScope oldWidget) =>
      onUserUpdated != oldWidget.onUserUpdated ||
      onLogout != oldWidget.onLogout ||
      isQuickLoggedIn != oldWidget.isQuickLoggedIn;
}
