import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/app_profile_avatar.dart';
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
    this.vehicleCatalogRepository,
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
  final VehicleCatalogRepository? vehicleCatalogRepository;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  static final Map<String, VehicleMake?> _assignedMakeCacheByDriverId = {};
  VehicleMake? _assignedMake;
  bool _isLoadingAssignedMake = true;
  ProfilePendingImageUpload? _pendingPhotoUpload;
  ProfilePendingImageUpload? _pendingLicenseUpload;
  bool _isSavingProfileChanges = false;

  VehicleCatalogRepository get _vehicleCatalogRepository =>
      widget.vehicleCatalogRepository ?? VehicleRequest.instance;

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
      final makes = await _vehicleCatalogRepository.getMakes();
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return null;
    }

    return ProfilePendingImageUpload(
      bytes: bytes,
      fileName: file.name,
      size: file.size,
      mimeType: _resolvedMimeType(file.extension),
    );
  }

  String? _resolvedMimeType(String? extension) {
    switch ((extension ?? '').trim().toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
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
      AppSnackbar.showSuccess(context, 'Profile changes saved.');
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

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final roleLabel = _formatRole(user.role);
    final driver = user.asDriver;
    final showDriverFields = driver != null;
    final hasLicensePreview =
        _pendingLicenseUpload != null ||
        _hasLicensePreviewValue(driver?.license);
    final showOnlineField = user.role == 'driver' || user.role == 'helper';
    final joinedLabel = _formatDateTime(user.createdAt);
    final updatedLabel = _formatDateTime(user.updatedAt);
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
            onChangePhotoPressed: widget.isCurrentUserView
                ? _pickProfilePhoto
                : null,
            pendingPhotoBytes: _pendingPhotoUpload?.bytes,
            isCurrentUserView: widget.isCurrentUserView,
            onQuickActionPressed: widget.onQuickActionPressed,
            quickActionLabel: widget.quickActionLabel,
            quickActionTextColor: widget.quickActionTextColor,
            quickActionBorderColor: widget.quickActionBorderColor,
          ),
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
              if (showDriverFields)
                _InfoRow(
                  label: 'LatLng',
                  value: _latLngValue(driver.lat, driver.lng),
                ),
            ],
          ),
          if (showDriverFields) ...[
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(child: AdminSectionTitle(title: 'License')),
                if (widget.isCurrentUserView || widget.onEditPressed != null)
                  _LicenseActionButton(
                    hasImage: hasLicensePreview,
                    onPressed: widget.isCurrentUserView
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
          const _SecuritySection(),
          if (widget.isCurrentUserView && _hasPendingChanges) ...[
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
                  _isSavingProfileChanges ? 'Saving...' : 'Save',
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

    return role
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static String _valueOrDash(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? '-' : trimmed;
  }

  static String _valueOrNotSet(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? 'Not set' : trimmed;
  }

  static String _latLngValue(double? lat, double? lng) {
    if (lat == null && lng == null) {
      return 'Not set';
    }
    final latLabel = lat?.toString() ?? 'Not set';
    final lngLabel = lng?.toString() ?? 'Not set';
    return '$latLabel, $lngLabel';
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
                        ? const Color(0xFFC93B3B)
                        : (quickActionTextColor ?? AppColors.primaryColor),
                    borderColor: isCurrentUserView
                        ? const Color(0xFFF2C2C7)
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
                    alpha: appPressablePressed(context) ? 0.34 : 0.22,
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
        builder: (context) => Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: appPressablePressed(context)
                ? AppColors.primarySurfaceAlt.withValues(alpha: 0.28)
                : appPressableHovered(context)
                ? AppColors.primarySurfaceAlt.withValues(alpha: 0.14)
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
              color: appPressablePressed(context)
                  ? AppColors.primarySurfaceAlt.withValues(alpha: 0.28)
                  : appPressableHovered(context)
                  ? AppColors.primarySurfaceAlt.withValues(alpha: 0.16)
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
      return _LicenseImageFrame(
        child: Image.memory(
          memoryBytes!,
          width: double.infinity,
          height: 220,
          fit: BoxFit.cover,
        ),
      );
    }

    final normalizedValue = imageValue?.trim();
    final hasNetworkImage =
        normalizedValue != null && normalizedValue.startsWith('http');
    final hasImageValue = normalizedValue != null && normalizedValue.isNotEmpty;
    final hasImageError = hasImageValue && !hasNetworkImage;

    if (hasNetworkImage) {
      return _LicenseImageFrame(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.network(
            normalizedValue,
            width: double.infinity,
            height: 220,
            fit: BoxFit.cover,
            webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
            errorBuilder: (context, error, stackTrace) {
              return const _LicenseImageFallback(
                icon: Icons.broken_image_rounded,
                label: 'Failed to load license image.',
                isError: true,
              );
            },
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

class _LicenseActionButton extends StatelessWidget {
  const _LicenseActionButton({required this.hasImage, required this.onPressed});

  final bool hasImage;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FilledButton.icon(
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
        icon: const Icon(Icons.upload_rounded, size: 18),
        label: const Text(
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
        ? const Color(0xFFD94B4B)
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
  const _SecuritySection();

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
                  onPressed: () {},
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
