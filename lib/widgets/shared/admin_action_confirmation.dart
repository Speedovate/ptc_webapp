import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';

Future<bool> showAdminActionConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool isDanger = false,
  Future<bool> Function()? onConfirmAsync,
  String? modalKey,
}) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    modalKey:
        modalKey ??
        'admin-action-confirmation:${title.trim()}:${confirmLabel.trim()}:${isDanger ? "danger" : "default"}',
    builder: (dialogContext) => _AdminActionConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      isDanger: isDanger,
      onConfirmAsync: onConfirmAsync,
    ),
  );

  return confirmed ?? false;
}

class _AdminActionConfirmationDialog extends StatefulWidget {
  const _AdminActionConfirmationDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.isDanger,
    required this.onConfirmAsync,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool isDanger;
  final Future<bool> Function()? onConfirmAsync;

  @override
  State<_AdminActionConfirmationDialog> createState() =>
      _AdminActionConfirmationDialogState();
}

class _AdminActionConfirmationDialogState
    extends State<_AdminActionConfirmationDialog> {
  bool _isSubmitting = false;

  Future<void> _handleConfirm() async {
    if (_isSubmitting) {
      return;
    }
    final onConfirmAsync = widget.onConfirmAsync;
    if (onConfirmAsync == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isSubmitting = true;
    });
    final shouldClose = await onConfirmAsync();
    if (!mounted) {
      return;
    }
    if (shouldClose) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Text(widget.message),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _handleConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: widget.isDanger
                ? AppColors.danger
                : AppColors.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
