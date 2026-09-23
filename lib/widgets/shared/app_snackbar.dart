import 'dart:async';
import 'package:webapp/services/sync_error_log_service.dart';
import 'package:flutter/material.dart';
import 'package:webapp/utils/functions.dart';

import 'package:webapp/constants/app_colors.dart';

class AppSnackbar {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static void showSupportNotification() {
    final messenger = messengerKey.currentState;
    if (messenger == null) {
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('New support message. Open Support to read it.'),
        duration: Duration(seconds: 5),
      ),
    );
  }

  static const _errorColor = AppColors.danger;
  static const _successColor = Color(0xFF2EAD62);

  static void showError(BuildContext context, String message) {
    unawaited(
      SyncErrorLogService.instance.report(
        message,
        StackTrace.current,
        source: 'app_snackbar.dart',
        operation: 'display error',
        kind: 'displayed_error',
      ),
    );

    final normalized = normalizeUserErrorText(message, fallback: '').trim();
    final resolved = normalized.isNotEmpty
        ? normalized
        : message.toString().trim().isNotEmpty
        ? message.toString().trim()
        : 'Error';
    _show(context, resolved, _errorColor);
  }

  static void showSuccess(BuildContext context, String message) {
    _show(context, message, _successColor);
  }

  static void _show(BuildContext context, String message, Color color) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(backgroundColor: color, content: Text(message)),
    );
  }
}
