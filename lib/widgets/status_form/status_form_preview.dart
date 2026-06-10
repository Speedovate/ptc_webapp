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
    setState(() {
      _errors = _engine.validateFields(widget.fields, _answers);
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
  Widget build(BuildContext context) {
    final statusText =
        widget.titleText?.trim() ?? widget.form?.statusText?.trim();
    final statusSubtext =
        widget.subtitleText?.trim() ?? widget.form?.statusSubtext?.trim();
    final buttonText = widget.form?.buttonText?.trim();
    final dependencies =
        widget.form?.dependencies ?? const <StatusDependency>[];
    final actionRowTopSpacing = widget.fields.isEmpty ? 14.0 : 6.0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF3EDFf),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.primaryColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PreviewHeaderCard(
                  title: statusText?.isNotEmpty == true
                      ? statusText!
                      : 'Untitled Status Form',
                  subtitle: statusSubtext,
                  showRequiredLegend: widget.fields.any(
                    (field) => field.required == true,
                  ),
                  showDependencyNotice: dependencies.isNotEmpty,
                ),
                const SizedBox(height: 14),
                if (widget.fields.isEmpty)
                  const _EmptyPreviewState()
                else
                  ...widget.fields.map(
                    (field) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: StatusFormRuntimeFieldCard(
                        key: ValueKey('${field.key}:$_resetTick'),
                        field: field,
                        initialValue: _answers[field.key],
                        errorText: _errors[field.key],
                        onChanged: (value) {
                          final key = field.key;
                          if (key == null || key.isEmpty) {
                            return;
                          }
                          _updateAnswer(key, value);
                        },
                      ),
                    ),
                  ),
                SizedBox(height: actionRowTopSpacing),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _validateForm,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
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
                    if (widget.fields.isNotEmpty) ...[
                      const Spacer(),
                      TextButton(
                        onPressed: _clearForm,
                        child: const Text('Clear Form'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewHeaderCard extends StatelessWidget {
  const _PreviewHeaderCard({
    required this.title,
    required this.subtitle,
    required this.showRequiredLegend,
    required this.showDependencyNotice,
  });

  final String title;
  final String? subtitle;
  final bool showRequiredLegend;
  final bool showDependencyNotice;

  @override
  Widget build(BuildContext context) {
    return BookingFormTitleCardShell(
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
              color: AppColors.primaryBorder,
            ),
            const SizedBox(height: 14),
            const Text(
              '* indicates required input',
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
            ),
          ],
          if (showDependencyNotice) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primaryBorder),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppColors.primaryColor,
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

class _EmptyPreviewState extends StatelessWidget {
  const _EmptyPreviewState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: const Text(
        'No fields yet. Add fields to see how the actual form will look.',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
