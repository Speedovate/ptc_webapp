import 'package:flutter/material.dart';
import 'package:webapp/utils/functions.dart';

import 'package:webapp/constants/app_colors.dart';

class AppSnackbar {
  static const _errorColor = AppColors.danger;
  static const _successColor = Color(0xFF2EAD62);

  static void showError(BuildContext context, String message) {
    _show(context, normalizeUserErrorText(message), _errorColor);
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
