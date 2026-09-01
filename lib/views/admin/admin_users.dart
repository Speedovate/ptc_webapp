import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/view_models/admin/admin_users.vm.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/views/admin/admin_bookings.dart';
import 'package:webapp/views/shared/profile_view.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_image_source_picker.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/user_bookings_section.dart';

class _PendingImageUpload {
  const _PendingImageUpload({
    required this.bytes,
    required this.fileName,
    required this.size,
    this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final int size;
  final String? mimeType;
}

class _UserFormDialogResult {
  const _UserFormDialogResult({
    required this.user,
    this.pendingPhotoUpload,
    this.pendingLicenseUpload,
  });

  final UserModel user;
  final _PendingImageUpload? pendingPhotoUpload;
  final _PendingImageUpload? pendingLicenseUpload;
}

class AdminUsersView extends StatefulWidget {
  const AdminUsersView({
    super.key,
    required this.user,
    required this.onCurrentUserUpdated,
    required this.onLogout,
    this.isQuickLoggedIn = false,
    this.initialEditUserId,
    this.onInitialEditHandled,
  });

  static const usersToolbarSectionGap = 12.0;
  static const usersTableSectionGap = 14.0;
  static const usersHeaderControlHeight = 52.0;
  static const usersFilterControlHeight = adminFilterFieldMinHeight;
  static const usersSurfaceRadius = 16.0;

  static String formatRole(String? role) =>
      _AdminUsersViewState.formatRole(role);

  static String initials(String? value) => _AdminUsersViewState.initials(value);

  static String formatCreatedAt(DateTime? value) =>
      _AdminUsersViewState.formatCreatedAt(value);

  static String formatCreatedAtSingleLine(DateTime? value) =>
      _AdminUsersViewState.formatCreatedAtSingleLine(value);

  static String formatUpdatedAt(DateTime? value) =>
      _AdminUsersViewState.formatCreatedAt(value);

  static String formatUpdatedAtSingleLine(DateTime? value) =>
      _AdminUsersViewState.formatCreatedAtSingleLine(value);

  static String buildEmptyStateMessage({
    required String noun,
    required bool hasSearch,
    required int activeFilterCount,
  }) => _AdminUsersViewState._buildEmptyStateMessage(
    noun: noun,
    hasSearch: hasSearch,
    activeFilterCount: activeFilterCount,
  );

  static Future<void> showEditUserDialog(
    BuildContext context,
    AdminUsersViewModel vm,
    UserModel user,
    Future<void> Function() onCurrentUserUpdated,
  ) => _AdminUsersViewState.showEditUserDialog(
    context,
    vm,
    user,
    onCurrentUserUpdated,
  );

  static Future<void> showNewUserDialog(
    BuildContext context,
    AdminUsersViewModel vm,
  ) => _AdminUsersViewState.showNewUserDialog(context, vm);

  static Future<void> showUserDetailDialog(
    BuildContext context, {
    required UserModel currentUser,
    required UserModel viewedUser,
    Future<void> Function()? onCurrentUserUpdated,
    VoidCallback? onLogout,
    bool isQuickLoggedIn = false,
  }) {
    return showAppDialog<void>(
      context: context,
      modalKey: 'user-detail:${viewedUser.id ?? "-"}',
      builder: (dialogContext) => _AdminUserDetailDialog(
        currentUser: currentUser,
        initialViewedUser: viewedUser,
        onCurrentUserUpdated: onCurrentUserUpdated ?? () async {},
        onLogout: onLogout ?? () {},
        isQuickLoggedIn: isQuickLoggedIn,
      ),
    );
  }

  static void handleDeleteUser(
    BuildContext context,
    AdminUsersViewModel vm,
    UserModel user,
  ) => _AdminUsersViewState.handleDeleteUser(context, vm, user);

  static void handleToggleUserActive(
    BuildContext context,
    AdminUsersViewModel vm,
    UserModel user,
  ) => _AdminUsersViewState.handleToggleUserActive(context, vm, user);

  final UserModel user;
  final Future<void> Function() onCurrentUserUpdated;
  final VoidCallback onLogout;
  final bool isQuickLoggedIn;
  final String? initialEditUserId;
  final VoidCallback? onInitialEditHandled;

  @override
  State<AdminUsersView> createState() => _AdminUsersViewState();
}

class _AdminUsersViewState extends State<AdminUsersView> {
  final AuthRepository _authRepository = AuthRequest.instance;
  String? _handledInitialEditUserId;
  bool _isLaunchingInitialEdit = false;
  bool _isUploadingViewedProfilePhoto = false;
  bool _isUploadingViewedLicensePhoto = false;

  String? _effectiveCurrentRole(AdminUsersViewModel vm) => RoleAccessService
      .instance
      .effectiveRoleKey(vm.currentUser?.role ?? widget.user.role);

  Future<void> _saveViewedUserProfileChanges(
    AdminUsersViewModel vm,
    UserModel user,
    ProfilePendingProfileChanges changes,
  ) async {
    if ((_isUploadingViewedProfilePhoto || _isUploadingViewedLicensePhoto) ||
        !changes.hasChanges) {
      return;
    }
    final userId = user.id?.trim();
    if (userId == null || userId.isEmpty) {
      throw const AuthFailure('User ID is required.');
    }

    setState(() {
      _isUploadingViewedProfilePhoto = changes.photoUpload != null;
      _isUploadingViewedLicensePhoto = changes.licenseUpload != null;
    });
    try {
      var updatedUser = user;
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
      vm.syncUser(updatedUser);
      if (updatedUser.id == widget.user.id) {
        await widget.onCurrentUserUpdated();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingViewedProfilePhoto = false;
          _isUploadingViewedLicensePhoto = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AdminUsersViewModel>.reactive(
      viewModelBuilder: AdminUsersViewModel.new,
      onViewModelReady: (vm) => vm.loadUsers(fallbackCurrentUser: widget.user),
      builder: (context, vm, child) {
        vm.ensureCurrentUserContext(widget.user);
        final filteredUsers = vm.users.where(vm.matches).toList();
        final viewedUser = vm.viewedUser;
        final pendingInitialEditUserId = widget.initialEditUserId;

        if (!_isLaunchingInitialEdit &&
            pendingInitialEditUserId != null &&
            pendingInitialEditUserId != _handledInitialEditUserId &&
            viewedUser == null &&
            !vm.isBusy) {
          UserModel? matchedUser;
          for (final user in vm.users) {
            if (user.id == pendingInitialEditUserId) {
              matchedUser = user;
              break;
            }
          }
          if (matchedUser != null) {
            _isLaunchingInitialEdit = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) {
                return;
              }
              _handledInitialEditUserId = pendingInitialEditUserId;
              await AdminUsersView.showEditUserDialog(
                context,
                vm,
                matchedUser!,
                widget.onCurrentUserUpdated,
              );
              if (!mounted) {
                return;
              }
              widget.onInitialEditHandled?.call();
              _isLaunchingInitialEdit = false;
            });
          }
        }

        if (viewedUser != null) {
          final isViewingCurrentUser = viewedUser.id == widget.user.id;
          final viewedBusinessUser = vm.parentBusinessFor(viewedUser);
          return AppPageLoadingOverlay(
            isVisible:
                vm.showBlockingLoading ||
                _isUploadingViewedProfilePhoto ||
                _isUploadingViewedLicensePhoto,
            message: _isUploadingViewedLicensePhoto
                ? 'Uploading license photo ...'
                : _isUploadingViewedProfilePhoto
                ? 'Uploading profile photo ...'
                : vm.busyMessage,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _UserDetailHeader(user: viewedUser, onBack: vm.closeUserView),
                  const SizedBox(height: 12),
                  ProfileView(
                    key: profileViewRefreshKey(viewedUser),
                    user: viewedUser,
                    scrollable: false,
                    padding: EdgeInsets.zero,
                    businessUser: viewedBusinessUser,
                    onBusinessDetailsPressed: viewedBusinessUser == null
                        ? null
                        : () => vm.openUserView(
                            viewedBusinessUser,
                            preserveCurrent: true,
                          ),
                    isCurrentUserView: isViewingCurrentUser,
                    onLogout: widget.onLogout,
                    logoutLabel: widget.isQuickLoggedIn ? 'Go Back' : 'Logout',
                    onSaveProfileChanges:
                        isViewingCurrentUser &&
                            RoleAccessService.instance.canAccess(
                              'profile.update',
                              role: _effectiveCurrentRole(vm),
                            )
                        ? (changes) => _saveViewedUserProfileChanges(
                            vm,
                            viewedUser,
                            changes,
                          )
                        : null,
                    onQuickActionPressed: isViewingCurrentUser
                        ? null
                        : !vm.canSignInAsOtherUsers
                        ? null
                        : () async {
                            final confirmed = await showAdminActionConfirmation(
                              context,
                              title: 'Sign In As User',
                              message:
                                  'Continue signing in as ${viewedUser.name ?? 'this user'} (${AdminUsersView.formatRole(viewedUser.role)})?',
                              confirmLabel: 'Sign In',
                              onConfirmAsync: () async {
                                try {
                                  await vm.loginAsUser(viewedUser);
                                  if (!context.mounted) {
                                    return false;
                                  }
                                  await widget.onCurrentUserUpdated();
                                  return true;
                                } on AuthFailure catch (error) {
                                  if (!context.mounted) {
                                    return false;
                                  }
                                  AppSnackbar.showError(context, error.message);
                                  return false;
                                }
                              },
                            );
                            if (!confirmed || !context.mounted) {
                              return;
                            }
                          },
                    quickActionLabel: isViewingCurrentUser
                        ? null
                        : vm.canSignInAsOtherUsers
                        ? 'Sign In'
                        : null,
                    onEditPressed: () async {
                      if (!vm.canUpdateUsers) {
                        return;
                      }
                      await AdminUsersView.showEditUserDialog(
                        context,
                        vm,
                        viewedUser,
                        widget.onCurrentUserUpdated,
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  UserBookingsSection(
                    user: viewedUser,
                    padding: const EdgeInsets.only(bottom: 24),
                    useAdminListStyle: true,
                    forceWideLayout: false,
                    onViewBooking: (booking) async {
                      await AdminBookingsView.showBookingDetailDialog(
                        context,
                        user: widget.user,
                        booking: booking,
                      );
                    },
                    onEditBooking:
                        !RoleAccessService.instance.canAccess(
                          'bookings.update',
                          role: _effectiveCurrentRole(vm),
                        )
                        ? null
                        : (booking) async {
                            try {
                              await AdminBookingsView.showEditBookingDialog(
                                context,
                                booking: booking,
                                currentUser: vm.currentUser ?? widget.user,
                              );
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              AppSnackbar.showError(
                                context,
                                userFacingErrorMessage(
                                  error,
                                  fallback:
                                      'We could not open the booking editor right now.',
                                ),
                              );
                            }
                          },
                    onNewBooking:
                        !RoleAccessService.instance.canAccess(
                          'bookings.create',
                          role: _effectiveCurrentRole(vm),
                        )
                        ? null
                        : () async {
                            try {
                              await AdminBookingsView.showNewBookingDialog(
                                context,
                                currentUser: vm.currentUser ?? widget.user,
                              );
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              AppSnackbar.showError(
                                context,
                                userFacingErrorMessage(
                                  error,
                                  fallback:
                                      'We could not open the new booking dialog right now.',
                                ),
                              );
                            }
                          },
                  ),
                ],
              ),
            ),
          );
        }

        return AppPageLoadingOverlay(
          isVisible:
              vm.showBlockingLoading ||
              _isUploadingViewedProfilePhoto ||
              _isUploadingViewedLicensePhoto,
          message: _isUploadingViewedLicensePhoto
              ? 'Uploading license photo ...'
              : _isUploadingViewedProfilePhoto
              ? 'Uploading profile photo ...'
              : vm.busyMessage,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 900;
              final hasAnyData = vm.users.isNotEmpty;
              final hasSearch = vm.searchQuery.trim().isNotEmpty;
              final activeFilterCount = [
                vm.roleFilter != 'All',
                vm.activeFilter != 'All',
                vm.onlineFilter != 'All',
                vm.startDate != null,
                vm.endDate != null,
                vm.updatedStartDate != null,
                vm.updatedEndDate != null,
              ].where((isActive) => isActive).length;
              final emptyMessage = hasAnyData
                  ? AdminUsersView.buildEmptyStateMessage(
                      noun: 'users',
                      hasSearch: hasSearch,
                      activeFilterCount: activeFilterCount,
                    )
                  : 'No users yet.';

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppRefreshStrip(isVisible: vm.showBlockingLoading),
                    _UsersToolbar(vm: vm),
                    const SizedBox(
                      height: AdminUsersView.usersToolbarSectionGap,
                    ),
                    if (isNarrow)
                      if (filteredUsers.isNotEmpty)
                        Column(
                          children: filteredUsers
                              .asMap()
                              .entries
                              .map(
                                (entry) => Padding(
                                  padding: EdgeInsets.only(
                                    bottom:
                                        entry.key == filteredUsers.length - 1
                                        ? 0
                                        : 12,
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: _UsersResponsiveCard(
                                      user: entry.value,
                                      vm: vm,
                                      onCurrentUserUpdated:
                                          widget.onCurrentUserUpdated,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: _UsersEmptyState(message: emptyMessage),
                        )
                    else
                      _UsersTable(
                        users: filteredUsers,
                        emptyMessage: emptyMessage,
                        vm: vm,
                        onCurrentUserUpdated: widget.onCurrentUserUpdated,
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  static String formatRole(String? role) {
    if (role == null || role.isEmpty) {
      return '-';
    }
    return humanizeDropdownValue(role);
  }

  static String initials(String? value) {
    if (value == null || value.isEmpty) {
      return '?';
    }

    final parts = value
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .toList();

    if (parts.isEmpty) {
      return '?';
    }

    return parts.map((part) => part[0].toUpperCase()).join();
  }

  static String formatCreatedAt(DateTime? value) {
    if (value == null) {
      return '-';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final month = months[value.month - 1];
    final day = value.day;
    final year = value.year;
    final hour24 = value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = ((hour24 + 11) % 12) + 1;

    return '$month $day, $year\n$hour12:$minute:$second $period';
  }

  static String formatCreatedAtSingleLine(DateTime? value) {
    if (value == null) {
      return '-';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final month = months[value.month - 1];
    final day = value.day;
    final year = value.year;
    final hour24 = value.hour;
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = ((hour24 + 11) % 12) + 1;

    return '$month $day, $year - $hour12:$minute:$second $period';
  }

  static String _buildEmptyStateMessage({
    required String noun,
    required bool hasSearch,
    required int activeFilterCount,
  }) {
    final hasFilters = activeFilterCount > 0;
    final filterLabel = activeFilterCount == 1 ? 'filter' : 'filters';

    if (hasSearch && hasFilters) {
      return 'No $noun matched your current search and $filterLabel.';
    }
    if (hasSearch) {
      return 'No $noun matched your current search.';
    }
    if (hasFilters) {
      return 'No $noun matched your current $filterLabel.';
    }
    return 'No $noun found.';
  }

  static Future<void> showEditUserDialog(
    BuildContext context,
    AdminUsersViewModel vm,
    UserModel user,
    Future<void> Function() onCurrentUserUpdated,
  ) async {
    if (!vm.canUpdateUsers) {
      AppSnackbar.showError(context, 'You do not have access to edit users.');
      return;
    }
    final editedUser = await showAppDialog<_UserFormDialogResult>(
      context: context,
      modalKey: 'user-edit:${user.id ?? "-"}',
      builder: (dialogContext) => _UserFormDialog(
        title: _userDialogTitle('Edit', user),
        initialUser: user,
        isEditing: true,
        clientOptions: vm.clientUsers(),
        onSaveAsync: (result) async {
          var savedUser = await vm.updateUser(result.user);
          savedUser = await _applyPendingUserImageUploads(
            vm,
            savedUser,
            result,
          );
          if (vm.currentUser?.id == savedUser.id) {
            await onCurrentUserUpdated();
          }
        },
      ),
    );

    if (editedUser != null && context.mounted) {
      AppSnackbar.showSuccess(context, _buildUserSaveMessage(isEditing: true));
    }
  }

  static Future<void> showNewUserDialog(
    BuildContext context,
    AdminUsersViewModel vm,
  ) async {
    if (!vm.canCreateUsers) {
      AppSnackbar.showError(context, 'You do not have access to create users.');
      return;
    }
    final newUser = await showAppDialog<_UserFormDialogResult>(
      context: context,
      modalKey: 'user-new',
      builder: (dialogContext) => _UserFormDialog(
        title: _userDialogTitle('New', vm.draftNewUser),
        isEditing: false,
        canCreateAdminUsers: vm.canCreateAdminUsers,
        initialUser: vm.draftNewUser,
        generatedId: vm.nextUserId,
        onDraftChanged: vm.updateDraftNewUser,
        clientOptions: vm.clientUsers(),
        onSaveAsync: (result) async {
          var savedUser = await vm.addUser(result.user);
          savedUser = await _applyPendingUserImageUploads(
            vm,
            savedUser,
            result,
          );
          vm.clearDraftNewUser();
          vm.syncUser(savedUser);
        },
      ),
    );

    if (newUser != null && context.mounted) {
      AppSnackbar.showSuccess(context, _buildUserSaveMessage(isEditing: false));
    }
  }

  static Future<UserModel> _applyPendingUserImageUploads(
    AdminUsersViewModel vm,
    UserModel user,
    _UserFormDialogResult dialogResult,
  ) async {
    final repository = AuthRequest.instance;
    var updatedUser = user;

    final pendingPhotoUpload = dialogResult.pendingPhotoUpload;
    if (pendingPhotoUpload != null && (updatedUser.id?.isNotEmpty == true)) {
      updatedUser = await repository.saveUserPhoto(
        userId: updatedUser.id!,
        bytes: pendingPhotoUpload.bytes,
        fileName: pendingPhotoUpload.fileName,
        mimeType: pendingPhotoUpload.mimeType,
        size: pendingPhotoUpload.size,
      );
      vm.syncUser(updatedUser);
    }

    final pendingLicenseUpload = dialogResult.pendingLicenseUpload;
    if (pendingLicenseUpload != null && (updatedUser.id?.isNotEmpty == true)) {
      updatedUser = await repository.saveDriverLicensePhoto(
        userId: updatedUser.id!,
        bytes: pendingLicenseUpload.bytes,
        fileName: pendingLicenseUpload.fileName,
        mimeType: pendingLicenseUpload.mimeType,
        size: pendingLicenseUpload.size,
      );
      vm.syncUser(updatedUser);
    }

    return updatedUser;
  }

  static String _buildUserSaveMessage({required bool isEditing}) {
    return isEditing ? 'User updated.' : 'User added.';
  }

  static void handleDeleteUser(
    BuildContext context,
    AdminUsersViewModel vm,
    UserModel user,
  ) async {
    if (!vm.canDeleteUsers) {
      AppSnackbar.showError(context, 'You do not have access to delete users.');
      return;
    }
    if (vm.currentUser?.id == user.id) {
      AppSnackbar.showError(
        context,
        'Current logged-in user cannot be deleted.',
      );
      return;
    }

    final confirmed = await _showUserActionConfirmation(
      context,
      title: _userDialogTitle('Delete', user),
      message: 'Are you sure you want to delete ${user.name ?? 'this user'}?',
      confirmLabel: 'Delete',
      isDanger: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    await vm.deleteUser(user);
    if (!context.mounted) {
      return;
    }
    AppSnackbar.showSuccess(context, 'User deleted.');
  }

  static void handleToggleUserActive(
    BuildContext context,
    AdminUsersViewModel vm,
    UserModel user,
  ) async {
    if (!vm.canUpdateUsers) {
      AppSnackbar.showError(context, 'You do not have access to update users.');
      return;
    }
    final willBeActive = !(user.isActive ?? false);
    final roleLabel = formatRole(user.role);
    final subjectLabel = roleLabel == '-' ? 'User' : roleLabel;
    final subjectTitle = user.id?.isNotEmpty == true
        ? '$subjectLabel ${user.id}'
        : subjectLabel;
    final confirmed = await _showUserActionConfirmation(
      context,
      title: willBeActive
          ? 'Activate $subjectTitle'
          : 'Deactivate $subjectTitle',
      message:
          'Are you sure you want to ${willBeActive ? 'activate' : 'deactivate'} ${user.name ?? 'this user'}?',
      confirmLabel: willBeActive ? 'Activate' : 'Deactivate',
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    await vm.setUserActive(user, willBeActive);
    if (!context.mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      willBeActive ? 'User activated.' : 'User deactivated.',
    );
  }

  static String _userDialogTitle(String action, UserModel? user) {
    final roleLabel = formatRole(user?.role);
    final subjectLabel = roleLabel == '-' ? 'User' : roleLabel;
    final idLabel = user?.id?.trim() ?? '';

    if (action == 'Edit' && idLabel.isNotEmpty) {
      return '$action $subjectLabel $idLabel';
    }
    return '$action $subjectLabel';
  }

  static Future<bool> _showUserActionConfirmation(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool isDanger = false,
  }) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: isDanger
                  ? AppColors.danger
                  : AppColors.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }
}

class _UsersToolbar extends StatelessWidget {
  const _UsersToolbar({required this.vm});

  final AdminUsersViewModel vm;

  @override
  Widget build(BuildContext context) {
    final roleOptions = vm.roleOptions();

    return SizedBox(
      width: double.infinity,
      child: AdminListToolbar(
        controlHeight: AdminUsersView.usersHeaderControlHeight,
        surfaceRadius: AdminUsersView.usersSurfaceRadius,
        search: _UsersSearchField(
          initialValue: vm.searchQuery,
          onChanged: vm.updateSearchQuery,
        ),
        filtersBuilder: (context, iconOnly) => _UsersFiltersPanel(
          vm: vm,
          roleOptions: roleOptions,
          iconOnly: iconOnly,
        ),
        onNewPressed: vm.canCreateUsers
            ? () => AdminUsersView.showNewUserDialog(context, vm)
            : null,
      ),
    );
  }
}

class _UsersFiltersPanel extends StatefulWidget {
  const _UsersFiltersPanel({
    required this.vm,
    required this.roleOptions,
    required this.iconOnly,
  });

  final AdminUsersViewModel vm;
  final List<String> roleOptions;
  final bool iconOnly;

  @override
  State<_UsersFiltersPanel> createState() => _UsersFiltersPanelState();
}

class _UsersFiltersPanelState extends State<_UsersFiltersPanel> {
  final FocusNode _roleFocusNode = FocusNode();
  final FocusNode _activeFocusNode = FocusNode();
  final FocusNode _onlineFocusNode = FocusNode();

  void _unfocusFilterFields() {
    _roleFocusNode.unfocus();
    _activeFocusNode.unfocus();
    _onlineFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _roleFocusNode.dispose();
    _activeFocusNode.dispose();
    _onlineFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    const overlayRightPadding = 24.0;
    const filterItemWidth = 180.0;
    const overlayPadding = 14.0;
    const desiredOverlayWidth = filterItemWidth + (overlayPadding * 2);
    final overlayWidth = (screenWidth - 32 - overlayRightPadding).clamp(
      1.0,
      desiredOverlayWidth,
    );
    final contentWidth = (overlayWidth - (overlayPadding * 2)).clamp(
      1.0,
      desiredOverlayWidth,
    );
    final itemWidth = contentWidth;

    return AdminListFiltersButton(
      controlHeight: AdminUsersView.usersFilterControlHeight,
      surfaceRadius: AdminUsersView.usersSurfaceRadius,
      iconOnly: widget.iconOnly,
      menuChildren: [
        SizedBox(
          width: overlayWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _unfocusFilterFields,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: itemWidth,
                    height: AdminUsersView.usersFilterControlHeight,
                    child: _UsersFilterDropdown(
                      label: 'Role',
                      value: widget.vm.roleFilter,
                      focusNode: _roleFocusNode,
                      items: widget.roleOptions,
                      onChanged: widget.vm.updateRoleFilter,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: AdminUsersView.usersFilterControlHeight,
                    child: _UsersFilterDropdown(
                      label: 'Is Active',
                      value: widget.vm.activeFilter,
                      focusNode: _activeFocusNode,
                      items: const ['All', 'Active', 'Inactive'],
                      onChanged: widget.vm.updateActiveFilter,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: AdminUsersView.usersFilterControlHeight,
                    child: _UsersFilterDropdown(
                      label: 'Is Online',
                      value: widget.vm.onlineFilter,
                      focusNode: _onlineFocusNode,
                      items: const ['All', 'Online', 'Offline'],
                      onChanged: widget.vm.updateOnlineFilter,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: AdminUsersView.usersFilterControlHeight,
                    child: _UsersDateFilter(
                      label: 'Created Start',
                      value: widget.vm.startDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateStartDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: AdminUsersView.usersFilterControlHeight,
                    child: _UsersDateFilter(
                      label: 'Created End',
                      value: widget.vm.endDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateEndDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: AdminUsersView.usersFilterControlHeight,
                    child: _UsersDateFilter(
                      label: 'Updated Start',
                      value: widget.vm.updatedStartDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateUpdatedStartDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: AdminUsersView.usersFilterControlHeight,
                    child: _UsersDateFilter(
                      label: 'Updated End',
                      value: widget.vm.updatedEndDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateUpdatedEndDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterClearButtonHeight,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
                        widget.vm.clearFilters();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AdminUsersView.usersSurfaceRadius,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UsersSearchField extends StatelessWidget {
  const _UsersSearchField({
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AdminListSearchField(
      controlHeight: AdminUsersView.usersHeaderControlHeight,
      surfaceRadius: AdminUsersView.usersSurfaceRadius,
      initialValue: initialValue,
      onChanged: onChanged,
    );
  }
}

class _UsersFilterDropdown extends StatelessWidget {
  const _UsersFilterDropdown({
    required this.label,
    required this.value,
    required this.focusNode,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final FocusNode focusNode;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  static const _subtlePrimaryTextStyle = adminDropdownDisplayTextStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AdminUsersView.usersFilterControlHeight,
      child: AdminDropdownFormField<String>(
        initialValue: value == 'All' ? null : value,
        focusNode: focusNode,
        unfocusOnDismissWithoutSelection: true,
        iconEnabledColor: AppColors.primaryColor,
        style: _subtlePrimaryTextStyle,
        decoration: adminFormInputDecoration(
          label,
          radius: AdminUsersView.usersSurfaceRadius,
          minHeight: AdminUsersView.usersFilterControlHeight,
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<String>(
                value: item,
                child: Text(
                  humanizeDropdownValue(item),
                  overflow: TextOverflow.ellipsis,
                  style: _subtlePrimaryTextStyle,
                ),
              ),
            )
            .toList(),
        onChanged: (selected) {
          onChanged(selected);
          focusNode.unfocus();
        },
      ),
    );
  }
}

class _UsersDateFilter extends StatefulWidget {
  const _UsersDateFilter({
    required this.label,
    required this.value,
    required this.formatter,
    required this.onSelected,
  });

  final String label;
  final DateTime? value;
  final String Function(DateTime?) formatter;
  final ValueChanged<DateTime?> onSelected;

  @override
  State<_UsersDateFilter> createState() => _UsersDateFilterState();
}

class _UsersDateFilterState extends State<_UsersDateFilter> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayValue);
    _focusNode = FocusNode()..canRequestFocus = false;
  }

  @override
  void didUpdateWidget(covariant _UsersDateFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != _displayValue) {
      _controller.value = _controller.value.copyWith(
        text: _displayValue,
        selection: TextSelection.collapsed(offset: _displayValue.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _displayValue =>
      widget.value == null ? '' : widget.formatter(widget.value);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (context.mounted) {
      widget.onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeFillColor = appFieldInteractiveFillColor(context);
    return SizedBox(
      height: AdminUsersView.usersFilterControlHeight,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: Listener(
          onPointerDown: (_) => setState(() => _isPressed = true),
          onPointerUp: (_) => setState(() => _isPressed = false),
          onPointerCancel: (_) => setState(() => _isPressed = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickDate,
            child: IgnorePointer(
              child: TextFormField(
                controller: _controller,
                focusNode: _focusNode,
                readOnly: true,
                showCursor: false,
                enableInteractiveSelection: false,
                style: adminDropdownDisplayTextStyle,
                decoration:
                    adminFormInputDecoration(
                      widget.label,
                      radius: AdminUsersView.usersSurfaceRadius,
                      minHeight: AdminUsersView.usersFilterControlHeight,
                    ).copyWith(
                      fillColor: _isHovered || _isPressed
                          ? activeFillColor
                          : Colors.white,
                      suffixIcon: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _pickDate,
                        child: Icon(
                          Icons.calendar_today_rounded,
                          size: 18,
                          color: AppColors.primaryColor,
                        ),
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 42,
                        minHeight: 42,
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.emptyMessage,
    required this.vm,
    required this.onCurrentUserUpdated,
  });

  final List<UserModel> users;
  final String emptyMessage;
  final AdminUsersViewModel vm;
  final Future<void> Function() onCurrentUserUpdated;

  static const _headerStyle = TextStyle(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w700,
  );

  static const _valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const _nameStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
  );
  static const _onlineNameColor = Color(0xFF2EAD62);

  static const _defaultTrailingPadding =
      AdminListMeasurements.defaultTrailingPadding;
  static const _extraWidthAllowance =
      AdminListMeasurements.defaultExtraWidthAllowance;
  static const _maxNameEmailBasisWidth = 170.0;
  static const _maxCreatedBasisWidth = 150.0;
  static const _actionsLaneMinWidth = 176.0;

  @override
  Widget build(BuildContext context) {
    final longestIdValue = _longestText(users.map((user) => user.id ?? '-'));
    final longestNameValue = _longestText(
      users.map((user) => user.name ?? '-'),
    );
    final longestPhoneValue = _longestText(
      users.map((user) => user.phone ?? '-'),
    );
    final longestEmailValue = _longestText(
      users.map((user) => user.email ?? '-'),
    );
    final longestRoleValue = _longestText(
      users.map((user) => AdminUsersView.formatRole(user.role)),
    );
    final longestCreatedAtValue = _longestText(
      users.map((user) => AdminUsersView.formatCreatedAt(user.createdAt)),
    );
    final longestUpdatedAtValue = _longestText(
      users.map((user) => AdminUsersView.formatUpdatedAt(user.updatedAt)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final idWidth = _maxTextWidth(
          context,
          textScaler,
          'ID',
          _headerStyle,
          longestIdValue,
          _valueStyle,
        );
        final nameWidth = _cappedBasisWidth(
          _maxTextWidth(
            context,
            textScaler,
            'Name',
            _headerStyle,
            longestNameValue,
            _nameStyle,
          ),
          _maxNameEmailBasisWidth,
        );
        final phoneWidth = _maxTextWidth(
          context,
          textScaler,
          'Phone',
          _headerStyle,
          longestPhoneValue,
          _valueStyle,
        );
        final roleWidth = _maxTextWidth(
          context,
          textScaler,
          'Role',
          _headerStyle,
          longestRoleValue,
          _valueStyle,
        );
        final emailWidth = _cappedBasisWidth(
          _maxTextWidth(
            context,
            textScaler,
            'Email',
            _headerStyle,
            longestEmailValue,
            _valueStyle,
          ),
          _maxNameEmailBasisWidth,
        );
        final createdAtWidth = _cappedBasisWidth(
          _maxTextWidth(
            context,
            textScaler,
            'Created',
            _headerStyle,
            longestCreatedAtValue,
            _valueStyle,
          ),
          _maxCreatedBasisWidth,
        );
        final updatedAtWidth = _cappedBasisWidth(
          _maxTextWidth(
            context,
            textScaler,
            'Updated',
            _headerStyle,
            longestUpdatedAtValue,
            _valueStyle,
          ),
          _maxCreatedBasisWidth,
        );
        final actionsWidth = _maxValue(
          _actionsLaneMinWidth,
          _measureTextWidth(context, textScaler, 'Actions', _headerStyle),
        );
        final resolvedIdWidth = _resolvedColumnWidth(idWidth);
        final resolvedNameWidth = _resolvedColumnWidth(nameWidth);
        final resolvedPhoneWidth = _resolvedColumnWidth(phoneWidth);
        final resolvedRoleWidth = _resolvedColumnWidth(roleWidth);
        final resolvedEmailWidth = _resolvedColumnWidth(emailWidth);
        final resolvedCreatedAtWidth = _resolvedColumnWidth(createdAtWidth);
        final resolvedUpdatedAtWidth = _resolvedColumnWidth(updatedAtWidth);
        final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;
        final totalMeasuredWidth =
            resolvedIdWidth +
            resolvedNameWidth +
            resolvedPhoneWidth +
            resolvedEmailWidth +
            resolvedRoleWidth +
            resolvedCreatedAtWidth +
            resolvedUpdatedAtWidth +
            resolvedActionsWidth +
            40;
        final useResponsiveCards = totalMeasuredWidth > constraints.maxWidth;
        if (useResponsiveCards) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AdminUsersView.usersTableSectionGap),
              if (users.isEmpty) _UsersEmptyState(message: emptyMessage),
              if (users.isNotEmpty)
                Column(
                  children: users
                      .asMap()
                      .entries
                      .map(
                        (entry) => Padding(
                          padding: EdgeInsets.only(
                            bottom: entry.key == users.length - 1 ? 0 : 12,
                          ),
                          child: _UsersResponsiveCard(
                            user: entry.value,
                            vm: vm,
                            onCurrentUserUpdated: onCurrentUserUpdated,
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminListHeaderBar(
              minHeight: AdminUsersView.usersHeaderControlHeight,
              borderRadius: AdminUsersView.usersSurfaceRadius,
              child: Row(
                children: [
                  _UsersFixedSlot(
                    width: resolvedIdWidth,
                    child: const _UsersHeader(
                      label: 'ID',
                      trailingPadding: _defaultTrailingPadding,
                    ),
                  ),
                  _UsersFixedSlot(
                    width: resolvedNameWidth,
                    child: const _UsersHeader(
                      label: 'Name',
                      trailingPadding: _defaultTrailingPadding,
                    ),
                  ),
                  _UsersFixedSlot(
                    width: resolvedPhoneWidth,
                    child: const _UsersHeader(
                      label: 'Phone',
                      trailingPadding: _defaultTrailingPadding,
                    ),
                  ),
                  _UsersFixedSlot(
                    width: resolvedEmailWidth,
                    child: const _UsersHeader(
                      label: 'Email',
                      trailingPadding: _defaultTrailingPadding,
                    ),
                  ),
                  _UsersFixedSlot(
                    width: resolvedRoleWidth,
                    child: const _UsersHeader(
                      label: 'Role',
                      trailingPadding: _defaultTrailingPadding,
                    ),
                  ),
                  _UsersFixedSlot(
                    width: resolvedCreatedAtWidth,
                    child: const _UsersHeader(
                      label: 'Created',
                      trailingPadding: _defaultTrailingPadding,
                    ),
                  ),
                  _UsersFixedSlot(
                    width: resolvedUpdatedAtWidth,
                    child: const _UsersHeader(
                      label: 'Updated',
                      trailingPadding: _defaultTrailingPadding,
                    ),
                  ),
                  AdminListTrailingActionsLane(
                    width: resolvedActionsWidth,
                    child: const _UsersHeader(
                      label: 'Actions',
                      trailingPadding: 0,
                      alignment: Alignment.centerRight,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AdminUsersView.usersTableSectionGap),
            if (users.isEmpty) _UsersEmptyState(message: emptyMessage),
            if (users.isNotEmpty)
              Column(
                children: users
                    .asMap()
                    .entries
                    .map(
                      (entry) => Padding(
                        padding: EdgeInsets.only(
                          bottom: entry.key == users.length - 1 ? 0 : 12,
                        ),
                        child: _UsersWideRow(
                          user: entry.value,
                          vm: vm,
                          onCurrentUserUpdated: onCurrentUserUpdated,
                          resolvedIdWidth: resolvedIdWidth,
                          resolvedNameWidth: resolvedNameWidth,
                          resolvedPhoneWidth: resolvedPhoneWidth,
                          resolvedEmailWidth: resolvedEmailWidth,
                          resolvedRoleWidth: resolvedRoleWidth,
                          resolvedCreatedAtWidth: resolvedCreatedAtWidth,
                          resolvedUpdatedAtWidth: resolvedUpdatedAtWidth,
                          resolvedActionsWidth: resolvedActionsWidth,
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        );
      },
    );
  }

  static double _maxValue(double first, double second) {
    return first > second ? first : second;
  }

  static double _cappedBasisWidth(double measuredWidth, double maxWidth) {
    return measuredWidth > maxWidth ? maxWidth : measuredWidth;
  }

  static String _longestText(Iterable<String> values) {
    var longest = '-';
    for (final value in values) {
      if (value.length > longest.length) {
        longest = value;
      }
    }
    return longest;
  }

  static double _resolvedColumnWidth(double measuredWidth) {
    return AdminListMeasurements.resolvedColumnWidth(
      measuredWidth,
      trailingPadding: _defaultTrailingPadding,
      extraWidthAllowance: _extraWidthAllowance,
    );
  }

  static double _maxTextWidth(
    BuildContext context,
    TextScaler textScaler,
    String label,
    TextStyle labelStyle,
    String value,
    TextStyle valueStyle,
  ) {
    return AdminListMeasurements.maxTextWidth(
      context,
      textScaler,
      label,
      labelStyle,
      value,
      valueStyle,
    );
  }

  static double _measureTextWidth(
    BuildContext context,
    TextScaler textScaler,
    String text,
    TextStyle style,
  ) {
    return AdminListMeasurements.measureTextWidth(
      context,
      textScaler,
      text,
      style,
    );
  }
}

class _UsersWideRow extends StatelessWidget {
  const _UsersWideRow({
    required this.user,
    required this.vm,
    required this.onCurrentUserUpdated,
    required this.resolvedIdWidth,
    required this.resolvedNameWidth,
    required this.resolvedPhoneWidth,
    required this.resolvedEmailWidth,
    required this.resolvedRoleWidth,
    required this.resolvedCreatedAtWidth,
    required this.resolvedUpdatedAtWidth,
    required this.resolvedActionsWidth,
  });

  final UserModel user;
  final AdminUsersViewModel vm;
  final Future<void> Function() onCurrentUserUpdated;
  final double resolvedIdWidth;
  final double resolvedNameWidth;
  final double resolvedPhoneWidth;
  final double resolvedEmailWidth;
  final double resolvedRoleWidth;
  final double resolvedCreatedAtWidth;
  final double resolvedUpdatedAtWidth;
  final double resolvedActionsWidth;

  bool get _isEligibleAndOnline =>
      RoleAccessService.instance.isOnlineEligibleRole(user.role) &&
      (user.isOnline ?? false);

  @override
  Widget build(BuildContext context) {
    final idValue = user.id ?? '-';
    final nameValue = user.name ?? '-';
    final phoneValue = user.phone ?? '-';
    final emailValue = user.email ?? '-';
    final roleValue = AdminUsersView.formatRole(user.role);
    final createdAtValue = AdminUsersView.formatCreatedAt(user.createdAt);
    final updatedAtValue = AdminUsersView.formatUpdatedAt(user.updatedAt);
    return AdminListItemCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _UsersFixedSlot(
            width: resolvedIdWidth,
            child: _UsersCell(
              child: Text(
                idValue,
                style: _UsersTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _UsersFixedSlot(
            width: resolvedNameWidth,
            child: _UsersCell(
              child: Text(
                nameValue,
                style: _UsersTable._nameStyle.copyWith(
                  color: _isEligibleAndOnline
                      ? _UsersTable._onlineNameColor
                      : AppColors.textPrimary,
                ),
                softWrap: true,
              ),
            ),
          ),
          _UsersFixedSlot(
            width: resolvedPhoneWidth,
            child: _UsersCell(
              child: Text(
                phoneValue,
                style: _UsersTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _UsersFixedSlot(
            width: resolvedEmailWidth,
            child: _UsersCell(
              child: Text(
                emailValue,
                style: _UsersTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _UsersFixedSlot(
            width: resolvedRoleWidth,
            child: _UsersCell(
              child: Text(
                roleValue,
                style: _UsersTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _UsersFixedSlot(
            width: resolvedCreatedAtWidth,
            child: _UsersCell(
              child: Text(
                createdAtValue,
                style: _UsersTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _UsersFixedSlot(
            width: resolvedUpdatedAtWidth,
            child: _UsersCell(
              child: Text(
                updatedAtValue,
                style: _UsersTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          AdminListTrailingActionsLane(
            width: resolvedActionsWidth,
            child: _UsersCell(
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _UserActionButton(
                    icon: Icons.visibility_rounded,
                    backgroundColor: Colors.yellow.shade900,
                    onTap: () {
                      vm.openUserView(user);
                    },
                  ),
                  if (vm.canUpdateUsers)
                    _UserActionButton(
                      icon: Icons.edit_rounded,
                      onTap: () {
                        AdminUsersView.showEditUserDialog(
                          context,
                          vm,
                          user,
                          onCurrentUserUpdated,
                        );
                      },
                    ),
                  if (vm.canUpdateUsers)
                    _UserActionButton(
                      icon: (user.isActive ?? false)
                          ? Icons.close_rounded
                          : Icons.check_rounded,
                      backgroundColor: (user.isActive ?? false)
                          ? AppColors.dangerStrong
                          : const Color(0xFF2EAD62),
                      onTap: () {
                        AdminUsersView.handleToggleUserActive(
                          context,
                          vm,
                          user,
                        );
                      },
                    ),
                  if (vm.canDeleteUsers)
                    _UserActionButton(
                      icon: Icons.delete_rounded,
                      isDanger: true,
                      onTap: () {
                        AdminUsersView.handleDeleteUser(context, vm, user);
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersFixedSlot extends StatelessWidget {
  const _UsersFixedSlot({required this.child, required this.width});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AdminListFixedSlot(width: width, child: child);
  }
}

class _UsersHeader extends StatelessWidget {
  const _UsersHeader({
    required this.label,
    this.trailingPadding = _UsersTable._defaultTrailingPadding,
    this.alignment = Alignment.centerLeft,
    this.textAlign = TextAlign.left,
  });

  final String label;
  final double trailingPadding;
  final Alignment alignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return AdminListHeaderCell(
      label: label,
      trailingPadding: trailingPadding,
      alignment: alignment,
      textAlign: textAlign,
    );
  }
}

class _UsersResponsiveCard extends StatelessWidget {
  const _UsersResponsiveCard({
    required this.user,
    required this.vm,
    required this.onCurrentUserUpdated,
  });

  final UserModel user;
  final AdminUsersViewModel vm;
  final Future<void> Function() onCurrentUserUpdated;

  static final _labelStyle = TextStyle(
    color: AppColors.primaryColor.withValues(alpha: 0.72),
    fontWeight: FontWeight.w700,
  );

  static const _valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  bool get _isEligibleAndOnline =>
      RoleAccessService.instance.isOnlineEligibleRole(user.role) &&
      (user.isOnline ?? false);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const fieldGap = 16.0;
        final textScaler = MediaQuery.textScalerOf(context);
        final useSingleColumn = constraints.maxWidth < 520;
        final showTopActionsRow = constraints.maxWidth < 900;
        final stackTopActions = constraints.maxWidth < 320;
        final resolvedFields = [
          ('ID', user.id ?? '-'),
          ('Name', user.name ?? '-'),
          ('Phone', user.phone ?? '-'),
          ('Email', user.email ?? '-'),
          ('Role', AdminUsersView.formatRole(user.role)),
          ('Created', AdminUsersView.formatCreatedAtSingleLine(user.createdAt)),
          ('Updated', AdminUsersView.formatUpdatedAtSingleLine(user.updatedAt)),
        ];
        final contentWidths = resolvedFields
            .map(
              (field) => _resolvedFieldWidth(
                context,
                textScaler,
                constraints.maxWidth,
                field.$1,
                field.$2,
              ),
            )
            .toList();

        return AdminListItemCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: useSingleColumn
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (showTopActionsRow && !stackTopActions)
                Row(
                  children: [
                    const Spacer(),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _UserActionButton(
                          icon: Icons.visibility_rounded,
                          backgroundColor: Colors.yellow.shade900,
                          onTap: () {
                            vm.openUserView(user);
                          },
                        ),
                        _UserActionButton(
                          icon: Icons.edit_rounded,
                          onTap: () {
                            AdminUsersView.showEditUserDialog(
                              context,
                              vm,
                              user,
                              onCurrentUserUpdated,
                            );
                          },
                        ),
                        _UserActionButton(
                          icon: (user.isActive ?? false)
                              ? Icons.close_rounded
                              : Icons.check_rounded,
                          backgroundColor: (user.isActive ?? false)
                              ? AppColors.dangerStrong
                              : const Color(0xFF2EAD62),
                          onTap: () {
                            AdminUsersView.handleToggleUserActive(
                              context,
                              vm,
                              user,
                            );
                          },
                        ),
                        if (vm.canDeleteUsers)
                          _UserActionButton(
                            icon: Icons.delete_rounded,
                            isDanger: true,
                            onTap: () {
                              AdminUsersView.handleDeleteUser(
                                context,
                                vm,
                                user,
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              if (showTopActionsRow) const SizedBox(height: 18),
              Wrap(
                spacing: fieldGap,
                runSpacing: fieldGap,
                children: List.generate(
                  resolvedFields.length,
                  (index) => _UsersResponsiveField(
                    label: resolvedFields[index].$1,
                    value: resolvedFields[index].$2,
                    width: useSingleColumn
                        ? constraints.maxWidth
                        : contentWidths[index],
                    centered: useSingleColumn,
                    valueColor:
                        resolvedFields[index].$1 == 'Name' &&
                            _isEligibleAndOnline
                        ? _UsersTable._onlineNameColor
                        : null,
                  ),
                ).toList(),
              ),
              if (showTopActionsRow && stackTopActions) ...[
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _UserActionButton(
                      icon: Icons.visibility_rounded,
                      backgroundColor: Colors.yellow.shade900,
                      onTap: () {
                        vm.openUserView(user);
                      },
                    ),
                    if (vm.canUpdateUsers)
                      _UserActionButton(
                        icon: Icons.edit_rounded,
                        onTap: () {
                          AdminUsersView.showEditUserDialog(
                            context,
                            vm,
                            user,
                            onCurrentUserUpdated,
                          );
                        },
                      ),
                    if (vm.canUpdateUsers)
                      _UserActionButton(
                        icon: (user.isActive ?? false)
                            ? Icons.close_rounded
                            : Icons.check_rounded,
                        backgroundColor: (user.isActive ?? false)
                            ? AppColors.dangerStrong
                            : const Color(0xFF2EAD62),
                        onTap: () {
                          AdminUsersView.handleToggleUserActive(
                            context,
                            vm,
                            user,
                          );
                        },
                      ),
                    if (vm.canDeleteUsers)
                      _UserActionButton(
                        icon: Icons.delete_rounded,
                        isDanger: true,
                        onTap: () {
                          AdminUsersView.handleDeleteUser(context, vm, user);
                        },
                      ),
                  ],
                ),
              ],
              if (!showTopActionsRow) ...[
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.start,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _UserActionButton(
                      icon: Icons.visibility_rounded,
                      backgroundColor: Colors.yellow.shade900,
                      onTap: () {
                        vm.openUserView(user);
                      },
                    ),
                    if (vm.canUpdateUsers)
                      _UserActionButton(
                        icon: Icons.edit_rounded,
                        onTap: () {
                          AdminUsersView.showEditUserDialog(
                            context,
                            vm,
                            user,
                            onCurrentUserUpdated,
                          );
                        },
                      ),
                    if (vm.canUpdateUsers)
                      _UserActionButton(
                        icon: (user.isActive ?? false)
                            ? Icons.close_rounded
                            : Icons.check_rounded,
                        backgroundColor: (user.isActive ?? false)
                            ? AppColors.dangerStrong
                            : const Color(0xFF2EAD62),
                        onTap: () {
                          AdminUsersView.handleToggleUserActive(
                            context,
                            vm,
                            user,
                          );
                        },
                      ),
                    if (vm.canDeleteUsers)
                      _UserActionButton(
                        icon: Icons.delete_rounded,
                        isDanger: true,
                        onTap: () {
                          AdminUsersView.handleDeleteUser(context, vm, user);
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static double _resolvedFieldWidth(
    BuildContext context,
    TextScaler textScaler,
    double maxWidth,
    String label,
    String value,
  ) {
    return AdminListMeasurements.resolvedResponsiveFieldWidth(
      context,
      textScaler,
      maxWidth,
      label,
      value,
      labelStyle: _labelStyle,
      valueStyle: _valueStyle,
    );
  }
}

class _UsersResponsiveField extends StatelessWidget {
  const _UsersResponsiveField({
    required this.label,
    required this.value,
    required this.width,
    required this.centered,
    this.valueColor,
  });

  final String label;
  final String value;
  final double width;
  final bool centered;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return AdminListResponsiveField(
      title: label,
      value: value,
      width: width,
      centered: centered,
      valueColor: valueColor,
    );
  }
}

class _UsersCell extends StatelessWidget {
  const _UsersCell({
    required this.child,
    this.trailingPadding = _UsersTable._defaultTrailingPadding,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final double trailingPadding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AdminListBodyCell(
      trailingPadding: trailingPadding,
      alignment: alignment,
      child: child,
    );
  }
}

class _UsersEmptyState extends StatelessWidget {
  const _UsersEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AdminUserDetailDialog extends StatelessWidget {
  const _AdminUserDetailDialog({
    required this.currentUser,
    required this.initialViewedUser,
    required this.onCurrentUserUpdated,
    required this.onLogout,
    required this.isQuickLoggedIn,
  });

  final UserModel currentUser;
  final UserModel initialViewedUser;
  final Future<void> Function() onCurrentUserUpdated;
  final VoidCallback onLogout;
  final bool isQuickLoggedIn;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = size.width > 1280 ? 1160.0 : size.width - 48;
    final dialogHeight = size.height > 940 ? 860.0 : size.height - 48;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: _AdminUserDetailDialogBody(
          currentUser: currentUser,
          initialViewedUser: initialViewedUser,
          onCurrentUserUpdated: onCurrentUserUpdated,
          onLogout: onLogout,
          isQuickLoggedIn: isQuickLoggedIn,
        ),
      ),
    );
  }
}

class _AdminUserDetailDialogBody extends StatefulWidget {
  const _AdminUserDetailDialogBody({
    required this.currentUser,
    required this.initialViewedUser,
    required this.onCurrentUserUpdated,
    required this.onLogout,
    required this.isQuickLoggedIn,
  });

  final UserModel currentUser;
  final UserModel initialViewedUser;
  final Future<void> Function() onCurrentUserUpdated;
  final VoidCallback onLogout;
  final bool isQuickLoggedIn;

  @override
  State<_AdminUserDetailDialogBody> createState() =>
      _AdminUserDetailDialogBodyState();
}

class _AdminUserDetailDialogBodyState
    extends State<_AdminUserDetailDialogBody> {
  bool _initializedInitialViewedUser = false;
  bool _isUploadingViewedProfilePhoto = false;
  bool _isUploadingViewedLicensePhoto = false;

  String? _effectiveCurrentRole(AdminUsersViewModel vm) => RoleAccessService
      .instance
      .effectiveRoleKey(vm.currentUser?.role ?? widget.currentUser.role);

  Future<void> _saveViewedUserProfileChanges(
    AdminUsersViewModel vm,
    UserModel user,
    ProfilePendingProfileChanges changes,
  ) async {
    if ((_isUploadingViewedProfilePhoto || _isUploadingViewedLicensePhoto) ||
        !changes.hasChanges) {
      return;
    }
    final userId = user.id?.trim();
    if (userId == null || userId.isEmpty) {
      throw const AuthFailure('User ID is required.');
    }

    setState(() {
      _isUploadingViewedProfilePhoto = changes.photoUpload != null;
      _isUploadingViewedLicensePhoto = changes.licenseUpload != null;
    });
    try {
      var updatedUser = user;
      final photoUpload = changes.photoUpload;
      if (photoUpload != null) {
        updatedUser = await AuthRequest.instance.saveUserPhoto(
          userId: userId,
          bytes: photoUpload.bytes,
          fileName: photoUpload.fileName,
          mimeType: photoUpload.mimeType,
          size: photoUpload.size,
        );
      }
      final licenseUpload = changes.licenseUpload;
      if (licenseUpload != null) {
        updatedUser = await AuthRequest.instance.saveDriverLicensePhoto(
          userId: userId,
          bytes: licenseUpload.bytes,
          fileName: licenseUpload.fileName,
          mimeType: licenseUpload.mimeType,
          size: licenseUpload.size,
        );
      }
      vm.syncUser(updatedUser);
      if (updatedUser.id == widget.currentUser.id) {
        await widget.onCurrentUserUpdated();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingViewedProfilePhoto = false;
          _isUploadingViewedLicensePhoto = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AdminUsersViewModel>.reactive(
      viewModelBuilder: AdminUsersViewModel.new,
      onViewModelReady: (vm) async {
        await vm.loadUsers(fallbackCurrentUser: widget.currentUser);
        if (!mounted || _initializedInitialViewedUser) {
          return;
        }
        final matchedUser =
            vm.users
                .where((user) => user.id == widget.initialViewedUser.id)
                .firstOrNull ??
            widget.initialViewedUser;
        _initializedInitialViewedUser = true;
        vm.openUserView(matchedUser);
      },
      builder: (context, vm, _) {
        vm.ensureCurrentUserContext(widget.currentUser);
        final viewedUser = vm.viewedUser;
        if (viewedUser == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final isViewingCurrentUser = viewedUser.id == widget.currentUser.id;
        final viewedBusinessUser = vm.parentBusinessFor(viewedUser);
        return AppPageLoadingOverlay(
          isVisible:
              vm.showBlockingLoading ||
              _isUploadingViewedProfilePhoto ||
              _isUploadingViewedLicensePhoto,
          message: _isUploadingViewedLicensePhoto
              ? 'Uploading license photo ...'
              : _isUploadingViewedProfilePhoto
              ? 'Uploading profile photo ...'
              : vm.busyMessage,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileView(
                  key: profileViewRefreshKey(viewedUser),
                  user: viewedUser,
                  scrollable: false,
                  padding: EdgeInsets.zero,
                  businessUser: viewedBusinessUser,
                  onBusinessDetailsPressed: viewedBusinessUser == null
                      ? null
                      : () => vm.openUserView(
                          viewedBusinessUser,
                          preserveCurrent: true,
                        ),
                  isCurrentUserView: isViewingCurrentUser,
                  onLogout: widget.onLogout,
                  logoutLabel: widget.isQuickLoggedIn ? 'Go Back' : 'Logout',
                  onSaveProfileChanges:
                      isViewingCurrentUser &&
                          RoleAccessService.instance.canAccess(
                            'profile.update',
                            role: _effectiveCurrentRole(vm),
                          )
                      ? (changes) => _saveViewedUserProfileChanges(
                          vm,
                          viewedUser,
                          changes,
                        )
                      : null,
                  onQuickActionPressed: isViewingCurrentUser
                      ? null
                      : () => Navigator.of(context).pop(),
                  quickActionLabel: isViewingCurrentUser ? null : 'Close',
                  onEditPressed: () async {
                    if (!vm.canUpdateUsers) {
                      return;
                    }
                    await AdminUsersView.showEditUserDialog(
                      context,
                      vm,
                      viewedUser,
                      widget.onCurrentUserUpdated,
                    );
                  },
                ),
                const SizedBox(height: 18),
                UserBookingsSection(
                  user: viewedUser,
                  padding: EdgeInsets.zero,
                  useAdminListStyle: true,
                  forceWideLayout: false,
                  onViewBooking: (booking) async {
                    await AdminBookingsView.showBookingDetailDialog(
                      context,
                      user: widget.currentUser,
                      booking: booking,
                    );
                  },
                  onEditBooking:
                      !RoleAccessService.instance.canAccess(
                        'bookings.update',
                        role: _effectiveCurrentRole(vm),
                      )
                      ? null
                      : (booking) async {
                          try {
                            await AdminBookingsView.showEditBookingDialog(
                              context,
                              booking: booking,
                              currentUser: vm.currentUser ?? widget.currentUser,
                            );
                          } catch (error) {
                            if (!context.mounted) {
                              return;
                            }
                            AppSnackbar.showError(
                              context,
                              userFacingErrorMessage(
                                error,
                                fallback:
                                    'We could not open the booking editor right now.',
                              ),
                            );
                          }
                        },
                  onNewBooking:
                      !RoleAccessService.instance.canAccess(
                        'bookings.create',
                        role: _effectiveCurrentRole(vm),
                      )
                      ? null
                      : () async {
                          try {
                            await AdminBookingsView.showNewBookingDialog(
                              context,
                              currentUser: vm.currentUser ?? widget.currentUser,
                            );
                          } catch (error) {
                            if (!context.mounted) {
                              return;
                            }
                            AppSnackbar.showError(
                              context,
                              userFacingErrorMessage(
                                error,
                                fallback:
                                    'We could not open the new booking dialog right now.',
                              ),
                            );
                          }
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UserDetailHeader extends StatelessWidget {
  const _UserDetailHeader({required this.user, required this.onBack});

  final UserModel user;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Transform.translate(
            offset: const Offset(-8, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.primaryColor,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  visualDensity: VisualDensity.compact,
                  splashRadius: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'User ${user.id ?? '-'}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({
    required this.title,
    required this.isEditing,
    required this.clientOptions,
    this.canCreateAdminUsers = true,
    this.initialUser,
    this.generatedId,
    this.onDraftChanged,
    this.onSaveAsync,
  });

  final String title;
  final bool isEditing;
  final List<UserModel> clientOptions;
  final bool canCreateAdminUsers;
  final UserModel? initialUser;
  final String? generatedId;
  final ValueChanged<UserModel>? onDraftChanged;
  final Future<void> Function(_UserFormDialogResult result)? onSaveAsync;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  late final TextEditingController _emailController;
  late final TextEditingController _nameController;
  late final TextEditingController _photoController;
  late final TextEditingController _phoneController;
  late final TextEditingController _positionController;
  late final TextEditingController _licenseController;
  late final TextEditingController _passwordController;
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _positionFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  late String? _roleValue;
  late bool _isActive;
  late bool _isOnline;
  String? _vehicleTypeId;
  bool _isLoadingVehicleTypes = true;
  List<VehicleCatalogItem> _vehicleTypes = const [];
  bool _isPasswordObscured = true;
  String? _photoValue;
  String? _licenseValue;
  _PendingImageUpload? _pendingPhotoUpload;
  _PendingImageUpload? _pendingLicenseUpload;
  bool _isSubmitting = false;

  bool get _isDriverRole => _roleValue == 'driver';
  bool get _supportsOnlineRole => _supportsOnlineRoleStatic(_roleValue);
  List<String> get _roleOptions {
    final roles = RoleAccessService.instance.adminUserRoleKeys;
    if (widget.isEditing || widget.canCreateAdminUsers) {
      return roles;
    }
    return roles.where((role) => role != 'admin').toList(growable: false);
  }

  List<DropdownMenuItem<String>> _vehicleTypeDropdownItems() {
    final items = <DropdownMenuItem<String>>[];
    final seen = <String>{};

    void addItem(VehicleCatalogItem? item) {
      final value = item?.id?.trim();
      if (value == null || value.isEmpty || !seen.add(value)) {
        return;
      }
      final name = (item?.name ?? '').trim();
      final slug = (item?.slug ?? '').trim();
      final label = [
        if (name.isNotEmpty) name else 'Vehicle Type',
        if (slug.isNotEmpty) '($slug)',
      ].join(' ').trim();
      items.add(
        DropdownMenuItem<String>(
          value: value,
          child: Text(label, style: adminDropdownDisplayTextStyle),
        ),
      );
    }

    addItem(widget.initialUser?.asDriver?.vehicleType);
    for (final item in _vehicleTypes) {
      addItem(item);
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    final user = widget.initialUser ?? const UserModel();
    final driver = user.asDriver;
    _emailController = TextEditingController(text: user.email ?? '');
    _nameController = TextEditingController(text: user.name ?? '');
    _photoController = TextEditingController(text: user.photo ?? '');
    _phoneController = TextEditingController(text: user.phone ?? '');
    _positionController = TextEditingController(text: user.position ?? '');
    _licenseController = TextEditingController(text: driver?.license ?? '');
    _passwordController = TextEditingController(text: user.password ?? '');
    final normalizedInitialRole = normalizeRoleKey(user.role);
    _roleValue =
        normalizedInitialRole.isNotEmpty &&
            _roleOptions.contains(normalizedInitialRole)
        ? normalizedInitialRole
        : null;
    _vehicleTypeId = driver?.vehicleType?.id;
    _isActive = widget.isEditing ? (user.isActive ?? false) : true;
    _isOnline = _supportsOnlineRoleStatic(normalizedInitialRole)
        ? (user.isOnline ?? false)
        : false;
    _photoValue = user.photo;
    _licenseValue = driver?.license;
    _emailController.addListener(_handleDraftChanged);
    _nameController.addListener(_handleDraftChanged);
    _photoController.addListener(_handleDraftChanged);
    _phoneController.addListener(_handleDraftChanged);
    _positionController.addListener(_handleDraftChanged);
    _licenseController.addListener(_handleDraftChanged);
    _passwordController.addListener(_handleDraftChanged);
    _handleDraftChanged();
    _loadVehicleTypes();
  }

  Future<void> _loadVehicleTypes() async {
    try {
      final vehicleTypes = await VehicleRequest.instance.getTypes();
      if (!mounted) {
        return;
      }
      setState(() {
        _vehicleTypes = vehicleTypes;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVehicleTypes = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.removeListener(_handleDraftChanged);
    _nameController.removeListener(_handleDraftChanged);
    _photoController.removeListener(_handleDraftChanged);
    _phoneController.removeListener(_handleDraftChanged);
    _positionController.removeListener(_handleDraftChanged);
    _licenseController.removeListener(_handleDraftChanged);
    _passwordController.removeListener(_handleDraftChanged);
    _emailController.dispose();
    _nameController.dispose();
    _photoController.dispose();
    _phoneController.dispose();
    _positionController.dispose();
    _licenseController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _nameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _positionFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _focusNext(FocusNode focusNode) {
    if (!mounted) {
      return;
    }
    FocusScope.of(context).requestFocus(focusNode);
  }

  void _unfocusCurrentField() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus) {
      currentFocus.unfocus();
    }
  }

  Future<void> _submitForm() async {
    final validationMessage = _validationMessage();
    if (validationMessage != null) {
      AppSnackbar.showError(context, validationMessage);
      return;
    }
    if (!widget.isEditing &&
        !widget.canCreateAdminUsers &&
        normalizeRoleKey(_roleValue) == 'admin') {
      AppSnackbar.showError(
        context,
        'Only admin users can create other admin users.',
      );
      return;
    }
    final baseUser = widget.initialUser ?? const UserModel();
    final now = DateTime.now();
    final selectedVehicleType = _vehicleTypes.where(
      (item) => item.id == _vehicleTypeId,
    );
    final fallbackVehicleType = widget.initialUser?.asDriver?.vehicleType;
    final result = _UserFormDialogResult(
      user: baseUser.copyWith(
        id: widget.isEditing ? baseUser.id : widget.generatedId,
        role: _roleValue,
        parentClientId: null,
        email: _nullIfEmpty(_emailController.text),
        name: _nullIfEmpty(_nameController.text),
        photo: _photoValue,
        phone: normalizePhilippinePhone(_phoneController.text),
        position: null,
        isActive: _isActive,
        isOnline: _supportsOnlineRole ? _isOnline : false,
        password: _nullIfEmpty(_passwordController.text),
        createdAt: widget.isEditing ? baseUser.createdAt : now,
        updatedAt: now,
        license: _isDriverRole ? _licenseValue : null,
        vehicleType: _isDriverRole
            ? (selectedVehicleType.isNotEmpty
                  ? selectedVehicleType.first
                  : (fallbackVehicleType?.id == _vehicleTypeId
                        ? fallbackVehicleType
                        : null))
            : null,
      ),
      pendingPhotoUpload: _pendingPhotoUpload,
      pendingLicenseUpload: _pendingLicenseUpload,
    );
    if (widget.onSaveAsync == null) {
      Navigator.of(context).pop(result);
      return;
    }
    if (_isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await widget.onSaveAsync!(result);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppSnackbar.showError(context, error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: widget.title,
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 14),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submitForm,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Text('Save'),
        ),
      ],
      child: AdminModalFormBody(
        children: _isDriverRole && _isLoadingVehicleTypes
            ? const [
                SizedBox(
                  height: 220,
                  child: AppPageLoading(
                    message: 'Loading vehicle types ...',
                    compact: true,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ]
            : [
                AdminModalFieldsSection(
                  children: [
                    AdminModalDropdownField<String>(
                      label: 'Role',
                      initialValue: _roleValue,
                      iconEnabledColor: AppColors.primaryColor,
                      bottomPadding: 6,
                      items: _roleOptions
                          .map(
                            (role) => DropdownMenuItem<String>(
                              value: role,
                              child: Text(
                                humanizeDropdownValue(role),
                                style: adminDropdownDisplayTextStyle,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() {
                        _roleValue = value;
                        if (_roleValue != 'driver') {
                          _vehicleTypeId = null;
                          _pendingLicenseUpload = null;
                        }
                        if (!_supportsOnlineRole) {
                          _isOnline = false;
                        }
                        _handleDraftChanged();
                      }),
                    ),
                    if (_isDriverRole)
                      AdminModalDropdownField<String>(
                        label: 'Vehicle Type',
                        initialValue: _vehicleTypeId,
                        iconEnabledColor: AppColors.primaryColor,
                        bottomPadding: 6,
                        disabledTapMessage:
                            'No active vehicle types available.',
                        items: _vehicleTypeDropdownItems(),
                        onChanged: (value) => setState(() {
                          _vehicleTypeId = value;
                          _handleDraftChanged();
                        }),
                      ),
                    _buildField(
                      _emailController,
                      'Email',
                      bottomPadding: 4,
                      focusNode: _emailFocusNode,
                      textInputAction: widget.isEditing
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onSubmitted: (_) => widget.isEditing
                          ? _submitForm()
                          : _focusNext(_nameFocusNode),
                    ),
                    _buildField(
                      _nameController,
                      'Name',
                      focusNode: _nameFocusNode,
                      textInputAction: widget.isEditing
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onSubmitted: (_) => widget.isEditing
                          ? _submitForm()
                          : _focusNext(_phoneFocusNode),
                    ),
                    _buildUploadField(
                      label: 'Photo',
                      controller: _photoController,
                      onTap: _pickPhotoFieldImage,
                    ),
                    _buildField(
                      _phoneController,
                      'Phone',
                      focusNode: _phoneFocusNode,
                      textInputAction: widget.isEditing
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onSubmitted: (_) => widget.isEditing
                          ? _submitForm()
                          : _focusNext(_passwordFocusNode),
                    ),
                    if (_isDriverRole)
                      _buildUploadField(
                        label: 'License',
                        controller: _licenseController,
                        onTap: _pickLicenseFieldImage,
                      ),
                    _buildField(
                      _passwordController,
                      'Password',
                      obscureText: true,
                      bottomPadding: 0,
                      focusNode: _passwordFocusNode,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        _unfocusCurrentField();
                        _submitForm();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildToggleRow(
                  title: 'Active',
                  value: _isActive,
                  onChanged: (value) => setState(() {
                    _isActive = value;
                    _handleDraftChanged();
                  }),
                ),
                if (_supportsOnlineRole) ...[
                  const SizedBox(height: 8),
                  _buildToggleRow(
                    title: 'Online',
                    value: _isOnline,
                    onChanged: (value) => setState(() {
                      _isOnline = value;
                      _handleDraftChanged();
                    }),
                  ),
                ],
              ],
      ),
    );
  }

  void _handleDraftChanged() {
    if (widget.isEditing) {
      return;
    }
    widget.onDraftChanged?.call(
      _buildUserFromFields(widget.initialUser ?? const UserModel()),
    );
  }

  UserModel _buildUserFromFields(UserModel baseUser) {
    final selectedVehicleType = _vehicleTypes.where(
      (item) => item.id == _vehicleTypeId,
    );
    final fallbackVehicleType = widget.initialUser?.asDriver?.vehicleType;
    return baseUser.copyWith(
      id: widget.isEditing ? baseUser.id : widget.generatedId,
      role: _roleValue,
      parentClientId: null,
      email: _nullIfEmpty(_emailController.text),
      name: _nullIfEmpty(_nameController.text),
      photo: _photoValue,
      phone: normalizePhilippinePhone(_phoneController.text),
      position: null,
      isActive: _isActive,
      isOnline: _supportsOnlineRole ? _isOnline : false,
      password: _nullIfEmpty(_passwordController.text),
      license: _isDriverRole ? _licenseValue : null,
      vehicleType: _isDriverRole
          ? (selectedVehicleType.isNotEmpty
                ? selectedVehicleType.first
                : (fallbackVehicleType?.id == _vehicleTypeId
                      ? fallbackVehicleType
                      : null))
          : null,
    );
  }

  Future<void> _pickPhotoFieldImage() async {
    await _pickImageField(
      controller: _photoController,
      onSelected: (upload) {
        _pendingPhotoUpload = upload;
      },
    );
  }

  Future<void> _pickLicenseFieldImage() async {
    await _pickImageField(
      controller: _licenseController,
      onSelected: (upload) {
        _pendingLicenseUpload = upload;
      },
    );
  }

  Future<void> _pickImageField({
    required TextEditingController controller,
    required ValueChanged<_PendingImageUpload> onSelected,
  }) async {
    final image = await showAppImageSourcePicker(context);
    if (image == null) {
      return;
    }
    final upload = _PendingImageUpload(
      bytes: image.bytes,
      fileName: image.fileName,
      size: image.size,
      mimeType: image.mimeType,
    );
    setState(() {
      controller.text = image.fileName;
      onSelected(upload);
    });
    _handleDraftChanged();
  }

  Widget _buildToggleRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AdminModalToggleRow(
      title: title,
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label, {
    String? hintText,
    bool obscureText = false,
    double bottomPadding = 4,
    bool readOnly = false,
    VoidCallback? onTap,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return AdminModalTextField(
      controller: controller,
      label: label,
      focusNode: focusNode,
      hintText: hintText,
      obscureText: obscureText ? _isPasswordObscured : false,
      readOnly: readOnly,
      onTap: onTap,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      textCapitalization: label == 'Name'
          ? TextCapitalization.words
          : TextCapitalization.none,
      inputFormatters: label == 'Name'
          ? const <TextInputFormatter>[NameCaseTextInputFormatter()]
          : label == 'Phone'
          ? const <TextInputFormatter>[PhilippinesPhoneInputFormatter()]
          : null,
      bottomPadding: bottomPadding,
      suffixIcon: obscureText
          ? Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                onPressed: () {
                  setState(() {
                    _isPasswordObscured = !_isPasswordObscured;
                  });
                },
                icon: Icon(
                  _isPasswordObscured
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppColors.primaryColor,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildUploadField({
    required String label,
    required TextEditingController controller,
    required VoidCallback onTap,
    double bottomPadding = 4,
  }) {
    return AdminModalActionField(
      label: label,
      valueText: controller.text,
      hintText: '',
      bottomPadding: bottomPadding,
      onTap: onTap,
      suffixIcon: const Padding(
        padding: EdgeInsets.only(right: 6),
        child: Icon(Icons.upload_rounded, color: AppColors.primaryColor),
      ),
    );
  }

  static String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _supportsOnlineRoleStatic(String? role) {
    return RoleAccessService.instance.isOnlineEligibleRole(role);
  }

  String? _validationMessage() {
    if (widget.isEditing) {
      return _validateInactiveOnline(_isActive, _isOnline) ??
          _validateOnlineRole(_roleValue, _isOnline) ??
          _validateOptionalEmail(_emailController.text) ??
          _validateOptionalName(_nameController.text) ??
          _validateOptionalPhone(_phoneController.text) ??
          (_isDriverRole ? _validateOptionalLicense(_licenseValue) : null) ??
          _validateOptionalPassword(_passwordController.text);
    }
    final roleMessage = _roleValue == null || _roleValue!.isEmpty
        ? 'Role is required.'
        : null;
    return roleMessage ??
        (_isDriverRole && (_vehicleTypeId?.trim().isNotEmpty != true)
            ? 'Vehicle type is required.'
            : null) ??
        _validateInactiveOnline(_isActive, _isOnline) ??
        _validateOnlineRole(_roleValue, _isOnline) ??
        _validateEmail(_emailController.text) ??
        _validateName(_nameController.text) ??
        (_pendingPhotoUpload != null ? null : _validatePhoto(_photoValue)) ??
        _validatePhone(_phoneController.text) ??
        (_isDriverRole
            ? (_pendingLicenseUpload != null
                  ? null
                  : _validateLicense(_licenseValue))
            : null) ??
        _validatePassword(_passwordController.text);
  }

  static String? _validateOptionalEmail(String? value) {
    return (value?.trim().isEmpty ?? true) ? null : _validateEmail(value);
  }

  static String? _validateOptionalName(String? value) {
    return (value?.trim().isEmpty ?? true) ? null : _validateName(value);
  }

  static String? _validateOptionalPhone(String? value) {
    return (value?.trim().isEmpty ?? true) ? null : _validatePhone(value);
  }

  static String? _validateOptionalPassword(String? value) {
    return (value?.trim().isEmpty ?? true) ? null : _validatePassword(value);
  }

  static String? _validateOptionalLicense(String? value) {
    return (value?.trim().isEmpty ?? true) ? null : _validateLicense(value);
  }

  static String? _validateInactiveOnline(bool isActive, bool isOnline) {
    if (isActive || !isOnline) {
      return null;
    }
    return 'Inactive users cannot be set online.';
  }

  static String? _validateOnlineRole(String? role, bool isOnline) {
    if (!isOnline) {
      return null;
    }
    if (_supportsOnlineRoleStatic(role)) {
      return null;
    }
    return 'Online status is only available for Driver and Helper roles.';
  }

  static String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Email is required.';
    }
    final emailRegex = RegExp(
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
    );
    if (!emailRegex.hasMatch(trimmed)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? _validateName(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Name is required.';
    }
    if (trimmed.length < 2) {
      return 'Name must be at least 2 characters.';
    }
    return null;
  }

  static String? _validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Phone is required.';
    }
    if (!isValidPhilippinePhone(trimmed)) {
      return 'Enter a valid PH mobile number.';
    }
    return null;
  }

  static String? _validatePassword(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Password is required.';
    }
    if (trimmed.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  static String? _validatePhoto(String? value) {
    return null;
  }

  static String? _validateLicense(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'License is required.';
    }
    return null;
  }
}

class _UserActionButton extends StatelessWidget {
  const _UserActionButton({
    required this.icon,
    this.isDanger = false,
    this.backgroundColor,
    this.onTap,
  });

  final IconData icon;
  final bool isDanger;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final resolvedBackgroundColor =
        backgroundColor ??
        (isDanger ? AppColors.dangerStrong : AppColors.primaryColor);

    return AdminListActionButton(
      icon: icon,
      onTap: onTap,
      backgroundColor: resolvedBackgroundColor,
      size: 38,
      iconSize: 18,
      borderRadius: 12,
    );
  }
}
