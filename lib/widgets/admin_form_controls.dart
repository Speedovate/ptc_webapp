import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

const adminFieldValueTextStyle = TextStyle(
  color: AppColors.textPrimary,
  fontWeight: FontWeight.w400,
  fontSize: 15,
  height: 1.2,
);
const adminDropdownDisplayTextStyle = adminFieldValueTextStyle;
const adminFieldLabelTextStyle = TextStyle(
  color: AppColors.primaryColor,
  fontWeight: FontWeight.w400,
  fontSize: 15,
  height: 1.2,
);
const adminFieldFloatingLabelTextStyle = TextStyle(
  color: AppColors.primaryColor,
  fontWeight: FontWeight.w500,
  fontSize: 15,
  height: 1.2,
);
const adminFieldHintTextStyle = TextStyle(
  color: AppColors.textSecondary,
  fontWeight: FontWeight.w400,
  fontSize: 15,
  height: 1.2,
);
const adminFieldHelperTextStyle = TextStyle(
  color: AppColors.textSecondary,
  fontWeight: FontWeight.w400,
  fontSize: 12,
  height: 1.35,
);
const double adminModalFieldMinHeight = 56;
const double adminFilterFieldMinHeight = 52;
const double adminFilterClearButtonHeight = 44;

InputDecoration _normalizeCollapsedSelectionDecoration(
  InputDecoration baseDecoration,
) {
  final normalizedHintText = baseDecoration.hintText?.trim().isNotEmpty == true
      ? baseDecoration.hintText
      : baseDecoration.labelText;
  return baseDecoration.copyWith(
    labelText: '',
    floatingLabelBehavior: FloatingLabelBehavior.never,
    hintText: normalizedHintText,
  );
}

// InputDecoration.copyWith cannot clear a non-null errorText, so make a clean
// decoration before supplying the shared, left-aligned dropdown error widget.
InputDecoration _withoutInlineFieldFeedback(InputDecoration decoration) {
  return InputDecoration(
    icon: decoration.icon,
    iconColor: decoration.iconColor,
    label: decoration.label,
    labelText: decoration.labelText,
    labelStyle: decoration.labelStyle,
    floatingLabelStyle: decoration.floatingLabelStyle,
    hint: decoration.hint,
    hintText: decoration.hintText,
    hintStyle: decoration.hintStyle,
    hintTextDirection: decoration.hintTextDirection,
    hintFadeDuration: decoration.hintFadeDuration,
    hintMaxLines: decoration.hintMaxLines,
    maintainHintSize: decoration.maintainHintSize,
    maintainLabelSize: decoration.maintainLabelSize,
    floatingLabelBehavior: decoration.floatingLabelBehavior,
    floatingLabelAlignment: decoration.floatingLabelAlignment,
    isCollapsed: decoration.isCollapsed,
    isDense: decoration.isDense,
    contentPadding: decoration.contentPadding,
    prefixIcon: decoration.prefixIcon,
    prefix: decoration.prefix,
    prefixText: decoration.prefixText,
    prefixIconConstraints: decoration.prefixIconConstraints,
    prefixStyle: decoration.prefixStyle,
    prefixIconColor: decoration.prefixIconColor,
    suffixIcon: decoration.suffixIcon,
    suffix: decoration.suffix,
    suffixText: decoration.suffixText,
    suffixStyle: decoration.suffixStyle,
    suffixIconColor: decoration.suffixIconColor,
    suffixIconConstraints: decoration.suffixIconConstraints,
    counter: decoration.counter,
    counterText: decoration.counterText,
    counterStyle: decoration.counterStyle,
    filled: decoration.filled,
    fillColor: decoration.fillColor,
    focusColor: decoration.focusColor,
    hoverColor: decoration.hoverColor,
    errorBorder: decoration.errorBorder,
    focusedBorder: decoration.focusedBorder,
    focusedErrorBorder: decoration.focusedErrorBorder,
    disabledBorder: decoration.disabledBorder,
    enabledBorder: decoration.enabledBorder,
    border: decoration.border,
    enabled: decoration.enabled,
    semanticCounterText: decoration.semanticCounterText,
    alignLabelWithHint: decoration.alignLabelWithHint,
    constraints: decoration.constraints,
    visualDensity: decoration.visualDensity,
  );
}

