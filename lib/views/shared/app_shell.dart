import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/view_models/shared/app_shell.vm.dart';
import 'package:webapp/views/admin/admin_home.dart';
import 'package:webapp/views/auth/auth_view.dart';
import 'package:webapp/views/client/client_home.dart';
import 'package:webapp/views/driver/driver_home.dart';
import 'package:webapp/views/helper/helper_home.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AppShellViewModel>.reactive(
      viewModelBuilder: AppShellViewModel.new,
      onViewModelReady: (vm) => vm.initialize(),
      builder: (context, vm, child) {
        if (vm.isLoading) {
          return const Scaffold(
            backgroundColor: AppColors.primaryColor,
            body: AppPageLoading(
              message: 'Loading, please wait ...',
            ),
          );
        }

        final user = vm.currentUser;
        if (user == null) {
          return AuthView(
            onAuthenticated: (_) => vm.refreshCurrentUser(),
          );
        }

        return _buildRoleHome(
          user,
          isQuickLoggedIn: vm.isQuickLoggedIn,
          onUserUpdated: () async {
            await vm.refreshCurrentUser();
          },
          onLogout: () async {
            if (vm.isQuickLoggedIn) {
              await vm.goBackFromQuickLogin();
              return;
            }
            await vm.logout();
          },
        );
      },
    );
  }

  Widget _buildRoleHome(
    UserModel user, {
    required bool isQuickLoggedIn,
    required Future<void> Function() onUserUpdated,
    required VoidCallback onLogout,
  }) {
    switch (user.role) {
      case 'admin':
        return AdminHome(
          user: user,
          isQuickLoggedIn: isQuickLoggedIn,
          onUserUpdated: onUserUpdated,
          onLogout: onLogout,
        );
      case 'driver':
        return DriverHome(
          user: user,
          onLogout: onLogout,
          isQuickLoggedIn: isQuickLoggedIn,
        );
      case 'helper':
        return HelperHome(
          user: user,
          onLogout: onLogout,
          isQuickLoggedIn: isQuickLoggedIn,
        );
      case 'client':
      default:
        return ClientHome(
          user: user,
          onLogout: onLogout,
          isQuickLoggedIn: isQuickLoggedIn,
        );
    }
  }
}
