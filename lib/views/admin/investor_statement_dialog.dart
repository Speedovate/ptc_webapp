import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/investor_statement_workbook.dart';
import 'package:webapp/services/investor_commission_rate_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/admin/investor_statement.vm.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

import 'package:webapp/services/export_file_service_stub.dart'
    if (dart.library.html) 'package:webapp/services/export_file_service_web.dart'
    if (dart.library.io) 'package:webapp/services/export_file_service_io.dart'
    as export_impl;

/// Builds the month the office is most likely to want first: this month, then
/// going back far enough to cover a statement that has not been sent yet.
List<KpiPeriod> _recentMonths() {
  final now = DateTime.now().toUtc();
  return [
    for (var back = 0; back < 18; back++)
      KpiPeriod.month(now.year, now.month - back),
  ];
}

String _monthOptionLabel(KpiPeriod period) => kpiMonthLabel(period);

/// The office's side of the investor statement: pick an investor, pick a month,
/// read the numbers, send the file.
///
/// There is no investor login by design, so this screen *is* the access
/// control. It shows the statement before it exports it, because the person
/// pressing the button is the only person who will ever check these figures.
class InvestorStatementDialog extends StatefulWidget {
  const InvestorStatementDialog({
    super.key,
    required this.makes,
    this.users = const [],
    this.kpiStore,
    this.rateStore,
  });

  final List<VehicleMake> makes;

  /// The accounts ownership is resolved from. A truck has no owner field, so
  /// without these every truck reads as Paltranco and the list is empty.
  final List<UserModel> users;

  /// Injectable so the dialog can be exercised without a live database, the
  /// same way the fuel ledger takes its store.
  final PmKpiStore? kpiStore;
  final InvestorCommissionRateStore? rateStore;

  static Future<void> show(
    BuildContext context,
    List<VehicleMake> makes, {
    List<UserModel> users = const [],
  }) => showAppDialog<void>(
    context: context,
    builder: (_) => InvestorStatementDialog(makes: makes, users: users),
  );

  @override
  State<InvestorStatementDialog> createState() =>
      _InvestorStatementDialogState();
}

class _InvestorStatementDialogState extends State<InvestorStatementDialog> {
  late final InvestorStatementViewModel _vm;
  final _shareController = TextEditingController();
  final _shareFocusNode = FocusNode();
  var _share = 10.0;
  var _savingShare = false;

  @override
  void initState() {
    super.initState();
    _vm =
        InvestorStatementViewModel(
            kpiStore: widget.kpiStore,
            rateStore: widget.rateStore,
          )
          ..setUsers(widget.users)
          ..setMakes(widget.makes);
    _shareController.text = _number(_share);
    _loadShare();
  }

  @override
  void dispose() {
    _shareController.dispose();
    _shareFocusNode.dispose();
    _vm.dispose();
    super.dispose();
  }

  Future<void> _loadShare() async {
    double percent;
    try {
      percent = await _vm.loadPlatformShare();
    } catch (_) {
      // Offline or unreachable: keep the documented default rather than
      // leaving the office staring at an empty field.
      if (!mounted) return;
      return;
    }
    if (!mounted) return;
    setState(() {
      _share = percent;
      _shareController.text = _number(percent);
    });
  }

