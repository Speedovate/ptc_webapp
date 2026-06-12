import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_icon_action_button.dart';
import 'package:webapp/widgets/shared/admin_shell_layout_scope.dart';

typedef AdminToolbarFilterBuilder =
    Widget Function(BuildContext context, bool iconOnly);

class AdminListToolbar extends StatelessWidget {
  const AdminListToolbar({
    super.key,
    required this.controlHeight,
    required this.surfaceRadius,
    required this.search,
    required this.filtersBuilder,
    required this.onNewPressed,
    this.buttonLabel = 'New',
    this.buttonIcon = Icons.add_rounded,
  });

  final double controlHeight;
  final double surfaceRadius;
  final Widget search;
  final AdminToolbarFilterBuilder filtersBuilder;
  final VoidCallback onNewPressed;
  final String buttonLabel;
  final IconData buttonIcon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final iconOnly = availableWidth < 520;
        final compactGap = availableWidth < 360
            ? 6.0
            : availableWidth < 420
            ? 8.0
            : 12.0;
        final searchFlex = availableWidth >= 1000 ? 4 : 1;
        final iconOnlySquareSize = controlHeight - 4;
        final buttonWidth = iconOnly
            ? iconOnlySquareSize
            : (availableWidth >= 1000 ? 108.0 : 96.0);
        final filterWidth = iconOnly
            ? iconOnlySquareSize
            : (availableWidth >= 1000 ? 132.0 : 116.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: searchFlex, child: search),
            SizedBox(width: compactGap),
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: filterWidth,
                maxWidth: filterWidth,
              ),
              child: filtersBuilder(context, iconOnly),
            ),
            SizedBox(width: compactGap),
            SizedBox(
              width: buttonWidth,
              child: AdminListNewButton(
                controlHeight: controlHeight,
                surfaceRadius: surfaceRadius,
                iconOnly: iconOnly,
                onTap: onNewPressed,
                label: buttonLabel,
                icon: buttonIcon,
              ),
            ),
          ],
        );
      },
    );
  }
}

class AdminListSearchField extends StatefulWidget {
  const AdminListSearchField({
    super.key,
    required this.controlHeight,
    required this.surfaceRadius,
    required this.onChanged,
    this.initialValue = '',
  });

  final double controlHeight;
  final double surfaceRadius;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<AdminListSearchField> createState() => _AdminListSearchFieldState();
}

class _AdminListSearchFieldState extends State<AdminListSearchField> {
  late final TextEditingController _controller;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant AdminListSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initialValue,
        selection: TextSelection.collapsed(offset: widget.initialValue.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeFillColor = appFieldInteractiveFillColor(context);
    return SizedBox(
      height: widget.controlHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() {
            _isHovered = false;
            _isPressed = false;
          }),
          child: Listener(
            onPointerDown: (_) => setState(() => _isPressed = true),
            onPointerUp: (_) {
              if (_isPressed) {
                setState(() => _isPressed = false);
              }
            },
            onPointerCancel: (_) {
              if (_isPressed) {
                setState(() => _isPressed = false);
              }
            },
            child: TextField(
              controller: _controller,
              onChanged: widget.onChanged,
              style: adminFieldValueTextStyle,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search',
                hintStyle: adminFieldHintTextStyle.copyWith(
                  color: AppColors.primaryColor.withValues(alpha: 0.72),
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.primaryColor,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 46,
                  minHeight: 46,
                ),
                filled: true,
                fillColor: _isHovered || _isPressed
                    ? activeFillColor
                    : AppColors.primarySurface,
                contentPadding: const EdgeInsets.only(
                  top: 18,
                  right: 14,
                  bottom: 18,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(widget.surfaceRadius),
                  borderSide: const BorderSide(color: AppColors.primaryBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(widget.surfaceRadius),
                  borderSide: const BorderSide(color: AppColors.primaryBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(widget.surfaceRadius),
                  borderSide: const BorderSide(color: AppColors.primaryColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminListNewButton extends StatelessWidget {
  const AdminListNewButton({
    super.key,
    required this.controlHeight,
    required this.surfaceRadius,
    required this.iconOnly,
    required this.onTap,
    this.label = 'New',
    this.icon = Icons.add_rounded,
  });

  final double controlHeight;
  final double surfaceRadius;
  final bool iconOnly;
  final VoidCallback onTap;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: controlHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 16),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(surfaceRadius),
            ),
          ),
          child: iconOnly
              ? Icon(icon)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 10),
                    Icon(icon, size: 18),
                  ],
                ),
        ),
      ),
    );
  }
}

