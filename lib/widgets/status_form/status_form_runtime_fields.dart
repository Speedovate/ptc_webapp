import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/constants/palawan_locations.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/requests/chassis.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/booking_form_primitives.dart';
import 'package:webapp/widgets/shared/chassis_status_presentation.dart';

String? _runtimeFieldPlaceholder(StatusField field) {
  final placeholder = field.placeholder?.trim();
  if (field.required == true && placeholder?.toLowerCase() == 'optional') {
    return null;
  }
  return placeholder;
}

class StatusFormRuntimeFieldCard extends StatelessWidget {
  const StatusFormRuntimeFieldCard({
    super.key,
    required this.field,
    required this.initialValue,
    required this.onChanged,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    this.formTitle,
    this.formButtonText,
    this.formStatusKey,
    this.errorText,
    this.optionLabels = const {},
    this.onDisabledTap,
    this.onAdvanceAfterSelection,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final String? formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final String? errorText;
  final Map<String, String> optionLabels;
  final VoidCallback? onDisabledTap;
  final ValueChanged<dynamic>? onAdvanceAfterSelection;

  @override
  Widget build(BuildContext context) {
    final title = field.title?.trim();
    final subtitle = field.subtitle?.trim();
    final instructions = field.instructions?.trim();
    final fieldType = (field.type ?? '').trim().toLowerCase();
    final fieldKey = (field.key ?? '').trim().toLowerCase();
    final isSearchDropdownCard =
        fieldType == 'search_dropdown' || isPalawanLocationFieldKey(fieldKey);
    final isNormalDropdownCard = fieldType == 'dropdown';
    final usesDropdownCard = isNormalDropdownCard || isSearchDropdownCard;
    final palette = bookingFormResolvedStatusPalette(
      title: formTitle,
      buttonText: formButtonText,
      currentStatusKey: formStatusKey,
    );

    return BookingFormFieldCard(
      title: title?.isNotEmpty == true ? title! : 'Untitled Field',
      buttonText: formButtonText,
      paletteOverride: palette,
      required: field.required == true,
      hasError: errorText?.trim().isNotEmpty == true,
      subtitle: subtitle,
      instructions: instructions,
      inputTopSpacing: usesDropdownCard ? 10 : 14,
      containerPadding: isSearchDropdownCard
          ? const EdgeInsets.fromLTRB(18, 18, 18, 4)
          : (isNormalDropdownCard
                ? const EdgeInsets.fromLTRB(18, 18, 18, 8)
                : const EdgeInsets.all(18)),
      input: StatusFormRuntimeFieldInput(
        field: field,
        initialValue: initialValue,
        focusNode: focusNode,
        nextFocusNode: nextFocusNode,
        activateNextFocus: activateNextFocus,
        errorText: errorText,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        optionLabels: optionLabels,
        onDisabledTap: onDisabledTap,
        onAdvanceAfterSelection: onAdvanceAfterSelection,
        onChanged: onChanged,
      ),
    );
  }
}

class StatusFormRuntimeFieldInput extends StatelessWidget {
  const StatusFormRuntimeFieldInput({
    super.key,
    required this.field,
    required this.initialValue,
    required this.onChanged,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    this.formTitle,
    this.formButtonText,
    this.formStatusKey,
    this.errorText,
    this.optionLabels = const {},
    this.onDisabledTap,
    this.onAdvanceAfterSelection,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final String? formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final String? errorText;
  final Map<String, String> optionLabels;
  final VoidCallback? onDisabledTap;
  final ValueChanged<dynamic>? onAdvanceAfterSelection;

  @override
  Widget build(BuildContext context) {
    final fieldKey = (field.key ?? '').trim().toLowerCase();
    if (isPalawanLocationFieldKey(fieldKey)) {
      return _PalawanLocationFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        focusNode: focusNode,
        nextFocusNode: nextFocusNode,
        activateNextFocus: activateNextFocus,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        onAdvanceAfterSelection: onAdvanceAfterSelection,
        onChanged: onChanged,
      );
    }
    return switch (field.type) {
      'photo' => _PhotoFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        focusNode: focusNode,
        nextFocusNode: nextFocusNode,
        activateNextFocus: activateNextFocus,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        onAdvanceAfterSelection: onAdvanceAfterSelection,
        onChanged: onChanged,
      ),
      'search_dropdown' => _SearchDropdownFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        focusNode: focusNode,
        nextFocusNode: nextFocusNode,
        activateNextFocus: activateNextFocus,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        onAdvanceAfterSelection: onAdvanceAfterSelection,
        onChanged: onChanged,
      ),
      'dropdown' => _DropdownFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        focusNode: focusNode,
        nextFocusNode: nextFocusNode,
        activateNextFocus: activateNextFocus,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        onDisabledTap: onDisabledTap,
        optionLabels: optionLabels,
        onAdvanceAfterSelection: onAdvanceAfterSelection,
        onChanged: onChanged,
      ),
      'checkbox' => _CheckboxFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        onChanged: onChanged,
      ),
      'date' => _DateFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        onChanged: onChanged,
      ),
      'time' => _TimeFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        onChanged: onChanged,
      ),
      'email' => _TextFieldInput(
        field: field,
        initialValue: initialValue,
        focusNode: focusNode,
        nextFocusNode: nextFocusNode,
        activateNextFocus: activateNextFocus,
        errorText: errorText,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        onChanged: onChanged,
        keyboardType: TextInputType.emailAddress,
      ),
      'phone' => _TextFieldInput(
        field: field,
        initialValue: initialValue,
        focusNode: focusNode,
        nextFocusNode: nextFocusNode,
        activateNextFocus: activateNextFocus,
        errorText: errorText,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        onChanged: onChanged,
        keyboardType: TextInputType.phone,
      ),
      'number' => _TextFieldInput(
        field: field,
        initialValue: initialValue,
        focusNode: focusNode,
        nextFocusNode: nextFocusNode,
        activateNextFocus: activateNextFocus,
        errorText: errorText,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        onChanged: onChanged,
        keyboardType: TextInputType.number,
      ),
      _ => _TextFieldInput(
        field: field,
        initialValue: initialValue,
        focusNode: focusNode,
        nextFocusNode: nextFocusNode,
        activateNextFocus: activateNextFocus,
        errorText: errorText,
        formTitle: formTitle,
        formButtonText: formButtonText,
        formStatusKey: formStatusKey,
        onChanged: onChanged,
        keyboardType: TextInputType.text,
      ),
    };
  }
}