InputDecoration _dropdownFeedbackDecoration(
  InputDecoration decoration,
  String? errorText,
) {
  final baseDecoration = _withoutInlineFieldFeedback(decoration);
  if (errorText?.isNotEmpty != true) {
    return baseDecoration;
  }
  return baseDecoration.copyWith(
    error: Transform.translate(
      // Native error placement keeps the compact field-to-error spacing.
      // Shift only its visual label back to the field-card content edge.
      offset: const Offset(-14, 0),
      child: Text(
        errorText!,
        style: const TextStyle(color: AppColors.danger, fontSize: 12),
      ),
    ),
  );
}

Color appFieldInteractiveFillColor(BuildContext context) {
  return Colors.white;
}

Color appDropdownBaseFillColor(BuildContext context) {
  return Colors.white;
}

Color appDropdownInteractiveFillColor(BuildContext context) {
  return Colors.white;
}

String adminEnterPlaceholder(String label, {String? override}) {
  final trimmedOverride = override?.trim();
  if (trimmedOverride != null && trimmedOverride.isNotEmpty) {
    return trimmedOverride;
  }
  return 'Enter $label';
}

String adminSelectPlaceholder(String label, {String? override}) {
  final trimmedOverride = override?.trim();
  if (trimmedOverride != null && trimmedOverride.isNotEmpty) {
    return trimmedOverride;
  }
  return 'Select $label';
}

String adminUploadPlaceholder(String label, {String? override}) {
  final trimmedOverride = override?.trim();
  if (trimmedOverride != null && trimmedOverride.isNotEmpty) {
    return trimmedOverride;
  }
  return 'Upload $label';
}

class AdminDropdownMenuCoordinator {
  static VoidCallback? _activeDismissCallback;

  static void registerActiveDismissCallback(VoidCallback callback) {
    _activeDismissCallback = callback;
  }

  static void unregisterActiveDismissCallback(VoidCallback callback) {
    if (identical(_activeDismissCallback, callback)) {
      _activeDismissCallback = null;
    }
  }

  static bool dismissActiveMenu() {
    final callback = _activeDismissCallback;
    if (callback == null) {
      return false;
    }
    _activeDismissCallback = null;
    callback();
    return true;
  }
}

class AdminDropdownFormField<T> extends StatefulWidget {
  const AdminDropdownFormField({
    super.key,
    this.initialValue,
    this.focusNode,
    this.onFocusChanged,
    this.unfocusOnDismissWithoutSelection = true,
    this.iconEnabledColor,
    this.style,
    this.decoration,
    this.items,
    this.onChanged,
    this.selectedDisplayText,
    this.isExpanded = true,
    this.disabledTapMessage,
    this.onDisabledTap,
  });

  final T? initialValue;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChanged;
  final bool unfocusOnDismissWithoutSelection;
  final Color? iconEnabledColor;
  final TextStyle? style;
  final InputDecoration? decoration;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final String? selectedDisplayText;
  final bool isExpanded;
  final String? disabledTapMessage;
  final VoidCallback? onDisabledTap;

  @override
  State<AdminDropdownFormField<T>> createState() =>
      _AdminDropdownFormFieldState<T>();
}

class _AdminDropdownFormFieldState<T> extends State<AdminDropdownFormField<T>> {
  final GlobalKey _fieldKey = GlobalKey();
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  T? _selectedValue;
  bool _isHovered = false;
  bool _isPressed = false;