class AdminListFiltersButton extends StatefulWidget {
  const AdminListFiltersButton({
    super.key,
    required this.controlHeight,
    required this.surfaceRadius,
    required this.iconOnly,
    required this.menuChildren,
    this.alignmentOffset = const Offset(0, 10),
    this.menuPadding = const EdgeInsets.all(8),
    this.topGap = 4,
    this.rightGap = 44,
  });

  final double controlHeight;
  final double surfaceRadius;
  final bool iconOnly;
  final List<Widget> menuChildren;
  final Offset alignmentOffset;
  final EdgeInsetsGeometry menuPadding;
  final double topGap;
  final double rightGap;

  @override
  State<AdminListFiltersButton> createState() => _AdminListFiltersButtonState();
}

class _AdminListFiltersButtonState extends State<AdminListFiltersButton> {
  final OverlayPortalController _controller = OverlayPortalController();
  final GlobalKey _buttonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final layoutScope = AdminShellLayoutScope.maybeOf(context);
    final effectiveRightGap = layoutScope?.filtersRightGap ?? widget.rightGap;
    final popupContentMaxWidth = (screenWidth - effectiveRightGap - 24).clamp(
      0.0,
      screenWidth,
    );
    final buttonBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final buttonTop = buttonBox?.localToGlobal(Offset.zero).dy ?? 0;
    final buttonHeight = buttonBox?.size.height ?? widget.controlHeight;
    final popupTop =
        buttonTop + buttonHeight + widget.alignmentOffset.dy + widget.topGap;

    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  _controller.hide();
                },
              ),
            ),
            Positioned(
              top: popupTop,
              right: effectiveRightGap,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: popupContentMaxWidth),
                child: Material(
                  color: Colors.white,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.white,
                  borderRadius: BorderRadius.circular(widget.surfaceRadius),
                  clipBehavior: Clip.antiAlias,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(widget.surfaceRadius),
                      border: Border.all(color: AppColors.primaryBorder),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A0F172A),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                      },
                      child: Padding(
                        padding: widget.menuPadding,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: widget.menuChildren,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: SizedBox(
        key: _buttonKey,
        height: widget.controlHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: FilledButton(
            onPressed: () {
              if (_controller.isShowing) {
                _controller.hide();
              } else {
                _controller.show();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: widget.iconOnly ? 0 : 14,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.surfaceRadius),
              ),
            ),
            child: widget.iconOnly
                ? const Icon(Icons.filter_alt_rounded)
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Filters',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(width: 12),
                      Icon(Icons.filter_alt_rounded),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class AdminListFixedSlot extends StatelessWidget {
  const AdminListFixedSlot({
    super.key,
    required this.width,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  final double width;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(alignment: alignment, child: child),
    );
  }
}

class AdminListHeaderBar extends StatelessWidget {
  const AdminListHeaderBar({
    super.key,
    required this.child,
    required this.minHeight,
    required this.borderRadius,
    this.horizontalPadding = 20,
    this.verticalPadding = 14,
  });

  final Widget child;
  final double minHeight;
  final double borderRadius;
  final double horizontalPadding;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: child,
    );
  }
}

class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    );
  }
}

class AdminListHeaderCell extends StatelessWidget {
  const AdminListHeaderCell({
    super.key,
    required this.label,
    this.trailingPadding = 20,
    this.alignment = Alignment.centerLeft,
    this.textAlign = TextAlign.left,
  });