  static String _number(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  Future<void> _saveShare() async {
    final parsed = double.tryParse(_shareController.text.trim());
    if (parsed == null) {
      setState(
        () => _vm.errorForShare = 'Enter the platform share as a number.',
      );
      return;
    }
    setState(() {
      _savingShare = true;
      _vm.errorForShare = null;
    });
    try {
      await _vm.savePlatformShare(parsed);
      if (!mounted) return;
      final percent = await _vm.loadPlatformShare();
      if (!mounted) return;
      setState(() {
        _share = percent;
        _shareController.text = _number(percent);
      });
      AppSnackbar.showSuccess(context, 'Platform share updated.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _vm.errorForShare = userFacingErrorMessage(error));
    } finally {
      if (mounted) setState(() => _savingShare = false);
    }
  }

  Future<void> _generate() async {
    await _vm.generate();
    if (!mounted) return;
    if (_vm.error != null) {
      AppSnackbar.showError(context, _vm.error!);
    }
  }

  Future<void> _download() async {
    final statement = _vm.statement;
    if (statement == null) return;
    final files = _vm.files(statement);
    try {
      final result = await export_impl.exportFiles(
        context,
        bundleFileName: InvestorStatementWorkbook.fileName(
          investorId: statement.investorId,
          periodKey: statement.periodKey,
        ),
        files: files,
      );
      if (!mounted) return;
      AppSnackbar.showSuccess(context, result.message);
    } catch (error) {
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        userFacingErrorMessage(error, fallback: 'Could not build the file.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: 'Investor Statement',
      maxWidth: 640,
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
      child: AnimatedBuilder(
        animation: _vm,
        builder: (context, _) {
          final statement = _vm.statement;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_vm.canRead)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('You do not have access to investor earnings.'),
                )
              else if (!_vm.hasInvestors)
                const _NoInvestors()
              else ...[
                AdminModalFieldsSection(
                  children: [
                    AdminModalDropdownField<String>(
                      label: 'Investor',
                      initialValue: _vm.investorId ?? '',
                      bottomPadding: 6,
                      iconEnabledColor: AppColors.primaryColor,
                      items: [
                        for (final entry in _vm.investors.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(
                              InvestorStatementViewModel.investorLabel(
                                entry.value,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) => _vm.selectInvestor(value),
                    ),
                    AdminModalDropdownField<KpiPeriod>(
                      label: 'Month',
                      initialValue: _vm.period,
                      bottomPadding: 0,
                      iconEnabledColor: AppColors.primaryColor,
                      items: [
                        for (final period in _recentMonths())
                          DropdownMenuItem(
                            value: period,
                            child: Text(_monthOptionLabel(period)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) _vm.selectPeriod(value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ShareField(
                  controller: _shareController,
                  focusNode: _shareFocusNode,
                  percent: _share,
                  canEdit: _vm.canEditRate,
                  saving: _savingShare,
                  error: _vm.errorForShare,
                  onSave: _saveShare,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _vm.busy ? null : _generate,
                      icon: _vm.busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.calculate_outlined),
                      label: Text(
                        _vm.busy ? 'Working ...' : 'Generate statement',
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (statement != null)
                      FilledButton.tonalIcon(
                        onPressed: _download,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Download'),
                      ),
                  ],
                ),
                if (_vm.error != null) ...[
                  const SizedBox(height: 12),
                  _Message(text: _vm.error!, isError: true),
                ],
                if (statement != null) ...[
                  const SizedBox(height: 20),
                  _StatementPreview(
                    statement: statement,
                    fromCache: _vm.fromCache,
                    makeCount: _vm.ownedMakes.length,
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _NoInvestors extends StatelessWidget {
  const _NoInvestors();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      'No truck on file belongs to an investor yet. Open a vehicle make and set '
      'its Investor ID to get started.',
      style: const TextStyle(height: 1.45),
    ),
  );
}

class _ShareField extends StatelessWidget {
  const _ShareField({
    required this.controller,
    required this.focusNode,
    required this.percent,
    required this.canEdit,
    required this.saving,
    required this.error,
    required this.onSave,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double percent;
  final bool canEdit;
  final bool saving;
  final String? error;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Paltranco keeps $_shown% of every trip. This is the share the '
          'investor is told, so it applies to every statement from now on.',
          style: const TextStyle(height: 1.45),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: AdminModalTextField(
                controller: controller,
                focusNode: focusNode,
                label: 'Platform share (%)',
                readOnly: !canEdit,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  FocusScope.of(context).unfocus();
                  onSave();
                },
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: FilledButton.tonal(
                onPressed: canEdit && !saving ? onSave : null,
                child: Text(saving ? 'Saving ...' : 'Save share'),
              ),
            ),
          ],
        ),
        if (!canEdit)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('You do not have access to change the platform share.'),
          ),
        if (error != null) _Message(text: error!, isError: true),
      ],
    );
  }

  String get _shown => percent == percent.roundToDouble()
      ? percent.toStringAsFixed(0)
      : '$percent';
}

class _StatementPreview extends StatelessWidget {
  const _StatementPreview({
    required this.statement,
    required this.fromCache,
    required this.makeCount,
  });

  final dynamic statement;
  final bool fromCache;
  final int makeCount;

  int get officeDays => statement.officeDayCount as int;
  int get unconfirmed => statement.unconfirmedDays as int;

  @override
  Widget build(BuildContext context) {
    final lines = (statement.statement as List).cast<dynamic>();
    final netDue = statement.netDue as double;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Preview · ${statement.tripCount} trip'
          '${statement.tripCount == 1 ? '' : 's'} across $makeCount truck'
          '${makeCount == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (final line in lines) ...[
          Builder(
            builder: (context) {
              final label = line.$1 as String;
              final amount = line.$2 as double;
              final isNet = label == 'Net due';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: isNet
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Text(
                      '${amount < 0 ? '-' : ''}₱${amount.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: isNet ? FontWeight.bold : FontWeight.normal,
                        color: amount < 0
                            ? AppColors.textPrimary
                            : AppColors.primaryColor,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 10),
        _Message(
          text: netDue < 0
              ? 'This period comes out negative. That is a real answer worth '
                    'looking at before it is sent.'
              : fromCache
              ? 'Figures came partly from the offline cache. Reconnect before '
                    'sending this.'
              : 'Ready to send.',
          isError: netDue < 0,
        ),
        if (unconfirmed > 0)
          _Message(
            // The office's figure was used because it is better than anything
            // the rate card could derive, but the office has not signed it off.
            text:
                '$unconfirmed of $officeDays day${officeDays == 1 ? '' : 's'} '
                'of crew cost came from the PM KPI and is not confirmed yet. '
                'Confirm it there before sending this.',
            isError: true,
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: TextStyle(
        height: 1.45,
        color: isError ? AppColors.danger : AppColors.textSecondary,
      ),
    ),
  );
}
