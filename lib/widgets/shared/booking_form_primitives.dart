import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';

class BookingFormHeaderCard extends StatelessWidget {
  const BookingFormHeaderCard({
    super.key,
    required this.title,
    this.subtitle,
    this.backgroundColor,
    this.borderColor,
    this.titleColor,
    this.subtitleColor,
    this.message,
    this.messageBackgroundColor,
    this.messageBorderColor,
    this.messageIcon,
    this.messageIconColor,
    this.messageTextColor,
  });

  final String title;
  final String? subtitle;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? titleColor;
  final Color? subtitleColor;
  final String? message;
  final Color? messageBackgroundColor;
  final Color? messageBorderColor;
  final IconData? messageIcon;
  final Color? messageIconColor;
  final Color? messageTextColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.primaryColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor ?? backgroundColor ?? AppColors.primaryColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: titleColor ?? Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if (subtitle?.trim().isNotEmpty == true)
            Text(
              subtitle!.trim(),
              style: TextStyle(
                color: subtitleColor ?? AppColors.primaryBorder,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          if (subtitle?.trim().isNotEmpty != true &&
              message?.trim().isNotEmpty == true)
            const SizedBox(height: 14),
          if (subtitle?.trim().isNotEmpty == true &&
              message?.trim().isNotEmpty == true)
            const SizedBox(height: 14),
          if (message?.trim().isNotEmpty == true) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: messageBackgroundColor ?? AppColors.primarySurfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: messageBorderColor ?? AppColors.primaryBorder,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (messageIcon != null) ...[
                    Icon(
                      messageIcon,
                      size: 18,
                      color: messageIconColor ?? AppColors.primaryColor,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      message!.trim(),
                      style: TextStyle(
                        color: messageTextColor ??
                            AppColors.primaryColor.withValues(alpha: 0.72),
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
    this.required = false,
    this.subtitle,
    this.instructions,
    this.headerTrailing,
    this.inputTopSpacing = 14,
    this.showContainer = true,
    this.containerPadding = const EdgeInsets.all(18),
  });

  final String title;
  final bool required;
  final String? subtitle;
  final String? instructions;
  final Widget input;
  final Widget? headerTrailing;
  final double inputTopSpacing;
  final bool showContainer;
  final EdgeInsetsGeometry containerPadding;

  @override
  Widget build(BuildContext context) {
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
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(
                          color: AppColors.primaryColor,
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
              color: AppColors.primaryColor.withValues(alpha: 0.72),
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        if (instructions?.trim().isNotEmpty == true)
          Text(
            instructions!.trim(),
            style: TextStyle(
              color: AppColors.primaryColor.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        if (hasSupportingText)
          const SizedBox(height: 14),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryBorder),
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
    required this.valueBuilder,
    required this.previewBytesBuilder,
    this.placeholder = 'Upload a photo',
    this.supportText = 'JPG, PNG, or supported image file',
    this.errorText,
    this.showRemoveAction = false,
  });

  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final Map<String, dynamic> Function(PlatformFile file, String encodedBytes)
  valueBuilder;
  final Uint8List? Function(dynamic value) previewBytesBuilder;
  final String placeholder;
  final String supportText;
  final String? errorText;
  final bool showRemoveAction;

  @override
  State<BookingPhotoFieldInput> createState() => _BookingPhotoFieldInputState();
}

class _BookingPhotoFieldInputState extends State<BookingPhotoFieldInput> {
  static const Duration _minimumProcessingIndicatorDuration = Duration(
    milliseconds: 450,
  );

  Map<String, dynamic>? _photo;
  Uint8List? _previewBytes;
  bool _isProcessing = false;
  bool _isSelectingPhoto = false;

  @override
  void initState() {
    super.initState();
    _syncFromInitialValue();
  }

  @override
  void didUpdateWidget(covariant BookingPhotoFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _syncFromInitialValue();
    }
  }

  void _syncFromInitialValue() {
    _photo = widget.initialValue is Map<String, dynamic>
        ? Map<String, dynamic>.from(widget.initialValue as Map<String, dynamic>)
        : widget.initialValue is Map
        ? Map<String, dynamic>.from(widget.initialValue as Map)
        : null;
    _previewBytes = widget.previewBytesBuilder(widget.initialValue);
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
      _photo = {
        'name': file.name,
        'size': file.size,
      };
      _previewBytes = bytes;
    });
    final startedAt = DateTime.now();
    final encoded = await compute(_encodePhotoBytesBase64, bytes);
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < _minimumProcessingIndicatorDuration) {
      await Future<void>.delayed(
        _minimumProcessingIndicatorDuration - elapsed,
      );
    }
    if (!mounted) {
      return;
    }
    final nextPhoto = widget.valueBuilder(file, encoded);
    setState(() {
      _photo = nextPhoto;
      _isProcessing = false;
      _isSelectingPhoto = false;
    });
    widget.onChanged(nextPhoto);
  }

