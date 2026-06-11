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
        child: Column(children: children),
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
    this.bottomPadding = 6,
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

class AdminModalTextField extends StatefulWidget {
  const AdminModalTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.obscureText = false,
    this.suffixIcon,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.bottomPadding = 6,
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
  State<AdminModalTextField> createState() => _AdminModalTextFieldState();
}

class _AdminModalTextFieldState extends State<AdminModalTextField> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final activeFillColor = appFieldInteractiveFillColor(context);
    return AdminModalFieldSlot(
      bottomPadding: widget.bottomPadding,
      child: MouseRegion(
        cursor: widget.readOnly && widget.onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.text,
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
          child: TextFormField(
            controller: widget.controller,
            obscureText: widget.obscureText,
            readOnly: widget.readOnly,
            textCapitalization: widget.textCapitalization,
            inputFormatters: widget.inputFormatters,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            keyboardType: widget.keyboardType,
            onTap: widget.onTap,
            decoration: adminFormInputDecoration(
              widget.label,
              hintText: widget.hintText,
            ).copyWith(
              suffixIcon: widget.suffixIcon,
              fillColor: _isPressed || _isHovered
                  ? activeFillColor
                  : AppColors.primarySurface,
            ),
          ),
        ),
      ),
    );
  }
}

class AdminModalActionField extends StatefulWidget {
  const AdminModalActionField({
    super.key,
    required this.label,
    required this.onTap,
    this.valueText,
    this.hintText,
    this.suffixIcon,
    this.bottomPadding = 6,
  });

  final String label;
  final VoidCallback onTap;
  final String? valueText;
  final String? hintText;
  final Widget? suffixIcon;
  final double bottomPadding;

  @override
  State<AdminModalActionField> createState() => _AdminModalActionFieldState();
}

class _AdminModalActionFieldState extends State<AdminModalActionField> {
  late final TextEditingController _controller;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.valueText ?? '');
  }

  @override
  void didUpdateWidget(covariant AdminModalActionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextValue = widget.valueText ?? '';
    if (_controller.text != nextValue) {
      _controller.value = _controller.value.copyWith(
        text: nextValue,
        selection: TextSelection.collapsed(offset: nextValue.length),
        composing: TextRange.empty,
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
    final hoveredFillColor = appFieldInteractiveFillColor(context);
    final decoration =
        adminFormInputDecoration(
          widget.label,
          hintText: widget.hintText,
        ).copyWith(
          suffixIcon: widget.suffixIcon,
          fillColor: _isPressed || _isHovered
              ? hoveredFillColor
              : AppColors.primarySurface,
        );

    return AdminModalFieldSlot(
      bottomPadding: widget.bottomPadding,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() {
          _isHovered = false;
          _isPressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapCancel: () => setState(() => _isPressed = false),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTap: widget.onTap,
          child: IgnorePointer(
            child: TextFormField(
              controller: _controller,
              readOnly: true,
              showCursor: false,
              enableInteractiveSelection: false,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
              decoration: decoration,
            ),
          ),
        ),
      ),
    );
  }
}

class AdminModalValueTextField extends StatefulWidget {
  const AdminModalValueTextField({
    super.key,
    required this.label,
    this.initialValue,
    this.hintText,
    this.onChanged,
    this.bottomPadding = 6,
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
  State<AdminModalValueTextField> createState() =>
      _AdminModalValueTextFieldState();
}

class _AdminModalValueTextFieldState extends State<AdminModalValueTextField> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final activeFillColor = appFieldInteractiveFillColor(context);
    return AdminModalFieldSlot(
      bottomPadding: widget.bottomPadding,
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
          child: TextFormField(
            initialValue: widget.initialValue,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            keyboardType: widget.keyboardType,
            decoration: adminFormInputDecoration(
              widget.label,
              hintText: widget.hintText,
            ).copyWith(
              fillColor: _isPressed || _isHovered
                  ? activeFillColor
                  : AppColors.primarySurface,
            ),
            onChanged: widget.onChanged,
          ),
        ),
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
    this.bottomPadding = 6,
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
