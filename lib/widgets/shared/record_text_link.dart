import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';

class RecordTextLink extends StatelessWidget {
  const RecordTextLink({
    super.key,
    required this.label,
    this.onTap,
    this.style,
  });
  final String label;
  final VoidCallback? onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: onTap == null
          ? style
          : (style ?? const TextStyle()).copyWith(
              color: AppColors.primaryColor,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.primaryColor,
            ),
    );
    return onTap == null ? text : InkWell(onTap: onTap, child: text);
  }
}
