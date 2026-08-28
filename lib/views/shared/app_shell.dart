import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/view_models/shared/app_shell.vm.dart';
import 'package:webapp/views/admin/admin_home.dart';
import 'package:webapp/views/auth/auth_view.dart';
import 'package:webapp/views/client/client_home.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';
import 'package:webapp/widgets/shared/app_sync_status_banner.dart';
import 'package:webapp/widgets/shared/in_app_browser_guard.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static final RoleAccessService _roleAccessService = RoleAccessService.instance;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AppShellViewModel>.reactive(
      viewModelBuilder: AppShellViewModel.new,
      onViewModelReady: (vm) => vm.initialize(),
      builder: (context, vm, child) {
        if (vm.isLoading) {
          return const SelectionArea(
            child: InAppBrowserGuard(
              child: Scaffold(
                backgroundColor: Colors.white,
                body: SafeArea(
                  bottom: false,
                  child: ColoredBox(
                    color: Color(0xFF5C33CF),
                    child: Center(
                      child: AppPageLoading(
                        message: 'Loading, please wait ...',
                        compact: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final content = vm.currentUser == null
            ? AuthView(onAuthenticated: vm.completeAuthentication)
            : _buildRoleHome(
                vm.currentUser!,
                isQuickLoggedIn: vm.isQuickLoggedIn,
                onUserUpdated: () async {
                  await vm.refreshCurrentUser();
                },
                onLogout: () async {
                  final isQuickLoggedIn = vm.isQuickLoggedIn;
                  final confirmed = await showAdminActionConfirmation(
                    context,
                    title: isQuickLoggedIn ? 'Go Back?' : 'Logout?',
                    message: isQuickLoggedIn
                        ? 'Are you sure you want to go back to your previous account?'
                        : 'Are you sure you want to log out of your account?',
                    confirmLabel: isQuickLoggedIn ? 'Go Back' : 'Logout',
                    isDanger: !isQuickLoggedIn,
                  );
                  if (!confirmed) {
                    return;
                  }
                  if (vm.isQuickLoggedIn) {
                    await vm.goBackFromQuickLogin();
                    return;
                  }
                  await vm.logout();
                },
              );

        return SelectionArea(
          child: InAppBrowserGuard(
            child: AppSyncStatusBanner(
              currentUser: vm.currentUser,
              child: content,
            ),
          ),
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
    if (_roleAccessService.usesAdminShell(role: user.role)) {
      return AdminHome(
        user: user,
        isQuickLoggedIn: isQuickLoggedIn,
        onUserUpdated: onUserUpdated,
        onLogout: onLogout,
      );
    }
    return ClientHome(
      user: user,
      onLogout: onLogout,
      isQuickLoggedIn: isQuickLoggedIn,
    );
  }
}
