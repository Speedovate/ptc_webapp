import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/services/dashboard_export_naming.dart';
import 'package:webapp/services/dashboard_docx_export_service.dart';
import 'package:webapp/services/export_file_service.dart';
import 'package:webapp/view_models/admin/admin_dashboard.vm.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_icon_action_button.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

class AdminDashboardView extends StatelessWidget {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AdminDashboardViewModel>.reactive(
      viewModelBuilder: AdminDashboardViewModel.new,
      onViewModelReady: (vm) => vm.load(),
      builder: (context, vm, child) {
        final filteredBookings = vm.filteredCompletedBookings();
        if (vm.errorMessage != null) {
          return AppPageLoadingOverlay(
            isVisible: vm.isBusy,
            message: vm.busyMessage,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppRefreshStrip(isVisible: vm.isBusy),
                  _AdminDashboardToolbar(
                    vm: vm,
                    onExportPressed: () =>
                        _exportBookings(context, vm, filteredBookings),
                  ),
                  const SizedBox(height: 14),
                  AdminListItemCard(
                    padding: const EdgeInsets.all(24),
                    child: AdminListStateText(message: vm.errorMessage!),
                  ),
                ],
              ),
            ),
          );
        }

        if (vm.completedBookings.isEmpty) {
          return AppPageLoadingOverlay(
            isVisible: vm.isBusy,
            message: vm.busyMessage,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppRefreshStrip(isVisible: vm.isBusy),
                  _AdminDashboardToolbar(
                    vm: vm,
                    onExportPressed: () =>
                        _exportBookings(context, vm, filteredBookings),
                  ),
                  const SizedBox(height: 14),
                  AdminListItemCard(
                    padding: EdgeInsets.all(24),
                    child: AdminListStateText(
                      message: 'No completed bookings yet.',
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return AppPageLoadingOverlay(
          isVisible: vm.isBusy,
          message: vm.busyMessage,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppRefreshStrip(isVisible: vm.isBusy),
                _AdminDashboardToolbar(
                  vm: vm,
                  onExportPressed: () =>
                      _exportBookings(context, vm, filteredBookings),
                ),
                const SizedBox(height: 14),
                if (filteredBookings.isEmpty)
                  AdminListItemCard(
                    padding: const EdgeInsets.all(24),
                    child: const AdminListStateText(
                      message:
                          'No completed bookings matched your current search.',
                    ),
                  )
                else
                  _AdminDashboardCompletedBookingsTable(
                    bookings: filteredBookings,
                    vm: vm,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _exportBookings(
  BuildContext context,
  AdminDashboardViewModel vm,
  List<Booking> bookings,
) async {
  if (bookings.isEmpty) {
    AppSnackbar.showError(
      context,
      'No completed bookings available to export.',
    );
    return;
  }

  final exportConfig = await showDialog<_DashboardBatchExportConfig>(
    context: context,
    builder: (dialogContext) =>
        _DashboardExportDialog(bookings: bookings, vm: vm),
  );
  if (!context.mounted || exportConfig == null) {
    return;
  }

  vm.beginExport(exportConfig.types.length + 1);
  await _yieldExportProgressFrame();
  try {
    final exportedDocuments = <String, Uint8List>{};
    for (final type in exportConfig.types) {
      final config = exportConfig.configFor(type);
      final payload = _buildDashboardExportPayload(
        bookings: bookings,
        vm: vm,
        config: config,
      );
      final document = await DashboardDocxExportService.instance.buildDocument(
        payload,
      );
      exportedDocuments[dashboardExportFileName(config)] = document;
      vm.advanceExport();
      await _yieldExportProgressFrame();
    }

    if (!context.mounted) {
      vm.endExport();
      return;
    }
    vm.completeExport();
    await _yieldExportProgressFrame();
    if (!context.mounted) {
      vm.endExport();
      return;
    }
    final exportResult = await ExportFileService.export(
      context,
      bundleFileName: _buildDashboardExportZipFileName(exportConfig),
      files: exportedDocuments,
    );
    if (!context.mounted) {
      vm.endExport();
      return;
    }
    AppSnackbar.showSuccess(context, exportResult.message);
  } catch (error) {
    if (!context.mounted) {
      vm.endExport();
      return;
    }
    AppSnackbar.showError(context, dashboardExportErrorMessage(error));
  } finally {
    vm.endExport();
  }
}

Future<void> _yieldExportProgressFrame() async {
  await Future<void>.delayed(const Duration(milliseconds: 16));
}

class _AdminDashboardToolbar extends StatelessWidget {
  const _AdminDashboardToolbar({
    required this.vm,
    required this.onExportPressed,
  });

  final AdminDashboardViewModel vm;
  final VoidCallback onExportPressed;

  @override
  Widget build(BuildContext context) {
    return AdminListToolbar(
      controlHeight: 52,
      surfaceRadius: 16,
      search: AdminListSearchField(
        controlHeight: 52,
        surfaceRadius: 16,
        initialValue: vm.searchQuery,
        onChanged: vm.setSearchQuery,
      ),
      filtersBuilder: (context, iconOnly) =>
          _DashboardFiltersPanel(vm: vm, iconOnly: iconOnly),
      onNewPressed: vm.isExporting ? null : onExportPressed,
      buttonLabel: vm.exportProgressLabel,
      buttonIcon: Icons.download_rounded,
    );
  }
}

typedef _DashboardExportType = DashboardExportDocumentType;
typedef _DashboardExportConfig = DashboardExportConfig;

class _DashboardBatchExportConfig {
  const _DashboardBatchExportConfig({
    required this.types,
    required this.documentDate,
    required this.coveredStartDate,
    required this.coveredEndDate,
    required this.regularStatementNumber,
    required this.hustlingStatementNumber,
    required this.companyName,
    required this.representativeName,
    required this.greetingLine,
    required this.preparedBy,
    required this.preparedByTitle,
    required this.approvedBy,
    required this.approvedByTitle,
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
  });

  final List<_DashboardExportType> types;
  final DateTime documentDate;
  final DateTime coveredStartDate;
  final DateTime coveredEndDate;
  final String regularStatementNumber;
  final String hustlingStatementNumber;
  final String companyName;
  final String representativeName;
  final String greetingLine;
  final String preparedBy;
  final String preparedByTitle;
  final String approvedBy;
  final String approvedByTitle;
  final String bankName;
  final String accountName;
  final String accountNumber;

  _DashboardExportConfig configFor(_DashboardExportType type) {
    return _DashboardExportConfig(
      type: type,
      documentDate: documentDate,
      coveredStartDate: coveredStartDate,
      coveredEndDate: coveredEndDate,
      billingStatementNumber: type.isHustling
          ? hustlingStatementNumber
          : regularStatementNumber,
      companyName: companyName,
      representativeName: representativeName,
      greetingLine: greetingLine,
      preparedBy: preparedBy,
      preparedByTitle: preparedByTitle,
      approvedBy: approvedBy,
      approvedByTitle: approvedByTitle,
      bankName: bankName,
      accountName: accountName,
      accountNumber: accountNumber,
    );
  }
}

class _DashboardExportDialog extends StatefulWidget {
  const _DashboardExportDialog({required this.bookings, required this.vm});

  final List<Booking> bookings;
  final AdminDashboardViewModel vm;

  @override
  State<_DashboardExportDialog> createState() => _DashboardExportDialogState();
}

class _DashboardExportDialogState extends State<_DashboardExportDialog> {
  late final TextEditingController _regularStatementNumberController;
  late final TextEditingController _hustlingStatementNumberController;
  late final TextEditingController _companyNameController;
  late final TextEditingController _representativeNameController;
  late final TextEditingController _greetingLineController;
  late final TextEditingController _preparedByController;
  late final TextEditingController _preparedByTitleController;
  late final TextEditingController _approvedByController;
  late final TextEditingController _approvedByTitleController;
  late final TextEditingController _bankNameController;
  late final TextEditingController _accountNameController;
  late final TextEditingController _accountNumberController;

  late DateTime _documentDate;
  late DateTime _coveredStartDate;
  late DateTime _coveredEndDate;
  final Set<_DashboardExportType> _selectedTypes = <_DashboardExportType>{};

  @override
  void initState() {
    super.initState();
    final coveredDates = _resolveCoveredDates(widget.bookings);
    _documentDate = DateTime.now();
    _coveredStartDate = coveredDates.$1;
    _coveredEndDate = coveredDates.$2;
    _regularStatementNumberController = TextEditingController();
    _hustlingStatementNumberController = TextEditingController();
    _companyNameController = TextEditingController(
      text: _defaultCompanyName(widget.bookings, widget.vm),
    );
    _representativeNameController = TextEditingController();
    _greetingLineController = TextEditingController(text: 'Dear Ma’am/Sir:');
    _preparedByController = TextEditingController(text: 'Amelita Jara');
    _preparedByTitleController = TextEditingController(
      text: 'Sales & Operation',
    );
    _approvedByController = TextEditingController(text: 'Evelyn N. Pua');
    _approvedByTitleController = TextEditingController(text: 'General Manager');
    _bankNameController = TextEditingController(
      text: 'Chinabank – Puerto Princesa City',
    );
    _accountNameController = TextEditingController(
      text: 'F&E Divine Manna Corporation',
    );
    _accountNumberController = TextEditingController(text: '118700006140');
  }

  @override
  void dispose() {
    _regularStatementNumberController.dispose();
    _hustlingStatementNumberController.dispose();
    _companyNameController.dispose();
    _representativeNameController.dispose();
    _greetingLineController.dispose();
    _preparedByController.dispose();
    _preparedByTitleController.dispose();
    _approvedByController.dispose();
    _approvedByTitleController.dispose();
    _bankNameController.dispose();
    _accountNameController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  bool get _requiresRegularStatementNumber =>
      _selectedTypes.any((type) => !type.isHustling);
  bool get _requiresHustlingStatementNumber =>
      _selectedTypes.any((type) => type.isHustling);
  bool get _showsRepresentativeFields =>
      _selectedTypes.any((type) => type.isBillingStatement);
  bool get _showsBankFields =>
      _selectedTypes.any((type) => type.isBillingStatement);
  bool get _showsCoveredDateRange => widget.bookings.length > 1;

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: 'Export As',
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 14),
      actionsInset: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Download')),
      ],
      child: AdminModalFormBody(
        children: [
          AdminModalFieldsSection(
            children: [
              AdminModalFieldSlot(
                bottomPadding: _selectedTypes.isEmpty ? 0 : 20,
                child: _ExportTypeChoiceField(
                  values: _selectedTypes,
                  onChanged: (value) {
                    setState(() {
                      if (_selectedTypes.contains(value)) {
                        _selectedTypes.remove(value);
                      } else {
                        _selectedTypes.add(value);
                      }
                    });
                  },
                ),
              ),
              if (_selectedTypes.isNotEmpty) ...[
                _DashboardExportDateField(
                  label: 'Document Date',
                  value: _documentDate,
                  bottomPadding: _showsCoveredDateRange ? 4 : 0,
                  onChanged: (value) {
                    setState(() {
                      _documentDate = value;
                    });
                  },
                ),
                if (_showsCoveredDateRange)
                  _DashboardExportDateField(
                    label: 'Covered Start Date',
                    value: _coveredStartDate,
                    bottomPadding: 4,
                    onChanged: (value) {
                      setState(() {
                        _coveredStartDate = value;
                        if (_coveredEndDate.isBefore(value)) {
                          _coveredEndDate = value;
                        }
                      });
                    },
                  ),
                if (_showsCoveredDateRange)
                  _DashboardExportDateField(
                    label: 'Covered End Date',
                    value: _coveredEndDate,
                    bottomPadding: 4,
                    onChanged: (value) {
                      setState(() {
                        _coveredEndDate = value;
                        if (_coveredStartDate.isAfter(value)) {
                          _coveredStartDate = value;
                        }
                      });
                    },
                  ),
                if (_requiresRegularStatementNumber)
                  AdminModalTextField(
                    controller: _regularStatementNumberController,
                    label: 'Regular Statement Number',
                    bottomPadding: 4,
                  ),
                if (_requiresHustlingStatementNumber)
                  AdminModalTextField(
                    controller: _hustlingStatementNumberController,
                    label: 'Hustling Statement Number',
                    bottomPadding: 4,
                  ),
                AdminModalTextField(
                  controller: _companyNameController,
                  label: 'Company Name',
                  textCapitalization: TextCapitalization.words,
                  bottomPadding: 4,
                ),
                if (_showsRepresentativeFields)
                  AdminModalTextField(
                    controller: _representativeNameController,
                    label: 'Representative Name',
                    textCapitalization: TextCapitalization.words,
                    bottomPadding: 4,
                  ),
                if (_showsRepresentativeFields)
                  AdminModalTextField(
                    controller: _greetingLineController,
                    label: 'Greeting Line',
                    bottomPadding: 4,
                  ),
                AdminModalTextField(
                  controller: _preparedByController,
                  label: 'Prepared By',
                  textCapitalization: TextCapitalization.words,
                  bottomPadding: 4,
                ),
                AdminModalTextField(
                  controller: _preparedByTitleController,
                  label: 'Prepared By Title',
                  textCapitalization: TextCapitalization.words,
                  bottomPadding: 4,
                ),
                AdminModalTextField(
                  controller: _approvedByController,
                  label: 'Approved By',
                  textCapitalization: TextCapitalization.words,
                  bottomPadding: 4,
                ),
                AdminModalTextField(
                  controller: _approvedByTitleController,
                  label: 'Approved By Title',
                  textCapitalization: TextCapitalization.words,
                  bottomPadding: _showsBankFields ? 4 : 0,
                ),
                if (_showsBankFields)
                  AdminModalTextField(
                    controller: _bankNameController,
                    label: 'Bank Name',
                    bottomPadding: 4,
                  ),
                if (_showsBankFields)
                  AdminModalTextField(
                    controller: _accountNameController,
                    label: 'Account Name',
                    bottomPadding: 4,
                  ),
                if (_showsBankFields)
                  AdminModalTextField(
                    controller: _accountNumberController,
                    label: 'Account Number',
                    bottomPadding: 0,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _submit() {
    final regularStatementNumber = _regularStatementNumberController.text
        .trim();
    final hustlingStatementNumber = _hustlingStatementNumberController.text
        .trim();
    final companyName = _companyNameController.text.trim();
    final representativeName = _representativeNameController.text.trim();
    final greetingLine = _greetingLineController.text.trim();
    final preparedBy = _preparedByController.text.trim();
    final preparedByTitle = _preparedByTitleController.text.trim();
    final approvedBy = _approvedByController.text.trim();
    final approvedByTitle = _approvedByTitleController.text.trim();
    final bankName = _bankNameController.text.trim();
    final accountName = _accountNameController.text.trim();
    final accountNumber = _accountNumberController.text.trim();

    if (_selectedTypes.isEmpty) {
      AppSnackbar.showError(
        context,
        'Please select at least one document type.',
      );
      return;
    }
    if (_requiresRegularStatementNumber && regularStatementNumber.isEmpty) {
      AppSnackbar.showError(
        context,
        'Please enter the regular statement number.',
      );
      return;
    }
    if (_requiresHustlingStatementNumber && hustlingStatementNumber.isEmpty) {
      AppSnackbar.showError(
        context,
        'Please enter the hustling statement number.',
      );
      return;
    }
    if (companyName.isEmpty) {
      AppSnackbar.showError(context, 'Please enter the company name.');
      return;
    }
    if (_showsRepresentativeFields && representativeName.isEmpty) {
      AppSnackbar.showError(context, 'Please enter the representative name.');
      return;
    }
    if (_showsRepresentativeFields && greetingLine.isEmpty) {
      AppSnackbar.showError(context, 'Please enter the greeting line.');
      return;
    }
    if (preparedBy.isEmpty ||
        preparedByTitle.isEmpty ||
        approvedBy.isEmpty ||
        approvedByTitle.isEmpty) {
      AppSnackbar.showError(context, 'Please complete the signature details.');
      return;
    }
    if (_showsBankFields &&
        (bankName.isEmpty || accountName.isEmpty || accountNumber.isEmpty)) {
      AppSnackbar.showError(context, 'Please complete the bank details.');
      return;
    }

    Navigator.of(context).pop(
      _DashboardBatchExportConfig(
        types: _selectedTypes.toList(),
        documentDate: _documentDate,
        coveredStartDate: _coveredStartDate,
        coveredEndDate: _coveredEndDate,
        regularStatementNumber: regularStatementNumber,
        hustlingStatementNumber: hustlingStatementNumber,
        companyName: companyName,
        representativeName: representativeName,
        greetingLine: greetingLine,
        preparedBy: preparedBy,
        preparedByTitle: preparedByTitle,
        approvedBy: approvedBy,
        approvedByTitle: approvedByTitle,
        bankName: bankName,
        accountName: accountName,
        accountNumber: accountNumber,
      ),
    );
  }
}

class _ExportTypeChoiceField extends StatelessWidget {
  const _ExportTypeChoiceField({required this.values, required this.onChanged});

  final Set<_DashboardExportType> values;
  final ValueChanged<_DashboardExportType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'Document Type',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _DashboardExportType.values.map((type) {
            return _DashboardExportTypeChip(
              label: type.buttonLabel
                  .replaceAll('Regular', 'Reg')
                  .replaceAll('Hustling', 'Hus'),
              selected: values.contains(type),
              onTap: () => onChanged(type),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DashboardExportTypeChip extends StatelessWidget {
  const _DashboardExportTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.primaryColor
        : AppColors.primaryBorder;
    final backgroundColor = selected ? AppColors.primarySurface : Colors.white;
    final textColor = selected ? AppColors.primaryColor : AppColors.textPrimary;

    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Builder(
        builder: (context) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: appPressableActive(context)
                ? AppColors.primarySurfaceAlt.withValues(alpha: 0.34)
                : backgroundColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
                color: selected
                    ? AppColors.primaryColor
                    : AppColors.primaryColor.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardExportDateField extends StatefulWidget {
  const _DashboardExportDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.bottomPadding = 6,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final double bottomPadding;

  @override
  State<_DashboardExportDateField> createState() =>
      _DashboardExportDateFieldState();
}

class _DashboardExportDateFieldState extends State<_DashboardExportDateField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _longDate(widget.value));
  }

  @override
  void didUpdateWidget(covariant _DashboardExportDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = _longDate(widget.value);
    if (_controller.text != text) {
      _controller.value = _controller.value.copyWith(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && context.mounted) {
      widget.onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalActionField(
      label: widget.label,
      valueText: _controller.text,
      hintText: 'Select date',
      bottomPadding: widget.bottomPadding,
      suffixIcon: const Icon(
        Icons.calendar_today_rounded,
        size: 18,
        color: AppColors.primaryColor,
      ),
      onTap: _pickDate,
    );
  }
}

DashboardDocxExportPayload _buildDashboardExportPayload({
  required List<Booking> bookings,
  required AdminDashboardViewModel vm,
  required _DashboardExportConfig config,
}) {
  final totalAmountValue = bookings.fold<double>(
    0,
    (sum, booking) =>
        sum + _parseCurrency(AdminDashboardViewModel.amount(booking)),
  );
  final rows = bookings.map((booking) {
    final exportDate =
        vm.deliveredAt(booking) ?? booking.updatedAt ?? booking.createdAt;
    return DashboardExportBookingRow(
      deliveryReceiptNumber: AdminDashboardViewModel.deliveryFormNumber(
        booking,
      ),
      date: dashboardExportShortDate(exportDate ?? DateTime.now()),
      waybillNumber: AdminDashboardViewModel.waybillNumber(booking),
      vanNumber: AdminDashboardViewModel.vanNumber(booking),
      vanSize: vm.vanSize(booking),
      client: vm.client(booking),
      amount: dashboardExportCurrency(
        _parseCurrency(AdminDashboardViewModel.amount(booking)),
      ),
    );
  }).toList();

  return DashboardDocxExportPayload(
    config: config,
    rows: rows,
    totalAmount: dashboardExportCurrency(totalAmountValue),
  );
}

String _buildDashboardExportZipFileName(
  _DashboardBatchExportConfig exportConfig,
) {
  final now = DateTime.now();
  final month = now.month.toString();
  final day = now.day.toString();
  final year = (now.year % 100).toString().padLeft(2, '0');
  final hour24 = now.hour;
  final meridiem = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final hour = hour12.toString();
  final minute = now.minute.toString().padLeft(2, '0');
  final second = now.second.toString().padLeft(2, '0');
  return 'Paltranco Export $month-$day-$year $hour-$minute-$second $meridiem.zip';
}

String _defaultCompanyName(List<Booking> bookings, AdminDashboardViewModel vm) {
  if (bookings.isEmpty) {
    return '';
  }
  final first = vm.client(bookings.first);
  final upper = first.toUpperCase();
  final parenIndex = upper.indexOf(' (');
  return parenIndex > 0 ? upper.substring(0, parenIndex) : upper;
}

(DateTime, DateTime) _resolveCoveredDates(List<Booking> bookings) {
  if (bookings.isEmpty) {
    final now = DateTime.now();
    return (now, now);
  }
  final dates = bookings
      .map((booking) => booking.createdAt)
      .whereType<DateTime>()
      .toList();
  if (dates.isEmpty) {
    final now = DateTime.now();
    return (now, now);
  }
  var minDate = dates.first;
  var maxDate = dates.first;
  for (final date in dates.skip(1)) {
    if (date.isBefore(minDate)) {
      minDate = date;
    }
    if (date.isAfter(maxDate)) {
      maxDate = date;
    }
  }
  return (minDate, maxDate);
}

double _parseCurrency(String value) {
  final normalized = value.replaceAll(RegExp(r'[^0-9.-]'), '');
  return double.tryParse(normalized) ?? 0;
}

String _longDate(DateTime value) {
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

class _DashboardFiltersPanel extends StatefulWidget {
  const _DashboardFiltersPanel({required this.vm, required this.iconOnly});

  final AdminDashboardViewModel vm;
  final bool iconOnly;

  @override
  State<_DashboardFiltersPanel> createState() => _DashboardFiltersPanelState();
}

class _DashboardFiltersPanelState extends State<_DashboardFiltersPanel> {
  void _unfocusFilterFields() {
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    const overlayRightPadding = 24.0;
    const filterItemWidth = 180.0;
    const overlayPadding = 14.0;
    const desiredOverlayWidth = filterItemWidth + (overlayPadding * 2);
    final overlayWidth = (screenWidth - 32 - overlayRightPadding).clamp(
      1.0,
      desiredOverlayWidth,
    );
    final contentWidth = (overlayWidth - (overlayPadding * 2)).clamp(
      1.0,
      desiredOverlayWidth,
    );
    final itemWidth = contentWidth;

    return AdminListFiltersButton(
      controlHeight: adminFilterFieldMinHeight,
      surfaceRadius: 16,
      iconOnly: widget.iconOnly,
      menuChildren: [
        SizedBox(
          width: overlayWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _unfocusFilterFields,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: _DashboardDateFilter(
                      label: 'Start Date',
                      value: widget.vm.startDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateStartDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: _DashboardDateFilter(
                      label: 'End Date',
                      value: widget.vm.endDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateEndDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
                        widget.vm.clearFilters();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardDateFilter extends StatefulWidget {
  const _DashboardDateFilter({
    required this.label,
    required this.value,
    required this.formatter,
    required this.onSelected,
  });

  final String label;
  final DateTime? value;
  final String Function(DateTime?) formatter;
  final ValueChanged<DateTime?> onSelected;

  @override
  State<_DashboardDateFilter> createState() => _DashboardDateFilterState();
}

class _DashboardDateFilterState extends State<_DashboardDateFilter> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayValue);
    _focusNode = FocusNode()..canRequestFocus = false;
  }

  @override
  void didUpdateWidget(covariant _DashboardDateFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != _displayValue) {
      _controller.value = _controller.value.copyWith(
        text: _displayValue,
        selection: TextSelection.collapsed(offset: _displayValue.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _displayValue =>
      widget.value == null ? '' : widget.formatter(widget.value);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (context.mounted) {
      widget.onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeFillColor = appFieldInteractiveFillColor(context);
    return SizedBox(
      height: adminFilterFieldMinHeight,
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
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickDate,
            child: IgnorePointer(
              child: TextFormField(
                controller: _controller,
                focusNode: _focusNode,
                readOnly: true,
                showCursor: false,
                enableInteractiveSelection: false,
                style: adminDropdownDisplayTextStyle,
                decoration:
                    adminFormInputDecoration(
                      widget.label,
                      radius: 16,
                      minHeight: adminFilterFieldMinHeight,
                    ).copyWith(
                      fillColor: _isHovered || _isPressed
                          ? activeFillColor
                          : AppColors.primarySurface,
                      suffixIcon: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.value == null
                            ? _pickDate
                            : () => widget.onSelected(null),
                        child: Icon(
                          widget.value == null
                              ? Icons.calendar_today_rounded
                              : Icons.close_rounded,
                          size: 18,
                          color: AppColors.primaryColor,
                        ),
                      ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 42,
                        minHeight: 42,
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminDashboardCompletedBookingsTable extends StatelessWidget {
  const _AdminDashboardCompletedBookingsTable({
    required this.bookings,
    required this.vm,
  });

  static const _headerStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );
  static const _valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
  static const _defaultTrailingPadding = 20.0;
  static const _extraWidthAllowance = 16.0;

  final List<Booking> bookings;
  final AdminDashboardViewModel vm;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final resolvedDeliveryNumberWidth = _resolvedColumnWidth(
          _maxTextWidth(
            context,
            textScaler,
            'Dr No.',
            _longerText(
              'Dr No.',
              _longestText(
                bookings.map(AdminDashboardViewModel.deliveryFormNumber),
              ),
            ),
          ),
        );
        final resolvedDateWidth = _resolvedColumnWidth(
          _maxTextWidth(
            context,
            textScaler,
            'Date',
            _longerText(
              'Date',
              _longestText(
                bookings.map(
                  (booking) => _formatBookingDateTime(booking.createdAt),
                ),
              ),
            ),
          ),
        );
        final resolvedWaybillWidth = _resolvedColumnWidth(
          _maxTextWidth(
            context,
            textScaler,
            'Waybill No.',
            _longerText(
              'Waybill No.',
              _longestText(bookings.map(AdminDashboardViewModel.waybillNumber)),
            ),
          ) + 12,
        );
        final resolvedVanNumberWidth = _resolvedColumnWidth(
          _maxTextWidth(
            context,
            textScaler,
            'Van No.',
            _longerText(
              'Van No.',
              _longestText(bookings.map(AdminDashboardViewModel.vanNumber)),
            ),
          ),
        );
        final resolvedVanSizeWidth = _resolvedColumnWidth(
          _maxTextWidth(
            context,
            textScaler,
            'Van Size',
            _longerText('Van Size', _longestText(bookings.map(vm.vanSize))),
          ),
        );
        final resolvedClientWidth = _resolvedColumnWidth(
          _maxTextWidth(
            context,
            textScaler,
            'Client',
            _longerText(
              'Client',
              _longestText(
                bookings.map(
                  (booking) => _widestRenderedLine(
                    _displayClientName(vm.client(booking)),
                  ),
                ),
              ),
            ),
          ),
        );
        final resolvedAmountWidth = _resolvedColumnWidth(
          _maxTextWidth(
            context,
            textScaler,
            'Amount',
            _longerText(
              'Amount',
              _longestText(bookings.map(AdminDashboardViewModel.amount)),
            ),
          ),
        );
        const actionButtonWidth = 38.0;
        final actionsTitleWidth = AdminListMeasurements.measureTextWidth(
          context,
          textScaler,
          'Actions',
          _headerStyle,
        );
        final actionsWidth = actionsTitleWidth > actionButtonWidth
            ? actionsTitleWidth
            : actionButtonWidth;
        final resolvedActionWidth = actionsWidth + 8;

        final totalMeasuredWidth =
            resolvedDeliveryNumberWidth +
            resolvedDateWidth +
            resolvedWaybillWidth +
            resolvedVanNumberWidth +
            resolvedVanSizeWidth +
            resolvedClientWidth +
            resolvedAmountWidth +
            resolvedActionWidth +
            40;
        final useResponsiveCards = totalMeasuredWidth > constraints.maxWidth;

        if (useResponsiveCards) {
          return Column(
            children: bookings
                .map(
                  (booking) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AdminDashboardResponsiveCard(
                      booking: booking,
                      vm: vm,
                      clientName: vm.client(booking),
                      dateValue: booking.createdAt,
                      onExportPressed: () =>
                          _exportBookings(context, vm, <Booking>[booking]),
                    ),
                  ),
                )
                .toList(),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminListHeaderBar(
              minHeight: 52,
              borderRadius: 16,
              child: Row(
                children: [
                  _DashboardFixedSlot(
                    width: resolvedDeliveryNumberWidth,
                    child: const _DashboardHeaderCell(label: 'Dr No.'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedDateWidth,
                    child: const _DashboardHeaderCell(label: 'Date'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedWaybillWidth,
                    child: const _DashboardHeaderCell(label: 'Waybill No.'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedVanNumberWidth,
                    child: const _DashboardHeaderCell(label: 'Van No.'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedVanSizeWidth,
                    child: const _DashboardHeaderCell(label: 'Van Size'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedClientWidth,
                    child: const _DashboardHeaderCell(label: 'Client'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedAmountWidth,
                    child: const _DashboardHeaderCell(label: 'Amount'),
                  ),
                  AdminListTrailingActionsLane(
                    width: resolvedActionWidth,
                    child: const _DashboardHeaderCell(
                      label: 'Actions',
                      trailingPadding: 0,
                      alignment: Alignment.centerRight,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...bookings.map(
              (booking) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AdminDashboardWideRow(
                  booking: booking,
                  vm: vm,
                  clientName: vm.client(booking),
                  dateValue: booking.createdAt,
                  resolvedDeliveryNumberWidth: resolvedDeliveryNumberWidth,
                  resolvedDateWidth: resolvedDateWidth,
                  resolvedWaybillWidth: resolvedWaybillWidth,
                  resolvedVanNumberWidth: resolvedVanNumberWidth,
                  resolvedVanSizeWidth: resolvedVanSizeWidth,
                  resolvedClientWidth: resolvedClientWidth,
                  resolvedAmountWidth: resolvedAmountWidth,
                  resolvedActionWidth: resolvedActionWidth,
                  onExportPressed: () =>
                      _exportBookings(context, vm, <Booking>[booking]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _longestText(Iterable<String> values) {
    var longest = '-';
    for (final value in values) {
      if (value.length > longest.length) {
        longest = value;
      }
    }
    return longest;
  }

  static String _longerText(String current, String candidate) {
    return candidate.length > current.length ? candidate : current;
  }

  static String _displayClientName(String value) {
    return value.replaceFirst(RegExp(r'\s+\('), '\n(');
  }

  static String _widestRenderedLine(String value) {
    final lines = value.split('\n');
    var widest = '';
    for (final line in lines) {
      if (line.length > widest.length) {
        widest = line;
      }
    }
    return widest;
  }

  static double _resolvedColumnWidth(double measuredWidth) {
    return AdminListMeasurements.resolvedColumnWidth(
      measuredWidth,
      trailingPadding: _defaultTrailingPadding,
      extraWidthAllowance: _extraWidthAllowance,
    );
  }

  static double _maxTextWidth(
    BuildContext context,
    TextScaler textScaler,
    String label,
    String value,
  ) {
    return AdminListMeasurements.maxTextWidth(
      context,
      textScaler,
      label,
      _headerStyle,
      value,
      _valueStyle,
    );
  }

  static String _formatBookingDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final year = (value.year % 100).toString().padLeft(2, '0');
    return '${value.month}/${value.day}/$year';
  }
}

class _AdminDashboardWideRow extends StatelessWidget {
  const _AdminDashboardWideRow({
    required this.booking,
    required this.vm,
    required this.clientName,
    required this.dateValue,
    required this.resolvedDeliveryNumberWidth,
    required this.resolvedDateWidth,
    required this.resolvedWaybillWidth,
    required this.resolvedVanNumberWidth,
    required this.resolvedVanSizeWidth,
    required this.resolvedClientWidth,
    required this.resolvedAmountWidth,
    required this.resolvedActionWidth,
    required this.onExportPressed,
  });

  final Booking booking;
  final AdminDashboardViewModel vm;
  final String clientName;
  final DateTime? dateValue;
  final double resolvedDeliveryNumberWidth;
  final double resolvedDateWidth;
  final double resolvedWaybillWidth;
  final double resolvedVanNumberWidth;
  final double resolvedVanSizeWidth;
  final double resolvedClientWidth;
  final double resolvedAmountWidth;
  final double resolvedActionWidth;
  final VoidCallback? onExportPressed;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _DashboardFixedSlot(
            width: resolvedDeliveryNumberWidth,
            child: _DashboardBodyCell(
              child: Text(
                AdminDashboardViewModel.deliveryFormNumber(booking),
                style: _AdminDashboardCompletedBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _DashboardFixedSlot(
            width: resolvedDateWidth,
            child: _DashboardBodyCell(
              child: Text(
                _AdminDashboardCompletedBookingsTable._formatBookingDateTime(
                  dateValue,
                ),
                style: _AdminDashboardCompletedBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _DashboardFixedSlot(
            width: resolvedWaybillWidth,
            child: _DashboardBodyCell(
              child: Text(
                _dashboardDisplayWaybill(
                  AdminDashboardViewModel.waybillNumber(booking),
                ),
                style: _AdminDashboardCompletedBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _DashboardFixedSlot(
            width: resolvedVanNumberWidth,
            child: _DashboardBodyCell(
              child: Text(
                AdminDashboardViewModel.vanNumber(booking),
                style: _AdminDashboardCompletedBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _DashboardFixedSlot(
            width: resolvedVanSizeWidth,
            child: _DashboardBodyCell(
              child: Text(
                vm.vanSize(booking),
                style: _AdminDashboardCompletedBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _DashboardFixedSlot(
            width: resolvedClientWidth,
            child: _DashboardBodyCell(
              child: Text(
                _AdminDashboardCompletedBookingsTable._displayClientName(
                  clientName,
                ),
                style: _AdminDashboardCompletedBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _DashboardFixedSlot(
            width: resolvedAmountWidth,
            child: _DashboardBodyCell(
              child: Text(
                AdminDashboardViewModel.amount(booking),
                style: _AdminDashboardCompletedBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          AdminListTrailingActionsLane(
            width: resolvedActionWidth,
            child: _DashboardBodyCell(
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              child: Align(
                alignment: Alignment.centerRight,
                child: AdminIconActionButton(
                  icon: Icons.download_rounded,
                  onTap: onExportPressed,
                  backgroundColor: AppColors.primaryColor,
                  size: 38,
                  iconSize: 18,
                  borderRadius: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDashboardResponsiveCard extends StatelessWidget {
  const _AdminDashboardResponsiveCard({
    required this.booking,
    required this.vm,
    required this.clientName,
    required this.dateValue,
    required this.onExportPressed,
  });

  final Booking booking;
  final AdminDashboardViewModel vm;
  final String clientName;
  final DateTime? dateValue;
  final VoidCallback? onExportPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        final spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        final items = [
          ('Dr No.', AdminDashboardViewModel.deliveryFormNumber(booking)),
          (
            'Date',
            _AdminDashboardCompletedBookingsTable._formatBookingDateTime(
              dateValue,
            ),
          ),
          ('Waybill No.', AdminDashboardViewModel.waybillNumber(booking)),
          ('Van No.', AdminDashboardViewModel.vanNumber(booking)),
          ('Van Size', vm.vanSize(booking)),
          ('Client', clientName),
          ('Amount', AdminDashboardViewModel.amount(booking)),
        ];

        return AdminListItemCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: spacing,
                runSpacing: 10,
                children: items
                    .map(
                      (item) => AdminListResponsiveField(
                        title: item.$1,
                        value: item.$2,
                        width: itemWidth,
                        centered: false,
                        isTitle: false,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: AdminIconActionButton(
                  icon: Icons.download_rounded,
                  onTap: onExportPressed,
                  backgroundColor: AppColors.primaryColor,
                  size: 38,
                  iconSize: 18,
                  borderRadius: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardFixedSlot extends StatelessWidget {
  const _DashboardFixedSlot({
    required this.width,
    required this.child,
  });

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdminListFixedSlot(width: width, child: child);
  }
}

class _DashboardHeaderCell extends StatelessWidget {
  const _DashboardHeaderCell({
    required this.label,
    this.trailingPadding = 20,
    this.alignment = Alignment.centerLeft,
    this.textAlign = TextAlign.left,
  });

  final String label;
  final double trailingPadding;
  final Alignment alignment;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return AdminListHeaderCell(
      label: label,
      trailingPadding: trailingPadding,
      alignment: alignment,
      textAlign: textAlign,
    );
  }
}

class _DashboardBodyCell extends StatelessWidget {
  const _DashboardBodyCell({
    required this.child,
    this.trailingPadding = 20,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final double trailingPadding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AdminListBodyCell(
      trailingPadding: trailingPadding,
      alignment: alignment,
      child: child,
    );
  }
}

String _dashboardDisplayWaybill(String value) {
  return value.replaceAll('-', '\u2011');
}
