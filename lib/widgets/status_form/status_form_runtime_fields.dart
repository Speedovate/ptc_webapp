import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/booking_form_primitives.dart';

class StatusFormRuntimeFieldCard extends StatelessWidget {
  const StatusFormRuntimeFieldCard({
    super.key,
    required this.field,
    required this.initialValue,
    required this.onChanged,
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final title = field.title?.trim();
    final subtitle = field.subtitle?.trim();
    final instructions = field.instructions?.trim();
    final fieldType = (field.type ?? '').trim().toLowerCase();
    final usesDropdownCard = fieldType == 'dropdown';

    return BookingFormFieldCard(
      title: title?.isNotEmpty == true ? title! : 'Untitled Field',
      required: field.required == true,
      subtitle: subtitle,
      instructions: instructions,
      containerPadding: usesDropdownCard
          ? const EdgeInsets.fromLTRB(18, 18, 18, 12)
          : const EdgeInsets.all(18),
      input: StatusFormRuntimeFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
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
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return switch (field.type) {
      'photo' => _PhotoFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        onChanged: onChanged,
      ),
      'dropdown' => _DropdownFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        onChanged: onChanged,
      ),
      'checkbox' => _CheckboxFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        onChanged: onChanged,
      ),
      'date' => _DateFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        onChanged: onChanged,
      ),
      'time' => _TimeFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        onChanged: onChanged,
      ),
      'email' => _TextFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        onChanged: onChanged,
        keyboardType: TextInputType.emailAddress,
      ),
      'phone' => _TextFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        onChanged: onChanged,
        keyboardType: TextInputType.phone,
      ),
      'number' => _TextFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        onChanged: onChanged,
        keyboardType: TextInputType.number,
      ),
      _ => _TextFieldInput(
        field: field,
        initialValue: initialValue,
        errorText: errorText,
        onChanged: onChanged,
        keyboardType: TextInputType.text,
      ),
    };
  }
}

class _TextFieldInput extends StatefulWidget {
  const _TextFieldInput({
    required this.field,
    required this.initialValue,
    required this.onChanged,
    required this.keyboardType,
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final TextInputType keyboardType;
  final String? errorText;

  @override
  State<_TextFieldInput> createState() => _TextFieldInputState();
}

class _TextFieldInputState extends State<_TextFieldInput> {
  late final TextEditingController _controller;

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
    _controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChanged);
    _controller.dispose();
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

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.field.placeholder?.trim();
    final hint = placeholder?.isNotEmpty == true
        ? placeholder!
        : switch (widget.field.type) {
            'number' => 'Enter a number',
            'email' => 'Enter an email address',
            'phone' => 'Enter a phone number',
            _ => 'Your answer',
          };

    return TextField(
      controller: _controller,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.field.type == 'phone'
          ? const [PhilippinesPhoneInputFormatter()]
          : null,
      scrollPadding: EdgeInsets.zero,
      onTapOutside: _unfocusWithoutScroll,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: AppColors.primaryColor,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w500,
        ),
        isDense: true,
        filled: false,
        contentPadding: const EdgeInsets.only(
          left: 2,
          right: 2,
          top: 14,
          bottom: 10,
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.primaryBorder),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red, width: 2),
        ),
        errorText: widget.errorText,
        helperText: _constraintHint(widget.field),
        helperStyle: TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.35,
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
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final placeholder = field.placeholder?.trim();
    final hintText = placeholder?.isNotEmpty == true
        ? placeholder!
        : field.required == true
        ? 'Choose an option'
        : 'Optional';
    return AdminDropdownFormField<String>(
      initialValue: initialValue is String ? initialValue : null,
      isExpanded: true,
      iconEnabledColor: AppColors.primaryColor,
      style: adminDropdownDisplayTextStyle,
      decoration: adminPlainDropdownDecoration(
        hintText,
      ).copyWith(errorText: errorText),
      items: field.options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option,
              child: Text(
                option,
                overflow: TextOverflow.ellipsis,
                style: adminDropdownDisplayTextStyle,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _CheckboxFieldInput extends StatefulWidget {
  const _CheckboxFieldInput({
    required this.field,
    required this.initialValue,
    required this.onChanged,
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
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
                        ? appFieldInteractiveFillColor(context)
                        : AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primaryBorder),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _selected.contains(option),
                        onChanged: (value) => _toggle(option, value ?? false),
                        activeColor: AppColors.primaryColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          option,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
              style: const TextStyle(color: Colors.red, fontSize: 12),
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
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final String? errorText;

  @override
  State<_DateFieldInput> createState() => _DateFieldInputState();
}

class _DateFieldInputState extends State<_DateFieldInput> {
  DateTime? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue is String
        ? DateTime.tryParse(widget.initialValue as String)
        : null;
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
        ? (widget.field.placeholder?.trim().isNotEmpty == true
              ? widget.field.placeholder!.trim()
              : 'Select a date')
        : _formatDateLabel(_value!);

    return _PickerFieldShell(
      text: display,
      isPlaceholder: _value == null,
      icon: Icons.calendar_today_rounded,
      errorText: widget.errorText,
      onTap: _pickDate,
    );
  }
}

class _TimeFieldInput extends StatefulWidget {
  const _TimeFieldInput({
    required this.field,
    required this.initialValue,
    required this.onChanged,
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final String? errorText;

  @override
  State<_TimeFieldInput> createState() => _TimeFieldInputState();
}

class _TimeFieldInputState extends State<_TimeFieldInput> {
  TimeOfDay? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue is String
        ? _parseTime(widget.initialValue as String)
        : null;
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
        ? (widget.field.placeholder?.trim().isNotEmpty == true
              ? widget.field.placeholder!.trim()
              : 'Select a time')
        : _value!.format(context);

    return _PickerFieldShell(
      text: display,
      isPlaceholder: _value == null,
      icon: Icons.schedule_rounded,
      errorText: widget.errorText,
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
    this.errorText,
  });

  final String text;
  final bool isPlaceholder;
  final IconData icon;
  final VoidCallback onTap;
  final String? errorText;

  @override
  State<_PickerFieldShell> createState() => _PickerFieldShellState();
}

class _PickerFieldShellState extends State<_PickerFieldShell> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final activeFillColor = appFieldInteractiveFillColor(context);
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
                        : AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: widget.errorText == null
                          ? AppColors.primaryBorder
                          : Colors.red,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.text,
                          style: TextStyle(
                            color: widget.isPlaceholder
                                ? AppColors.primaryColor.withValues(alpha: 0.72)
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Icon(
                        widget.icon,
                        size: 18,
                        color: AppColors.primaryColor,
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
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.errorText!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
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
    this.errorText,
  });

  final StatusField field;
  final dynamic initialValue;
  final ValueChanged<dynamic> onChanged;
  final String? errorText;

  @override
  State<_PhotoFieldInput> createState() => _PhotoFieldInputState();
}

class _PhotoFieldInputState extends State<_PhotoFieldInput> {
  @override
  Widget build(BuildContext context) {
    return BookingPhotoFieldInput(
      initialValue: widget.initialValue,
      errorText: widget.errorText,
      placeholder: ((widget.field.placeholder ?? '').trim().isNotEmpty
          ? widget.field.placeholder!.trim()
          : 'Upload a photo'),
      showRemoveAction: true,
      onChanged: widget.onChanged,
    );
  }
}

String? _constraintHint(StatusField field) {
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

String _formatTimeValue(TimeOfDay value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
