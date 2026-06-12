import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/views/client/client_booking_history_view.dart';
import 'package:webapp/views/client/client_booking_home_view.dart';
import 'package:webapp/view_models/shared/role_assigned_home.vm.dart';
import 'package:webapp/view_models/shared/role_platform_home.vm.dart';
import 'package:webapp/views/shared/profile_view.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';
import 'package:webapp/widgets/shared/platform_shell.dart';
import 'package:webapp/widgets/sidebar_menu_item.dart';

class RolePlatformHome extends StatefulWidget {
  const RolePlatformHome({
    super.key,
    required this.user,
    required this.onLogout,
    this.isQuickLoggedIn = false,
  });

  final UserModel user;
  final VoidCallback onLogout;
  final bool isQuickLoggedIn;

  @override
  State<RolePlatformHome> createState() => _RolePlatformHomeState();
}

class _RolePlatformHomeState extends State<RolePlatformHome> {
  final RolePlatformHomeViewModel _viewModel = RolePlatformHomeViewModel();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AuthRepository _authRepository = AuthRequest.instance;
  Booking? _selectedHistoryBooking;
  late UserModel _shellUser;
  bool _isUploadingProfilePhoto = false;
  bool _isUploadingLicensePhoto = false;

  @override
  void initState() {
    super.initState();
    _shellUser = widget.user;
  }