class _SearchDropdownFieldInput extends StatelessWidget {
  const _SearchDropdownFieldInput({
    required this.field,
    required this.initialValue,
    required this.onChanged,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    this.errorText,
    this.onAdvanceAfterSelection,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final String? formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final String? errorText;
  final ValueChanged<dynamic>? onAdvanceAfterSelection;

  void _closeSelectionFlow(BuildContext context, dynamic value) {
    onChanged(value);
    final handleAdvance = onAdvanceAfterSelection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      if (handleAdvance != null) {
        handleAdvance(value);
        return;
      }
      FocusScope.of(context).unfocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = bookingFormResolvedStatusPalette(
      title: formTitle,
      buttonText: formButtonText,
      currentStatusKey: formStatusKey,
    );
    final fieldLabel = field.title?.trim().isNotEmpty == true
        ? field.title!.trim()
        : 'Field';
    if (field.options.isEmpty) {
    } else {}

    return AdminSearchSelectFormField(
      initialValue: initialValue?.toString(),
      focusNode: focusNode,
      dialogTitle: adminSelectPlaceholder(fieldLabel),
      decoration:
          adminPlainDropdownDecoration(
            field.required == true
                ? adminSelectPlaceholder(
                    fieldLabel,
                    override: _runtimeFieldPlaceholder(field),
                  )
                : ((field.placeholder?.trim().isNotEmpty == true)
                      ? field.placeholder!.trim()
                      : 'Optional'),
          ).copyWith(
            fillColor: Colors.white,
            hintStyle: adminFieldHintTextStyle.copyWith(
              color: palette.accentMuted,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.accent),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.border),
            ),
            errorText: errorText,
          ),
      options: field.options,
      onChanged: (value) => _closeSelectionFlow(context, value),
    );
  }
}

