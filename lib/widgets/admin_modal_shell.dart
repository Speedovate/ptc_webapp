import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';

class AdminModalShell extends StatelessWidget {
  static const BorderRadius _dialogBorderRadius = BorderRadius.all(
    Radius.circular(28),
  );

  const AdminModalShell({
    super.key,
    required this.title,
    required this.child,
    this.maxWidth = 560,
    this.maxHeightFactor = 0.82,
    this.actions,
    this.contentInset = const EdgeInsets.fromLTRB(0, 16, 0, 24),
    this.actionsInset = const EdgeInsets.fromLTRB(24, 0, 24, 24),
    this.isLoading = false,
    this.loadingMessage = 'Loading, please wait ...',
    this.loadingPadding = const EdgeInsets.all(24),
    this.loadingOpacity = 0.72,
    this.loadingAlignmentY = 0,
  });

  final String title;
  final Widget child;
  final double maxWidth;
  final double maxHeightFactor;
  final List<Widget>? actions;
  final EdgeInsets contentInset;
  final EdgeInsets actionsInset;
  final bool isLoading;
  final String loadingMessage;
  final EdgeInsets loadingPadding;
  final double loadingOpacity;
  final double loadingAlignmentY;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaSize = MediaQuery.sizeOf(context);
    final hasActions = actions != null && actions!.isNotEmpty;
    final dialogMaxHeight = mediaSize.height * maxHeightFactor;
    final horizontalInset = 24.0;
    final verticalInset = 24.0;
    final availableWidth = (mediaSize.width - (horizontalInset * 2)).clamp(
      0.0,
      maxWidth,
    );
    final bodyMaxHeight = hasActions
        ? (dialogMaxHeight - 120).clamp(0.0, dialogMaxHeight)
        : (dialogMaxHeight - 56).clamp(0.0, dialogMaxHeight);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: AppColors.primaryColor,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AppColors.primaryColor;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primaryColor;
            }
            return AppColors.primarySurfaceAlt;
          }),
          trackOutlineColor: WidgetStateProperty.resolveWith((states) {
            return AppColors.primaryColor;
          }),
        ),
      ),
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: _dialogBorderRadius),
        clipBehavior: Clip.antiAlias,
        insetPadding: EdgeInsets.symmetric(
          horizontal: horizontalInset,
          vertical: verticalInset,
        ),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: availableWidth,
                maxHeight: mediaSize.height * maxHeightFactor,
              ),
              child: SizedBox(
                width: availableWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      child: Text(title, style: theme.textTheme.titleLarge),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: bodyMaxHeight),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Padding(padding: contentInset, child: child),
                      ),
                    ),
                    if (hasActions)
                      Padding(
                        padding: actionsInset,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 12,
                          runSpacing: 8,
                          children: actions!,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (isLoading)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: loadingOpacity),
                  child: Align(
                    alignment: Alignment(0, loadingAlignmentY),
                    child: AppPageLoading(
                      message: loadingMessage,
                      compact: true,
                      padding: loadingPadding,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AdminModalToggleRow extends StatelessWidget {
  const AdminModalToggleRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.leftInset = 24,
    this.rightInset = 20,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final double leftInset;
  final double rightInset;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: leftInset),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(title, style: labelStyle),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Switch(value: value, onChanged: onChanged),
        ),
        SizedBox(width: rightInset),
      ],
    );
  }
}