  @override
  void didUpdateWidget(covariant RolePlatformHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.user.updatedAt != widget.user.updatedAt) {
      _shellUser = widget.user;
    }
  }

  Future<void> _saveProfileChanges(ProfilePendingProfileChanges changes) async {
    if ((_isUploadingProfilePhoto || _isUploadingLicensePhoto) ||
        !changes.hasChanges) {
      return;
    }
    final userId = _shellUser.id?.trim();
    if (userId == null || userId.isEmpty) {
      throw const AuthFailure('User ID is required.');
    }

    setState(() {
      _isUploadingProfilePhoto = changes.photoUpload != null;
      _isUploadingLicensePhoto = changes.licenseUpload != null;
    });
    try {
      var updatedUser = _shellUser;
      final photoUpload = changes.photoUpload;
      if (photoUpload != null) {
        updatedUser = await _authRepository.saveUserPhoto(
          userId: userId,
          bytes: photoUpload.bytes,
          fileName: photoUpload.fileName,
          mimeType: photoUpload.mimeType,
          size: photoUpload.size,
        );
      }
      final licenseUpload = changes.licenseUpload;
      if (licenseUpload != null) {
        updatedUser = await _authRepository.saveDriverLicensePhoto(
          userId: userId,
          bytes: licenseUpload.bytes,
          fileName: licenseUpload.fileName,
          mimeType: licenseUpload.mimeType,
          size: licenseUpload.size,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _shellUser = updatedUser;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingProfilePhoto = false;
          _isUploadingLicensePhoto = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<RolePlatformHomeViewModel>.reactive(
      viewModelBuilder: () => _viewModel,
      builder: (context, vm, _) {
        final width = MediaQuery.of(context).size.width;
        final isCompact = width < 1100;
        final showRail = !isCompact && vm.showDrawer;
        final overlayVisible =
            _isUploadingProfilePhoto || _isUploadingLicensePhoto;
        final overlayMessage = _isUploadingLicensePhoto
            ? 'Uploading license photo ...'
            : 'Uploading profile photo ...';

        return PlatformShell(
          scaffoldKey: _scaffoldKey,
          user: _shellUser,
          title: vm.selectedSection.title,
          isCompact: isCompact,
          showRail: showRail,
          onToggleNavigation: vm.toggleDrawer,
          onProfile: () => vm.selectSection(RolePlatformSection.profile),
          onLogout: widget.onLogout,
          logoutLabel: widget.isQuickLoggedIn ? 'Go Back' : 'Logout',
          sidebar: _buildSidebar(vm, isCompact: isCompact),
          body: AppPageLoadingOverlay(
            isVisible: overlayVisible,
            message: overlayMessage,
            child: KeyedSubtree(
              key: ValueKey(vm.selectedSection),
              child: _buildSelectedSection(vm.selectedSection),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar(
    RolePlatformHomeViewModel vm, {
    required bool isCompact,
  }) {
    return PlatformSidebarContainer(
      onBrandTap: () {
        setState(() {
          _selectedHistoryBooking = null;
        });
        vm.selectSection(RolePlatformSection.home);
        if (isCompact && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      children: [
        _sectionItem(
          vm: vm,
          section: RolePlatformSection.home,
          icon: Icons.home_rounded,
          isCompact: isCompact,
        ),
        _sectionItem(
          vm: vm,
          section: RolePlatformSection.history,
          icon: Icons.history_rounded,
          isCompact: isCompact,
        ),
        _sectionItem(
          vm: vm,
          section: RolePlatformSection.profile,
          icon: Icons.account_circle_rounded,
          isCompact: isCompact,
        ),
      ],
    );
  }

  Widget _sectionItem({
    required RolePlatformHomeViewModel vm,
    required RolePlatformSection section,
    required IconData icon,
    required bool isCompact,
  }) {
    return SidebarMenuItem(
      label: section.title,
      icon: icon,
      isSelected: vm.selectedSection == section,
      onTap: () {
        if (section != RolePlatformSection.history) {
          setState(() {
            _selectedHistoryBooking = null;
          });
        }
        vm.selectSection(section);
        if (isCompact) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  Widget _buildSelectedSection(RolePlatformSection section) {
    return switch (section) {
      RolePlatformSection.home =>
        widget.user.role == 'client'
            ? ClientBookingHomeView(
                user: _shellUser,
                onBookingSubmitted: (booking) {
                  setState(() {
                    _selectedHistoryBooking = booking;
                  });
                  _viewModel.selectSection(RolePlatformSection.history);
                },
              )
            : _RoleAssignedHomeSection(
                user: _shellUser,
                onUserUpdated: (updatedUser) {
                  setState(() {
                    _shellUser = updatedUser;
                  });
                },
                onOpenBooking: (booking) {
                  setState(() {
                    _selectedHistoryBooking = booking;
                  });
                  _viewModel.selectSection(RolePlatformSection.history);
                },
              ),
      RolePlatformSection.history => ClientBookingHistoryView(
        user: _shellUser,
        initialSelectedBooking: _selectedHistoryBooking,
        onNewPressed: () {
          setState(() {
            _selectedHistoryBooking = null;
          });
          _viewModel.selectSection(RolePlatformSection.home);
        },
      ),
      RolePlatformSection.profile => ProfileView(
        user: _shellUser,
        isCurrentUserView: true,
        onLogout: widget.onLogout,
        logoutLabel: widget.isQuickLoggedIn ? 'Go Back' : 'Logout',
        onSaveProfileChanges: _saveProfileChanges,
      ),
    };
  }
}

class _RoleAssignedHomeSection extends StatelessWidget {
  const _RoleAssignedHomeSection({
    required this.user,
    required this.onUserUpdated,
    required this.onOpenBooking,
  });

  final UserModel user;
  final ValueChanged<UserModel> onUserUpdated;
  final ValueChanged<Booking> onOpenBooking;

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<RoleAssignedHomeViewModel>.reactive(
      viewModelBuilder: RoleAssignedHomeViewModel.new,
      onViewModelReady: (vm) => vm.load(user),
      builder: (context, vm, _) {
        if (vm.errorMessage != null && vm.currentUser == null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: AdminListItemCard(
              padding: const EdgeInsets.all(24),
              child: AdminListStateText(message: vm.errorMessage!),
            ),
          );
        }

        final currentUser = vm.currentUser ?? user;
        final roleLabel = currentUser.role == 'driver' ? 'Driver' : 'Helper';

        return AppPageLoadingOverlay(
          isVisible: vm.isBusy,
          message: vm.busyMessage,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppRefreshStrip(isVisible: vm.isBusy),
                AdminListItemCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$roleLabel Availability',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (currentUser.isOnline ?? false)
                                  ? 'You are currently online and assignable.'
                                  : 'You are currently offline.',
                              style: TextStyle(
                                color: AppColors.primaryColor.withValues(
                                  alpha: 0.72,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: currentUser.isOnline ?? false,
                        trackOutlineColor: WidgetStateProperty.all(
                          AppColors.primaryColor,
                        ),
                        inactiveThumbColor: AppColors.primaryColor,
                        onChanged: vm.isBusy
                            ? null
                            : (value) async {
                                try {
                                  final updatedUser = await vm.setOnline(value);
                                  if (updatedUser != null) {
                                    onUserUpdated(updatedUser);
                                  }
                                } on AuthFailure catch (error) {
                                  if (!context.mounted) {
                                    return;
                                  }
                                  AppSnackbar.showError(context, error.message);
                                }
                              },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (vm.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AdminListItemCard(
                      padding: const EdgeInsets.all(24),
                      child: AdminListStateText(message: vm.errorMessage!),
                    ),
                  ),
                if (vm.assignedBookings.isEmpty)
                  AdminListItemCard(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No active assigned bookings yet.',
                      style: TextStyle(
                        color: AppColors.primaryColor.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Column(
                    children: vm.assignedBookings
                        .asMap()
                        .entries
                        .map(
                          (entry) => Padding(
                            padding: EdgeInsets.only(
                              bottom:
                                  entry.key == vm.assignedBookings.length - 1
                                      ? 0
                                      : 12,
                            ),
                            child: BookingRecordCard(
                              booking: entry.value,
                              onTap: () => onOpenBooking(entry.value),
                              headlineStatusLabel: vm.statusLabelForKey(
                                entry.value.clientStatus,
                              ),
                              statusLabelForKey: vm.statusLabelForKey,
                              showStatusSubmissions: false,
                              clientName: vm.clientName(entry.value),
                              clientPhone: vm.clientPhone(entry.value),
                              driverName: vm.driverName(entry.value),
                              driverPhone: vm.driverPhone(entry.value),
                              helperName: vm.helperName(entry.value),
                              helperPhone: vm.helperPhone(entry.value),
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
