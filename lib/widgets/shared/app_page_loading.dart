import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';

class AppPageLoading extends StatelessWidget {
  const AppPageLoading({
    super.key,
    this.message = 'Loading ...',
    this.padding = const EdgeInsets.all(24),
    this.compact = false,
  });

  final String message;
  final EdgeInsets padding;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final indicatorSize = compact ? 28.0 : 36.0;
    final horizontalPadding = compact ? 20.0 : 28.0;
    final verticalPadding = compact ? 12.0 : 16.0;
    final cardRadius = compact ? 18.0 : 22.0;
    final maxWidth = compact ? 260.0 : 320.0;
    final minHeight = compact ? 72.0 : 92.0;

    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            minWidth: compact ? 0 : 220,
            minHeight: minHeight,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(cardRadius),
              border: Border.all(color: AppColors.primaryBorder),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                verticalPadding,
                horizontalPadding,
                verticalPadding,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: indicatorSize,
                    height: indicatorSize,
                    child: const CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primaryColor,
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 12 : 14),
                  Flexible(
                    child: Text(
                      message,
                      textAlign: TextAlign.left,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 15 : 16,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
