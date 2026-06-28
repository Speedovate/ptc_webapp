import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/app_cached_network_image.dart';

const Color bookingFormDangerStripColor = AppColors.dangerStrong;
const double bookingFormContentHorizontalPadding = 18;
const EdgeInsets bookingFormOuterShellPadding = EdgeInsets.all(20);

class BookingFormPalette {
  const BookingFormPalette({
    required this.strip,
    required this.accent,
    required this.accentMuted,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
  });

  final Color strip;
  final Color accent;
  final Color accentMuted;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
}

const BookingFormPalette bookingFormPrimaryPalette = BookingFormPalette(
  strip: AppColors.primaryColor,
  accent: AppColors.primaryColor,
  accentMuted: AppColors.primaryBorderDark,
  surface: AppColors.primarySurface,
  surfaceAlt: AppColors.primarySurfaceAlt,
  border: AppColors.primaryBorder,
);

const BookingFormPalette bookingFormDangerPalette = BookingFormPalette(
  strip: AppColors.dangerStrong,
  accent: AppColors.dangerStrong,
  accentMuted: AppColors.danger,
  surface: AppColors.dangerSurface,
  surfaceAlt: AppColors.dangerSurfaceAlt,
  border: AppColors.dangerBorder,
);

const BookingFormPalette bookingFormDeliveredPalette = BookingFormPalette(
  strip: Color(0xFF2EAD62),
  accent: Color(0xFF2EAD62),
  accentMuted: Color(0xFF4D7C5C),
  surface: Color(0xFFF4FBF6),
  surfaceAlt: Color(0xFFE7F5EB),
  border: Color(0xFFBFE1C8),
);

bool bookingFormUsesDangerTheme({String? title, String? buttonText}) {
  bool containsCancel(String? value) =>
      value?.toLowerCase().contains('cancel') == true;

  return containsCancel(title) || containsCancel(buttonText);
}

BookingFormPalette bookingFormResolvedPalette({
  String? title,
  String? buttonText,
}) {
  return bookingFormUsesDangerTheme(title: title, buttonText: buttonText)
      ? bookingFormDangerPalette
      : bookingFormPrimaryPalette;
}

BookingFormPalette bookingFormResolvedStatusPalette({
  String? title,
  String? buttonText,
  String? currentStatusKey,
}) {
  if (bookingFormUsesDangerTheme(title: title, buttonText: buttonText)) {
    return bookingFormDangerPalette;
  }
  if (currentStatusKey?.trim() == 'delivered') {
    return bookingFormDeliveredPalette;
  }
  return bookingFormPrimaryPalette;
}

Color bookingFormResolvedStripColor({
  String? title,
  String? buttonText,
  Color? fallbackColor,
}) {
  if (bookingFormUsesDangerTheme(title: title, buttonText: buttonText)) {
    return bookingFormDangerPalette.strip;
  }
  return fallbackColor ?? AppColors.primaryColor;
}

Color bookingFormResolvedActionColor({
  String? title,
  String? buttonText,
  Color? fallbackColor,
}) {
  if (bookingFormUsesDangerTheme(title: title, buttonText: buttonText)) {
    return bookingFormDangerPalette.accent;
  }
  return fallbackColor ?? AppColors.primaryColor;
}

Color bookingFormResolvedLegendColor({String? title, String? buttonText}) {
  if (bookingFormUsesDangerTheme(title: title, buttonText: buttonText)) {
    return bookingFormDangerPalette.accent;
  }
  return AppColors.primaryColor;
}

class BookingFormTitleCardShell extends StatelessWidget {
  const BookingFormTitleCardShell({
    super.key,
    required this.child,
    this.stripColor = AppColors.primaryColor,
    this.borderColor = AppColors.primaryBorder,
    this.bodyColor = Colors.white,
    this.radius = 18,
    this.stripRadius = 16,
    this.stripHeight = 12,
    this.bodyPadding = const EdgeInsets.fromLTRB(
      bookingFormContentHorizontalPadding,
      12,
      bookingFormContentHorizontalPadding,
      16,
    ),
  });