class _PalawanLocationFieldInput extends StatelessWidget {
  const _PalawanLocationFieldInput({
    required this.field,
    required this.initialValue,
    required this.onChanged,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    this.errorText,
    this.onAdvanceAfterSelection,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final String? formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final String? errorText;
  final ValueChanged<dynamic>? onAdvanceAfterSelection;

  void _closeSelectionFlow(BuildContext context, dynamic value) {
    onChanged(value);
    final handleAdvance = onAdvanceAfterSelection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      if (handleAdvance != null) {
        handleAdvance(value);
        return;
      }
      FocusScope.of(context).unfocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = bookingFormResolvedStatusPalette(
      title: formTitle,
      buttonText: formButtonText,
      currentStatusKey: formStatusKey,
    );

    return AdminSearchSelectFormField(
      initialValue: initialValue?.toString(),
      focusNode: focusNode,
      dialogTitle: adminSelectPlaceholder(
        field.title?.trim().isNotEmpty == true
            ? field.title!.trim()
            : 'Location',
      ),
      decoration:
          adminPlainDropdownDecoration(
            field.required == true
                ? adminSelectPlaceholder(
                    field.title?.trim().isNotEmpty == true
                        ? field.title!.trim()
                        : 'Location',
                    override: _runtimeFieldPlaceholder(field),
                  )
                : ((field.placeholder?.trim().isNotEmpty == true)
                      ? field.placeholder!.trim()
                      : 'Optional'),
          ).copyWith(
            fillColor: Colors.white,
            hintStyle: adminFieldHintTextStyle.copyWith(
              color: palette.accentMuted,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.accent),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: palette.border),
            ),
            errorText: errorText,
          ),
      options: palawanLocationOptions,
      onChanged: (value) => _closeSelectionFlow(context, value),
    );
  }
}

class _TextFieldInput extends StatefulWidget {
  const _TextFieldInput({
    required this.field,
    required this.initialValue,
    required this.onChanged,
    required this.keyboardType,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final TextInputType keyboardType;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final String? formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final String? errorText;

  @override
  State<_TextFieldInput> createState() => _TextFieldInputState();
}

class _TextFieldInputState extends State<_TextFieldInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;

  void _focusAndMaybeActivateNext(FocusNode nextFocusNode) {
    FocusScope.of(context).requestFocus(nextFocusNode);
    if (!widget.activateNextFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final primaryFocus = FocusManager.instance.primaryFocus;
      final targetContext = primaryFocus?.context ?? nextFocusNode.context;
      if (targetContext != null) {
        Actions.maybeInvoke(targetContext, const ActivateIntent());
      }
    });
  }

  String get _debugFieldLabel {
    final key = (widget.field.key ?? '').trim();
    final title = (widget.field.title ?? '').trim();
    final type = (widget.field.type ?? '').trim();
    return 'key=${key.isEmpty ? '-' : key} title=${title.isEmpty ? '-' : title} type=${type.isEmpty ? '-' : type}';
  }

