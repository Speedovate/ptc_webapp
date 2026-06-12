import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';

class AppProfileAvatar extends StatelessWidget {
  const AppProfileAvatar({
    super.key,
    required this.radius,
    this.photo,
    this.memoryBytes,
    this.fallbackText,
  });

  final double radius;
  final String? photo;
  final Uint8List? memoryBytes;
  final String? fallbackText;

  static const double _borderRatio = 0.16;

  @override
  Widget build(BuildContext context) {
    final normalizedPhoto = photo?.trim();
    final borderColor = AppColors.primarySurfaceAlt;
    final hasMemoryImage = memoryBytes != null && memoryBytes!.isNotEmpty;
    final hasPhotoValue = normalizedPhoto != null && normalizedPhoto.isNotEmpty;
    final hasNetworkImage =
        !hasMemoryImage &&
        normalizedPhoto != null &&
        normalizedPhoto.startsWith('http');
    final hasImageError = !hasMemoryImage && hasPhotoValue && !hasNetworkImage;

    final innerBorderWidth = radius * _borderRatio;
    final diameter = radius * 2;

    return SizedBox(
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
                  hasNetworkImage: hasNetworkImage,
                  hasImageError: hasImageError,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: innerBorderWidth),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarContent({
    required Uint8List? memoryBytes,
    required String? normalizedPhoto,
    required bool hasNetworkImage,
    required bool hasImageError,
  }) {
    if (memoryBytes != null && memoryBytes.isNotEmpty) {
      return Image.memory(memoryBytes, fit: BoxFit.cover);
    }

    if (hasNetworkImage) {
      return Image.network(
        normalizedPhoto!,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        errorBuilder: (context, error, stackTrace) {
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