  void _dismissActiveMenu() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).maybePop();
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _selectedValue = widget.initialValue;
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AdminDropdownFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextItems = widget.items ?? <DropdownMenuItem<T>>[];
    final nextWidgetValue = widget.initialValue;
    final hasSelectedValue = nextItems.any(
      (item) => item.value == _selectedValue,
    );
    final hasWidgetValue = nextItems.any(
      (item) => item.value == nextWidgetValue,
    );

    if (oldWidget.initialValue != nextWidgetValue) {
      _selectedValue = hasWidgetValue ? nextWidgetValue : null;
      return;
    }

    if (!hasSelectedValue) {
      _selectedValue = hasWidgetValue ? nextWidgetValue : null;
    }
  }

  @override
  void dispose() {
    AdminDropdownMenuCoordinator.unregisterActiveDismissCallback(
      _dismissActiveMenu,
    );
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChanged() {
    widget.onFocusChanged?.call(_focusNode.hasFocus);
  }

  void _handleMenuOpened() {
    AdminDropdownMenuCoordinator.registerActiveDismissCallback(
      _dismissActiveMenu,
    );
  }

  Future<void> _openMenu() async {
    final items = widget.items ?? <DropdownMenuItem<T>>[];
    if (items.isEmpty || widget.onChanged == null) {
      return;
    }
    _handleMenuOpened();
    final fieldContext = _fieldKey.currentContext;
    if (fieldContext == null) {
      AdminDropdownMenuCoordinator.unregisterActiveDismissCallback(
        _dismissActiveMenu,
      );
      return;
    }
    final fieldBox = fieldContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (fieldBox == null || overlayBox == null) {
      AdminDropdownMenuCoordinator.unregisterActiveDismissCallback(
        _dismissActiveMenu,
      );
      return;
    }
    final topLeft = fieldBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final rect = topLeft & fieldBox.size;
    final result = await showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlayBox.size),
      constraints: BoxConstraints.tightFor(width: rect.width),
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shadowColor: const Color(0x3D1A1333),
      elevation: 18,
      menuPadding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      items: items
          .map(
            (item) => PopupMenuItem<T>(
              value: item.value,
              enabled: item.enabled,
              padding: EdgeInsets.zero,
              child: _AdminDropdownMenuOption(
                child: DefaultTextStyle.merge(
                  style: widget.style ?? adminDropdownDisplayTextStyle,
                  child: item.child,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
    AdminDropdownMenuCoordinator.unregisterActiveDismissCallback(
      _dismissActiveMenu,
    );
    if (!mounted) {
      return;
    }
    if (result == null) {
      if (_focusNode.hasFocus) {
        _focusNode.unfocus();
      }
      return;
    }
    setState(() {
      _selectedValue = result;
    });
    widget.onChanged?.call(result);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final baseDecoration = widget.decoration ?? const InputDecoration();
    final decoration = _normalizeCollapsedSelectionDecoration(baseDecoration);
    final errorText = decoration.errorText?.trim();
    final helperText = decoration.helperText?.trim();
    final neutralBorder = decoration.enabledBorder ?? decoration.border;
    final activeFillColor = appDropdownInteractiveFillColor(context);
    final fieldDecoration = _dropdownFeedbackDecoration(
      decoration,
      errorText,
    ).copyWith(helperStyle: const TextStyle(fontSize: 0, height: 0));
    final minHeight =
        decoration.constraints?.minHeight ?? adminModalFieldMinHeight;
    final verticalPadding = minHeight <= adminFilterFieldMinHeight
        ? 12.0
        : 14.0;
    final contentPadding = switch (decoration.contentPadding) {
      EdgeInsets edgeInsets => EdgeInsets.fromLTRB(
        edgeInsets.left,
        verticalPadding,
        edgeInsets.right,
        verticalPadding,
      ),
      EdgeInsetsDirectional edgeInsets => EdgeInsetsDirectional.fromSTEB(
        edgeInsets.start,
        verticalPadding,
        edgeInsets.end,
        verticalPadding,
      ),
      _ => EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
    };
    final hasItems = widget.items?.isNotEmpty == true;
    final isDisabled = widget.onChanged == null || !hasItems;
    final hintText = fieldDecoration.hintText?.trim();
    final hintStyle =
        fieldDecoration.hintStyle ??
        adminFieldHintTextStyle.copyWith(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
        );
    final disabledTapMessage = _disabledTapMessage(fieldDecoration, hasItems);
    final selectedItem = (widget.items ?? <DropdownMenuItem<T>>[])
        .cast<DropdownMenuItem<T>?>()
        .firstWhere(
          (item) => item?.value == _selectedValue,
          orElse: () => null,
        );
    final explicitSelectedLabel = widget.selectedDisplayText?.trim();
    final selectedLabel = explicitSelectedLabel?.isNotEmpty == true
        ? explicitSelectedLabel
        : selectedItem == null
        ? null
        : _collapsedDropdownLabel(selectedItem.child);
    final hasSelectedLabel = selectedLabel?.trim().isNotEmpty == true;
    final displayText = hasSelectedLabel
        ? selectedLabel!.trim()
        : (hintText ?? '');
    final displayStyle = hasSelectedLabel
        ? (widget.style ?? adminFieldValueTextStyle)
        : hintStyle;
    final dropdown = Builder(
      builder: (dropdownContext) {
        return FocusableActionDetector(
          focusNode: _focusNode,
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (intent) {
                if (!isDisabled) {
                  unawaited(_openMenu());
                }
                return null;
              },
            ),
          },
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.enter):
                const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.numpadEnter):
                const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.space):
                const ActivateIntent(),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isDisabled
                ? null
                : () {
                    unawaited(_openMenu());
                  },
            child: InputDecorator(
              key: _fieldKey,
              isFocused: _focusNode.hasFocus,
              isEmpty: !hasSelectedLabel,
              decoration: fieldDecoration.copyWith(
                labelText: '',
                hintText: null,
                floatingLabelBehavior: fieldDecoration.floatingLabelBehavior,
                fillColor: _isHovered || _isPressed
                    ? activeFillColor
                    : appDropdownBaseFillColor(context),
                contentPadding: contentPadding,
                focusedBorder: neutralBorder,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                suffixIcon: Icon(
                  Icons.arrow_drop_down_rounded,
                  color: widget.iconEnabledColor,
                ),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  displayText,
                  style: displayStyle,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );
      },
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

    Widget decoratedField = interactiveDropdown;
    if (isDisabled && disabledTapMessage != null) {
      decoratedField = Stack(
        children: [
          interactiveDropdown,
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.basic,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  final onDisabledTap = widget.onDisabledTap;
                  if (onDisabledTap != null) {
                    onDisabledTap();
                    return;
                  }
                  AppSnackbar.showError(context, disabledTapMessage);
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        decoratedField,
        if (errorText?.isNotEmpty != true && helperText?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(helperText!, style: adminFieldHelperTextStyle),
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

  String _collapsedDropdownLabel(Widget child) {
    if (child is Text) {
      final data = child.data;
      if (data != null) {
        return data;
      }
    }
    // Popup options can use a Row (for example, name plus Online/Offline).
    // The collapsed field should use the first readable label, not fall back
    // to its placeholder just because the option is not a bare Text widget.
    if (child is ProxyWidget) {
      return _collapsedDropdownLabel(child.child);
    }
    if (child is MultiChildRenderObjectWidget) {
      for (final nestedChild in child.children) {
        final label = _collapsedDropdownLabel(nestedChild);
        if (label.isNotEmpty) {
          return label;
        }
      }
    }
    return '';
  }
}

class AdminSearchSelectFormField extends StatefulWidget {
  const AdminSearchSelectFormField({
    super.key,
    required this.options,
    required this.onChanged,
    this.initialValue,
    this.focusNode,
    this.onFocusChanged,
    this.decoration,
    this.enabled = true,
    this.dialogTitle,
  });

  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String? initialValue;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChanged;
  final InputDecoration? decoration;
  final bool enabled;
  final String? dialogTitle;

  @override
  State<AdminSearchSelectFormField> createState() =>
      _AdminSearchSelectFormFieldState();
}

class _AdminSearchSelectFormFieldState
    extends State<AdminSearchSelectFormField> {
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  late final TextEditingController _controller;
  String? _selectedValue;
  bool _isOpeningPicker = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _selectedValue = _resolvedSelectedValue(widget.initialValue);
    _controller = TextEditingController(text: _selectedValue ?? '');
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AdminSearchSelectFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSelected = _resolvedSelectedValue(widget.initialValue);
    if (oldWidget.initialValue != widget.initialValue ||
        oldWidget.options.join('|') != widget.options.join('|')) {
      _selectedValue = nextSelected;
      _controller.value = TextEditingValue(
        text: nextSelected ?? '',
        selection: TextSelection.collapsed(offset: (nextSelected ?? '').length),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  String? _resolvedSelectedValue(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return widget.options.firstWhere(
      (item) => item.toLowerCase() == trimmed.toLowerCase(),
      orElse: () => trimmed,
    );
  }

  void _handleFocusChanged() {
    widget.onFocusChanged?.call(_focusNode.hasFocus);
  }

  Future<void> _openPicker() async {
    if (!widget.enabled || widget.options.isEmpty || _isOpeningPicker) {
      return;
    }

    _isOpeningPicker = true;
    String? selected;
    try {
      // Search selection is intentionally nested inside form dialogs. Using
      // the local navigator avoids the global modal guard/root overlay race.
      selected = await showDialog<String>(
        context: context,
        useRootNavigator: false,
        builder: (context) => _AdminSearchSelectDialog(
          title: _resolvedDialogTitle(widget.dialogTitle, widget.decoration),
          options: widget.options,
          initialQuery: _controller.text.trim(),
        ),
      );
    } finally {
      _isOpeningPicker = false;
    }

    if (!mounted) {
      return;
    }

    if (selected == null) {
      _focusNode.unfocus();
      return;
    }
    final selectedValue = selected;

    setState(() {
      _selectedValue = selectedValue;
      _controller.value = TextEditingValue(
        text: selectedValue,
        selection: TextSelection.collapsed(offset: selectedValue.length),
      );
    });
    widget.onChanged(selectedValue);
    _focusNode.unfocus();
  }

  String _resolvedDialogTitle(
    String? dialogTitle,
    InputDecoration? decoration,
  ) {
    final trimmedDialogTitle = dialogTitle?.trim();
    if (trimmedDialogTitle != null && trimmedDialogTitle.isNotEmpty) {
      return trimmedDialogTitle;
    }
    final labelText = decoration?.labelText?.trim();
    if (labelText != null && labelText.isNotEmpty) {
      return labelText;
    }
    final hintText = decoration?.hintText?.trim();
    if (hintText != null && hintText.isNotEmpty) {
      final normalizedHint = hintText
          .replaceFirst(RegExp(r'^Select\s+', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^Enter\s+', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^Upload\s+', caseSensitive: false), '')
          .trim();
      if (normalizedHint.isNotEmpty) {
        return normalizedHint;
      }
    }
    return 'Select Option';
  }

  @override
  Widget build(BuildContext context) {
    final baseDecoration = widget.decoration ?? const InputDecoration();
    final decoration = _normalizeCollapsedSelectionDecoration(baseDecoration);
    final errorText = decoration.errorText?.trim();
    final helperText = decoration.helperText?.trim();
    final activeFillColor = appDropdownInteractiveFillColor(context);
    final fieldDecoration = _dropdownFeedbackDecoration(
      decoration,
      errorText,
    ).copyWith(helperStyle: const TextStyle(fontSize: 0, height: 0));
    final hasSelection = (_selectedValue?.trim().isNotEmpty ?? false);
    final displayText = hasSelection
        ? _selectedValue!.trim()
        : (fieldDecoration.hintText?.trim() ?? '');
    final displayStyle = hasSelection
        ? adminFieldValueTextStyle
        : (fieldDecoration.hintStyle ??
              adminFieldHintTextStyle.copyWith(
                color: AppColors.primaryColor.withValues(alpha: 0.72),
              ));
    final contentPadding = switch (fieldDecoration.contentPadding) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: !widget.enabled
              ? null
              : () {
                  _openPicker();
                },
          child: Focus(
            focusNode: _focusNode,
            canRequestFocus: widget.enabled,
            child: InputDecorator(
              isFocused: _focusNode.hasFocus,
              isEmpty: !hasSelection,
              decoration: fieldDecoration.copyWith(
                labelText: '',
                hintText: null,
                fillColor: activeFillColor,
                contentPadding: contentPadding,
                suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
              ),
              child: Text(
                displayText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: displayStyle,
              ),
            ),
          ),
        ),
        if (errorText?.isNotEmpty != true && helperText?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(helperText!, style: adminFieldHelperTextStyle),
          ),
      ],
    );
  }
}

class _AdminSearchSelectDialog extends StatefulWidget {
  const _AdminSearchSelectDialog({
    required this.title,
    required this.options,
    this.initialQuery = '',
  });

  final String title;
  final List<String> options;
  final String initialQuery;

  @override
  State<_AdminSearchSelectDialog> createState() =>
      _AdminSearchSelectDialogState();
}

class _AdminSearchSelectDialogState extends State<_AdminSearchSelectDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final filtered = widget.options.where((item) {
      return query.isEmpty || item.toLowerCase().contains(query);
    }).toList();

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                decoration:
                    adminFormInputDecoration(
                      '',
                      hintText: 'Search location',
                    ).copyWith(
                      labelText: null,
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: _controller.clear,
                              icon: const Icon(Icons.close_rounded),
                            ),
                      fillColor: Colors.white,
                    ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching locations found.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return ListTile(
                            tileColor: Colors.white,
                            hoverColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            minVerticalPadding: 0,
                            visualDensity: const VisualDensity(
                              horizontal: 0,
                              vertical: -2,
                            ),
                            title: Text(item, style: adminFieldValueTextStyle),
                            onTap: () => Navigator.of(context).pop(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminDropdownMenuOption extends StatefulWidget {
  const _AdminDropdownMenuOption({required this.child});

  final Widget child;

  @override
  State<_AdminDropdownMenuOption> createState() =>
      _AdminDropdownMenuOptionState();
}

class _AdminDropdownMenuOptionState extends State<_AdminDropdownMenuOption> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _isPressed
        ? AppColors.primarySurfaceAlt
        : _isHovered
        ? AppColors.primarySurface
        : Colors.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) => setState(() => _isPressed = false),
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          constraints: const BoxConstraints(minHeight: 48),
          color: backgroundColor,
          child: widget.child,
        ),
      ),
    );
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
    labelStyle: adminFieldLabelTextStyle.copyWith(
      color: AppColors.primaryColor.withValues(alpha: 0.72),
    ),
    floatingLabelStyle: adminFieldFloatingLabelTextStyle,
    hintStyle: adminFieldHintTextStyle.copyWith(
      color: AppColors.primaryColor.withValues(alpha: 0.72),
    ),
    helperStyle: adminFieldHelperTextStyle.copyWith(
      color: AppColors.primaryColor.withValues(alpha: 0.72),
    ),
    prefixIconColor: AppColors.primaryColor,
    suffixIconColor: AppColors.primaryColor,
    filled: true,
    fillColor: Colors.white,
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
    fillColor: Colors.white,
  );
}
