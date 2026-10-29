import 'package:webapp/services/status_field_option_resolver.dart';
import 'package:webapp/services/client_representative_suggestions.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/widgets/shared/booking_form_primitives.dart';
import 'package:webapp/widgets/status_form/status_form_runtime_fields.dart';

class StatusFormPreview extends StatefulWidget {
  const StatusFormPreview({
    super.key,
    required this.form,
    required this.fields,
    this.titleText,
    this.subtitleText,
    this.clientId,
  });

  final StatusForm? form;
  final List<StatusField> fields;
  final String? titleText;
  final String? subtitleText;
  final String? clientId;

  @override
  State<StatusFormPreview> createState() => _StatusFormPreviewState();
}

class _StatusFormPreviewState extends State<StatusFormPreview> {
  final _optionResolver = StatusFieldOptionResolver();
  final _phoneAutofill = RepresentativePhoneAutofill();

  @override
  void initState() {
    super.initState();
    _optionResolver.hydrateFieldsFromResolvedSnapshots(widget.fields);
  }

  @override
  void didUpdateWidget(covariant StatusFormPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.fields, widget.fields)) {
      _optionResolver.hydrateFieldsFromResolvedSnapshots(widget.fields);
    }
    if (oldWidget.clientId != widget.clientId ||
        oldWidget.form?.id != widget.form?.id) {
      _phoneAutofill.reset();
    }
  }

  String? get _selectedClientId => _answers.containsKey('client_id')
      ? representativeClientSelectionId(
          _answers['client_id']?.toString(),
          AuthRequest.hydratedUsersSnapshot,
        )
      : widget.clientId;

  final StatusFormEngine _engine = StatusFormEngine(StatusRequest.instance);
  Map<String, dynamic> _answers = {};
  Map<String, String> _errors = {};
  int _resetTick = 0;
  final Map<String, FocusNode> _fieldFocusNodes = {};
  final FocusNode _submitFocusNode = FocusNode(
    debugLabel: 'booking_field(__cta__)',
  );

  String _focusKeyForField(StatusField field, int index) {
    final key = (field.key ?? '').trim();
    if (key.isNotEmpty) {
      return key;
    }
    final title = (field.title ?? '').trim();
    final type = (field.type ?? '').trim();
    return '__index_$index:${title.isEmpty ? '-' : title}|${type.isEmpty ? '-' : type}';
  }

  void _syncFocusNodes(List<StatusField> fields) {
    final activeKeys = <String>{};
    for (var index = 0; index < fields.length; index++) {
      final field = fields[index];
      final focusKey = _focusKeyForField(field, index);
      activeKeys.add(focusKey);
      _fieldFocusNodes.putIfAbsent(
        focusKey,
        () => FocusNode(debugLabel: 'booking_field($focusKey)'),
      );
    }
    final removedKeys = _fieldFocusNodes.keys
        .where((key) => !activeKeys.contains(key))
        .toList();
    for (final key in removedKeys) {
      _fieldFocusNodes.remove(key)?.dispose();
    }
  }

  void _moveToNextVisibleFieldAfterSelection(
    StatusField currentField,
    dynamic nextValue,
  ) {
    final currentFieldKey = currentField.key?.trim();
    if (currentFieldKey == null || currentFieldKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        FocusScope.of(context).unfocus();
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      FocusScope.of(context).unfocus();
    });
  }

  void _updateAnswer(String key, dynamic value) {
    if (key == 'representative_phone') _phoneAutofill.markManualEdit();
    final nextAnswers = Map<String, dynamic>.from(_answers);
    if (_isEmptyValue(value)) {
      nextAnswers.remove(key);
    } else {
      nextAnswers[key] = value;
    }
    setState(() {
      _answers = nextAnswers;
      _errors = Map<String, String>.from(_errors)..remove(key);
    });
  }

  void _clearForm() {
    _phoneAutofill.reset();
    setState(() {
      _answers = {};
      _errors = {};
      _resetTick += 1;
    });
  }

  void _validateForm() {
    final visibleFields = StatusFormEngine.visibleFields(
      _effectiveFields,
      _answers,
    );
    setState(() {
      _errors = _engine.validateFields(visibleFields, _answers);
    });
  }

  List<StatusField> get _effectiveFields {
    final form = widget.form;
    if (form == null || form.fieldOverrides.isEmpty) {
      return widget.fields;
    }
    return widget.fields
        .map((field) {
          final fieldId = field.id?.trim();
          if (fieldId == null || fieldId.isEmpty) {
            return field;
          }
          final override = form.fieldOverrides[fieldId];
          if (override == null) {
            return field;
          }
          return field.copyWith(
            required: override.required,
            placeholder: override.placeholder,
          );
        })
        .toList(growable: false);
  }

  static bool _isEmptyValue(dynamic value) {
    if (value == null) {
      return true;
    }
    if (value is String) {
      return value.trim().isEmpty;
    }
    if (value is List) {
      return value.isEmpty;
    }
    if (value is Map) {
      return value.isEmpty;
    }
    return false;
  }

  @override
  void dispose() {
    for (final node in _fieldFocusNodes.values) {
      node.dispose();
    }
    _submitFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trimmedOverrideTitle = widget.titleText?.trim();
    final trimmedFormTitle = widget.form?.statusText?.trim();
    final statusText =
        trimmedOverrideTitle != null && trimmedOverrideTitle.isNotEmpty
        ? trimmedOverrideTitle
        : trimmedFormTitle;
    final statusSubtext =
        widget.subtitleText?.trim() ?? widget.form?.statusSubtext?.trim();
    final buttonText = widget.form?.buttonText?.trim();
    final resolvedTitle = statusText?.isNotEmpty == true
        ? statusText!
        : 'Untitled Status Form';
    final currentStatusKey = widget.form?.currentStatusKey?.trim();
    final nextStatusKey = widget.form?.nextStatusKey?.trim();
    final palette = bookingFormResolvedStatusPalette(
      title: resolvedTitle,
      buttonText: buttonText,
      currentStatusKey: currentStatusKey,
    );
    final dependencies =
        widget.form?.dependencies ?? const <StatusDependency>[];
    final effectiveFields = _effectiveFields;
    final visibleFields = _optionResolver.withClientRepresentativeSuggestions(
      StatusFormEngine.visibleFields(effectiveFields, _answers),
      clientId: _selectedClientId,
      answers: _answers,
    );
    _syncFocusNodes(visibleFields);
    final hasFields = visibleFields.isNotEmpty;
    final hasNextStatus = nextStatusKey != null && nextStatusKey.isNotEmpty;
    final showSubmitButton = hasFields || hasNextStatus;
    final showActionRow = showSubmitButton || hasFields;
    final actionRowTopSpacing = effectiveFields.isEmpty ? 14.0 : 6.0;

    return BookingFormOuterShell(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PreviewHeaderCard(
            title: resolvedTitle,
            subtitle: statusSubtext,
            buttonText: buttonText,
            currentStatusKey: currentStatusKey,
            showRequiredLegend: visibleFields.any(
              (field) => field.required == true,
            ),
            showDependencyNotice: dependencies.isNotEmpty,
          ),
          if (hasFields) ...[
            const SizedBox(height: 14),
            ...visibleFields.map((field) {
              final index = visibleFields.indexOf(field);
              final isLastField = index == visibleFields.length - 1;
              final nextField = isLastField ? null : visibleFields[index + 1];
              final focusKey = _focusKeyForField(field, index);
              final nextFocusKey = nextField == null
                  ? null
                  : _focusKeyForField(nextField, index + 1);
              final focusNode = _fieldFocusNodes[focusKey];
              final nextFocusNode = isLastField
                  ? _submitFocusNode
                  : (nextFocusKey == null
                        ? null
                        : _fieldFocusNodes[nextFocusKey]);
              final nextFieldType = (nextField?.type ?? '')
                  .trim()
                  .toLowerCase();
              final activateNextFocus =
                  isLastField ||
                  nextFieldType == 'date' ||
                  nextFieldType == 'time' ||
                  nextFieldType == 'photo';
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: StatusFormRuntimeFieldCard(
                  key: ValueKey('${field.key}:$_resetTick'),
                  field: field,
                  focusNode: focusNode,
                  nextFocusNode: nextFocusNode,
                  activateNextFocus: activateNextFocus,
                  onAdvanceAfterSelection: (value) =>
                      _moveToNextVisibleFieldAfterSelection(field, value),
                  initialValue: _answers[field.key],
                  errorText: _errors[field.key],
                  formTitle: resolvedTitle,
                  formButtonText: buttonText,
                  formStatusKey: currentStatusKey,
                  workflowLayout: true,
                  suggestionDetail: (name) =>
                      _optionResolver.representativePhone(
                        _selectedClientId,
                        name,
                      ) ??
                      'Walang phone number',
                  onSuggestionSelected: (name) {
                    if (!field.usesClientRepresentativeSuggestions ||
                        field.key != 'representative_name' ||
                        !visibleFields.any(
                          (f) => f.key == 'representative_phone',
                        )) {
                      return;
                    }
                    final phone = _optionResolver.representativePhone(
                      _selectedClientId,
                      name,
                    );
                    final value = _phoneAutofill.valueForSelection(
                      suggestedPhone: phone,
                      currentPhone: _answers['representative_phone']
                          ?.toString(),
                    );
                    if (value != null) {
                      setState(() {
                        _answers = {..._answers, 'representative_phone': value};
                        _errors = {..._errors}..remove('representative_phone');
                      });
                    }
                  },
                  onChanged: (value) {
                    final key = field.key;
                    if (key == null || key.isEmpty) {
                      return;
                    }
                    _updateAnswer(key, value);
                  },
                ),
              );
            }),
          ],
          if (showActionRow) ...[
            SizedBox(height: actionRowTopSpacing),
            Row(
              children: [
                if (showSubmitButton)
                  FilledButton(
                    onPressed: _validateForm,
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      buttonText?.isNotEmpty == true ? buttonText! : 'Submit',
                    ),
                  ),
                if (hasFields) ...[
                  const Spacer(),
                  TextButton(
                    onPressed: _clearForm,
                    style: TextButton.styleFrom(
                      foregroundColor: palette.accent,
                    ),
                    child: const Text('Clear Form'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewHeaderCard extends StatelessWidget {
  const _PreviewHeaderCard({
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.currentStatusKey,
    required this.showRequiredLegend,
    required this.showDependencyNotice,
  });

  final String title;
  final String? subtitle;
  final String? buttonText;
  final String? currentStatusKey;
  final bool showRequiredLegend;
  final bool showDependencyNotice;

  @override
  Widget build(BuildContext context) {
    final palette = bookingFormResolvedStatusPalette(
      title: title,
      buttonText: buttonText,
      currentStatusKey: currentStatusKey,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BookingFormHeaderCard(
          title: title,
          subtitle: subtitle,
          buttonText: buttonText,
          paletteOverride: palette,
          showRequiredLegend: showRequiredLegend,
        ),
        if (showDependencyNotice) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: bookingFormContentHorizontalPadding,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: palette.accent,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This form has dependency rules before it can be submitted.',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
