import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/utils/functions.dart';
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
    this.focusNode,
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
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
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
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AdminModalTextField> createState() => _AdminModalTextFieldState();
}

class _AdminModalTextFieldState extends State<AdminModalTextField> {
  bool _isHovered = false;
  bool _isPressed = false;

  bool get _isSingleLineField =>
      (widget.minLines ?? 1) == 1 && (widget.maxLines ?? 1) == 1;

  TextInputAction? get _resolvedTextInputAction {
    if (widget.textInputAction != null) {
      return widget.textInputAction;
    }
    if (!_isSingleLineField || widget.readOnly) {
      return null;
    }
    return TextInputAction.next;
  }

  bool get _isNameField =>
      RegExp(r'\bname\b', caseSensitive: false).hasMatch(widget.label);

  bool get _isPhoneField => RegExp(
    r'phone|mobile|contact\s+number',
    caseSensitive: false,
  ).hasMatch(widget.label);

  List<TextInputFormatter>? get _resolvedInputFormatters {
    final explicitFormatters = widget.inputFormatters;
    if (explicitFormatters != null) {
      return explicitFormatters;
    }
    if (_isPhoneField) {
      return const [PhilippinesPhoneInputFormatter()];
    }
    return _isNameField ? const [NameCaseTextInputFormatter()] : null;
  }

  void _handleSubmitted(String value) {
    if (widget.onSubmitted case final onSubmitted?) {
      onSubmitted(value);
      return;
    }
    if (!_isSingleLineField || widget.readOnly) {
      return;
    }
    final focusScope = FocusScope.of(context);
    if (!focusScope.nextFocus()) {
      focusScope.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    const activeFillColor = Colors.white;
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
            focusNode: widget.focusNode,
            obscureText: widget.obscureText,
            readOnly: widget.readOnly,
            keyboardType: _isPhoneField
                ? TextInputType.phone
                : widget.keyboardType,
            textCapitalization: _isNameField
                ? TextCapitalization.words
                : widget.textCapitalization,
            inputFormatters: _resolvedInputFormatters,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            onTap: widget.onTap,
            textInputAction: _resolvedTextInputAction,
            onFieldSubmitted: _handleSubmitted,
            style: adminFieldValueTextStyle,
            decoration:
                adminFormInputDecoration(
                  widget.label,
                  hintText: adminEnterPlaceholder(
                    widget.label,
                    override: widget.hintText,
                  ),
                ).copyWith(
                  suffixIcon: widget.suffixIcon,
                  fillColor: _isPressed || _isHovered
                      ? activeFillColor
                      : Colors.white,
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
    this.focusNode,
    this.activateOnFocus = false,
    this.onSubmitted,
    this.bottomPadding = 6,
  });

  final String label;
  final VoidCallback onTap;
  final String? valueText;
  final String? hintText;
  final Widget? suffixIcon;
  final FocusNode? focusNode;
  final bool activateOnFocus;
  final VoidCallback? onSubmitted;
  final double bottomPadding;

  @override
  State<AdminModalActionField> createState() => _AdminModalActionFieldState();
}

class _AdminModalActionFieldState extends State<AdminModalActionField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
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
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleActivate() {
    if (widget.onSubmitted case final onSubmitted?) {
      onSubmitted();
      return;
    }
    widget.onTap();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    const hoveredFillColor = Colors.white;
    final decoration =
        adminFormInputDecoration(
          widget.label,
          hintText: adminSelectPlaceholder(
            widget.label,
            override: widget.hintText,
          ),
        ).copyWith(
          suffixIcon: widget.suffixIcon,
          fillColor: _isPressed || _isHovered ? hoveredFillColor : Colors.white,
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
        child: FocusableActionDetector(
          focusNode: _focusNode,
          onFocusChange: (_) => _handleFocusChanged(),
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (intent) {
                _handleActivate();
                return null;
              },
            ),
          },
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
                style: adminFieldValueTextStyle,
                decoration: decoration,
              ),
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
    this.textInputAction,
    this.onSubmitted,
    this.bottomPadding = 6,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String label;
  final String? initialValue;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
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

  bool get _isSingleLineField =>
      (widget.minLines ?? 1) == 1 && (widget.maxLines ?? 1) == 1;

  TextInputAction? get _resolvedTextInputAction {
    if (widget.textInputAction != null) {
      return widget.textInputAction;
    }
    if (!_isSingleLineField) {
      return null;
    }
    return TextInputAction.next;
  }

  void _handleSubmitted(String value) {
    if (widget.onSubmitted case final onSubmitted?) {
      onSubmitted(value);
      return;
    }
    if (!_isSingleLineField) {
      return;
    }
    final focusScope = FocusScope.of(context);
    if (!focusScope.nextFocus()) {
      focusScope.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    const activeFillColor = Colors.white;
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
            textInputAction: _resolvedTextInputAction,
            style: adminFieldValueTextStyle,
            onFieldSubmitted: _handleSubmitted,
            decoration:
                adminFormInputDecoration(
                  widget.label,
                  hintText: adminEnterPlaceholder(
                    widget.label,
                    override: widget.hintText,
                  ),
                ).copyWith(
                  fillColor: _isPressed || _isHovered
                      ? activeFillColor
                      : Colors.white,
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
    this.hintText,
    this.errorText,
    this.focusNode,
    this.items,
    this.onChanged,
    this.selectedDisplayText,
    this.onSelectionCompleted,
    this.bottomPadding = 6,
    this.iconEnabledColor,
    this.style,
    this.isExpanded = false,
    this.disabledTapMessage,
  });

  final String label;
  final T? initialValue;
  final String? hintText;
  final String? errorText;
  final FocusNode? focusNode;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final String? selectedDisplayText;
  final VoidCallback? onSelectionCompleted;
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
        focusNode: focusNode,
        iconEnabledColor: iconEnabledColor ?? AppColors.primaryColor,
        style: style ?? adminDropdownDisplayTextStyle,
        isExpanded: isExpanded,
        decoration:
            adminPlainDropdownDecoration(
              adminSelectPlaceholder(label, override: hintText),
            ).copyWith(
              errorText: errorText,
              constraints: const BoxConstraints(
                minHeight: adminModalFieldMinHeight,
              ),
            ),
        items: items,
        selectedDisplayText: selectedDisplayText,
        onChanged: (value) {
          onChanged?.call(value);
          onSelectionCompleted?.call();
        },
        disabledTapMessage: disabledTapMessage,
      ),
    );
  }
}
