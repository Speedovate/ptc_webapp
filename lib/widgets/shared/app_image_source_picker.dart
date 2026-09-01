import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/services/auth_camera_service.dart';
import 'package:webapp/services/auth_image_picker_service.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

Future<AuthPickedImage?> showAppImageSourcePicker(
  BuildContext context, {
  String chooserTitle = 'Choose Photo Source',
  String captureTitle = 'Take Photo',
}) async {
  final source = await showAppModalBottomSheet<AuthImagePickSource>(
    context: context,
    modalKey: 'image-source-picker:${chooserTitle.trim()}',
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.primaryBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chooserTitle,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ImageSourceAction(
                    icon: Icons.photo_camera_outlined,
                    label: 'Camera',
                    onTap: () => Navigator.of(sheetContext).pop(
                      AuthImagePickSource.camera,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ImageSourceAction(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    onTap: () => Navigator.of(sheetContext).pop(
                      AuthImagePickSource.gallery,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  if (source == null) {
    return null;
  }
  if (source == AuthImagePickSource.gallery) {
    return pickAuthImage(source);
  }
  if (!context.mounted) {
    return null;
  }
  return _captureCameraImage(context, captureTitle: captureTitle);
}

Future<AuthPickedImage?> _captureCameraImage(
  BuildContext context, {
  required String captureTitle,
}) async {
  if (!authCameraSupported) {
    if (context.mounted) {
      AppSnackbar.showError(
        context,
        'Camera is not supported on this browser. Please use Gallery instead.',
      );
    }
    return null;
  }

  final session = createAuthCameraSession();
  final initializeFuture = session.initialize();
  try {
    final image = await showAppDialog<AuthPickedImage>(
      context: context,
      modalKey: 'camera-capture:${captureTitle.trim()}',
      barrierDismissible: true,
      builder: (dialogContext) {
        var isCapturing = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final modalWidth = constraints.maxWidth.clamp(0.0, 760.0);
                  final isCompact = modalWidth < 560;
                  return Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: modalWidth,
                      padding: EdgeInsets.fromLTRB(
                        isCompact ? 16 : 20,
                        isCompact ? 16 : 20,
                        isCompact ? 16 : 20,
                        isCompact ? 16 : 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: AppColors.primaryBorder),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x261A1333),
                            blurRadius: 28,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: FutureBuilder<void>(
                        future: initializeFuture,
                        builder: (context, snapshot) {
                          final hasError = snapshot.hasError;
                          final isReady =
                              snapshot.connectionState ==
                                  ConnectionState.done &&
                              !hasError;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: AppColors.primarySurface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppColors.primaryBorder,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.photo_camera_outlined,
                                      color: AppColors.primaryColor,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          captureTitle,
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            height: 1.1,
                                          ),
                                        ),
                                        if (hasError) ...[
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Camera permission was denied or unavailable.',
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  width: double.infinity,
                                  constraints: BoxConstraints(
                                    maxHeight: isCompact ? 420 : 520,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryDark,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: AspectRatio(
                                    aspectRatio: isCompact ? 3 / 4 : 4 / 3,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (hasError)
                                          const Center(
                                            child: Padding(
                                              padding: EdgeInsets.all(24),
                                              child: Text(
                                                'We could not open the camera. Check browser permission settings and try again.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          )
                                        else if (!isReady)
                                          const Center(
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                            ),
                                          )
                                        else
                                          HtmlElementView(
                                            viewType: session.viewType!,
                                          ),
                                        IgnorePointer(
                                          child: Padding(
                                            padding: EdgeInsets.all(
                                              isCompact ? 18 : 24,
                                            ),
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xCCFFFFFF,
                                                  ),
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Flex(
                                direction: isCompact
                                    ? Axis.vertical
                                    : Axis.horizontal,
                                children: [
                                  if (!isCompact)
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext).pop(),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              AppColors.textPrimary,
                                          side: const BorderSide(
                                            color: AppColors.primaryBorder,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 15,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                        ),
                                        child: const Text('Cancel'),
                                      ),
                                    )
                                  else
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: !isReady || isCapturing
                                            ? null
                                            : () async {
                                                setModalState(() {
                                                  isCapturing = true;
                                                });
                                                try {
                                                  final image =
                                                      await session.capture();
                                                  if (dialogContext.mounted) {
                                                    Navigator.of(
                                                      dialogContext,
                                                    ).pop(image);
                                                  }
                                                } catch (error) {
                                                  if (context.mounted) {
                                                    AppSnackbar.showError(
                                                      context,
                                                      userFacingErrorMessage(
                                                        error,
                                                        fallback:
                                                            'We could not capture the image right now.',
                                                      ),
                                                    );
                                                  }
                                                  if (dialogContext.mounted) {
                                                    setModalState(() {
                                                      isCapturing = false;
                                                    });
                                                  }
                                                }
                                              },
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              AppColors.primaryColor,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                        ),
                                        child: Text(
                                          isCapturing
                                              ? 'Capturing ...'
                                              : 'Capture Photo',
                                        ),
                                      ),
                                    ),
                                  if (!isCompact) const SizedBox(width: 12),
                                  if (!isCompact)
                                    Expanded(
                                      flex: 2,
                                      child: _CaptureButton(
                                        isReady: isReady,
                                        isCapturing: isCapturing,
                                        onPressed: () async {
                                          setModalState(() {
                                            isCapturing = true;
                                          });
                                          try {
                                            final image =
                                                await session.capture();
                                            if (dialogContext.mounted) {
                                              Navigator.of(
                                                dialogContext,
                                              ).pop(image);
                                            }
                                          } catch (error) {
                                            if (context.mounted) {
                                              AppSnackbar.showError(
                                                context,
                                                userFacingErrorMessage(
                                                  error,
                                                  fallback:
                                                      'We could not capture the image right now.',
                                                ),
                                              );
                                            }
                                            if (dialogContext.mounted) {
                                              setModalState(() {
                                                isCapturing = false;
                                              });
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  if (isCompact) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext).pop(),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              AppColors.textPrimary,
                                          side: const BorderSide(
                                            color: AppColors.primaryBorder,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                        ),
                                        child: const Text('Cancel'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
    return image;
  } finally {
    await SchedulerBinding.instance.endOfFrame;
    await session.dispose();
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.isReady,
    required this.isCapturing,
    required this.onPressed,
  });

  final bool isReady;
  final bool isCapturing;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: !isReady || isCapturing ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: Text(
        isCapturing ? 'Capturing ...' : 'Capture Photo',
      ),
    );
  }
}

class _ImageSourceAction extends StatelessWidget {
  const _ImageSourceAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F1FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primaryBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryColor, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
