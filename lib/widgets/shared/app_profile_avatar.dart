import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/widgets/shared/app_cached_network_image.dart';
import 'package:webapp/widgets/shared/app_image_viewer.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';

class AppProfileAvatar extends StatelessWidget {
  const AppProfileAvatar({
    super.key,
    required this.radius,
    this.photo,
    this.memoryBytes,
    this.fallbackText,
    this.enablePreview = false,
    this.previewTitle,
    this.borderColor,
    this.debugLabel,
  });

  final double radius;
  final String? photo;
  final Uint8List? memoryBytes;
  final String? fallbackText;
  final bool enablePreview;
  final String? previewTitle;
  final Color? borderColor;
  final String? debugLabel;

  static const double _borderRatio = 0.16;

  @override
  Widget build(BuildContext context) {
    final normalizedPhoto = photo?.trim();
    final resolvedBorderColor = borderColor ?? AppColors.primarySurfaceAlt;
    final hasMemoryImage = memoryBytes != null && memoryBytes!.isNotEmpty;
    final hasPhotoValue = normalizedPhoto != null && normalizedPhoto.isNotEmpty;
    final hasDisplayablePhoto =
        !hasMemoryImage &&
        normalizedPhoto != null &&
        (normalizedPhoto.startsWith('http') ||
            normalizedPhoto.startsWith('data:'));
    final hasImageError =
        !hasMemoryImage && hasPhotoValue && !hasDisplayablePhoto;
    _trace(
      'build memory=$hasMemoryImage photo=$hasPhotoValue '
      'displayable=$hasDisplayablePhoto invalid=$hasImageError '
      'source=${_sourceFingerprint(normalizedPhoto)}',
    );

    final innerBorderWidth = radius * _borderRatio;
    final diameter = radius * 2;

    final avatar = SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: Colors.white,
            child: ClipOval(
              child: SizedBox.expand(
                child: _buildAvatarContent(
                  memoryBytes: memoryBytes,
                  normalizedPhoto: normalizedPhoto,
                  hasDisplayablePhoto: hasDisplayablePhoto,
                  hasImageError: hasImageError,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: resolvedBorderColor,
                  width: innerBorderWidth,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final canPreview = enablePreview && (hasMemoryImage || hasDisplayablePhoto);
    if (!canPreview) {
      return avatar;
    }

    return AppMousePressable(
      onTap: () {
        showAppImageViewer(
          context,
          title: previewTitle ?? fallbackText ?? 'Profile Photo',
          memoryBytes: hasMemoryImage ? memoryBytes : null,
          imageUrl: hasDisplayablePhoto ? normalizedPhoto : null,
        );
      },
      borderRadius: BorderRadius.circular(radius),
      child: avatar,
    );
  }

  Widget _buildAvatarContent({
    required Uint8List? memoryBytes,
    required String? normalizedPhoto,
    required bool hasDisplayablePhoto,
    required bool hasImageError,
  }) {
    if (memoryBytes != null && memoryBytes.isNotEmpty) {
      return Image.memory(memoryBytes, fit: BoxFit.cover);
    }

    if (hasDisplayablePhoto) {
      return AppCachedNetworkImage(
        imageUrl: normalizedPhoto!,
        debugLabel: debugLabel,
        fit: BoxFit.cover,
        errorBuilder: (context, error) {
          return _FallbackAvatarContent(
            radius: radius,
            fallbackText: fallbackText,
            isError: true,
          );
        },
      );
    }

    return _FallbackAvatarContent(
      radius: radius,
      fallbackText: fallbackText,
      isError: hasImageError,
    );
  }

  void _trace(String message) {
    final label = debugLabel?.trim();
    if (label == null || label.isEmpty) {
      return;
    }
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[$timestamp][ProfileAvatarTrace][$label] $message');
  }

  String _sourceFingerprint(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return '-';
    }
    final queryIndex = normalized.indexOf('?');
    return queryIndex < 0 ? normalized : normalized.substring(0, queryIndex);
  }
}

class _FallbackAvatarContent extends StatelessWidget {
  const _FallbackAvatarContent({
    required this.radius,
    required this.fallbackText,
    this.isError = false,
  });

  final double radius;
  final String? fallbackText;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    if (isError) {
      return ColoredBox(
        color: const Color(0xFFFFF1F1),
        child: Center(
          child: Icon(
            Icons.broken_image_rounded,
            color: AppColors.danger,
            size: radius * 0.8,
          ),
        ),
      );
    }

    final label = fallbackText?.trim() ?? '';
    if (label.isNotEmpty) {
      return ColoredBox(
        color: AppColors.primaryColor,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: (radius * 0.62).clamp(12.0, 20.0),
              height: 1,
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.primaryColor,
      child: Center(
        child: Icon(
          Icons.person_outline_rounded,
          color: Colors.white,
          size: radius,
        ),
      ),
    );
  }
}