  void _unfocusWithoutScroll(PointerDownEvent event) {
    final scrollPosition = Scrollable.maybeOf(context)?.position;
    final scrollOffset = scrollPosition?.hasPixels == true
        ? scrollPosition!.pixels
        : null;
    FocusManager.instance.primaryFocus?.unfocus();
    if (scrollPosition == null || scrollOffset == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollPosition.hasPixels) {
        return;
      }
      final clampedOffset = scrollOffset.clamp(
        scrollPosition.minScrollExtent,
        scrollPosition.maxScrollExtent,
      );
      if ((scrollPosition.pixels - clampedOffset).abs() >= 0.5) {
        scrollPosition.jumpTo(clampedOffset);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue?.toString() ?? '',
    );
    _ownsFocusNode = widget.focusNode == null;
    _focusNode =
        widget.focusNode ??
        FocusNode(debugLabel: 'booking_field($_debugFieldLabel)');
    _controller.addListener(_handleChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _TextFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = widget.initialValue?.toString() ?? '';
    if (_controller.text == nextText) {
      return;
    }
    _controller.removeListener(_handleChanged);
    _controller.value = _controller.value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
    _controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleChanged() {
    final raw = _controller.text;
    if (widget.field.type == 'number') {
      widget.onChanged(num.tryParse(raw) ?? raw);
      return;
    }
    widget.onChanged(raw);
  }

  void _handleFocusChanged() {}

  bool get _isNameField {
    final key = (widget.field.key ?? '').trim().toLowerCase();
    final title = (widget.field.title ?? '').trim();
    return key.contains('name') ||
        RegExp(r'\bname\b', caseSensitive: false).hasMatch(title);
  }

  bool get _isPhoneField {
    final haystack = '${widget.field.key ?? ''} ${widget.field.title ?? ''}'
        .toLowerCase();
    return widget.field.type == 'phone' ||
        haystack.contains('phone') ||
        haystack.contains('mobile') ||
        haystack.contains('contact number');
  }

  @override
  Widget build(BuildContext context) {
    final palette = bookingFormResolvedStatusPalette(
      title: widget.formTitle,
      buttonText: widget.formButtonText,
      currentStatusKey: widget.formStatusKey,
    );
    final placeholder = _runtimeFieldPlaceholder(widget.field);
    final fieldLabel = widget.field.title?.trim().isNotEmpty == true
        ? widget.field.title!.trim()
        : 'Field';
    final hint = placeholder?.isNotEmpty == true
        ? placeholder!
        : widget.field.required == true
        ? adminEnterPlaceholder(fieldLabel)
        : 'Optional';

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: _isPhoneField ? TextInputType.phone : widget.keyboardType,
      textInputAction: widget.nextFocusNode != null
          ? TextInputAction.next
          : TextInputAction.done,
      textCapitalization: _isNameField
          ? TextCapitalization.words
          : TextCapitalization.none,
      inputFormatters: _isPhoneField
          ? const [PhilippinesPhoneInputFormatter()]
          : (_isNameField ? const [NameCaseTextInputFormatter()] : null),
      onSubmitted: (_) {
        final nextFocusNode = widget.nextFocusNode;
        if (nextFocusNode != null) {
          _focusAndMaybeActivateNext(nextFocusNode);
        } else {
          FocusScope.of(context).unfocus();
        }
      },
      scrollPadding: EdgeInsets.zero,
      onTapOutside: _unfocusWithoutScroll,
      style: adminFieldValueTextStyle,
      cursorColor: palette.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: adminFieldHintTextStyle.copyWith(color: palette.accentMuted),
        isDense: true,
        filled: false,
        contentPadding: const EdgeInsets.only(
          left: 2,
          right: 2,
          top: 14,
          bottom: 10,
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: palette.accent, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.danger, width: 2),
        ),
        errorText: widget.errorText,
        helperText: _constraintHint(widget.field),
        helperStyle: adminFieldHelperTextStyle.copyWith(
          color: palette.accentMuted,
        ),
      ),
    );
  }
}

class _DropdownFieldInput extends StatelessWidget {
  const _DropdownFieldInput({
    required this.field,
    required this.initialValue,
    required this.onChanged,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    this.errorText,
    this.optionLabels = const {},
    this.onDisabledTap,
    this.onAdvanceAfterSelection,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final String? formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final String? errorText;
  final Map<String, String> optionLabels;
  final VoidCallback? onDisabledTap;
  final ValueChanged<dynamic>? onAdvanceAfterSelection;

  @override
  Widget build(BuildContext context) {
    final optionSourceKey = StatusFieldOptionResolver.resolvedOptionSourceKey(
      field,
    );
    final effectiveOptions = field.options.isNotEmpty
        ? field.options
        : optionLabels.keys.toList();
    final palette = bookingFormResolvedStatusPalette(
      title: formTitle,
      buttonText: formButtonText,
      currentStatusKey: formStatusKey,
    );
    final placeholder = _runtimeFieldPlaceholder(field);
    final fieldLabel = field.title?.trim().isNotEmpty == true
        ? field.title!.trim()
        : 'Field';
    if (effectiveOptions.isEmpty) {
    } else {}
    final hintText = placeholder?.isNotEmpty == true
        ? placeholder!
        : field.required == true
        ? adminSelectPlaceholder(fieldLabel)
        : 'Optional';
    void closeSelectionFlow(dynamic value) {
      onChanged(value);
      final handleAdvance = onAdvanceAfterSelection;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) {
          return;
        }
        if (handleAdvance != null) {
          handleAdvance(value);
          return;
        }
        FocusScope.of(context).unfocus();
      });
    }

