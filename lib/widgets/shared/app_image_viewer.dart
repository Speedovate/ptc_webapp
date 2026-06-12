import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/widgets/shared/app_cached_network_image.dart';

Future<void> showAppImageViewer(
  BuildContext context, {
  required String title,
  Uint8List? memoryBytes,
  String? imageUrl,
}) {
  final normalizedUrl = imageUrl?.trim();
  final hasMemoryImage = memoryBytes != null && memoryBytes.isNotEmpty;
  final resolvedImageUrl =
      !hasMemoryImage &&
          normalizedUrl != null &&
          normalizedUrl.isNotEmpty &&
          normalizedUrl.startsWith('http')
      ? normalizedUrl
      : null;
  final hasNetworkImage = resolvedImageUrl != null;

  if (!hasMemoryImage && !hasNetworkImage) {
    return Future.value();
  }

  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.trim().isEmpty ? 'Image Preview' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0x22FFFFFF)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: ColoredBox(
                          color: Colors.black,
                          child: InteractiveViewer(
                            minScale: 0.8,
                            maxScale: 5,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: Center(
                                child: hasMemoryImage
                                    ? Image.memory(
                                        memoryBytes,
                                        width: constraints.maxWidth,
                                        height: constraints.maxHeight,
                                        fit: BoxFit.contain,
                                      )
                                    : AppCachedNetworkImage(
                                        imageUrl: resolvedImageUrl!,
                                        width: constraints.maxWidth,
                                        height: constraints.maxHeight,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error) {
                                          return const _AppImageViewerFallback(
                                            icon: Icons.broken_image_rounded,
                                            label: 'Failed to load image.',
                                          );
                                        },
                                      ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  'Pinch or scroll to zoom.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AppImageViewerFallback extends StatelessWidget {
  const _AppImageViewerFallback({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.dangerStrong, size: 34),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
