import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/services/kpi/kpi_rating_rules.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';

class SharedKpiRulesDialog extends StatefulWidget {
  const SharedKpiRulesDialog({
    super.key,
    required this.store,
    required this.onBack,
    this.backLabel = 'Go Back',
    this.onSaved,
  });
  final PmKpiStore store;
  final VoidCallback onBack;
  final String backLabel;
  final VoidCallback? onSaved;
  @override
  State<SharedKpiRulesDialog> createState() => _SharedKpiRulesDialogState();
}

class _SharedKpiRulesDialogState extends State<SharedKpiRulesDialog> {
  static const labels = [
    'Gross income: Satisfactory from (%)',
    'Gross income: Excellent from (%)',
    'Complaints: Excellent up to',
    'Complaints: Satisfactory up to',
    'Accidents: Excellent up to',
    'Gross income target (%)',
  ];
  final controllers = <TextEditingController>[];
  Map<String, dynamic> _document = {};
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final document = await widget.store.loadFleetRules().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) return;
      final rules = KpiRatingRules.fromMap(document);
      setState(() {
        _document = document;
        _error = null;
        for (final c in controllers) {
          c.dispose();
        }
        controllers.clear();
        for (final value in [
          rules.grossSatisfactoryMin,
          rules.grossExcellentMin,
          rules.complaintsExcellentMax,
          rules.complaintsSatisfactoryMax,
          rules.accidentsExcellentMax,
          rules.targetPercent,
        ]) {
          controllers.add(TextEditingController(text: '$value'));
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Rules could not be loaded. Please retry.');
      }
    }
  }

  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: RoleAccessService.instance,
    builder: (context, _) {
      if (!widget.store.canRead || !widget.store.canEdit) {
        return AdminModalShell(
          title: 'Rules',
          actions: [
            TextButton(onPressed: widget.onBack, child: Text(widget.backLabel)),
          ],
          child: const Text('You do not have access to edit KPI rules.'),
        );
      }
      if (controllers.isEmpty) {
        return AdminModalShell(
          title: 'Rules',
          maxWidth: AdminModalShell.kpiMaxWidth,
          actions: [
            TextButton(onPressed: widget.onBack, child: Text(widget.backLabel)),
          ],
          child: _error == null
              ? const AppPageLoading(compact: true)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
        );
      }
      final dialogContext = context;
      return StatefulBuilder(
        builder: (context, update) => AdminModalShell(
          maxWidth: AdminModalShell.kpiMaxWidth,
          title: 'Rules',
          flexibleBody: true,
          bodyHandlesScrolling: true,
          actions: [
            TextButton(onPressed: widget.onBack, child: Text(widget.backLabel)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AdminModalRecordList(
              horizontalOnDesktop: true,
              trailingActions: true,
              titles: const ['Rule', 'Value', 'Actions'],
              itemCount: labels.length,
              columnExtraWidths: const {2: 40},
              valuesAt: (row) {
                final i = const [0, 1, 3, 2, 4, 5][row];
                return [labels[i], controllers[i].text, ''];
              },
              cellBuilder: (row, column) {
                if (column != 2) return null;
                final i = const [0, 1, 3, 2, 4, 5][row];
                return AdminListActionButton(
                  key: ValueKey('kpi-rule-edit-$i'),
                  icon: Icons.edit_outlined,
                  onTap: () async {
                    final editor = TextEditingController(
                      text: controllers[i].text,
                    );
                    String? editError;
                    bool saving = false;
                    final edited = await showAppDialog<String>(
                      context: dialogContext,
                      builder: (editContext) => StatefulBuilder(
                        builder: (context, editUpdate) => AdminModalShell(
                          maxWidth: 420,
                          title: 'Edit Rule',
                          actions: [
                            TextButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(editContext),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final values = controllers
                                          .map((c) => c.text.trim())
                                          .toList();
                                      values[i] = editor.text.trim();
                                      final nums = values
                                          .map(double.tryParse)
                                          .toList();
                                      if (nums.any(
                                            (n) => n == null || !n.isFinite,
                                          ) ||
                                          nums
                                              .skip(2)
                                              .take(3)
                                              .any(
                                                (n) =>
                                                    n != n!.truncateToDouble(),
                                              )) {
                                        editUpdate(
                                          () => editError =
                                              'Enter valid percentages and whole-number counts.',
                                        );
                                        return;
                                      }
                                      final rules = KpiRatingRules(
                                        grossSatisfactoryMin: nums[0]!,
                                        grossExcellentMin: nums[1]!,
                                        complaintsExcellentMax: nums[2]!
                                            .toInt(),
                                        complaintsSatisfactoryMax: nums[3]!
                                            .toInt(),
                                        accidentsExcellentMax: nums[4]!.toInt(),
                                        targetPercent: nums[5]!,
                                      );
                                      if (!rules.valid) {
                                        editUpdate(
                                          () => editError =
                                              'Check threshold order, percentages (0–100), and nonnegative counts.',
                                        );
                                        return;
                                      }
                                      editUpdate(() {
                                        saving = true;
                                        editError = null;
                                      });
                                      try {
                                        // Each edit uses the latest persisted version, including prior offline saves.
                                        await widget.store.saveFleetRules(
                                          rules,
                                          _document,
                                        );
                                        _document = await widget.store
                                            .loadFleetRules(localOnly: true);
                                        widget.onSaved?.call();
                                        if (editContext.mounted) {
                                          Navigator.pop(editContext, values[i]);
                                        }
                                      } catch (failure) {
                                        if (editContext.mounted) {
                                          editUpdate(() {
                                            saving = false;
                                            editError =
                                                failure is TimeoutException
                                                ? 'Saving took too long. Please try again.'
                                                : failure.toString();
                                          });
                                        }
                                      }
                                    },
                              child: Text(saving ? 'Saving…' : 'Save'),
                            ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: editor,
                                  enabled: !saving,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: adminFormInputDecoration(
                                    labels[i],
                                  ),
                                ),
                                if (editError != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    editError!,
                                    style: const TextStyle(
                                      color: AppColors.dangerStrong,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                    await Future<void>.delayed(
                      const Duration(milliseconds: 300),
                    );
                    await Future<void>.delayed(
                      const Duration(milliseconds: 300),
                    );
                    editor.dispose();
                    if (!dialogContext.mounted || edited == null) return;
                    update(() {
                      controllers[i].text = edited;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
    },
  );
}
