import 'package:flutter/material.dart';
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

Color appFieldInteractiveFillColor(BuildContext context) {
  return AppColors.primarySurfaceAlt;
}

String adminEnterPlaceholder(
  String label, {
  String? override,
}) {
  final trimmedOverride = override?.trim();
  if (trimmedOverride != null && trimmedOverride.isNotEmpty) {
    return trimmedOverride;
  }
  return 'Enter $label';
}

String adminSelectPlaceholder(
  String label, {
  String? override,
}) {
  final trimmedOverride = override?.trim();
  if (trimmedOverride != null && trimmedOverride.isNotEmpty) {
    return trimmedOverride;
  }
  return 'Select $label';
}

String adminUploadPlaceholder(
  String label, {
  String? override,
}) {
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
    this.autoActivateOnFocus = false,
    this.unfocusOnDismissWithoutSelection = true,
    this.iconEnabledColor,
    this.style,
    this.decoration,
    this.items,
    this.onChanged,
    this.isExpanded = true,
    this.disabledTapMessage,
  });

  final T? initialValue;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChanged;
  final bool autoActivateOnFocus;
  final bool unfocusOnDismissWithoutSelection;
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
  T? _selectedValue;
  bool _isHovered = false;
  bool _isPressed = false;
  int _menuWatchToken = 0;
  bool _selectionMadeWhileMenuOpen = false;
  bool _suppressFocusActivationOnce = false;
  BuildContext? _dropdownContext;

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
    if (!_focusNode.hasFocus) {
      _suppressFocusActivationOnce = false;
      return;
    }
    if (!widget.autoActivateOnFocus || _suppressFocusActivationOnce) {
      _suppressFocusActivationOnce = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) {
        return;
      }
      final targetContext = _dropdownContext ?? _focusNode.context;
      if (targetContext != null) {
        Actions.maybeInvoke(targetContext, const ActivateIntent());
      }
    });
  }

  void _handleMenuOpened() {
    if (widget.unfocusOnDismissWithoutSelection == false) {
      AdminDropdownMenuCoordinator.registerActiveDismissCallback(
        _dismissActiveMenu,
      );
    } else {
      AdminDropdownMenuCoordinator.registerActiveDismissCallback(
        _dismissActiveMenu,
      );
    }
    final route = ModalRoute.of(context);
    if (route == null) {
      return;
    }
    _selectionMadeWhileMenuOpen = false;
    final watchToken = ++_menuWatchToken;
    _watchMenuDismiss(route, watchToken);
  }

  Future<void> _watchMenuDismiss(
    ModalRoute<dynamic> route,
    int watchToken,
  ) async {
    var sawPopupRoute = false;
    for (var index = 0; index < 180; index++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted || watchToken != _menuWatchToken) {
        return;
      }
      final isCurrent = route.isCurrent;
      if (!sawPopupRoute) {
        if (!isCurrent) {
          sawPopupRoute = true;
        }
        continue;
      }
      if (!isCurrent) {
        continue;
      }
      AdminDropdownMenuCoordinator.unregisterActiveDismissCallback(
        _dismissActiveMenu,
      );
      if (!_selectionMadeWhileMenuOpen && _focusNode.hasFocus) {
        _focusNode.unfocus();
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final decoration = widget.decoration ?? const InputDecoration();
    final errorText = decoration.errorText?.trim();
    final helperText = decoration.helperText?.trim();
    final neutralBorder = decoration.enabledBorder ?? decoration.border;
    final activeFillColor = appFieldInteractiveFillColor(context);
    final fieldDecoration = decoration.copyWith(
      errorText: null,
      helperText: null,
      errorStyle: const TextStyle(fontSize: 0, height: 0),
      helperStyle: const TextStyle(fontSize: 0, height: 0),
    );
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
    final hintText = fieldDecoration.hintText?.trim();
    final hintStyle =
        fieldDecoration.hintStyle ??
        adminFieldHintTextStyle.copyWith(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
        );
    final hintWidget = hintText?.isNotEmpty == true
        ? Text(hintText!, overflow: TextOverflow.ellipsis, style: hintStyle)
        : null;
    final disabledTapMessage = _disabledTapMessage(fieldDecoration, hasItems);
    final menuInteractiveColor = AppColors.primarySurfaceAlt;
    final itemSignature =
        widget.items
            ?.map((item) => item.value?.toString() ?? '-')
            .join('|') ??
        '-';
    final dropdown = Theme(
      data: Theme.of(context).copyWith(
        hoverColor: menuInteractiveColor,
        highlightColor: Colors.transparent,
        splashColor: menuInteractiveColor,
      ),
      child: Builder(
        builder: (dropdownContext) {
          _dropdownContext = dropdownContext;
          return DropdownButtonFormField<T>(
            key: ValueKey<String>(
              '${_selectedValue?.toString() ?? '-'}::$itemSignature',
            ),
            initialValue: _selectedValue,
            focusNode: _focusNode,
            autofocus: false,
            isDense: true,
            iconEnabledColor: widget.iconEnabledColor,
            style: widget.style,
            decoration: fieldDecoration.copyWith(
              fillColor: _isHovered || _isPressed
                  ? activeFillColor
                  : (fieldDecoration.fillColor ?? AppColors.primarySurface),
              contentPadding: contentPadding,
              focusedBorder: neutralBorder,
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
            ),
            hint: hintWidget,
            disabledHint: hintWidget,
            items: widget.items,
            selectedItemBuilder: widget.items == null
                ? null
                : (context) => widget.items!.map((item) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _collapsedDropdownLabel(item.child),
                        style: widget.style ?? adminFieldValueTextStyle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
            isExpanded: widget.isExpanded,
            onTap: isDisabled ? null : _handleMenuOpened,
            onChanged: isDisabled
                ? null
                : (value) {
                    _selectionMadeWhileMenuOpen = true;
                    setState(() {
                      _selectedValue = value;
                    });
                    widget.onChanged?.call(value);
                    _focusNode.unfocus();
                  },
          );
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
            _suppressFocusActivationOnce = true;
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
                onTap: () => AppSnackbar.showError(context, disabledTapMessage),
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
        if (errorText?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
              ),
            ),
          )
        else if (helperText?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              helperText!,
              style: adminFieldHelperTextStyle,
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

  String _collapsedDropdownLabel(Widget child) {
    if (child is Text) {
      final data = child.data;
      if (data != null) {
        return data;
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
    this.autoActivateOnFocus = false,
    this.decoration,
    this.enabled = true,
  });

  final List<String> options;
  final ValueChanged<String?> onChanged;
  final String? initialValue;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChanged;
  final bool autoActivateOnFocus;
  final InputDecoration? decoration;
  final bool enabled;

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
  bool _suppressFocusActivationOnce = false;

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
        selection: TextSelection.collapsed(
          offset: (nextSelected ?? '').length,
        ),
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
    if (!_focusNode.hasFocus) {
      _suppressFocusActivationOnce = false;
      return;
    }
    if (!widget.autoActivateOnFocus || _suppressFocusActivationOnce) {
      _suppressFocusActivationOnce = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) {
        return;
      }
      _openPicker();
    });
  }

  Future<void> _openPicker() async {
    if (!widget.enabled || widget.options.isEmpty) {
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _AdminSearchSelectDialog(
        title: _resolvedDialogTitle(widget.decoration),
        options: widget.options,
        initialQuery: _controller.text.trim(),
      ),
    );

    if (!mounted) {
      return;
    }

    if (selected == null) {
      _focusNode.unfocus();
      return;
    }

    setState(() {
      _selectedValue = selected;
      _controller.value = TextEditingValue(
        text: selected,
        selection: TextSelection.collapsed(offset: selected.length),
      );
    });
    widget.onChanged(selected);
    _focusNode.unfocus();
  }

  String _resolvedDialogTitle(InputDecoration? decoration) {
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
    final decoration = widget.decoration ?? const InputDecoration();
    final errorText = decoration.errorText?.trim();
    final helperText = decoration.helperText?.trim();
    final activeFillColor = appFieldInteractiveFillColor(context);
    final fieldDecoration = decoration.copyWith(
      errorText: null,
      helperText: null,
      errorStyle: const TextStyle(fontSize: 0, height: 0),
      helperStyle: const TextStyle(fontSize: 0, height: 0),
    );
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
                  _suppressFocusActivationOnce = true;
                  if (!_focusNode.hasFocus) {
                    _focusNode.requestFocus();
                  }
                  _openPicker();
                },
          child: Focus(
            focusNode: _focusNode,
            canRequestFocus: widget.enabled,
            child: InputDecorator(
              isFocused: _focusNode.hasFocus,
              isEmpty: !hasSelection,
              decoration: fieldDecoration.copyWith(
                hintText: null,
                fillColor: fieldDecoration.fillColor ?? activeFillColor,
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
        if (errorText?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
              ),
            ),
          )
        else if (helperText?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              helperText!,
              style: adminFieldHelperTextStyle,
            ),
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
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search location',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 14),
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
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return ListTile(
                            title: Text(
                              item,
                              style: adminFieldValueTextStyle,
                            ),
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
