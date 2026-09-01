import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_cached_network_image.dart';
import 'package:webapp/widgets/shared/app_image_source_picker.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/app_image_viewer.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/app_profile_avatar.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

class ProfilePendingImageUpload {
  const ProfilePendingImageUpload({
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

class ProfilePendingProfileChanges {
  const ProfilePendingProfileChanges({this.photoUpload, this.licenseUpload});

  final ProfilePendingImageUpload? photoUpload;
  final ProfilePendingImageUpload? licenseUpload;

  bool get hasChanges => photoUpload != null || licenseUpload != null;
}

ValueKey<String> profileViewRefreshKey(UserModel user) {
  return ValueKey<String>(
    [
      user.id ?? '',
      user.updatedAt?.toIso8601String() ?? '',
      user.name ?? '',
      user.email ?? '',
      user.phone ?? '',
      user.photo ?? '',
      user.asDriver?.license ?? '',
      user.role ?? '',
    ].join('|'),
  );
}

class ProfileView extends StatefulWidget {
  const ProfileView({
    super.key,
    required this.user,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 24),
    this.onEditPressed,
    this.onLogout,
    this.logoutLabel = 'Logout',
    this.onSaveProfileChanges,
    this.onRemoveLicensePressed,
    this.isCurrentUserView = false,
    this.onQuickActionPressed,
    this.quickActionLabel,
    this.quickActionTextColor,
    this.quickActionBorderColor,
    this.businessUser,
    this.onBusinessDetailsPressed,
    this.vehicleCatalogRepository,
    this.authRepository,
  });

  final UserModel user;
  final bool scrollable;
  final EdgeInsets padding;
  final VoidCallback? onEditPressed;
  final VoidCallback? onLogout;
  final String logoutLabel;
  final Future<void> Function(ProfilePendingProfileChanges changes)?
  onSaveProfileChanges;
  final VoidCallback? onRemoveLicensePressed;
  final bool isCurrentUserView;
  final VoidCallback? onQuickActionPressed;
  final String? quickActionLabel;
  final Color? quickActionTextColor;
  final Color? quickActionBorderColor;
  final UserModel? businessUser;
  final VoidCallback? onBusinessDetailsPressed;
  final VehicleCatalogRepository? vehicleCatalogRepository;
  final AuthRepository? authRepository;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  static final Map<String, VehicleMake?> _assignedMakeCacheByDriverId = {};
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  VehicleMake? _assignedMake;
  bool _isLoadingAssignedMake = true;
  ProfilePendingImageUpload? _pendingPhotoUpload;
  ProfilePendingImageUpload? _pendingLicenseUpload;
  bool _isSavingProfileChanges = false;

  VehicleCatalogRepository get _vehicleCatalogRepository =>
      widget.vehicleCatalogRepository ?? VehicleRequest.instance;
  AuthRepository get _authRepository =>
      widget.authRepository ?? AuthRequest.instance;

  @override
  void initState() {
    super.initState();
    final driverId = widget.user.id?.trim() ?? '';
    if (driverId.isNotEmpty &&
        _assignedMakeCacheByDriverId.containsKey(driverId)) {
      _assignedMake = _assignedMakeCacheByDriverId[driverId];
      _isLoadingAssignedMake = false;
    }
    _loadAssignedMake();
  }

  @override
  void didUpdateWidget(covariant ProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.user.role != widget.user.role) {
      _pendingPhotoUpload = null;
      _pendingLicenseUpload = null;
      _loadAssignedMake();
      return;
    }
    if (oldWidget.user.photo != widget.user.photo) {
      _pendingPhotoUpload = null;
    }
    if (oldWidget.user.asDriver?.license != widget.user.asDriver?.license) {
      _pendingLicenseUpload = null;
    }
  }

  bool get _hasPendingChanges =>
      _pendingPhotoUpload != null || _pendingLicenseUpload != null;

  bool get _canUpdateProfile => widget.onSaveProfileChanges != null;

  Future<void> _loadAssignedMake() async {
    final driverId = widget.user.id?.trim();
    if (widget.user.role != 'driver' || driverId == null || driverId.isEmpty) {
      if (mounted) {
        setState(() {
          _assignedMake = null;
          _isLoadingAssignedMake = false;
        });
      }
      return;
    }

    setState(() {
      _isLoadingAssignedMake = true;
    });

    try {
      final makes = await _vehicleCatalogRepository.getMakes().timeout(
        const Duration(seconds: 6),
        onTimeout: () => const <VehicleMake>[],
      );
      final match = makes.where((item) => item.driver?.id == driverId);
      if (!mounted) {
        return;
      }
      setState(() {
        _assignedMake = match.isEmpty ? null : match.first;
        _assignedMakeCacheByDriverId[driverId] = _assignedMake;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAssignedMake = false;
        });
      }
    }
  }