    return AdminDropdownFormField<String>(
      initialValue: initialValue is String ? initialValue : null,
      focusNode: focusNode,
      onFocusChanged: (hasFocus) {},
      isExpanded: true,
      iconEnabledColor: palette.accent,
      style: adminDropdownDisplayTextStyle,
      decoration: adminPlainDropdownDecoration(hintText).copyWith(
        fillColor: Colors.white,
        hintStyle: adminFieldHintTextStyle.copyWith(color: palette.accentMuted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.accent),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        errorText: errorText,
      ),
      items: effectiveOptions.map((option) {
        final label =
            optionLabels[option] ??
            (optionSourceKey == statusFieldOptionSourceVehicleSizes
                ? VehicleRequest.instance.displayVehicleSizeLabel(option)
                : optionSourceKey == statusFieldOptionSourceChassis
                ? ChassisRequest.instance.displayChassisLabel(option)
                : option);
        return DropdownMenuItem<String>(
          value: option,
          child: optionSourceKey == statusFieldOptionSourceChassis
              ? ChassisStatusOptionLabel(
                  label: label,
                  status:
                      ChassisRequest.instance.hydratedChassisSnapshot
                          .where((chassis) => chassis.id.toString() == option)
                          .firstOrNull
                          ?.currentStatus ??
                      '',
                )
              : Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: adminDropdownDisplayTextStyle,
                ),
        );
      }).toList(),
      onChanged: (value) => closeSelectionFlow(value),
      onDisabledTap: onDisabledTap,
    );
  }
}

class _CheckboxFieldInput extends StatefulWidget {
  const _CheckboxFieldInput({
    required this.field,
    required this.initialValue,
    required this.onChanged,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final String? formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final String? errorText;

  @override
  State<_CheckboxFieldInput> createState() => _CheckboxFieldInputState();
}

class _CheckboxFieldInputState extends State<_CheckboxFieldInput> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue is List
        ? List<String>.from(widget.initialValue as List)
        : <String>[];
  }

  @override
  void didUpdateWidget(covariant _CheckboxFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSelected = widget.initialValue is List
        ? List<String>.from(widget.initialValue as List)
        : <String>[];
    if (_selected.length == nextSelected.length) {
      final sameValues =
          _selected.toSet().containsAll(nextSelected) &&
          nextSelected.toSet().containsAll(_selected);
      if (sameValues) {
        return;
      }
    }
    setState(() {
      _selected = nextSelected;
    });
  }