  void _removePhoto() {
    if (_isProcessing) {
      return;
    }
    setState(() {
      _photo = null;
      _previewBytes = null;
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final previewBytes = _previewBytes;
    final fileName = _photo?['name']?.toString().trim();
    final hasFileName = fileName?.isNotEmpty == true;
    final hasImage = previewBytes != null;
    final processingLabel = _isSelectingPhoto
        ? 'Preparing photo...'
        : 'Processing photo...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: hasImage ? EdgeInsets.zero : const EdgeInsets.all(18),
          decoration: hasImage
              ? null
              : BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.errorText == null
                        ? AppColors.primaryBorder
                        : Colors.red,
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
                          Image.memory(
                            previewBytes,
                            width: double.infinity,
                            fit: BoxFit.fitWidth,
                          ),
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
                const Icon(
                  Icons.add_a_photo_outlined,
                  size: 28,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(height: 10),
              ],
              Text(
                hasFileName ? fileName! : widget.placeholder,
                style: TextStyle(
                  color: hasFileName
                      ? AppColors.textPrimary
                      : AppColors.primaryColor.withValues(alpha: 0.72),
                  fontWeight: hasFileName ? FontWeight.w700 : FontWeight.w800,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              if (!hasFileName)
                Text(
                  widget.supportText,
                  style: TextStyle(
                    color: AppColors.primaryColor.withValues(alpha: 0.72),
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
                          color: AppColors.primaryColor.withValues(alpha: 0.78),
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
                      onPressed: _isProcessing ? null : _pickPhoto,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
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
                                  ? 'Preparing...'
                                  : 'Processing...')
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
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

Uint8List? decodeBase64PhotoBytes(dynamic value, {String key = 'bytes_base64'}) {
  final mapValue = value is Map<String, dynamic>
      ? value
      : value is Map
      ? Map<String, dynamic>.from(value)
      : null;
  final encoded = mapValue?[key]?.toString();
  if (encoded == null || encoded.isEmpty) {
    return null;
  }
  try {
    return base64Decode(encoded);
  } catch (_) {
    return null;
  }
}

Uint8List? decodePhotoBytes(dynamic value, {String key = 'bytes'}) {
  if (value is Uint8List) {
    return value;
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  final mapValue = value is Map<String, dynamic>
      ? value
      : value is Map
      ? Map<String, dynamic>.from(value)
      : null;
  final sourceValue = mapValue?[key] ?? value;
  if (sourceValue is Uint8List) {
    return sourceValue;
  }
  if (sourceValue is List<int>) {
    return Uint8List.fromList(sourceValue);
  }
  if (sourceValue is String && sourceValue.trim().isNotEmpty) {
    try {
      return base64Decode(sourceValue);
    } catch (_) {
      return null;
    }
  }
  return null;
}

String _encodePhotoBytesBase64(Uint8List bytes) => base64Encode(bytes);
