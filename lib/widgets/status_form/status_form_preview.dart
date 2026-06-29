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
  });

  final StatusForm? form;
  final List<StatusField> fields;
  final String? titleText;
  final String? subtitleText;

  @override
  State<StatusFormPreview> createState() => _StatusFormPreviewState();
}

class _StatusFormPreviewState extends State<StatusFormPreview> {
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

  bool _shouldActivateNextField(StatusField? nextField, FocusNode? nextFocus) {
    if (nextFocus == null) {
      return false;
    }
    if (nextField == null) {
      return true;
    }
    final nextFieldType = (nextField.type ?? '').trim().toLowerCase();
    return nextFieldType == 'dropdown' ||
        nextFieldType == 'search_dropdown' ||
        nextFieldType == 'date' ||
        nextFieldType == 'time' ||
        nextFieldType == 'photo';
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
        FocusScope.of(context).requestFocus(_submitFocusNode);
      });
      return;
    }

    final nextAnswers = Map<String, dynamic>.from(_answers);
    if (_isEmptyValue(nextValue)) {
      nextAnswers.remove(currentFieldKey);
    } else {
      nextAnswers[currentFieldKey] = nextValue;
    }

    final visibleFields = StatusFormEngine.visibleFields(widget.fields, nextAnswers);
    final currentIndex = visibleFields.indexWhere((field) {
      final fieldKey = field.key?.trim();
      if (fieldKey?.isNotEmpty == true && fieldKey == currentFieldKey) {
        return true;
      }
      return field.id != null && field.id == currentField.id;
    });
    final nextField =
        currentIndex >= 0 && currentIndex + 1 < visibleFields.length
        ? visibleFields[currentIndex + 1]
        : null;
    final nextFocusKey = nextField == null
        ? null
        : _focusKeyForField(nextField, currentIndex + 1);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final resolvedNextFocusNode = nextField == null
          ? _submitFocusNode
          : (nextFocusKey == null ? null : _fieldFocusNodes[nextFocusKey]);
      if (resolvedNextFocusNode == null) {
        FocusScope.of(context).unfocus();
        return;
      }
      FocusScope.of(context).requestFocus(resolvedNextFocusNode);
      if (_shouldActivateNextField(nextField, resolvedNextFocusNode)) {
        final primaryFocus = FocusManager.instance.primaryFocus;
        final targetContext =
            primaryFocus?.context ?? resolvedNextFocusNode.context;
        if (targetContext != null) {
          Actions.maybeInvoke(targetContext, const ActivateIntent());
        }
      }
    });
  }

  void _updateAnswer(String key, dynamic value) {
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
    setState(() {
      _answers = {};
      _errors = {};
      _resetTick += 1;
    });
  }

  void _validateForm() {
    final visibleFields = StatusFormEngine.visibleFields(widget.fields, _answers);
    setState(() {
      _errors = _engine.validateFields(visibleFields, _answers);
    });
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
    final visibleFields = StatusFormEngine.visibleFields(widget.fields, _answers);
    _syncFocusNodes(visibleFields);
    final hasFields = visibleFields.isNotEmpty;
    final hasNextStatus = nextStatusKey != null && nextStatusKey.isNotEmpty;
    final showSubmitButton = hasFields || hasNextStatus;
    final showActionRow = showSubmitButton || hasFields;
    final actionRowTopSpacing = widget.fields.isEmpty ? 14.0 : 6.0;

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
            ...visibleFields.map(
              (field) {
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
                final nextFieldType =
                    (nextField?.type ?? '').trim().toLowerCase();
                final activateNextFocus =
                    isLastField ||
                    nextFieldType == 'dropdown' ||
                    nextFieldType == 'search_dropdown' ||
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
                  onChanged: (value) {
                    final key = field.key;
                    if (key == null || key.isEmpty) {
                      return;
                    }
                    _updateAnswer(key, value);
                  },
                ),
              );
              },
            ),
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
    return BookingFormTitleCardShell(
      stripColor: bookingFormResolvedStripColor(
        title: title,
        buttonText: buttonText,
        fallbackColor: palette.strip,
      ),
      borderColor: palette.border,
      bodyColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if (subtitle?.trim().isNotEmpty == true) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!.trim(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if (showRequiredLegend) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 1,
              color: palette.border,
            ),
            const SizedBox(height: 14),
            Text(
              '* indicates required input',
              style: TextStyle(
                color: bookingFormResolvedLegendColor(
                  title: title,
                  buttonText: buttonText,
                ),
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
            ),
          ],
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
      ),
    );
  }
}