  void _toggle(String option, bool selected) {
    setState(() {
      if (selected) {
        _selected = [..._selected, option];
      } else {
        _selected = _selected.where((item) => item != option).toList();
      }
    });
    widget.onChanged(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final palette = bookingFormResolvedStatusPalette(
      title: widget.formTitle,
      buttonText: widget.formButtonText,
      currentStatusKey: widget.formStatusKey,
    );
    final activeFillColor = palette.surfaceAlt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...widget.field.options.map(
          (option) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppMousePressable(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _toggle(option, !_selected.contains(option)),
              child: Builder(
                builder: (context) => AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: appPressableActive(context)
                        ? activeFillColor
                        : palette.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _selected.contains(option),
                        onChanged: (value) => _toggle(option, value ?? false),
                        activeColor: palette.accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(option, style: adminFieldValueTextStyle),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              widget.errorText!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _DateFieldInput extends StatefulWidget {
  const _DateFieldInput({
    required this.field,
    required this.initialValue,
    required this.onChanged,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final String? formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final String? errorText;

  @override
  State<_DateFieldInput> createState() => _DateFieldInputState();
}

class _DateFieldInputState extends State<_DateFieldInput> {
  DateTime? _value;

  @override
  void initState() {
    super.initState();
    _value = _parseDateValue(widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _DateFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue == widget.initialValue) {
      return;
    }
    final nextValue = _parseDateValue(widget.initialValue);
    if (_value == nextValue) {
      return;
    }
    setState(() {
      _value = nextValue;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _value ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    setState(() => _value = picked);
    widget.onChanged(_formatDateValue(picked));
  }

  @override
  Widget build(BuildContext context) {
    final display = _value == null
        ? (widget.field.required == true
              ? adminSelectPlaceholder(
                  widget.field.title?.trim().isNotEmpty == true
                      ? widget.field.title!.trim()
                      : 'Date',
                  override: _runtimeFieldPlaceholder(widget.field),
                )
              : (widget.field.placeholder?.trim().isNotEmpty == true
                    ? widget.field.placeholder!.trim()
                    : 'Optional'))
        : _formatDateLabel(_value!);

    return _PickerFieldShell(
      text: display,
      isPlaceholder: _value == null,
      icon: Icons.calendar_today_rounded,
      errorText: widget.errorText,
      formTitle: widget.formTitle,
      formButtonText: widget.formButtonText,
      formStatusKey: widget.formStatusKey,
      onTap: _pickDate,
    );
  }
}

class _TimeFieldInput extends StatefulWidget {
  const _TimeFieldInput({
    required this.field,
    required this.initialValue,
    required this.onChanged,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final String? formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final String? errorText;

  @override
  State<_TimeFieldInput> createState() => _TimeFieldInputState();
}

class _TimeFieldInputState extends State<_TimeFieldInput> {
  TimeOfDay? _value;

  @override
  void initState() {
    super.initState();
    _value = _parseTimeValue(widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _TimeFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue == widget.initialValue) {
      return;
    }
    final nextValue = _parseTimeValue(widget.initialValue);
    final hasSameValue =
        _value?.hour == nextValue?.hour && _value?.minute == nextValue?.minute;
    if (hasSameValue) {
      return;
    }
    setState(() {
      _value = nextValue;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _value ?? TimeOfDay.now(),
    );
    if (picked == null) {
      return;
    }
    setState(() => _value = picked);
    widget.onChanged(_formatTimeValue(picked));
  }

  @override
  Widget build(BuildContext context) {
    final display = _value == null
        ? (widget.field.required == true
              ? adminSelectPlaceholder(
                  widget.field.title?.trim().isNotEmpty == true
                      ? widget.field.title!.trim()
                      : 'Time',
                  override: _runtimeFieldPlaceholder(widget.field),
                )
              : (widget.field.placeholder?.trim().isNotEmpty == true
                    ? widget.field.placeholder!.trim()
                    : 'Optional'))
        : _value!.format(context);

    return _PickerFieldShell(
      text: display,
      isPlaceholder: _value == null,
      icon: Icons.schedule_rounded,
      errorText: widget.errorText,
      formTitle: widget.formTitle,
      formButtonText: widget.formButtonText,
      formStatusKey: widget.formStatusKey,
      onTap: _pickTime,
    );
  }
}

class _PickerFieldShell extends StatefulWidget {
  const _PickerFieldShell({
    required this.text,
    required this.isPlaceholder,
    required this.icon,
    required this.onTap,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    this.errorText,
  });

  final String text;
  final bool isPlaceholder;
  final IconData icon;
  final VoidCallback onTap;
  final String? formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final String? errorText;

  @override
  State<_PickerFieldShell> createState() => _PickerFieldShellState();
}

class _PickerFieldShellState extends State<_PickerFieldShell> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = bookingFormResolvedStatusPalette(
      title: widget.formTitle,
      buttonText: widget.formButtonText,
      currentStatusKey: widget.formStatusKey,
    );
    final activeFillColor = palette.surfaceAlt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: adminModalFieldMinHeight,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() {
              _isHovered = false;
              _isPressed = false;
            }),
            child: Listener(
              onPointerDown: (_) => setState(() => _isPressed = true),
              onPointerUp: (_) => setState(() => _isPressed = false),
              onPointerCancel: (_) => setState(() => _isPressed = false),
              child: AppMousePressable(
                borderRadius: BorderRadius.circular(14),
                onTap: widget.onTap,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _isHovered || _isPressed
                        ? activeFillColor
                        : palette.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: widget.errorText == null
                          ? palette.border
                          : AppColors.danger,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.text,
                          style:
                              (widget.isPlaceholder
                                      ? adminFieldHintTextStyle
                                      : adminFieldValueTextStyle)
                                  .copyWith(
                                    color: widget.isPlaceholder
                                        ? palette.accentMuted
                                        : AppColors.textPrimary,
                                  ),
                        ),
                      ),
                      Icon(widget.icon, size: 18, color: palette.accent),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.errorText!,
              style: const TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _PhotoFieldInput extends StatefulWidget {
  const _PhotoFieldInput({
    required this.field,
    required this.initialValue,
    required this.onChanged,
    this.focusNode,
    this.nextFocusNode,
    this.activateNextFocus = false,
    required this.formTitle,
    required this.formButtonText,
    required this.formStatusKey,
    this.errorText,
    this.onAdvanceAfterSelection,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final bool activateNextFocus;
  final String? formTitle;
  final String? formButtonText;
  final String? formStatusKey;
  final String? errorText;
  final ValueChanged<dynamic>? onAdvanceAfterSelection;

  @override
  State<_PhotoFieldInput> createState() => _PhotoFieldInputState();
}

class _PhotoFieldInputState extends State<_PhotoFieldInput> {
  void _focusAndMaybeActivateNext(FocusNode nextFocusNode) {
    FocusScope.of(context).requestFocus(nextFocusNode);
    if (!widget.activateNextFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final primaryFocus = FocusManager.instance.primaryFocus;
      final targetContext = primaryFocus?.context ?? nextFocusNode.context;
      if (targetContext != null) {
        Actions.maybeInvoke(targetContext, const ActivateIntent());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BookingPhotoFieldInput(
      initialValue: widget.initialValue,
      focusNode: widget.focusNode,
      nextFocusNode: widget.nextFocusNode,
      activateNextFocus: widget.activateNextFocus,
      errorText: widget.errorText,
      palette: bookingFormResolvedStatusPalette(
        title: widget.formTitle,
        buttonText: widget.formButtonText,
        currentStatusKey: widget.formStatusKey,
      ),
      placeholder: widget.field.required == true
          ? adminUploadPlaceholder(
              widget.field.title?.trim().isNotEmpty == true
                  ? widget.field.title!.trim()
                  : 'Photo',
              override: _runtimeFieldPlaceholder(widget.field),
            )
          : (((widget.field.placeholder ?? '').trim().isNotEmpty)
                ? widget.field.placeholder!.trim()
                : 'Optional'),
      showRemoveAction: true,
      onMoveToNextFocus: _focusAndMaybeActivateNext,
      onAdvanceAfterSelection: widget.onAdvanceAfterSelection,
      onChanged: widget.onChanged,
    );
  }
}

String? _constraintHint(StatusField field) {
  if ((field.type ?? '').trim().toLowerCase() == 'phone') {
    return null;
  }
  final parts = <String>[];
  if (field.min != null) {
    parts.add('Min: ${field.min}');
  }
  if (field.max != null) {
    parts.add('Max: ${field.max}');
  }
  if (parts.isEmpty) {
    return null;
  }
  return parts.join(' • ');
}

String _formatDateLabel(DateTime value) {
  final monthNames = const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${monthNames[value.month - 1]} ${value.day}, ${value.year}';
}

String _formatDateValue(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

DateTime? _parseDateValue(dynamic value) {
  if (value is! String) {
    return null;
  }
  return DateTime.tryParse(value);
}

TimeOfDay? _parseTime(String value) {
  final parts = value.split(':');
  if (parts.length < 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  return TimeOfDay(hour: hour, minute: minute);
}

TimeOfDay? _parseTimeValue(dynamic value) {
  if (value is! String) {
    return null;
  }
  return _parseTime(value);
}

String _formatTimeValue(TimeOfDay value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
