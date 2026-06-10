import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/widgets/admin_form_controls.dart';

class AdminModalFormBody extends StatelessWidget {
  const AdminModalFormBody({
    super.key,
    required this.children,
    this.readOnly = false,
    this.horizontalPadding = 24,
    this.topToggleSpacing = 8,
    this.readOnlyOpacity = 0.9,
  });

  final List<Widget> children;
  final bool readOnly;
  final double horizontalPadding;
  final double topToggleSpacing;
  final double readOnlyOpacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: readOnly,
      child: Opacity(
        opacity: readOnly ? readOnlyOpacity : 1,
        child: Column(
          children: children,
        ),
      ),
    );
  }
}

class AdminModalFieldsSection extends StatelessWidget {
  const AdminModalFieldsSection({
    super.key,
    required this.children,
    this.horizontalPadding = 24,
  });

  final List<Widget> children;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class AdminModalFieldSlot extends StatelessWidget {
  const AdminModalFieldSlot({
    super.key,
    required this.child,
    this.bottomPadding = 10,
  });

  final Widget child;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: child,
    );
  }
}

class AdminModalTextField extends StatelessWidget {
  const AdminModalTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.obscureText = false,
    this.suffixIcon,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.bottomPadding = 10,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
    this.readOnly = false,
    this.onTap,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final double bottomPadding;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AdminModalFieldSlot(
      bottomPadding: bottomPadding,
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        readOnly: readOnly,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onTap: onTap,
        decoration: adminFormInputDecoration(
          label,
          hintText: hintText,
        ).copyWith(
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}

class AdminModalActionField extends StatelessWidget {
  const AdminModalActionField({
    super.key,
    required this.label,
    required this.onTap,
    this.valueText,
    this.hintText,
    this.suffixIcon,
    this.bottomPadding = 10,
  });

  final String label;
  final VoidCallback onTap;
  final String? valueText;
  final String? hintText;
  final Widget? suffixIcon;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final trimmedValue = valueText?.trim() ?? '';
    final hasValue = trimmedValue.isNotEmpty;
    final decoration = adminFormInputDecoration(
      label,
      hintText: hintText,
    ).copyWith(suffixIcon: suffixIcon);

    final borderRadius =
        (decoration.enabledBorder is OutlineInputBorder)
            ? (decoration.enabledBorder as OutlineInputBorder).borderRadius
            : BorderRadius.circular(16);

    return AdminModalFieldSlot(
      bottomPadding: bottomPadding,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: InputDecorator(
            isEmpty: !hasValue,
            isFocused: false,
            decoration: decoration,
            child: Text(
              hasValue ? trimmedValue : (hintText?.trim().isNotEmpty == true ? hintText!.trim() : ''),
              style: hasValue
                  ? const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    )
                  : TextStyle(
                      color: AppColors.primaryColor.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminModalValueTextField extends StatelessWidget {
  const AdminModalValueTextField({
    super.key,
    required this.label,
    this.initialValue,
    this.hintText,
    this.onChanged,
    this.bottomPadding = 10,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String label;
  final String? initialValue;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final double bottomPadding;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return AdminModalFieldSlot(
      bottomPadding: bottomPadding,
      child: TextFormField(
        initialValue: initialValue,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: adminFormInputDecoration(
          label,
          hintText: hintText,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class AdminModalDropdownField<T> extends StatelessWidget {
  const AdminModalDropdownField({
    super.key,
    required this.label,
    this.initialValue,
    this.items,
    this.onChanged,
    this.bottomPadding = 10,
    this.iconEnabledColor,
    this.style,
    this.isExpanded = false,
    this.disabledTapMessage,
  });

  final String label;
  final T? initialValue;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final double bottomPadding;
  final Color? iconEnabledColor;
  final TextStyle? style;
  final bool isExpanded;
  final String? disabledTapMessage;

  @override
  Widget build(BuildContext context) {
    return AdminModalFieldSlot(
      bottomPadding: bottomPadding,
      child: AdminDropdownFormField<T>(
        initialValue: initialValue,
        iconEnabledColor: iconEnabledColor ?? AppColors.primaryColor,
        style: style ?? adminDropdownDisplayTextStyle,
        isExpanded: isExpanded,
        decoration: adminFormInputDecoration(label),
        items: items,
        onChanged: onChanged,
        disabledTapMessage: disabledTapMessage,
      ),
    );
  }
}
