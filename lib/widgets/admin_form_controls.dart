import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

const adminDropdownDisplayTextStyle = TextStyle(
  color: AppColors.textPrimary,
  fontWeight: FontWeight.w400,
  height: 1.2,
);
const double adminModalFieldMinHeight = 56;
const double adminFilterFieldMinHeight = 52;

Color appFieldInteractiveFillColor(BuildContext context) {
  return Color.alphaBlend(
    Theme.of(context).hoverColor,
    AppColors.primarySurface,
  );
}

class AdminDropdownFormField<T> extends StatefulWidget {
  const AdminDropdownFormField({
    super.key,
    this.initialValue,
    this.focusNode,
    this.iconEnabledColor,
    this.style,
    this.decoration,
    this.items,
    this.onChanged,
    this.isExpanded = false,
    this.disabledTapMessage,
  });

  final T? initialValue;
  final FocusNode? focusNode;
  final Color? iconEnabledColor;
  final TextStyle? style;
  final InputDecoration? decoration;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final String? disabledTapMessage;

  @override
  State<AdminDropdownFormField<T>> createState() =>
      _AdminDropdownFormFieldState<T>();
}

class _AdminDropdownFormFieldState<T> extends State<AdminDropdownFormField<T>> {
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.canRequestFocus = false;
  }

  @override
  void dispose() {
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decoration = widget.decoration ?? const InputDecoration();
    final neutralBorder = decoration.enabledBorder ?? decoration.border;
    final activeFillColor = appFieldInteractiveFillColor(context);
    final contentPadding = switch (decoration.contentPadding) {
      EdgeInsets edgeInsets => EdgeInsets.fromLTRB(
        edgeInsets.left,
        14,
        edgeInsets.right,
        14,
      ),
      EdgeInsetsDirectional edgeInsets => EdgeInsetsDirectional.fromSTEB(
        edgeInsets.start,
        14,
        edgeInsets.end,
        14,
      ),
      _ => const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    };
    final hasItems = widget.items?.isNotEmpty == true;
    final isDisabled = widget.onChanged == null || !hasItems;
    final hintText = decoration.hintText?.trim();
    final hintStyle =
        decoration.hintStyle ??
        TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w400,
        );
    final hintWidget = hintText?.isNotEmpty == true
        ? Text(hintText!, overflow: TextOverflow.ellipsis, style: hintStyle)
        : null;
    final disabledTapMessage = _disabledTapMessage(decoration, hasItems);
    final dropdown = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      descendantsAreFocusable: false,
      child: DropdownButtonFormField<T>(
        initialValue: widget.initialValue,
        focusNode: _focusNode,
        autofocus: false,
        isDense: true,
        iconEnabledColor: widget.iconEnabledColor,
        style: widget.style,
        decoration: decoration.copyWith(
          fillColor: _isHovered || _isPressed
              ? activeFillColor
              : (decoration.fillColor ?? AppColors.primarySurface),
          contentPadding: contentPadding,
          focusedBorder: neutralBorder,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        hint: hintWidget,
        disabledHint: hintWidget,
        items: widget.items,
        isExpanded: widget.isExpanded,
        onChanged: isDisabled
            ? null
            : (value) {
                widget.onChanged?.call(value);
                _focusNode.unfocus();
              },
      ),
    );

    final interactiveDropdown = MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: Listener(
        onPointerDown: (_) {
          if (!isDisabled) {
            setState(() => _isPressed = true);
          }
        },
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
        child: dropdown,
      ),
    );

    if (!isDisabled || disabledTapMessage == null) {
      return interactiveDropdown;
    }

    return Stack(
      children: [
        interactiveDropdown,
        Positioned.fill(
          child: MouseRegion(
            cursor: SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => AppSnackbar.showError(context, disabledTapMessage),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }

  String? _disabledTapMessage(InputDecoration decoration, bool hasItems) {
    final explicitMessage = widget.disabledTapMessage?.trim();
    if (explicitMessage?.isNotEmpty == true) {
      return explicitMessage;
    }
    if (hasItems) {
      return null;
    }
    final label = decoration.labelText?.trim();
    if (label?.isNotEmpty == true) {
      return 'No available ${label!.toLowerCase()} options.';
    }
    return 'No options available.';
  }
}

InputDecoration adminFormInputDecoration(
  String label, {
  String? hintText,
  String? helperText,
  double radius = 16,
  double minHeight = adminModalFieldMinHeight,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    helperText: helperText,
    constraints: BoxConstraints(minHeight: minHeight),
    labelStyle: TextStyle(
      color: AppColors.primaryColor.withValues(alpha: 0.72),
      fontWeight: FontWeight.w400,
    ),
    floatingLabelStyle: const TextStyle(
      color: AppColors.primaryColor,
      fontWeight: FontWeight.w500,
    ),
    hintStyle: TextStyle(
      color: AppColors.primaryColor.withValues(alpha: 0.72),
      fontWeight: FontWeight.w400,
    ),
    helperStyle: TextStyle(
      color: AppColors.primaryColor.withValues(alpha: 0.72),
      fontWeight: FontWeight.w400,
      fontSize: 12,
    ),
    prefixIconColor: AppColors.primaryColor,
    suffixIconColor: AppColors.primaryColor,
    filled: true,
    fillColor: AppColors.primarySurface,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: const BorderSide(color: AppColors.primaryBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: const BorderSide(color: AppColors.primaryBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: const BorderSide(color: AppColors.primaryColor),
    ),
  );
}

InputDecoration adminPlainDropdownDecoration(
  String hintText, {
  double radius = 16,
}) {
  return adminFormInputDecoration(
    '',
    hintText: hintText,
    radius: radius,
  ).copyWith(
    labelText: null,
    floatingLabelBehavior: FloatingLabelBehavior.never,
  );
}
