import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/services/startup_splash.dart';
import 'package:webapp/view_models/shared/app_shell.vm.dart';
import 'package:webapp/views/admin/admin_home.dart';
import 'package:webapp/views/auth/auth_view.dart';
import 'package:webapp/views/client/client_home.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/app_sync_status_banner.dart';
import 'package:webapp/widgets/shared/in_app_browser_guard.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static final RoleAccessService _roleAccessService = RoleAccessService.instance;
  static bool _hasDismissedStartupSplash = false;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AppShellViewModel>.reactive(
      viewModelBuilder: AppShellViewModel.new,
      onViewModelReady: (vm) {
        vm.initialize();
      },
      builder: (context, vm, child) {
        if (vm.isLoading) {
          // The HTML splash remains above Flutter until the first home page
          // has a trustworthy data state. Do not replace it with a second,
          // generic Flutter loading card during shell initialization.
          return const ColoredBox(color: Color(0xFF5C33CF));
        }

        // Auth has no data-loading home screen, so its first frame is ready.
        // Authenticated roles dismiss from their initial home content instead.
        if (vm.currentUser == null && !_hasDismissedStartupSplash) {
          _hasDismissedStartupSplash = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            dismissStartupSplash();
          });
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
                    onConfirmAsync: () async {
                      if (vm.isQuickLoggedIn) {
                        await vm.goBackFromQuickLogin();
                        return true;
                      }
                      await vm.logout();
                      return true;
                    },
                  );
                  if (!confirmed) {
                    return;
                  }
                },
              );

        return SelectionArea(
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              systemNavigationBarColor: Colors.white,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
            child: InAppBrowserGuard(
              child: _AppPageBottomSafeArea(
                child: AppSyncStatusBanner(
                  currentUser: vm.currentUser,
                  child: content,
                ),
              ),
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

class _AppPageBottomSafeArea extends StatelessWidget {
  const _AppPageBottomSafeArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    if (bottomInset == 0) {
      return child;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: bottomInset,
          child: const IgnorePointer(child: ColoredBox(color: Colors.white)),
        ),
      ],
    );
  }
}