  Future<void> _pickProfilePhoto() async {
    final upload = await _pickImageUpload();
    if (!mounted || upload == null) {
      return;
    }
    setState(() {
      _pendingPhotoUpload = upload;
    });
  }

  Future<void> _pickLicensePhoto() async {
    final upload = await _pickImageUpload();
    if (!mounted || upload == null) {
      return;
    }
    setState(() {
      _pendingLicenseUpload = upload;
    });
  }

  Future<ProfilePendingImageUpload?> _pickImageUpload() async {
    final image = await showAppImageSourcePicker(context);
    if (image == null) {
      return null;
    }

    return ProfilePendingImageUpload(
      bytes: image.bytes,
      fileName: image.fileName,
      size: image.size,
      mimeType: image.mimeType,
    );
  }

  Future<void> _saveProfileChanges() async {
    final onSave = widget.onSaveProfileChanges;
    if (onSave == null || !_hasPendingChanges || _isSavingProfileChanges) {
      return;
    }

    setState(() {
      _isSavingProfileChanges = true;
    });

    try {
      await onSave(
        ProfilePendingProfileChanges(
          photoUpload: _pendingPhotoUpload,
          licenseUpload: _pendingLicenseUpload,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingPhotoUpload = null;
        _pendingLicenseUpload = null;
      });
      AppSnackbar.showSuccess(context, 'Profile updated.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppSnackbar.showError(
        context,
        error is Exception
            ? error.toString().replaceFirst('Exception: ', '')
            : 'We could not save your profile changes right now.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingProfileChanges = false;
        });
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    if (!_canUpdateProfile) {
      AppSnackbar.showError(
        context,
        'You do not have access to update this profile.',
      );
      return;
    }
    final userId = widget.user.id?.trim();
    if (userId == null || userId.isEmpty) {
      AppSnackbar.showError(context, 'User ID is required.');
      return;
    }
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => _ChangePasswordDialog(
        onSave: (result) async {
          await _authRepository.changePassword(
            userId: userId,
            oldPassword: result.oldPassword,
            newPassword: result.newPassword,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final roleLabel = _formatRole(user.role);
    final driver = user.asDriver;
    final showDriverFields = driver != null;
    final hasLicensePreview =
        _pendingLicenseUpload != null ||
        _hasLicensePreviewValue(driver?.license);
    final showOnlineField = _roleAccessService.isOnlineEligibleRole(user.role);
    final showBusinessSection = isSubClientRole(user.role);
    final joinedLabel = _formatDateTime(user.createdAt);
    final updatedLabel = _formatDateTime(user.updatedAt);
    final businessUser = widget.businessUser;
    final content = Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showDriverFields)
            AppRefreshStrip(isVisible: _isLoadingAssignedMake),
          _ProfileIdentityHeader(
            user: user,
            roleLabel: roleLabel,
            joinedLabel: joinedLabel,
            updatedLabel: updatedLabel,
            onEditPressed: widget.onEditPressed,
            onLogout: widget.onLogout,
            logoutLabel: widget.logoutLabel,
            onChangePhotoPressed: widget.isCurrentUserView && _canUpdateProfile
                ? _pickProfilePhoto
                : null,
            pendingPhotoBytes: _pendingPhotoUpload?.bytes,
            isCurrentUserView: widget.isCurrentUserView,
            onQuickActionPressed: widget.onQuickActionPressed,
            quickActionLabel: widget.quickActionLabel,
            quickActionTextColor: widget.quickActionTextColor,
            quickActionBorderColor: widget.quickActionBorderColor,
          ),
          if (showBusinessSection) ...[
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const AdminSectionTitle(title: 'Business'),
                if (widget.onBusinessDetailsPressed != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _SectionIconButton(
                      icon: Icons.arrow_forward_rounded,
                      onTap: widget.onBusinessDetailsPressed!,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _InfoGroupContent(
              rows: [
                _InfoRow(
                  label: 'Name',
                  value: _valueOrNotSet(businessUser?.name),
                ),
                _InfoRow(
                  label: 'Position',
                  value: _valueOrNotSet(user.position),
                ),
                _InfoRow(
                  label: 'ID',
                  value: _valueOrDash(businessUser?.id ?? user.parentClientId),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          const AdminSectionTitle(title: 'Personal'),
          const SizedBox(height: 10),
          _InfoGroupContent(
            rows: [
              _InfoRow(label: 'Name', value: _valueOrNotSet(user.name)),
              _InfoRow(label: 'Email', value: _valueOrDash(user.email)),
              _InfoRow(
                label: 'Mobile number',
                value: _valueOrNotSet(user.phone),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const AdminSectionTitle(title: 'Account'),
          const SizedBox(height: 10),
          _InfoGroupContent(
            rows: [
              _InfoRow(label: 'ID', value: _valueOrDash(user.id)),
              _InfoRow(
                label: 'Role',
                value: roleLabel.isEmpty ? '-' : roleLabel,
              ),
              _InfoRow(
                label: 'Active',
                value: (user.isActive ?? false) ? 'Active' : 'Inactive',
              ),
              if (showOnlineField)
                _InfoRow(
                  label: 'Online',
                  value: (user.isOnline ?? false) ? 'Online' : 'Offline',
                ),
              if (showDriverFields)
                _InfoRow(
                  label: 'Vehicle make code',
                  value: _valueOrNotSet(_assignedMake?.code),
                ),
              if (showDriverFields)
                _InfoRow(
                  label: 'Vehicle type',
                  value: _valueOrNotSet(driver.vehicleType?.name),
                ),
            ],
          ),
          if (showDriverFields) ...[
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(child: AdminSectionTitle(title: 'License')),
                if (_canUpdateProfile || widget.onEditPressed != null)
                  _LicenseActionButton(
                    hasImage: hasLicensePreview,
                    onPressed: widget.isCurrentUserView && _canUpdateProfile
                        ? _pickLicensePhoto
                        : widget.onEditPressed,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _LicensePreview(
              imageValue: driver.license,
              memoryBytes: _pendingLicenseUpload?.bytes,
            ),
          ],
          const SizedBox(height: 18),
          const AdminSectionTitle(title: 'Security'),
          const SizedBox(height: 10),
          _SecuritySection(onChangePassword: _showChangePasswordDialog),
          if (widget.isCurrentUserView &&
              _canUpdateProfile &&
              _hasPendingChanges) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSavingProfileChanges ? null : _saveProfileChanges,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _isSavingProfileChanges ? 'Saving ...' : 'Save',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return widget.scrollable ? SingleChildScrollView(child: content) : content;
  }

  static String _formatRole(String? role) {
    if (role == null || role.isEmpty) {
      return '';
    }
    return humanizeDropdownValue(role);
  }

  static String _valueOrDash(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? '-' : trimmed;
  }

  static String _valueOrNotSet(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? 'Not set' : trimmed;
  }

  static String _initials(String? value) {
    if (value == null || value.isEmpty) {
      return '';
    }

    final parts = value
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .toList();

    if (parts.isEmpty) {
      return '';
    }

    return parts.map((part) => part[0].toUpperCase()).join();
  }

  static String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Not set';
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
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    final hour = ((value.hour + 11) % 12) + 1;
    return '$month $day, $year | $hour:$minute:$second $period';
  }

  static bool _hasLicensePreviewValue(String? value) {
    final normalizedValue = value?.trim();
    if (normalizedValue == null || normalizedValue.isEmpty) {
      return false;
    }
    return normalizedValue.startsWith('http');
  }
}

class _ProfileIdentityHeader extends StatelessWidget {
  const _ProfileIdentityHeader({
    required this.user,
    required this.roleLabel,
    required this.joinedLabel,
    required this.updatedLabel,
    required this.onEditPressed,
    required this.onLogout,
    required this.logoutLabel,
    required this.onChangePhotoPressed,
    required this.pendingPhotoBytes,
    required this.isCurrentUserView,
    required this.onQuickActionPressed,
    required this.quickActionLabel,
    required this.quickActionTextColor,
    required this.quickActionBorderColor,
  });

  final UserModel user;
  final String roleLabel;
  final String joinedLabel;
  final String updatedLabel;
  final VoidCallback? onEditPressed;
  final VoidCallback? onLogout;
  final String logoutLabel;
  final VoidCallback? onChangePhotoPressed;
  final Uint8List? pendingPhotoBytes;
  final bool isCurrentUserView;
  final VoidCallback? onQuickActionPressed;
  final String? quickActionLabel;
  final Color? quickActionTextColor;
  final Color? quickActionBorderColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 560;
        final nameFontSize = constraints.maxWidth < 420 ? 14.0 : 16.0;
        final avatarRadius = isCompact ? 32.0 : 38.0;
        final showChangePhoto =
            isCurrentUserView && onChangePhotoPressed != null;
        final actionLabel = isCurrentUserView ? logoutLabel : quickActionLabel;
        final actionOnTap = isCurrentUserView ? onLogout : onQuickActionPressed;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AppProfileAvatar(
                          photo: user.photo,
                          memoryBytes: pendingPhotoBytes,
                          fallbackText: _ProfileViewState._initials(user.name),
                          radius: avatarRadius,
                          enablePreview: true,
                          previewTitle: user.name?.trim().isNotEmpty == true
                              ? '${user.name} Photo'
                              : 'Profile Photo',
                        ),
                        if (showChangePhoto)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: _ProfilePhotoCameraButton(
                              onTap: onChangePhotoPressed!,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                SizedBox(width: isCompact ? 12 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              user.name?.isNotEmpty == true ? user.name! : '-',
                              maxLines: isCompact ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: nameFontSize,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (onEditPressed != null) ...[
                            const SizedBox(width: 6),
                            _ProfileEditButton(onTap: onEditPressed!),
                          ],
                        ],
                      ),
                      Text(
                        roleLabel.isEmpty ? 'User' : roleLabel,
                        style: const TextStyle(
                          height: 1.2,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (actionOnTap != null &&
                    actionLabel?.trim().isNotEmpty == true) ...[
                  const SizedBox(width: 12),
                  _ProfileActionPill(
                    label: actionLabel!,
                    onTap: actionOnTap,
                    textColor: isCurrentUserView
                        ? AppColors.dangerStrong
                        : (quickActionTextColor ?? AppColors.primaryColor),
                    borderColor: isCurrentUserView
                        ? AppColors.dangerBorderAlt
                        : (quickActionBorderColor ??
                              AppColors.primaryColor.withValues(alpha: 0.18)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _HeaderPill(label: 'Joined $joinedLabel'),
                _HeaderPill(label: 'Updated $updatedLabel'),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ProfileEditButton extends StatelessWidget {
  const _ProfileEditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Builder(
        builder: (context) => Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: appPressableActive(context)
                ? AppColors.primarySurfaceAlt.withValues(
                    alpha: appPressablePressed(context) ? 0.38 : 0.26,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.edit_rounded,
            size: 18,
            color: AppColors.primaryColor,
          ),
        ),
      ),
    );
  }
}

class _ProfilePhotoCameraButton extends StatelessWidget {
  const _ProfilePhotoCameraButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Builder(
        builder: (context) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: appPressableActive(context)
                ? AppColors.primaryBorder
                : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primaryBorder),
          ),
          child: const Icon(
            Icons.photo_camera_rounded,
            size: 14,
            color: AppColors.primaryColor,
          ),
        ),
      ),
    );
  }
}

class _ProfileActionPill extends StatelessWidget {
  const _ProfileActionPill({
    required this.label,
    required this.onTap,
    required this.textColor,
    required this.borderColor,
  });

  final String label;
  final VoidCallback onTap;
  final Color textColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(1000),
      child: Builder(
        builder: (context) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: appPressableActive(context)
                  ? AppColors.primarySurfaceAlt.withValues(alpha: 0.28)
                  : Colors.white,
              borderRadius: BorderRadius.circular(1000),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  label,
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      constraints: const BoxConstraints(minHeight: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(1000),
        border: Border.all(
          color: AppColors.primaryColor.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            style: TextStyle(
              color: AppColors.primaryColor.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionIconButton extends StatelessWidget {
  const _SectionIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Builder(
        builder: (context) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: appPressableActive(context)
                ? AppColors.primarySurfaceAlt.withValues(alpha: 0.28)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.primaryColor),
        ),
      ),
    );
  }
}

class _InfoGroupContent extends StatelessWidget {
  const _InfoGroupContent({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 640;
        if (isNarrow) {
          return Column(
            children: List.generate(rows.length, (index) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == rows.length - 1 ? 0 : 10,
                ),
                child: rows[index],
              );
            }),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(rows.length, (index) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == rows.length - 1 ? 0 : 10,
                ),
                child: rows[index],
              ),
            );
          }),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryColor.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              height: 1.2,
              color: AppColors.primaryColor.withValues(alpha: 0.72),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              height: 1.2,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LicensePreview extends StatelessWidget {
  const _LicensePreview({required this.imageValue, this.memoryBytes});

  final String? imageValue;
  final Uint8List? memoryBytes;

  @override
  Widget build(BuildContext context) {
    if (memoryBytes != null && memoryBytes!.isNotEmpty) {
      return _LicenseImageTapTarget(
        onTap: () {
          showAppImageViewer(
            context,
            title: 'License Photo',
            memoryBytes: memoryBytes,
          );
        },
        child: _LicenseImageFrame(
          child: Image.memory(
            memoryBytes!,
            width: double.infinity,
            height: 220,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    final normalizedValue = imageValue?.trim();
    final hasNetworkImage =
        normalizedValue != null && normalizedValue.startsWith('http');
    final hasImageValue = normalizedValue != null && normalizedValue.isNotEmpty;
    final hasImageError = hasImageValue && !hasNetworkImage;

    if (hasNetworkImage) {
      return _LicenseImageTapTarget(
        onTap: () {
          showAppImageViewer(
            context,
            title: 'License Photo',
            imageUrl: normalizedValue,
          );
        },
        child: _LicenseImageFrame(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AppCachedNetworkImage(
              imageUrl: normalizedValue,
              width: double.infinity,
              height: 220,
              fit: BoxFit.contain,
              errorBuilder: (context, error) {
                return const _LicenseImageFallback(
                  icon: Icons.broken_image_rounded,
                  label: 'Failed to load license image.',
                  isError: true,
                );
              },
            ),
          ),
        ),
      );
    }

    return _LicenseImageFrame(
      child: _LicenseImageFallback(
        icon: hasImageError
            ? Icons.broken_image_rounded
            : Icons.image_not_supported_outlined,
        label: hasImageError
            ? 'Failed to load license image.'
            : 'No license image found.',
        isError: hasImageError,
      ),
    );
  }
}

class _LicenseImageTapTarget extends StatelessWidget {
  const _LicenseImageTapTarget({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: child,
    );
  }
}

class _LicenseActionButton extends StatelessWidget {
  const _LicenseActionButton({required this.hasImage, required this.onPressed});

  final bool hasImage;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FilledButton(
        onPressed: onPressed ?? () {},
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(1000),
          ),
        ),
        child: const Text(
          'Upload',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _LicenseImageFallback extends StatelessWidget {
  const _LicenseImageFallback({
    required this.icon,
    required this.label,
    required this.isError,
  });

  final IconData icon;
  final String label;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final iconColor = isError
        ? AppColors.danger
        : AppColors.primaryColor.withValues(alpha: 0.72);
    final textColor = isError
        ? const Color(0xFFB63B3B)
        : AppColors.primaryColor.withValues(alpha: 0.72);
    final backgroundColor = isError ? const Color(0xFFFFF4F4) : Colors.white;

    return ColoredBox(
      color: backgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 34),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LicenseImageFrame extends StatelessWidget {
  const _LicenseImageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 220,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(18), child: child),
    );
  }
}

class _SecuritySection extends StatelessWidget {
  const _SecuritySection({required this.onChangePassword});

  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Password',
                      style: TextStyle(
                        height: 1.2,
                        color: AppColors.primaryColor.withValues(alpha: 0.72),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      '••••••••',
                      style: TextStyle(
                        height: 1.2,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 32,
                child: FilledButton(
                  onPressed: onChangePassword,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(1000),
                    ),
                  ),
                  child: const Text(
                    'Change',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangePasswordResult {
  const _ChangePasswordResult({
    required this.oldPassword,
    required this.newPassword,
  });

  final String oldPassword;
  final String newPassword;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.onSave});

  final Future<void> Function(_ChangePasswordResult result) onSave;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final FocusNode _oldPasswordFocusNode = FocusNode();
  final FocusNode _newPasswordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();
  bool _isOldPasswordObscured = true;
  bool _isNewPasswordObscured = true;
  bool _isConfirmPasswordObscured = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _oldPasswordFocusNode.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
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

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    final oldPassword = _oldPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    final validationMessage = _validate(
      oldPassword: oldPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
    if (validationMessage != null) {
      AppSnackbar.showError(context, validationMessage);
      return;
    }

    final result = _ChangePasswordResult(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
    setState(() {
      _isSubmitting = true;
    });
    try {
      await widget.onSave(result);
      if (!mounted) {
        return;
      }
      AppSnackbar.showSuccess(context, 'Password updated.');
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppSnackbar.showError(
        context,
        error is Exception
            ? error.toString().replaceFirst('Exception: ', '')
            : 'We could not change the password right now.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String? _validate({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  }) {
    if (oldPassword.isEmpty) {
      return 'Old password is required.';
    }
    if (newPassword.isEmpty) {
      return 'New password is required.';
    }
    if (newPassword.length < 6) {
      return 'New password must be at least 6 characters.';
    }
    if (newPassword == oldPassword) {
      return 'New password must be different from the old password.';
    }
    if (confirmPassword.isEmpty) {
      return 'Please confirm your new password.';
    }
    if (confirmPassword != newPassword) {
      return 'Confirm password does not match the new password.';
    }
    return null;
  }

  Widget _passwordSuffix({
    required bool obscured,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded,
      ),
      color: AppColors.primaryColor.withValues(alpha: 0.72),
      splashRadius: 18,
      tooltip: obscured ? 'Show password' : 'Hide password',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: 'Change Password',
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 14),
      actionsInset: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Save'),
        ),
      ],
      child: AdminModalFormBody(
        children: [
          AdminModalFieldsSection(
            children: [
              AdminModalTextField(
                controller: _oldPasswordController,
                focusNode: _oldPasswordFocusNode,
                label: 'Old Password',
                obscureText: _isOldPasswordObscured,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _focusNext(_newPasswordFocusNode),
                suffixIcon: _passwordSuffix(
                  obscured: _isOldPasswordObscured,
                  onPressed: () {
                    setState(() {
                      _isOldPasswordObscured = !_isOldPasswordObscured;
                    });
                  },
                ),
              ),
              AdminModalTextField(
                controller: _newPasswordController,
                focusNode: _newPasswordFocusNode,
                label: 'New Password',
                obscureText: _isNewPasswordObscured,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _focusNext(_confirmPasswordFocusNode),
                suffixIcon: _passwordSuffix(
                  obscured: _isNewPasswordObscured,
                  onPressed: () {
                    setState(() {
                      _isNewPasswordObscured = !_isNewPasswordObscured;
                    });
                  },
                ),
              ),
              AdminModalTextField(
                controller: _confirmPasswordController,
                focusNode: _confirmPasswordFocusNode,
                label: 'Confirm Password',
                obscureText: _isConfirmPasswordObscured,
                bottomPadding: 0,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  _unfocusCurrentField();
                  _submit();
                },
                suffixIcon: _passwordSuffix(
                  obscured: _isConfirmPasswordObscured,
                  onPressed: () {
                    setState(() {
                      _isConfirmPasswordObscured = !_isConfirmPasswordObscured;
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
