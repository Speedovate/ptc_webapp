import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';

class AppProfileAvatar extends StatelessWidget {
  const AppProfileAvatar({
    super.key,
    required this.radius,
    this.photo,
    this.fallbackText,
  });

  final double radius;
  final String? photo;
  final String? fallbackText;

  static const double _borderRatio = 0.16;

  @override
  Widget build(BuildContext context) {
    final normalizedPhoto = photo?.trim();
    final imageBytes = _decodeBase64Image(normalizedPhoto);
    final borderColor = AppColors.primarySurfaceAlt;
    final hasPhotoValue = normalizedPhoto != null && normalizedPhoto.isNotEmpty;
    final hasNetworkImage =
        normalizedPhoto != null && normalizedPhoto.startsWith('http');
    final hasImageError = hasPhotoValue && imageBytes == null && !hasNetworkImage;

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
                  normalizedPhoto: normalizedPhoto,
                  imageBytes: imageBytes,
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
                border: Border.all(
                  color: borderColor,
                  width: innerBorderWidth,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarContent({
    required String? normalizedPhoto,
    required Uint8List? imageBytes,
    required bool hasNetworkImage,
    required bool hasImageError,
  }) {
    if (imageBytes != null) {
      return Image.memory(
        imageBytes,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _FallbackAvatarContent(
            radius: radius,
            fallbackText: fallbackText,
            isError: true,
          );
        },
      );
    }

    if (hasNetworkImage) {
      return Image.network(
        normalizedPhoto!,
        fit: BoxFit.cover,
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

  Uint8List? _decodeBase64Image(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final data = value.contains(',') ? value.split(',').last : value;
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
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
            color: const Color(0xFFD94B4B),
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
