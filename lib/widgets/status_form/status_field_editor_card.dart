import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/utils/display_text.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';

class StatusFieldEditorCard extends StatelessWidget {
  const StatusFieldEditorCard({
    super.key,
    required this.field,
    required this.index,
    required this.fieldTypeOptions,
    required this.onUpdate,
    this.onRemove,
    this.showContainer = true,
    this.sectionGap = 14,
    this.headerBottomGap = 16,
    this.toggleTopGap = 8,
    this.toggleGap = 4,
  });

  final StatusField field;
  final int index;
  final List<String> fieldTypeOptions;
  final void Function(String property, dynamic value) onUpdate;
  final VoidCallback? onRemove;
  final bool showContainer;
  final double sectionGap;
  final double headerBottomGap;
  final double toggleTopGap;
  final double toggleGap;

  @override
  Widget build(BuildContext context) {
    final fieldType = field.type?.trim() ?? '';
    final supportsRange = _supportsRange(fieldType);
    final optionSourceKey =
        StatusField.normalizedOptionSourceKey(field.optionSourceKey) ??
        statusFieldOptionSourceStatic;
    final usesDynamicOptions =
        fieldType == 'dropdown' && _usesDynamicOptionSource(optionSourceKey);
    final showStaticChoices =
        fieldType == 'checkbox' ||
        (fieldType == 'dropdown' && !usesDynamicOptions);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onRemove != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Field ${index + 1}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD94B4B),
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: headerBottomGap),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 980;

            if (isNarrow) {
              return Column(
                children: [
                  _fullWidthField(
                    child: _dropdownField(
                      label: 'Type',
                      initialValue: fieldTypeOptions.contains(field.type)
                          ? field.type
                          : null,
                      items: fieldTypeOptions
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item,
                              child: Text(
                                humanizeDropdownValue(item),
                                style: adminDropdownDisplayTextStyle,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => onUpdate('type', value),
                    ),
                  ),
                  if (fieldType == 'dropdown') ...[
                    SizedBox(height: 10),
                    _fullWidthField(
                      child: _dropdownField(
                        label: 'Source',
                        initialValue: optionSourceKey,
                        items: _optionSourceItems(),
                        onChanged: (value) =>
                            onUpdate('optionSourceKey', value),
                      ),
                    ),
                    if (showStaticChoices) ...[
                      SizedBox(height: 10),
                      _fullWidthField(
                        child: _valueField(
                          label: 'Options',
                          initialValue: field.options.join(', '),
                          onChanged: (value) => onUpdate(
                            'options',
                            value
                                .split(',')
                                .map((item) => item.trim())
                                .where((item) => item.isNotEmpty)
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ],
                  SizedBox(height: showStaticChoices ? 4 : 8),
                  _fullWidthField(
                    child: _valueField(
                      label: 'Title',
                      initialValue: field.title,
                      onChanged: (value) => onUpdate('title', value),
                    ),
                  ),
                  SizedBox(height: 4),
                  _fullWidthField(
                    child: _valueField(
                      label: 'Subtitle',
                      initialValue: field.subtitle,
                      onChanged: (value) => onUpdate('subtitle', value),
                    ),
                  ),
                  SizedBox(height: 4),
                  _fullWidthField(
                    child: _valueField(
                      label: 'Field Key',
                      initialValue: field.key,
                      onChanged: (value) => onUpdate('key', value),
                    ),
                  ),
                  SizedBox(height: 4),
                  _fullWidthField(
                    child: _valueField(
                      key: ValueKey('placeholder-$fieldType-${field.required}'),
                      label: 'Placeholder',
                      initialValue: field.placeholder,
                      onChanged: (value) => onUpdate('placeholder', value),
                    ),
                  ),
                  SizedBox(height: 4),
                  _fullWidthField(
                    child: _valueField(
                      label: 'Instructions',
                      initialValue: field.instructions,
                      onChanged: (value) => onUpdate('instructions', value),
                    ),
                  ),
                  if (supportsRange) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: _valueField(
                            label: _minLabel(fieldType),
                            initialValue: field.min?.toString(),
                            keyboardType: TextInputType.number,
                            onChanged: (value) =>
                                onUpdate('min', int.tryParse(value)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _valueField(
                            label: _maxLabel(fieldType),
                            initialValue: field.max?.toString(),
                            keyboardType: TextInputType.number,
                            onChanged: (value) =>
                                onUpdate('max', int.tryParse(value)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: 4),
                  _fullWidthField(
                    child: _valueField(
                      label: 'Required Error',
                      initialValue: field.requiredError,
                      onChanged: (value) => onUpdate('requiredError', value),
                    ),
                  ),
                  SizedBox(height: 4),
                  _fullWidthField(
                    child: _valueField(
                      label: 'Validation Error',
                      initialValue: field.validationError,
                      onChanged: (value) => onUpdate('validationError', value),
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _dropdownField(
                        label: 'Type',
                        initialValue: fieldTypeOptions.contains(field.type)
                            ? field.type
                            : null,
                        items: fieldTypeOptions
                            .map(
                              (item) => DropdownMenuItem<String>(
                                value: item,
                                child: Text(
                                  humanizeDropdownValue(item),
                                  style: adminDropdownDisplayTextStyle,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => onUpdate('type', value),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: _valueField(
                        label: 'Title',
                        initialValue: field.title,
                        onChanged: (value) => onUpdate('title', value),
                      ),
                    ),
                  ],
                ),
                if (fieldType == 'dropdown') ...[
                  SizedBox(height: 10),
                  _dropdownField(
                    label: 'Source',
                    initialValue: optionSourceKey,
                    items: _optionSourceItems(),
                    onChanged: (value) => onUpdate('optionSourceKey', value),
                  ),
                  if (showStaticChoices) ...[
                    SizedBox(height: 10),
                    _valueField(
                      label: 'Options',
                      initialValue: field.options.join(', '),
                      onChanged: (value) => onUpdate(
                        'options',
                        value
                            .split(',')
                            .map((item) => item.trim())
                            .where((item) => item.isNotEmpty)
                            .toList(),
                      ),
                    ),
                  ],
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _valueField(
                        label: 'Subtitle',
                        initialValue: field.subtitle,
                        onChanged: (value) => onUpdate('subtitle', value),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _valueField(
                        label: 'Field Key',
                        initialValue: field.key,
                        onChanged: (value) => onUpdate('key', value),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _valueField(
                        key: ValueKey(
                          'placeholder-$fieldType-${field.required}',
                        ),
                        label: 'Placeholder',
                        initialValue: field.placeholder,
                        onChanged: (value) => onUpdate('placeholder', value),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                _valueField(
                  label: 'Instructions',
                  initialValue: field.instructions,
                  onChanged: (value) => onUpdate('instructions', value),
                ),
                if (supportsRange) ...[
                  SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (supportsRange) ...[
                        Expanded(
                          child: _valueField(
                            label: _minLabel(fieldType),
                            initialValue: field.min?.toString(),
                            keyboardType: TextInputType.number,
                            onChanged: (value) =>
                                onUpdate('min', int.tryParse(value)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _valueField(
                            label: _maxLabel(fieldType),
                            initialValue: field.max?.toString(),
                            keyboardType: TextInputType.number,
                            onChanged: (value) =>
                                onUpdate('max', int.tryParse(value)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                SizedBox(height: 4),
                _valueField(
                  label: 'Required Error',
                  initialValue: field.requiredError,
                  onChanged: (value) => onUpdate('requiredError', value),
                ),
                SizedBox(height: 4),
                _valueField(
                  label: 'Validation Error',
                  initialValue: field.validationError,
                  onChanged: (value) => onUpdate('validationError', value),
                ),
              ],
            );
          },
        ),
        Padding(
          padding: EdgeInsets.only(top: 4),
          child: _toggle(
            context: context,
            title: 'Required',
            value: field.required ?? false,
            onChanged: (value) => onUpdate('required', value),
          ),
        ),
        SizedBox(height: 8),
        _toggle(
          context: context,
          title: 'Active',
          value: field.isActive ?? true,
          onChanged: (value) => onUpdate('isActive', value),
        ),
      ],
    );

    if (!showContainer) {
      return content;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: content,
    );
  }

  static Widget _fullWidthField({required Widget child}) {
    return SizedBox(width: double.infinity, child: child);
  }

  static Widget _valueField({
    Key? key,
    required String label,
    String? initialValue,
    ValueChanged<String>? onChanged,
    TextInputType? keyboardType,
  }) {
    return AdminModalValueTextField(
      key: key,
      label: label,
      initialValue: initialValue,
      bottomPadding: 0,
      keyboardType: keyboardType,
      onChanged: onChanged,
    );
  }

  static Widget _dropdownField({
    required String label,
    required List<DropdownMenuItem<String>> items,
    String? initialValue,
    ValueChanged<String?>? onChanged,
  }) {
    return AdminModalDropdownField<String>(
      label: label,
      initialValue: initialValue,
      bottomPadding: 0,
      items: items,
      onChanged: onChanged,
    );
  }

  static Widget _toggle({
    required BuildContext context,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AdminModalToggleRow(
      title: title,
      value: value,
      onChanged: onChanged,
      leftInset: 0,
      rightInset: 0,
    );
  }

  static bool _usesDynamicOptionSource(String? sourceKey) {
    return statusFieldDynamicOptionSources.contains(sourceKey);
  }

  static List<DropdownMenuItem<String>> _optionSourceItems() {
    const orderedSourceKeys = <String>[
      statusFieldOptionSourceStatic,
      statusFieldOptionSourceUsers,
      statusFieldOptionSourceClients,
      statusFieldOptionSourceAdmins,
      statusFieldOptionSourceDrivers,
      statusFieldOptionSourceHelpers,
      statusFieldOptionSourceVehicleMakes,
      statusFieldOptionSourceVehicleTypes,
      statusFieldOptionSourceVehicleSizes,
      statusFieldOptionSourceStatuses,
      statusFieldOptionSourceForms,
      statusFieldOptionSourceFields,
      statusFieldOptionSourceBookings,
    ];
    return orderedSourceKeys
        .map(
          (sourceKey) => DropdownMenuItem<String>(
            value: sourceKey,
            child: Text(
              statusFieldOptionSourceLabels[sourceKey] ?? sourceKey,
              style: adminDropdownDisplayTextStyle,
            ),
          ),
        )
        .toList();
  }

  static bool _supportsRange(String type) {
    return switch (type) {
      'text' || 'number' || 'checkbox' => true,
      _ => false,
    };
  }

  static String _minLabel(String type) {
    return switch (type) {
      'text' => 'Minimum Length',
      'number' => 'Minimum Value',
      'checkbox' => 'Minimum Items',
      _ => 'Minimum',
    };
  }

  static String _maxLabel(String type) {
    return switch (type) {
      'text' => 'Maximum Length',
      'number' => 'Maximum Value',
      'checkbox' => 'Maximum Items',
      _ => 'Maximum',
    };
  }
}
