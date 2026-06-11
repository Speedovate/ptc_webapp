import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/admin/admin_users.vm.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/views/shared/profile_view.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_profile_avatar.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';

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

  static const usersSectionGap = 14.0;
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
          return AppPageLoadingOverlay(
            isVisible:
                vm.isBusy ||
                _isUploadingViewedProfilePhoto ||
                _isUploadingViewedLicensePhoto,
            message: _isUploadingViewedLicensePhoto
                ? 'Uploading license photo...'
                : _isUploadingViewedProfilePhoto
                ? 'Uploading profile photo...'
                : vm.busyMessage,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.translate(
                    offset: const Offset(-12, 0),
                    child: _UserDetailHeader(
                      user: viewedUser,
                      onBack: vm.closeUserView,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ProfileView(
                    user: viewedUser,
                    scrollable: false,
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
                    isCurrentUserView: isViewingCurrentUser,
                    onLogout: widget.onLogout,
                    logoutLabel: widget.isQuickLoggedIn ? 'Go Back' : 'Logout',
                    onSaveProfileChanges: isViewingCurrentUser
                        ? (changes) => _saveViewedUserProfileChanges(
                            vm,
                            viewedUser,
                            changes,
                          )
                        : null,
                    onQuickActionPressed: isViewingCurrentUser
                        ? null
                        : () async {
                            try {
                              await vm.loginAsUser(viewedUser);
                              if (!context.mounted) {
                                return;
                              }
                              await widget.onCurrentUserUpdated();
                            } on AuthFailure catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              AppSnackbar.showError(context, error.message);
                            }
                          },
                    quickActionLabel: isViewingCurrentUser ? null : 'Sign In',
                    onEditPressed: () {
                      vm.closeUserView();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) {
                          return;
                        }
                        AdminUsersView.showEditUserDialog(
                          context,
                          vm,
                          viewedUser,
                          widget.onCurrentUserUpdated,
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
          );
        }

        return AppPageLoadingOverlay(
          isVisible:
              vm.isBusy ||
              _isUploadingViewedProfilePhoto ||
              _isUploadingViewedLicensePhoto,
          message: _isUploadingViewedLicensePhoto
              ? 'Uploading license photo...'
              : _isUploadingViewedProfilePhoto
              ? 'Uploading profile photo...'
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
                    AppRefreshStrip(isVisible: vm.isBusy),
                    _UsersToolbar(vm: vm),
                    const SizedBox(height: AdminUsersView.usersSectionGap),
                    if (isNarrow)
                      if (filteredUsers.isNotEmpty)
                        Column(
                          children: filteredUsers
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: _UsersResponsiveCard(
                                      user: item,
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

    return role
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
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
    final editedUser = await showDialog<_UserFormDialogResult>(
      context: context,
      builder: (dialogContext) => _UserFormDialog(
        title: _userDialogTitle('Edit', user),
        initialUser: user,
        isEditing: true,
      ),
    );

    if (editedUser != null && context.mounted) {
      var savedUser = await vm.updateUser(editedUser.user);
      savedUser = await _applyPendingUserImageUploads(
        vm,
        savedUser,
        editedUser,
      );
      if (!context.mounted) {
        return;
      }
      if (vm.currentUser?.id == savedUser.id) {
        await onCurrentUserUpdated();
        if (!context.mounted) {
          return;
        }
      }
      AppSnackbar.showSuccess(
        context,
        _buildUserSaveMessage(savedUser, isEditing: true, originalUser: user),
      );
    }
  }

  static Future<void> showNewUserDialog(
    BuildContext context,
    AdminUsersViewModel vm,
  ) async {
    final newUser = await showDialog<_UserFormDialogResult>(
      context: context,
      builder: (dialogContext) => _UserFormDialog(
        title: _userDialogTitle('New', vm.draftNewUser),
        isEditing: false,
        initialUser: vm.draftNewUser,
        generatedId: vm.nextUserId,
        onDraftChanged: vm.updateDraftNewUser,
      ),
    );

    if (newUser != null && context.mounted) {
      var savedUser = await vm.addUser(newUser.user);
      savedUser = await _applyPendingUserImageUploads(vm, savedUser, newUser);
      vm.clearDraftNewUser();
      if (!context.mounted) {
        return;
      }
      AppSnackbar.showSuccess(
        context,
        _buildUserSaveMessage(savedUser, isEditing: false),
      );
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

  static String _buildUserSaveMessage(
    UserModel user, {
    required bool isEditing,
    UserModel? originalUser,
  }) {
    final roleLabel = formatRole(user.role);
    final nameLabel = (user.name ?? '').trim();
    final subject = [
      if (roleLabel != '-') roleLabel,
      if (nameLabel.isNotEmpty) nameLabel,
    ].join(' ');

    if (isEditing && originalUser != null) {
      final changedFields = _userChangedFields(originalUser, user);
      final detailedMessage = _buildDetailedUpdateMessage(
        subject: subject,
        changes: changedFields,
      );
      if (detailedMessage != null) {
        return detailedMessage;
      }
    }

    if (subject.isNotEmpty) {
      return isEditing
          ? '$subject has been updated.'
          : "$subject's account has been created.";
    }

    return isEditing
        ? 'User has been updated.'
        : 'User account has been created.';
  }

  static Map<String, String> _userChangedFields(
    UserModel before,
    UserModel after,
  ) {
    final changed = <String, String>{};

    if (before.role != after.role) {
      changed['role'] = formatRole(after.role);
    }
    if ((before.email ?? '').trim() != (after.email ?? '').trim()) {
      changed['email'] = after.email?.trim() ?? '-';
    }
    if ((before.name ?? '').trim() != (after.name ?? '').trim()) {
      changed['name'] = after.name?.trim() ?? '-';
    }
    if ((before.photo ?? '').trim() != (after.photo ?? '').trim()) {
      changed['photo'] = after.photo?.trim() ?? '-';
    }
    if ((before.phone ?? '').trim() != (after.phone ?? '').trim()) {
      changed['phone number'] = after.phone?.trim() ?? '-';
    }
    final beforeDriver = before.asDriver;
    final afterDriver = after.asDriver;
    if ((beforeDriver?.license ?? '').trim() !=
        (afterDriver?.license ?? '').trim()) {
      changed['license'] = afterDriver?.license?.trim() ?? '-';
    }
    if (beforeDriver?.lat != afterDriver?.lat) {
      changed['latitude'] = '${afterDriver?.lat ?? 'Not set'}';
    }
    if (beforeDriver?.lng != afterDriver?.lng) {
      changed['longitude'] = '${afterDriver?.lng ?? 'Not set'}';
    }
    if ((beforeDriver?.vehicleType?.name ?? '').trim() !=
        (afterDriver?.vehicleType?.name ?? '').trim()) {
      changed['vehicle type'] = afterDriver?.vehicleType?.name?.trim() ?? '-';
    }
    if ((before.password ?? '') != (after.password ?? '')) {
      changed['password'] = 'updated';
    }
    if ((before.isActive ?? false) != (after.isActive ?? false)) {
      changed['active status'] = '${after.isActive ?? false}';
    }
    if ((before.isOnline ?? false) != (after.isOnline ?? false)) {
      changed['online status'] = '${after.isOnline ?? false}';
    }

    return changed;
  }

  static String? _buildDetailedUpdateMessage({
    required String subject,
    required Map<String, String> changes,
  }) {
    if (changes.isEmpty) {
      return null;
    }
    if (changes.length == 1) {
      final entry = changes.entries.first;
      if (subject.isNotEmpty) {
        return "$subject's ${entry.key} has been updated to ${entry.value}.";
      }
      return '${_capitalize(entry.key)} has been updated to ${entry.value}.';
    }

    final summary = changes.entries
        .map((entry) => '${entry.key} = ${entry.value}')
        .join('; ');
    if (subject.isNotEmpty) {
      return '$subject has been updated: $summary.';
    }
    return 'Updated fields: $summary.';
  }

  static String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  static void handleDeleteUser(
    BuildContext context,
    AdminUsersViewModel vm,
    UserModel user,
  ) async {
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
      willBeActive ? '$subjectLabel activated.' : '$subjectLabel deactivated.',
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
    final confirmed = await showDialog<bool>(
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
                  ? const Color(0xFFD94B4B)
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
        onNewPressed: () => AdminUsersView.showNewUserDialog(context, vm),
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
                      label: 'Start Date',
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
                      label: 'End Date',
                      value: widget.vm.endDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateEndDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: AdminUsersView.usersFilterControlHeight,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
                        widget.vm.clearFilters();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD94B4B),
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
        iconEnabledColor: AppColors.primaryColor,
        style: _subtlePrimaryTextStyle,
        decoration: adminFormInputDecoration(
          label,
          radius: AdminUsersView.usersSurfaceRadius,
          minHeight: AdminUsersView.usersFilterControlHeight,
        ),
        items: items
            .where((item) => item != 'All')
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
                          : AppColors.primarySurface,
                      suffixIcon: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.value == null
                            ? _pickDate
                            : () => widget.onSelected(null),
                        child: Icon(
                          widget.value == null
                              ? Icons.calendar_today_rounded
                              : Icons.close_rounded,
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

  static const _defaultTrailingPadding = 20.0;
  static const _extraWidthAllowance = 16.0;

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
        final photoWidth = _maxValue(
          44,
          _measureTextWidth(context, textScaler, 'Photo', _headerStyle),
        );
        final nameWidth = _maxTextWidth(
          context,
          textScaler,
          'Name',
          _headerStyle,
          longestNameValue,
          _nameStyle,
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
        final emailWidth = _maxTextWidth(
          context,
          textScaler,
          'Email',
          _headerStyle,
          longestEmailValue,
          _valueStyle,
        );
        final createdAtWidth = _maxTextWidth(
          context,
          textScaler,
          'Created',
          _headerStyle,
          longestCreatedAtValue,
          _valueStyle,
        );
        final actionsWidth = _maxValue(
          176,
          _measureTextWidth(context, textScaler, 'Actions', _headerStyle),
        );
        final resolvedIdWidth = _resolvedColumnWidth(idWidth);
        final resolvedPhotoWidth = _resolvedColumnWidth(photoWidth);
        final resolvedNameWidth = _resolvedColumnWidth(nameWidth);
        final resolvedPhoneWidth = _resolvedColumnWidth(phoneWidth);
        final resolvedRoleWidth = _resolvedColumnWidth(roleWidth);
        final resolvedEmailWidth = _resolvedColumnWidth(emailWidth);
        final resolvedCreatedAtWidth = _resolvedColumnWidth(createdAtWidth);
        final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;
        final totalMeasuredWidth =
            resolvedIdWidth +
            resolvedPhotoWidth +
            resolvedNameWidth +
            resolvedPhoneWidth +
            resolvedEmailWidth +
            resolvedRoleWidth +
            resolvedCreatedAtWidth +
            resolvedActionsWidth +
            40;
        final shouldFlexNameAndEmail =
            totalMeasuredWidth > constraints.maxWidth;

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
                    child: const _UsersHeader(label: 'ID', trailingPadding: 20),
                  ),
                  _UsersFixedSlot(
                    width: resolvedPhotoWidth,
                    child: const _UsersHeader(
                      label: 'Photo',
                      trailingPadding: 20,
                    ),
                  ),
                  if (shouldFlexNameAndEmail)
                    const Expanded(
                      child: _UsersHeader(label: 'Name', trailingPadding: 20),
                    )
                  else
                    _UsersFixedSlot(
                      width: resolvedNameWidth,
                      child: const _UsersHeader(
                        label: 'Name',
                        trailingPadding: 20,
                      ),
                    ),
                  _UsersFixedSlot(
                    width: resolvedPhoneWidth,
                    child: const _UsersHeader(
                      label: 'Phone',
                      trailingPadding: 20,
                    ),
                  ),
                  if (shouldFlexNameAndEmail)
                    const Expanded(
                      child: _UsersHeader(label: 'Email', trailingPadding: 20),
                    )
                  else
                    _UsersFixedSlot(
                      width: resolvedEmailWidth,
                      child: const _UsersHeader(
                        label: 'Email',
                        trailingPadding: 20,
                      ),
                    ),
                  _UsersFixedSlot(
                    width: resolvedRoleWidth,
                    child: const _UsersHeader(
                      label: 'Role',
                      trailingPadding: 20,
                    ),
                  ),
                  _UsersFixedSlot(
                    width: resolvedCreatedAtWidth,
                    child: const _UsersHeader(
                      label: 'Created',
                      trailingPadding: 20,
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
            const SizedBox(height: AdminUsersView.usersSectionGap),
            if (users.isEmpty) _UsersEmptyState(message: emptyMessage),
            if (users.isNotEmpty)
              Column(
                children: users
                    .map(
                      (user) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _UsersWideRow(
                          user: user,
                          vm: vm,
                          onCurrentUserUpdated: onCurrentUserUpdated,
                          shouldFlexNameAndEmail: shouldFlexNameAndEmail,
                          resolvedIdWidth: resolvedIdWidth,
                          resolvedPhotoWidth: resolvedPhotoWidth,
                          resolvedNameWidth: resolvedNameWidth,
                          resolvedPhoneWidth: resolvedPhoneWidth,
                          resolvedEmailWidth: resolvedEmailWidth,
                          resolvedRoleWidth: resolvedRoleWidth,
                          resolvedCreatedAtWidth: resolvedCreatedAtWidth,
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
    required this.shouldFlexNameAndEmail,
    required this.resolvedIdWidth,
    required this.resolvedPhotoWidth,
    required this.resolvedNameWidth,
    required this.resolvedPhoneWidth,
    required this.resolvedEmailWidth,
    required this.resolvedRoleWidth,
    required this.resolvedCreatedAtWidth,
    required this.resolvedActionsWidth,
  });

  final UserModel user;
  final AdminUsersViewModel vm;
  final Future<void> Function() onCurrentUserUpdated;
  final bool shouldFlexNameAndEmail;
  final double resolvedIdWidth;
  final double resolvedPhotoWidth;
  final double resolvedNameWidth;
  final double resolvedPhoneWidth;
  final double resolvedEmailWidth;
  final double resolvedRoleWidth;
  final double resolvedCreatedAtWidth;
  final double resolvedActionsWidth;

  @override
  Widget build(BuildContext context) {
    final idValue = user.id ?? '-';
    final nameValue = user.name ?? '-';
    final phoneValue = user.phone ?? '-';
    final emailValue = user.email ?? '-';
    final roleValue = AdminUsersView.formatRole(user.role);
    final createdAtValue = AdminUsersView.formatCreatedAt(user.createdAt);

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
            width: resolvedPhotoWidth,
            child: _UsersCell(
              child: AppProfileAvatar(
                photo: user.photo,
                fallbackText: AdminUsersView.initials(user.name),
                radius: 22,
              ),
            ),
          ),
          if (shouldFlexNameAndEmail)
            Expanded(
              child: _UsersCell(
                child: Text(
                  nameValue,
                  style: _UsersTable._nameStyle.copyWith(
                    color: (user.isOnline ?? false)
                        ? _UsersTable._onlineNameColor
                        : AppColors.textPrimary,
                  ),
                  softWrap: true,
                ),
              ),
            )
          else
            _UsersFixedSlot(
              width: resolvedNameWidth,
              child: _UsersCell(
                child: Text(
                  nameValue,
                  style: _UsersTable._nameStyle.copyWith(
                    color: (user.isOnline ?? false)
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
          if (shouldFlexNameAndEmail)
            Expanded(
              child: _UsersCell(
                child: Text(
                  emailValue,
                  style: _UsersTable._valueStyle,
                  softWrap: true,
                ),
              ),
            )
          else
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
                        ? Colors.red.shade700
                        : const Color(0xFF2EAD62),
                    onTap: () {
                      AdminUsersView.handleToggleUserActive(context, vm, user);
                    },
                  ),
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
    this.trailingPadding = 24,
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
              if (showTopActionsRow && stackTopActions)
                Column(
                  children: [
                    AppProfileAvatar(
                      photo: user.photo,
                      fallbackText: AdminUsersView.initials(user.name),
                      radius: 24,
                    ),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AppProfileAvatar(
                      photo: user.photo,
                      fallbackText: AdminUsersView.initials(user.name),
                      radius: 24,
                    ),
                    if (showTopActionsRow) ...[
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
                                ? Colors.red.shade700
                                : const Color(0xFF2EAD62),
                            onTap: () {
                              AdminUsersView.handleToggleUserActive(
                                context,
                                vm,
                                user,
                              );
                            },
                          ),
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
                  ],
                ),
              const SizedBox(height: 18),
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
                            (user.isOnline ?? false)
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
                          ? Colors.red.shade700
                          : const Color(0xFF2EAD62),
                      onTap: () {
                        AdminUsersView.handleToggleUserActive(
                          context,
                          vm,
                          user,
                        );
                      },
                    ),
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
                          ? Colors.red.shade700
                          : const Color(0xFF2EAD62),
                      onTap: () {
                        AdminUsersView.handleToggleUserActive(
                          context,
                          vm,
                          user,
                        );
                      },
                    ),
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
    this.trailingPadding = 24,
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

class _UserDetailHeader extends StatelessWidget {
  const _UserDetailHeader({required this.user, required this.onBack});

  final UserModel user;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.primaryColor,
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
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({
    required this.title,
    required this.isEditing,
    this.initialUser,
    this.generatedId,
    this.onDraftChanged,
  });

  final String title;
  final bool isEditing;
  final UserModel? initialUser;
  final String? generatedId;
  final ValueChanged<UserModel>? onDraftChanged;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  static const _roleOptions = ['client', 'driver', 'admin', 'helper'];

  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  late final TextEditingController _emailController;
  late final TextEditingController _nameController;
  late final TextEditingController _photoController;
  late final TextEditingController _phoneController;
  late final TextEditingController _licenseController;
  late final TextEditingController _passwordController;

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

  bool get _isDriverRole => _roleValue == 'driver';

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
    _latController = TextEditingController(text: driver?.lat?.toString() ?? '');
    _lngController = TextEditingController(text: driver?.lng?.toString() ?? '');
    _emailController = TextEditingController(text: user.email ?? '');
    _nameController = TextEditingController(text: user.name ?? '');
    _photoController = TextEditingController(text: user.photo ?? '');
    _phoneController = TextEditingController(text: user.phone ?? '');
    _licenseController = TextEditingController(text: driver?.license ?? '');
    _passwordController = TextEditingController(text: user.password ?? '');
    _roleValue = _roleOptions.contains(user.role) ? user.role : null;
    _vehicleTypeId = driver?.vehicleType?.id;
    _isActive = widget.isEditing ? (user.isActive ?? false) : true;
    _isOnline = user.isOnline ?? false;
    _photoValue = user.photo;
    _licenseValue = driver?.license;
    _emailController.addListener(_handleDraftChanged);
    _nameController.addListener(_handleDraftChanged);
    _photoController.addListener(_handleDraftChanged);
    _phoneController.addListener(_handleDraftChanged);
    _licenseController.addListener(_handleDraftChanged);
    _latController.addListener(_handleDraftChanged);
    _lngController.addListener(_handleDraftChanged);
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
    _licenseController.removeListener(_handleDraftChanged);
    _latController.removeListener(_handleDraftChanged);
    _lngController.removeListener(_handleDraftChanged);
    _passwordController.removeListener(_handleDraftChanged);
    _latController.dispose();
    _lngController.dispose();
    _emailController.dispose();
    _nameController.dispose();
    _photoController.dispose();
    _phoneController.dispose();
    _licenseController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: widget.title,
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 14),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final validationMessage = _validationMessage();
            if (validationMessage != null) {
              AppSnackbar.showError(context, validationMessage);
              return;
            }
            final baseUser = widget.initialUser ?? const UserModel();
            final now = DateTime.now();
            final selectedVehicleType = _vehicleTypes.where(
              (item) => item.id == _vehicleTypeId,
            );
            final fallbackVehicleType =
                widget.initialUser?.asDriver?.vehicleType;
            Navigator.of(context).pop(
              _UserFormDialogResult(
                user: baseUser.copyWith(
                  id: widget.isEditing ? baseUser.id : widget.generatedId,
                  role: _roleValue,
                  email: _nullIfEmpty(_emailController.text),
                  name: _nullIfEmpty(_nameController.text),
                  photo: _photoValue,
                  phone: normalizePhilippinePhone(_phoneController.text),
                  isActive: _isActive,
                  isOnline: _isOnline,
                  password: _nullIfEmpty(_passwordController.text),
                  createdAt: widget.isEditing ? baseUser.createdAt : now,
                  updatedAt: now,
                  lat: _isDriverRole
                      ? _tryParseDouble(_latController.text)
                      : null,
                  lng: _isDriverRole
                      ? _tryParseDouble(_lngController.text)
                      : null,
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
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
      child: AdminModalFormBody(
        children: _isDriverRole && _isLoadingVehicleTypes
            ? const [
                SizedBox(
                  height: 220,
                  child: AppPageLoading(
                    message: 'Loading vehicle types...',
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
                    _buildField(_emailController, 'Email', bottomPadding: 4),
                    _buildField(_nameController, 'Name'),
                    _buildUploadField(
                      label: 'Photo',
                      controller: _photoController,
                      onTap: _pickPhotoFieldImage,
                    ),
                    _buildField(_phoneController, 'Phone'),
                    if (_isDriverRole)
                      _buildUploadField(
                        label: 'License',
                        controller: _licenseController,
                        onTap: _pickLicenseFieldImage,
                      ),
                    if (_isDriverRole) _buildField(_latController, 'Latitude'),
                    if (_isDriverRole) _buildField(_lngController, 'Longitude'),
                    _buildField(
                      _passwordController,
                      'Password',
                      obscureText: true,
                      bottomPadding: 0,
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
      email: _nullIfEmpty(_emailController.text),
      name: _nullIfEmpty(_nameController.text),
      photo: _photoValue,
      phone: normalizePhilippinePhone(_phoneController.text),
      isActive: _isActive,
      isOnline: _isOnline,
      password: _nullIfEmpty(_passwordController.text),
      lat: _isDriverRole ? _tryParseDouble(_latController.text) : null,
      lng: _isDriverRole ? _tryParseDouble(_lngController.text) : null,
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return;
    }
    final upload = _PendingImageUpload(
      bytes: bytes,
      fileName: file.name,
      size: file.size,
      mimeType: file.extension == null
          ? null
          : _resolvedMimeType(file.extension!),
    );
    setState(() {
      controller.text = file.name;
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
  }) {
    return AdminModalTextField(
      controller: controller,
      label: label,
      hintText: hintText,
      obscureText: obscureText ? _isPasswordObscured : false,
      readOnly: readOnly,
      onTap: onTap,
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

  static bool _supportsOnlineRole(String? role) {
    return role == 'driver' || role == 'helper';
  }

  String? _validationMessage() {
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
        (_isDriverRole ? _validateLatitude(_latController.text) : null) ??
        (_isDriverRole ? _validateLongitude(_lngController.text) : null) ??
        _validatePassword(_passwordController.text);
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
    if (_supportsOnlineRole(role)) {
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

  static String? _resolvedMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }

  static String? _validateLatitude(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Latitude is required.';
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed < -90 || parsed > 90) {
      return 'Latitude must be between -90 and 90.';
    }
    return null;
  }

  static String? _validateLongitude(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Longitude is required.';
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed < -180 || parsed > 180) {
      return 'Longitude must be between -180 and 180.';
    }
    return null;
  }

  static double? _tryParseDouble(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed);
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
        (isDanger ? Colors.red.shade700 : AppColors.primaryColor);

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