  final Widget child;
  final Color stripColor;
  final Color borderColor;
  final Color bodyColor;
  final double radius;
  final double stripRadius;
  final double stripHeight;
  final EdgeInsetsGeometry bodyPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          height: stripHeight,
          decoration: BoxDecoration(
            color: stripColor,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(stripRadius),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: bodyPadding,
          decoration: BoxDecoration(
            color: bodyColor,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(radius),
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

class BookingFormOuterShell extends StatelessWidget {
  const BookingFormOuterShell({
    super.key,
    required this.palette,
    required this.child,
    this.padding = bookingFormOuterShellPadding,
    this.radius = 20,
  });

  final BookingFormPalette palette;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

class BookingFormHeaderCard extends StatelessWidget {
  const BookingFormHeaderCard({
    super.key,
    required this.title,
    this.subtitle,
    this.buttonText,
    this.paletteOverride,
    this.backgroundColor,
    this.borderColor,
    this.bodyColor,
    this.titleColor,
    this.subtitleColor,
    this.message,
    this.messageBackgroundColor,
    this.messageBorderColor,
    this.messageIcon,
    this.messageIconColor,
    this.messageTextColor,
    this.showRequiredLegend = false,
  });

  final String title;
  final String? subtitle;
  final String? buttonText;
  final BookingFormPalette? paletteOverride;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? bodyColor;
  final Color? titleColor;
  final Color? subtitleColor;
  final String? message;
  final Color? messageBackgroundColor;
  final Color? messageBorderColor;
  final IconData? messageIcon;
  final Color? messageIconColor;
  final Color? messageTextColor;
  final bool showRequiredLegend;

  @override
  Widget build(BuildContext context) {
    final palette =
        paletteOverride ??
        bookingFormResolvedPalette(title: title, buttonText: buttonText);
    return BookingFormTitleCardShell(
      stripColor: bookingFormResolvedStripColor(
        title: title,
        buttonText: buttonText,
        fallbackColor: backgroundColor,
      ),
      borderColor: borderColor ?? palette.border,
      bodyColor: bodyColor ?? Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: titleColor ?? AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if (subtitle?.trim().isNotEmpty == true)
            Text(
              subtitle!.trim(),
              style: TextStyle(
                color: subtitleColor ?? AppColors.textPrimary,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          if (showRequiredLegend) ...[
            const SizedBox(height: 8),
            Container(width: double.infinity, height: 1, color: palette.border),
            const SizedBox(height: 14),
            Text(
              '* indicates required input',
              style: TextStyle(
                color: palette.accent,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
            ),
          ],
          if (subtitle?.trim().isNotEmpty != true &&
              message?.trim().isNotEmpty == true)
            const SizedBox(height: 14),
          if (message?.trim().isNotEmpty == true) const SizedBox(height: 14),
          if (message?.trim().isNotEmpty == true) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: bookingFormContentHorizontalPadding,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: messageBackgroundColor ?? palette.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: messageBorderColor ?? palette.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (messageIcon != null) ...[
                    Icon(
                      messageIcon,
                      size: 18,
                      color: messageIconColor ?? palette.accent,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      message!.trim(),
                      style: TextStyle(
                        color:
                            messageTextColor ??
                            palette.accent.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class BookingFormFieldCard extends StatelessWidget {
  const BookingFormFieldCard({
    super.key,
    required this.title,
    required this.input,
    this.buttonText,
    this.paletteOverride,
    this.required = false,
    this.subtitle,
    this.instructions,
    this.headerTrailing,
    this.inputTopSpacing = 14,
    this.showContainer = true,
    this.containerPadding = const EdgeInsets.all(18),
    this.containerColor,
  });

  final String title;
  final String? buttonText;
  final BookingFormPalette? paletteOverride;
  final bool required;
  final String? subtitle;
  final String? instructions;
  final Widget input;
  final Widget? headerTrailing;
  final double inputTopSpacing;
  final bool showContainer;
  final EdgeInsetsGeometry containerPadding;
  final Color? containerColor;

  @override
  Widget build(BuildContext context) {
    final palette =
        paletteOverride ??
        bookingFormResolvedPalette(title: title, buttonText: buttonText);
    final hasSupportingText =
        subtitle?.trim().isNotEmpty == true ||
        instructions?.trim().isNotEmpty == true;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  text: title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  children: [
                    if (required)
                      TextSpan(
                        text: ' *',
                        style: TextStyle(
                          color: palette.accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (headerTrailing != null) ...[
              const SizedBox(width: 12),
              headerTrailing!,
            ],
          ],
        ),
        if (subtitle?.trim().isNotEmpty == true)
          Text(
            subtitle!.trim(),
            style: TextStyle(
              color: palette.accentMuted,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        if (instructions?.trim().isNotEmpty == true)
          Text(
            instructions!.trim(),
            style: TextStyle(
              color: palette.accentMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        if (hasSupportingText) const SizedBox(height: 14),
        if (!hasSupportingText && inputTopSpacing > 0)
          SizedBox(height: inputTopSpacing),
        input,
      ],
    );

    if (!showContainer) {
      return content;
    }

    return Container(
      width: double.infinity,
      padding: containerPadding,
      decoration: BoxDecoration(
        color: containerColor ?? Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: content,
    );
  }
}

class BookingPhotoFieldInput extends StatefulWidget {
  const BookingPhotoFieldInput({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    this.onMoveToNextFocus,
    this.placeholder,
    this.supportText = 'JPG, PNG, or supported image file',
    this.errorText,
    this.showRemoveAction = false,
    this.palette = bookingFormPrimaryPalette,
  });

  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final ValueChanged<FocusNode>? onMoveToNextFocus;
  final String? placeholder;
  final String supportText;
  final String? errorText;
  final bool showRemoveAction;
  final BookingFormPalette palette;

  @override
  State<BookingPhotoFieldInput> createState() => _BookingPhotoFieldInputState();
}

class _BookingPhotoFieldInputState extends State<BookingPhotoFieldInput> {
  static const Duration _minimumProcessingIndicatorDuration = Duration(
    milliseconds: 450,
  );

  Map<String, dynamic>? _photo;
  Uint8List? _previewBytes;
  String? _previewUrl;
  bool _isProcessing = false;
  bool _isSelectingPhoto = false;

  FocusNode? get _focusNode => widget.focusNode;
  String get _placeholder =>
      widget.placeholder?.trim().isNotEmpty == true
          ? widget.placeholder!.trim()
          : adminUploadPlaceholder('Photo');

  @override
  void initState() {
    super.initState();
    _syncFromInitialValue();
    _focusNode?.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant BookingPhotoFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChanged);
      widget.focusNode?.addListener(_handleFocusChanged);
    }
    if (oldWidget.initialValue != widget.initialValue) {
      _syncFromInitialValue();
    }
  }

  @override
  void dispose() {
    _focusNode?.removeListener(_handleFocusChanged);
    super.dispose();
  }

  void _syncFromInitialValue() {
    _photo = widget.initialValue is Map<String, dynamic>
        ? Map<String, dynamic>.from(widget.initialValue as Map<String, dynamic>)
        : widget.initialValue is Map
        ? Map<String, dynamic>.from(widget.initialValue as Map)
        : null;
    _previewBytes = decodePhotoBytes(widget.initialValue);
    _previewUrl = photoDownloadUrl(widget.initialValue);
  }

  Future<void> _pickPhoto() async {
    if (_isProcessing) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return;
    }
    setState(() {
      _isProcessing = true;
      _isSelectingPhoto = true;
      _photo = {'name': file.name, 'size': file.size};
      _previewBytes = bytes;
    });
    await Future<void>.delayed(_minimumProcessingIndicatorDuration);
    if (!mounted) {
      return;
    }
    final nextPhoto = <String, dynamic>{
      'name': file.name,
      'bytes': bytes,
      'size': file.size,
      'mime_type': _resolvedMimeType(file),
    };
    setState(() {
      _photo = nextPhoto;
      _previewBytes = bytes;
      _previewUrl = null;
      _isProcessing = false;
      _isSelectingPhoto = false;
    });
    widget.onChanged(nextPhoto);
    final nextFocusNode = widget.nextFocusNode;
    if (nextFocusNode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final moveToNextFocus = widget.onMoveToNextFocus;
        if (moveToNextFocus != null) {
          moveToNextFocus(nextFocusNode);
          return;
        }
        FocusScope.of(context).requestFocus(nextFocusNode);
        if (widget.activateNextFocus) {
          final primaryFocus = FocusManager.instance.primaryFocus;
          final nextContext = primaryFocus?.context ?? nextFocusNode.context;
          if (nextContext != null) {
            Actions.maybeInvoke(nextContext, const ActivateIntent());
          }
        }
      });
    }
  }

  void _handleFocusChanged() {
    final focusNode = _focusNode;
    if (focusNode == null) {
      return;
    }
  }

  void _removePhoto() {
    if (_isProcessing) {
      return;
    }
    setState(() {
      _photo = null;
      _previewBytes = null;
      _previewUrl = null;
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final previewBytes = _previewBytes;
    final previewUrl = _previewUrl?.trim();
    final fileName = _photo?['name']?.toString().trim();
    final hasFileName = fileName?.isNotEmpty == true;
    final hasImage = previewBytes != null || (previewUrl?.isNotEmpty == true);
    final processingLabel = _isSelectingPhoto
        ? 'Preparing photo ...'
        : 'Processing photo ...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: hasImage ? EdgeInsets.zero : const EdgeInsets.all(18),
          decoration: hasImage
              ? null
              : BoxDecoration(
                  color: widget.palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.errorText == null
                        ? widget.palette.border
                        : AppColors.danger,
                  ),
                ),
          child: Column(
            children: [
              if (hasImage) ...[
                Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (previewBytes != null)
                            Image.memory(
                              previewBytes,
                              width: double.infinity,
                              fit: BoxFit.fitWidth,
                            )
                          else if (previewUrl?.isNotEmpty == true)
                            AppCachedNetworkImage(
                              imageUrl: previewUrl!,
                              width: double.infinity,
                              fit: BoxFit.fitWidth,
                              errorBuilder: (context, error) {
                                return const _BookingPhotoPreviewFallback(
                                  height: 180,
                                  message: 'Failed to load photo preview.',
                                );
                              },
                            )
                          else
                            const _BookingPhotoPreviewFallback(height: 180),
                          if (_isProcessing)
                            Positioned.fill(
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: 0.22),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.58,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          processingLabel,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
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
                const SizedBox(height: 12),
              ] else ...[
                Icon(
                  Icons.add_a_photo_outlined,
                  size: 28,
                  color: widget.palette.accent,
                ),
                const SizedBox(height: 10),
              ],
              Text(
                hasFileName ? fileName! : _placeholder,
                style: TextStyle(
                  color: hasFileName
                      ? AppColors.textPrimary
                      : widget.palette.accentMuted,
                  fontWeight: hasFileName ? FontWeight.w700 : FontWeight.w800,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              if (!hasFileName)
                Text(
                  widget.supportText,
                  style: TextStyle(
                    color: widget.palette.accentMuted,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 12),
              if (_isProcessing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        processingLabel,
                        style: TextStyle(
                          color: widget.palette.accentMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    height: 32,
                    child: FilledButton.icon(
                      focusNode: _focusNode,
                      onPressed: _isProcessing ? null : _pickPhoto,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.palette.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.upload_rounded, size: 18),
                      label: Text(
                        _isProcessing
                            ? (_isSelectingPhoto
                                  ? 'Preparing ...'
                                  : 'Processing ...')
                            : (_photo == null ? 'Choose File' : 'Replace File'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (widget.showRemoveAction && _photo != null)
                    TextButton(
                      onPressed: _isProcessing ? null : _removePhoto,
                      child: const Text('Remove'),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.errorText!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

String? _resolvedMimeType(PlatformFile file) {
  final extension = file.extension?.trim().toLowerCase();
  if (extension == null || extension.isEmpty) {
    return null;
  }
  return 'image/$extension';
}

class _BookingPhotoPreviewFallback extends StatelessWidget {
  const _BookingPhotoPreviewFallback({
    required this.height,
    this.message = 'No photo preview available.',
  });

  final double height;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      color: bookingFormPrimaryPalette.surface,
      alignment: Alignment.center,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: bookingFormPrimaryPalette.accentMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
