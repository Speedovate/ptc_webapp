import 'package:flutter/material.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/views/shared/role_platform_home.dart';

class HelperHome extends StatelessWidget {
  const HelperHome({
    super.key,
    required this.user,
    required this.onLogout,
    this.isQuickLoggedIn = false,
  });

  final UserModel user;
  final VoidCallback onLogout;
  final bool isQuickLoggedIn;

  @override
  Widget build(BuildContext context) {
    return RolePlatformHome(
      user: user,
      onLogout: onLogout,
      isQuickLoggedIn: isQuickLoggedIn,
    );
  }
}