  final String label;
  final double trailingPadding;
  final Alignment alignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: trailingPadding),
      child: Align(
        alignment: alignment,
        child: Text(
          label,
          textAlign: textAlign,
          style: TextStyle(
            color: AppColors.primaryColor.withValues(alpha: 0.72),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class AdminListBodyCell extends StatelessWidget {
  const AdminListBodyCell({
    super.key,
    required this.child,
    this.trailingPadding = 20,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final double trailingPadding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: trailingPadding),
      child: Align(alignment: alignment, child: child),
    );
  }
}

class AdminListResponsiveField extends StatelessWidget {
  const AdminListResponsiveField({
    super.key,
    required this.title,
    required this.value,
    required this.width,
    required this.centered,
    this.isTitle = false,
    this.valueColor,
  });

  final String title;
  final String value;
  final double width;
  final bool centered;
  final bool isTitle;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width.isFinite ? (width < 0 ? 0 : width) : double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: TextAlign.left,
            style: TextStyle(
              color: AppColors.primaryColor.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            softWrap: true,
            textAlign: centered ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontWeight: isTitle ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminListItemCard extends StatelessWidget {
  const AdminListItemCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: child,
    );
  }
}

class AdminListStateText extends StatelessWidget {
  const AdminListStateText({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: TextStyle(
        color: AppColors.primaryColor.withValues(alpha: 0.72),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class AdminListActionButton extends StatelessWidget {
  const AdminListActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.backgroundColor,
    this.isDanger = false,
    this.size = 40,
    this.iconSize = 18,
    this.borderRadius = 12,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final bool isDanger;
  final double size;
  final double iconSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return AdminIconActionButton(
      icon: icon,
      onTap: onTap,
      backgroundColor:
          backgroundColor ??
          (isDanger ? AppColors.dangerStrong : AppColors.primaryColor),
      size: size,
      iconSize: iconSize,
      borderRadius: borderRadius,
    );
  }
}

class AdminListTrailingActionsLane extends StatelessWidget {
  const AdminListTrailingActionsLane({
    super.key,
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Align(
        alignment: Alignment.centerRight,
        child: AdminListFixedSlot(
          width: width,
          alignment: Alignment.centerRight,
          child: child,
        ),
      ),
    );
  }
}

class AdminMetaPillPalette {
  const AdminMetaPillPalette({
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
}

AdminMetaPillPalette adminMetaPillPalette(
  String label, {
  bool isFilled = false,
}) {
  final normalizedLabel = label.trim().toLowerCase();
  final isSuccessVariant =
      isFilled || normalizedLabel == 'delivered' || normalizedLabel == 'active';
  final isDangerVariant =
      normalizedLabel == 'cancelled' ||
      normalizedLabel == 'canceled' ||
      normalizedLabel == 'inactive';

  return AdminMetaPillPalette(
    backgroundColor: isSuccessVariant
        ? const Color(0xFFE9F8EF)
        : isDangerVariant
        ? AppColors.dangerSurfaceAlt
        : AppColors.primarySurface,
    borderColor: isSuccessVariant
        ? const Color(0xFFB9E7C8)
        : isDangerVariant
        ? AppColors.dangerBorderAlt
        : AppColors.primaryBorder,
    textColor: isSuccessVariant
        ? const Color(0xFF2EAD62)
        : isDangerVariant
        ? AppColors.danger
        : AppColors.primaryColor,
  );
}

Widget adminMetaPill(String label, {bool isFilled = false}) {
  final palette = adminMetaPillPalette(label, isFilled: isFilled);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: palette.backgroundColor,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: palette.borderColor),
    ),
    child: Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: palette.textColor,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class AdminListMeasurements {
  static double resolvedColumnWidth(
    double measuredWidth, {
    double trailingPadding = 20,
    double extraWidthAllowance = 16,
  }) {
    return measuredWidth + trailingPadding + extraWidthAllowance;
  }

  static double maxTextWidth(
    BuildContext context,
    TextScaler textScaler,
    String headerText,
    TextStyle headerStyle,
    String valueText,
    TextStyle valueStyle,
  ) {
    return maxValue(
      measureTextWidth(context, textScaler, headerText, headerStyle),
      measureTextWidth(context, textScaler, valueText, valueStyle),
    );
  }

  static double measureTextWidth(
    BuildContext context,
    TextScaler textScaler,
    String text,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return painter.width.ceilToDouble();
  }

  static double resolvedResponsiveFieldWidth(
    BuildContext context,
    TextScaler textScaler,
    double maxWidth,
    String label,
    String value, {
    double horizontalPadding = 28,
    double minWidth = 96,
    TextStyle? labelStyle,
    TextStyle valueStyle = const TextStyle(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w600,
    ),
  }) {
    final resolvedLabelStyle =
        labelStyle ??
        TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w700,
        );
    final labelWidth = measureTextWidth(
      context,
      textScaler,
      label,
      resolvedLabelStyle,
    );
    final valueWidth = measureTextWidth(context, textScaler, value, valueStyle);
    final resolvedWidth =
        (labelWidth > valueWidth ? labelWidth : valueWidth) + horizontalPadding;
    return resolvedWidth.clamp(minWidth, maxWidth);
  }

  static double maxValue(double a, double b) => a > b ? a : b;

  static String longerText(String current, String candidate) {
    return candidate.length > current.length ? candidate : current;
  }
}
