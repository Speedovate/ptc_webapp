import 'dart:async';

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/dashboard_export_naming.dart';
import 'package:webapp/services/dashboard_docx_export_service.dart';
import 'package:webapp/services/export_file_service.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/view_models/admin/admin_dashboard.vm.dart';
import 'package:webapp/views/admin/admin_bookings.dart';
import 'package:webapp/views/shared/booking_workflow_view.dart';
import 'package:webapp/views/shared/support_center_view.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

class AdminDashboardView extends StatefulWidget {
  const AdminDashboardView({super.key, required this.user});

  final UserModel user;

  @override
  State<AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<AdminDashboardView> {
  static const double _toolbarSectionGap = 12;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  final AdminDashboardViewModel _viewModel = AdminDashboardViewModel();
  Booking? _selectedBooking;
  final Set<String> _excludedExportBookingIds = <String>{};
  late final ScrollController _detailScrollController;

  bool _canExport(UserModel? user) => _roleAccessService.canAccess(
    DispatcherAccessCapability.dashboardExport,
    role: _roleAccessService.effectiveRoleKey(user?.role),
  );

  bool _canUpdateBilling(UserModel? user) => _roleAccessService.canAccess(
    DispatcherAccessCapability.dashboardUpdateBilling,
    role: _roleAccessService.effectiveRoleKey(user?.role),
  );

  bool _canUpdateBookings(UserModel? user) => _roleAccessService.canAccess(
    DispatcherAccessCapability.bookingsUpdate,
    role: _roleAccessService.effectiveRoleKey(user?.role),
  );

  @override
  void initState() {
    super.initState();
    _detailScrollController = ScrollController();
    _viewModel.primeCurrentUser(widget.user);
    unawaited(_viewModel.load());
  }

  @override
  void didUpdateWidget(covariant AdminDashboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.user.updatedAt != widget.user.updatedAt ||
        oldWidget.user.role != widget.user.role) {
      _viewModel.primeCurrentUser(widget.user);
    }
  }

  @override
  void dispose() {
    _detailScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AdminDashboardViewModel>.reactive(
      viewModelBuilder: () => _viewModel,
      builder: (context, vm, child) {
        final selectedBooking = _selectedBooking == null
            ? null
            : vm.completedBookings
                  .where((booking) => booking.id == _selectedBooking!.id)
                  .firstOrNull;
        final filteredBookings = vm.filteredCompletedBookings();
        final showInitialLoading =
            !vm.hasResolvedInitialBookings &&
            selectedBooking == null &&
            vm.errorMessage == null &&
            vm.completedBookings.isEmpty;
        if (selectedBooking != null && vm.currentUser != null) {
          return AppPageLoadingOverlay(
            isVisible: false,
            message: vm.busyMessage,
            child: SingleChildScrollView(
              key: PageStorageKey(
                'admin-dashboard-booking-detail-${selectedBooking.id ?? ''}',
              ),
              controller: _detailScrollController,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AdminDashboardBookingDetailHeader(
                    booking: selectedBooking,
                    currentUser: vm.currentUser!,
                    onBack: () {
                      setState(() {
                        _selectedBooking = null;
                      });
                    },
                    onEdit: !_canUpdateBookings(vm.currentUser)
                        ? null
                        : () async {
                            final updatedBooking =
                                await AdminBookingsView.showEditBookingDialog(
                                  context,
                                  booking: selectedBooking,
                                  currentUser: vm.currentUser!,
                                );
                            if (!context.mounted || updatedBooking == null) {
                              return;
                            }
                            setState(() {
                              _selectedBooking = updatedBooking;
                            });
                          },
                  ),
                  const SizedBox(height: 16),
                  BookingWorkflowView(
                    key: ValueKey(
                      'admin-dashboard-booking-workflow-${selectedBooking.id ?? ''}',
                    ),
                    user: vm.currentUser!,
                    booking: selectedBooking,
                    embedded: true,
                    embeddedScrollController: _detailScrollController,
                    onBookingUpdated: (updatedBooking) {
                      setState(() {
                        _selectedBooking = updatedBooking;
                      });
                    },
                  ),
                ],
              ),
            ),
          );
        }
        if (vm.errorMessage != null) {
          return AppPageLoadingOverlay(
            isVisible: showInitialLoading,
            message: vm.busyMessage,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppRefreshStrip(isVisible: vm.isBusy),
                  _AdminDashboardToolbar(
                    vm: vm,
                    onExportPressed: _canExport(vm.currentUser)
                        ? () => _exportBookings(
                            context,
                            vm,
                            excludedBookingIds: _excludedExportBookingIds,
                            onToggleExcludedSession:
                                _toggleExportExcludedBookingId,
                          )
                        : null,
                  ),
                  const SizedBox(height: _toolbarSectionGap),
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
            isVisible: showInitialLoading,
            message: vm.busyMessage,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppRefreshStrip(isVisible: vm.isBusy),
                  _AdminDashboardToolbar(
                    vm: vm,
                    onExportPressed: _canExport(vm.currentUser)
                        ? () => _exportBookings(
                            context,
                            vm,
                            excludedBookingIds: _excludedExportBookingIds,
                            onToggleExcludedSession:
                                _toggleExportExcludedBookingId,
                          )
                        : null,
                  ),
                  const SizedBox(height: _toolbarSectionGap),
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
          isVisible: showInitialLoading,
          message: vm.busyMessage,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppRefreshStrip(isVisible: vm.isBusy),
                _AdminDashboardToolbar(
                  vm: vm,
                  onExportPressed: _canExport(vm.currentUser)
                      ? () => _exportBookings(
                          context,
                          vm,
                          excludedBookingIds: _excludedExportBookingIds,
                          onToggleExcludedSession:
                              _toggleExportExcludedBookingId,
                        )
                      : null,
                ),
                const SizedBox(height: _toolbarSectionGap),
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
                    onToggleBillingStatus: _canUpdateBilling(vm.currentUser)
                        ? (booking) =>
                              _toggleBillingStatus(context, vm, booking)
                        : (_) {},
                    onView: (booking) {
                      setState(() {
                        _selectedBooking = booking;
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleExportExcludedBookingId(String bookingId) {
    final normalizedId = normalizeId(bookingId);
    if (normalizedId == null) {
      return;
    }
    setState(() {
      if (_excludedExportBookingIds.contains(normalizedId)) {
        _excludedExportBookingIds.remove(normalizedId);
      } else {
        _excludedExportBookingIds.add(normalizedId);
      }
    });
  }

  Future<void> _toggleBillingStatus(
    BuildContext context,
    AdminDashboardViewModel vm,
    Booking booking,
  ) async {
    if (!_canUpdateBilling(vm.currentUser)) {
      AppSnackbar.showError(
        context,
        'You do not have access to update billing status.',
      );
      return;
    }
    final currentStatus = vm.billingStatusValue(booking);
    final nextStatus =
        currentStatus == AdminDashboardViewModel.billingStatusBilled
        ? AdminDashboardViewModel.billingStatusUnbilled
        : AdminDashboardViewModel.billingStatusBilled;
    final deliveryNumber =
        AdminDashboardViewModel.deliveryFormNumber(booking).trim().isNotEmpty
        ? AdminDashboardViewModel.deliveryFormNumber(booking).trim()
        : '-';
    final confirmed = await showAdminActionConfirmation(
      context,
      title: nextStatus == AdminDashboardViewModel.billingStatusBilled
          ? 'Mark $deliveryNumber as Billed'
          : 'Mark $deliveryNumber as Unbilled',
      message: nextStatus == AdminDashboardViewModel.billingStatusBilled
          ? 'Are you sure you want to mark DR No. $deliveryNumber as billed?'
          : 'Are you sure you want to mark DR No. $deliveryNumber as unbilled?',
      confirmLabel: nextStatus == AdminDashboardViewModel.billingStatusBilled
          ? 'Mark as Billed'
          : 'Mark as Unbilled',
      isDanger: nextStatus != AdminDashboardViewModel.billingStatusBilled,
      onConfirmAsync: () async {
        try {
          await vm.updateBookingBillingStatus(booking, nextStatus);
          return true;
        } catch (error) {
          if (context.mounted) {
            AppSnackbar.showError(context, error.toString());
          }
          return false;
        }
      },
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    AppSnackbar.showSuccess(
      context,
      nextStatus == AdminDashboardViewModel.billingStatusBilled
          ? 'Marked as billed.'
          : 'Marked as unbilled.',
    );
  }
}

Future<bool> _runDashboardExport(
  BuildContext context,
  AdminDashboardViewModel vm, {
  required _DashboardBatchExportConfig exportConfig,
  required List<Booking> availableBookings,
  required Set<String> excludedBookingIds,
  required ValueChanged<String> onToggleExcludedSession,
}) async {
  final selectedBookings = exportConfig.selectedBookings(availableBookings);
  final excludedCandidateIds = exportConfig.excludedCandidateBookingIds;
  if (selectedBookings.isEmpty) {
    AppSnackbar.showError(context, 'No bookings selected for export.');
    return false;
  }

  vm.beginExport(exportConfig.types.length + 1);
  await _yieldExportProgressFrame();
  try {
    final exportedDocuments = <String, Uint8List>{};
    for (final type in exportConfig.types) {
      final config = exportConfig.configFor(type);
      final payload = _buildDashboardExportPayload(
        bookings: selectedBookings,
        vm: vm,
        config: config,
      );
      final document = await DashboardDocxExportService.instance
          .buildDocument(payload)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              throw TimeoutException(
                'dashboard export document build timeout for ${type.name}',
              );
            },
          );
      exportedDocuments[dashboardExportFileName(config)] = document;
      vm.advanceExport();
      await _yieldExportProgressFrame();
    }

    if (!context.mounted) {
      vm.endExport();
      return false;
    }
    vm.completeExport();
    await _yieldExportProgressFrame();
    if (!context.mounted) {
      vm.endExport();
      return false;
    }
    final exportResult = await ExportFileService.export(
      context,
      bundleFileName: _buildDashboardExportZipFileName(exportConfig),
      files: exportedDocuments,
    );
    if (!context.mounted) {
      vm.endExport();
      return false;
    }
    if (!context.mounted) {
      return false;
    }
    AppSnackbar.showSuccess(context, exportResult.message);
    if (exportConfig.setAsBilledWhenExported) {
      await vm.updateBillingStatusesForExport(
        billedBookingIds: selectedBookings
            .map((booking) => booking.id ?? '')
            .where((bookingId) => bookingId.isNotEmpty),
        unbilledBookingIds: excludedCandidateIds,
      );
      for (final bookingId in exportConfig.candidateBookingIds) {
        if (excludedBookingIds.contains(bookingId)) {
          onToggleExcludedSession(bookingId);
        }
      }
      await _yieldExportProgressFrame();
    }
    return true;
  } catch (error) {
    if (!context.mounted) {
      vm.endExport();
      return false;
    }
    AppSnackbar.showError(context, dashboardExportErrorMessage(error));
    return false;
  } finally {
    vm.endExport();
  }
}

Future<void> _exportBookings(
  BuildContext context,
  AdminDashboardViewModel vm, {
  List<Booking>? bookings,
  bool singleItem = false,
  required Set<String> excludedBookingIds,
  required ValueChanged<String> onToggleExcludedSession,
}) async {
  final availableBookings = bookings ?? vm.completedBookings;
  final singleItemCandidates = singleItem ? availableBookings : null;
  if (availableBookings.isEmpty) {
    AppSnackbar.showError(
      context,
      'No completed bookings available to export.',
    );
    return;
  }
  await showAppDialog<void>(
    context: context,
    builder: (dialogContext) => _DashboardExportDialog(
      bookings: availableBookings,
      vm: vm,
      singleItem: singleItem,
      singleItemCandidates: singleItemCandidates,
      excludedBookingIds: excludedBookingIds,
      onToggleExcluded: onToggleExcludedSession,
      onSubmit: (exportConfig) {
        return _runDashboardExport(
          context,
          vm,
          exportConfig: exportConfig,
          availableBookings: availableBookings,
          excludedBookingIds: excludedBookingIds,
          onToggleExcludedSession: onToggleExcludedSession,
        );
      },
    ),
  );
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
  final VoidCallback? onExportPressed;

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
      filtersBuilder: (context, iconOnly) => AdminListDynamicFiltersPanel(
        iconOnly: iconOnly,
        filters: [
          AdminListDropdownFilterConfig(
            label: 'Is Billed',
            value: vm.billingStatusFilter,
            items: const [
              AdminDashboardViewModel.billingStatusAll,
              AdminDashboardViewModel.billingStatusBilled,
              AdminDashboardViewModel.billingStatusUnbilled,
            ],
            displayValue: (value) => switch (value) {
              AdminDashboardViewModel.billingStatusAll => 'All',
              AdminDashboardViewModel.billingStatusBilled => 'Billed',
              AdminDashboardViewModel.billingStatusUnbilled => 'Unbilled',
              _ => value,
            },
            onChanged: (value) => vm.updateBillingStatusFilter(
              value == AdminDashboardViewModel.billingStatusAll ? null : value,
            ),
          ),
          AdminListDateFilterConfig(
            label: 'Date Start',
            value: vm.startDate,
            onSelected: vm.updateStartDate,
            formatter: vm.formatDate,
          ),
          AdminListDateFilterConfig(
            label: 'Date End',
            value: vm.endDate,
            onSelected: vm.updateEndDate,
            formatter: vm.formatDate,
          ),
          AdminListDateFilterConfig(
            label: 'Created Start',
            value: vm.createdStartDate,
            onSelected: vm.updateCreatedStartDate,
            formatter: vm.formatDate,
          ),
          AdminListDateFilterConfig(
            label: 'Created End',
            value: vm.createdEndDate,
            onSelected: vm.updateCreatedEndDate,
            formatter: vm.formatDate,
          ),
          AdminListDateFilterConfig(
            label: 'Updated Start',
            value: vm.updatedStartDate,
            onSelected: vm.updateUpdatedStartDate,
            formatter: vm.formatDate,
          ),
          AdminListDateFilterConfig(
            label: 'Updated End',
            value: vm.updatedEndDate,
            onSelected: vm.updateUpdatedEndDate,
            formatter: vm.formatDate,
          ),
        ],
        onClear: vm.clearFilters,
      ),
      onNewPressed: vm.isExporting ? null : onExportPressed,
      buttonLabel: 'Export',
      buttonIcon: Icons.download_rounded,
      buttonBusy: vm.isExporting,
    );
  }
}

typedef _DashboardExportType = DashboardExportDocumentType;
typedef _DashboardExportConfig = DashboardExportConfig;

enum _DashboardExportSourceMode {
  currentRange,
  pastUnbilled,
  rangeAndPastUnbilled,
}

class _DashboardBatchExportConfig {
  const _DashboardBatchExportConfig({
    required this.types,
    required this.sourceMode,
    required this.setAsBilledWhenExported,
    required this.candidateBookingIds,
    required this.selectedBookingIds,
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
  final _DashboardExportSourceMode sourceMode;
  final bool setAsBilledWhenExported;
  final List<String> candidateBookingIds;
  final List<String> selectedBookingIds;
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

  Iterable<String> get excludedCandidateBookingIds => candidateBookingIds.where(
    (bookingId) => !selectedBookingIds.contains(bookingId),
  );

  List<Booking> selectedBookings(List<Booking> bookings) {
    final bookingById = {
      for (final booking in bookings)
        if ((booking.id ?? '').isNotEmpty) booking.id!: booking,
    };
    return selectedBookingIds
        .map((bookingId) => bookingById[bookingId])
        .whereType<Booking>()
        .toList();
  }

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
  const _DashboardExportDialog({
    required this.bookings,
    required this.vm,
    required this.singleItem,
    required this.excludedBookingIds,
    required this.onToggleExcluded,
    required this.onSubmit,
    this.singleItemCandidates,
  });

  final List<Booking> bookings;
  final AdminDashboardViewModel vm;
  final bool singleItem;
  final List<Booking>? singleItemCandidates;
  final Set<String> excludedBookingIds;
  final ValueChanged<String> onToggleExcluded;
  final Future<bool> Function(_DashboardBatchExportConfig config) onSubmit;

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
  late _DashboardExportSourceMode _sourceMode;
  bool _setAsBilledWhenExported = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final coveredDates = _resolveCurrentRangeWeekWindow(now);
    _documentDate = now;
    _coveredStartDate = coveredDates.$1;
    _coveredEndDate = coveredDates.$2;
    _sourceMode = _resolveInitialSourceMode();
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
  bool get _showsCoveredDateRange => !widget.singleItem;
  List<Booking> get _candidateBookings => _bookingsForSource(_sourceMode);
  List<String> get _candidateBookingIds => _candidateBookings
      .map((booking) => normalizeId(booking.id))
      .whereType<String>()
      .toList();
  List<String> get _selectedBookingIds => _candidateBookings
      .map((booking) => normalizeId(booking.id))
      .whereType<String>()
      .where((bookingId) => !widget.excludedBookingIds.contains(bookingId))
      .toList();

  void _unfocusCurrentField() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus) {
      currentFocus.unfocus();
    }
  }

  _DashboardExportSourceMode _resolveInitialSourceMode() {
    if (widget.singleItem) {
      return _DashboardExportSourceMode.currentRange;
    }
    return _DashboardExportSourceMode.rangeAndPastUnbilled;
  }

  List<Booking> _bookingsForSource(_DashboardExportSourceMode sourceMode) {
    if (widget.singleItem) {
      return widget.singleItemCandidates ?? widget.bookings.take(1).toList();
    }
    return switch (sourceMode) {
      _DashboardExportSourceMode.currentRange =>
        _currentRangeBookingsForCoveredDates(),
      _DashboardExportSourceMode.pastUnbilled =>
        _pastUnbilledBookingsForCoveredDates(),
      _DashboardExportSourceMode.rangeAndPastUnbilled =>
        _mergedBookingsForCoveredDates(),
    };
  }

  List<Booking> _currentRangeBookingsForCoveredDates() {
    return widget.bookings
        .where((booking) {
          final deliveredDate = _bookingSortDate(booking);
          if (deliveredDate == null) {
            return false;
          }
          final dateOnly = DateTime(
            deliveredDate.year,
            deliveredDate.month,
            deliveredDate.day,
          );
          final startOnly = DateTime(
            _coveredStartDate.year,
            _coveredStartDate.month,
            _coveredStartDate.day,
          );
          final endOnly = DateTime(
            _coveredEndDate.year,
            _coveredEndDate.month,
            _coveredEndDate.day,
          );
          return !dateOnly.isBefore(startOnly) && !dateOnly.isAfter(endOnly);
        })
        .toList(growable: false);
  }

  List<Booking> _pastUnbilledBookingsForCoveredDates() {
    final startOnly = DateTime(
      _coveredStartDate.year,
      _coveredStartDate.month,
      _coveredStartDate.day,
    );
    return widget.bookings
        .where((booking) {
          if (widget.vm.billingStatusValue(booking) !=
              AdminDashboardViewModel.billingStatusUnbilled) {
            return false;
          }
          final deliveredDate = _bookingSortDate(booking);
          if (deliveredDate == null) {
            return false;
          }
          final dateOnly = DateTime(
            deliveredDate.year,
            deliveredDate.month,
            deliveredDate.day,
          );
          return dateOnly.isBefore(startOnly);
        })
        .toList(growable: false);
  }

  List<Booking> _mergedBookingsForCoveredDates() {
    final byId = <String, Booking>{};
    for (final booking in _currentRangeBookingsForCoveredDates()) {
      final id = booking.id;
      if (id == null || id.isEmpty) {
        continue;
      }
      byId[id] = booking;
    }
    for (final booking in _pastUnbilledBookingsForCoveredDates()) {
      final id = booking.id;
      if (id == null || id.isEmpty) {
        continue;
      }
      byId.putIfAbsent(id, () => booking);
    }
    final merged = byId.values.toList(growable: false);
    merged.sort((left, right) {
      final byDate = _compareLatestFirst(
        _bookingSortDate(left),
        _bookingSortDate(right),
      );
      if (byDate != 0) {
        return byDate;
      }
      final leftId = int.tryParse(left.id ?? '');
      final rightId = int.tryParse(right.id ?? '');
      if (leftId != null && rightId != null) {
        return rightId.compareTo(leftId);
      }
      return (right.id ?? '').compareTo(left.id ?? '');
    });
    return merged;
  }

  DateTime? _bookingSortDate(Booking booking) {
    return _bookingEffectiveDate(booking);
  }

  int _compareLatestFirst(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return right.compareTo(left);
  }

  void _selectSourceMode(_DashboardExportSourceMode nextMode) {
    setState(() {
      _sourceMode = nextMode;
    });
  }

  void _toggleExcludedBooking(Booking booking) {
    final bookingId = normalizeId(booking.id);
    if (bookingId == null) {
      return;
    }
    widget.onToggleExcluded(bookingId);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final candidateBookings = _candidateBookings;
    return AdminModalShell(
      title: 'Export As',
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 14),
      actionsInset: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Download'),
        ),
      ],
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
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
                  AdminModalToggleRow(
                    title: 'Set as billed when exported',
                    value: _setAsBilledWhenExported,
                    onChanged: (value) {
                      setState(() {
                        _setAsBilledWhenExported = value;
                      });
                    },
                    leftInset: 0,
                    rightInset: 0,
                  ),
                  SizedBox(height: widget.singleItem ? 8 : 14),
                  AdminModalFieldSlot(
                    bottomPadding: 20,
                    child: _DashboardExportSourceSection(
                      singleItem: widget.singleItem,
                      sourceMode: _sourceMode,
                      currentRangeCount:
                          _currentRangeBookingsForCoveredDates().length,
                      pastUnbilledCount:
                          _pastUnbilledBookingsForCoveredDates().length,
                      combinedCount: _mergedBookingsForCoveredDates().length,
                      onChanged: _selectSourceMode,
                    ),
                  ),
                  if (!widget.singleItem)
                    AdminModalFieldSlot(
                      bottomPadding: 20,
                      child: _DashboardExportCandidateSection(
                        title: _candidateSectionTitle(
                          _sourceMode,
                          widget.singleItem,
                        ),
                        bookings: candidateBookings,
                        vm: widget.vm,
                        excludedBookingIds: widget.excludedBookingIds,
                        onToggleExcluded: _toggleExcludedBooking,
                      ),
                    ),
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
                    textInputAction: _showsBankFields
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_showsBankFields) {
                        _unfocusCurrentField();
                        _submit();
                      }
                    },
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
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        _unfocusCurrentField();
                        _submit();
                      },
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
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
    if (_candidateBookings.isEmpty) {
      AppSnackbar.showError(
        context,
        'No bookings are available for the selected export source.',
      );
      return;
    }
    if (_selectedBookingIds.isEmpty) {
      AppSnackbar.showError(
        context,
        'Please keep at least one booking included for export.',
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

    setState(() {
      _isSubmitting = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) {
      return;
    }
    final exportConfig = _DashboardBatchExportConfig(
      types: _selectedTypes.toList(),
      sourceMode: _sourceMode,
      setAsBilledWhenExported: _setAsBilledWhenExported,
      candidateBookingIds: _candidateBookingIds,
      selectedBookingIds: _selectedBookingIds,
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
    );
    final wasSuccessful = await widget.onSubmit(exportConfig);
    if (!mounted) {
      return;
    }
    if (wasSuccessful) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSubmitting = false;
    });
  }
}

String _candidateSectionTitle(
  _DashboardExportSourceMode sourceMode,
  bool singleItem,
) {
  if (singleItem) {
    return 'Selected Booking';
  }
  return switch (sourceMode) {
    _DashboardExportSourceMode.currentRange => 'Current Range Bookings',
    _DashboardExportSourceMode.pastUnbilled => 'Past Unbilled Bookings',
    _DashboardExportSourceMode.rangeAndPastUnbilled =>
      'Range + Past Unbilled Bookings',
  };
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

class _DashboardExportSourceSection extends StatelessWidget {
  const _DashboardExportSourceSection({
    required this.singleItem,
    required this.sourceMode,
    required this.currentRangeCount,
    required this.pastUnbilledCount,
    required this.combinedCount,
    required this.onChanged,
  });

  final bool singleItem;
  final _DashboardExportSourceMode sourceMode;
  final int currentRangeCount;
  final int pastUnbilledCount;
  final int combinedCount;
  final ValueChanged<_DashboardExportSourceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    if (singleItem) {
      return const SizedBox.shrink();
    }
    final helperStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
      height: 1.35,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'Export Source',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _DashboardExportSourceChip(
              label: 'Current Range',
              count: currentRangeCount,
              selected: sourceMode == _DashboardExportSourceMode.currentRange,
              onTap: () => onChanged(_DashboardExportSourceMode.currentRange),
            ),
            _DashboardExportSourceChip(
              label: 'Past Unbilled',
              count: pastUnbilledCount,
              selected: sourceMode == _DashboardExportSourceMode.pastUnbilled,
              onTap: () => onChanged(_DashboardExportSourceMode.pastUnbilled),
            ),
            _DashboardExportSourceChip(
              label: 'Range + Past Unbilled',
              count: combinedCount,
              selected:
                  sourceMode == _DashboardExportSourceMode.rangeAndPastUnbilled,
              onTap: () =>
                  onChanged(_DashboardExportSourceMode.rangeAndPastUnbilled),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 2),
          child: Text(
            'Current Range updates from the covered dates set below.',
            style: helperStyle,
          ),
        ),
      ],
    );
  }
}

class _DashboardExportSourceChip extends StatelessWidget {
  const _DashboardExportSourceChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
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
          child: Text(
            '$label ($count)',
            style: TextStyle(
              color: textColor,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardExportCandidateSection extends StatelessWidget {
  const _DashboardExportCandidateSection({
    required this.title,
    required this.bookings,
    required this.vm,
    required this.excludedBookingIds,
    required this.onToggleExcluded,
  });

  final String title;
  final List<Booking> bookings;
  final AdminDashboardViewModel vm;
  final Set<String> excludedBookingIds;
  final ValueChanged<Booking> onToggleExcluded;

  @override
  Widget build(BuildContext context) {
    final helperStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
      height: 1.35,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
            'Tick the checkbox to exclude a booking from this export session.',
            style: helperStyle,
          ),
        ),
        if (bookings.isEmpty)
          const AdminListItemCard(
            padding: EdgeInsets.all(20),
            child: AdminListStateText(
              message: 'No bookings are available for this export source.',
            ),
          )
        else
          ...bookings.asMap().entries.map((entry) {
            final bookingId = normalizeId(entry.value.id);
            final isExcluded =
                bookingId != null && excludedBookingIds.contains(bookingId);
            return Padding(
              padding: EdgeInsets.only(
                bottom: entry.key == bookings.length - 1 ? 0 : 10,
              ),
              child: _DashboardExportCandidateRow(
                booking: entry.value,
                vm: vm,
                isExcluded: isExcluded,
                onToggleExcluded: () => onToggleExcluded(entry.value),
              ),
            );
          }),
      ],
    );
  }
}

class _DashboardExportCandidateRow extends StatelessWidget {
  const _DashboardExportCandidateRow({
    required this.booking,
    required this.vm,
    required this.isExcluded,
    required this.onToggleExcluded,
  });

  final Booking booking;
  final AdminDashboardViewModel vm;
  final bool isExcluded;
  final VoidCallback onToggleExcluded;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DashboardExcludeCheckbox(value: isExcluded, onTap: onToggleExcluded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vm.client(booking).replaceFirst(RegExp(r'\s+\('), ' ('),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${AdminDashboardViewModel.deliveryFormNumber(booking)} | '
                  '${AdminDashboardViewModel.dropOffDateDisplay(booking)} | '
                  '${AdminDashboardViewModel.waybillNumber(booking)} | '
                  '${AdminDashboardViewModel.vanNumber(booking)}',
                  style: TextStyle(
                    color: isExcluded
                        ? AppColors.danger
                        : AppColors.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${vm.vanSize(booking)} | '
                  '${vm.billingStatusLabel(booking)} | '
                  '${AdminDashboardViewModel.amount(booking)}',
                  style: TextStyle(
                    color: isExcluded
                        ? AppColors.danger
                        : AppColors.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardExcludeCheckbox extends StatelessWidget {
  const _DashboardExcludeCheckbox({required this.value, required this.onTap});

  final bool value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = value
        ? AppColors.primaryColor
        : AppColors.primaryBorder;
    final fillColor = value ? AppColors.primaryColor : Colors.white;
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Builder(
        builder: (context) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: appPressableActive(context)
                ? (value
                      ? AppColors.primaryColor.withValues(alpha: 0.88)
                      : AppColors.primarySurfaceAlt.withValues(alpha: 0.4))
                : fillColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor, width: value ? 1.5 : 1.25),
          ),
          child: value
              ? const Icon(Icons.check_rounded, size: 11, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _DashboardBillingStatusAction extends StatelessWidget {
  const _DashboardBillingStatusAction({
    required this.value,
    required this.onTap,
  });

  static const Color _unbilledColor = Color(0xFF2EAD62);

  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isUnbilled = value == AdminDashboardViewModel.billingStatusUnbilled;
    return AdminListActionButton(
      icon: isUnbilled ? Icons.check_rounded : Icons.close_rounded,
      backgroundColor: isUnbilled ? _unbilledColor : AppColors.dangerStrong,
      onTap: onTap,
      size: 38,
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

(DateTime, DateTime) _resolveCurrentRangeWeekWindow(DateTime base) {
  final dateOnly = DateTime(base.year, base.month, base.day);
  final daysSinceSaturday =
      (dateOnly.weekday - DateTime.saturday + DateTime.daysPerWeek) %
      DateTime.daysPerWeek;
  final currentSaturday = dateOnly.subtract(Duration(days: daysSinceSaturday));
  final start = currentSaturday.subtract(const Duration(days: 7));
  final end = start.add(const Duration(days: 6));
  return (start, end);
}

DateTime? _bookingEffectiveDate(Booking booking) {
  final dropOffDate = BookingRecordCard.outputFieldDisplayValue(
    booking.statusOutputs,
    'drop_off_date',
  ).trim();
  if (dropOffDate.isNotEmpty) {
    final parsed = DateTime.tryParse(dropOffDate);
    if (parsed != null) {
      return parsed;
    }
  }
  final deliveredSection = booking.statusOutputs?['delivered'];
  if (deliveredSection is Map) {
    final submittedAt = deliveredSection['submitted_at'];
    if (submittedAt != null) {
      final parsed = DateTime.tryParse(submittedAt.toString());
      if (parsed != null) {
        return parsed;
      }
    }
    final completedAt = deliveredSection['completed_at'];
    if (completedAt != null) {
      final parsed = DateTime.tryParse(completedAt.toString());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return booking.updatedAt ?? booking.createdAt;
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
                      label: 'Date Start',
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
                      label: 'Date End',
                      value: widget.vm.endDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateEndDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: _DashboardDateFilter(
                      label: 'Created Start',
                      value: widget.vm.createdStartDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateCreatedStartDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: _DashboardDateFilter(
                      label: 'Created End',
                      value: widget.vm.createdEndDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateCreatedEndDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: _DashboardDateFilter(
                      label: 'Updated Start',
                      value: widget.vm.updatedStartDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateUpdatedStartDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: _DashboardDateFilter(
                      label: 'Updated End',
                      value: widget.vm.updatedEndDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateUpdatedEndDate,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: _DashboardBillingStatusFilter(
                      value: widget.vm.billingStatusFilter,
                      onChanged: widget.vm.updateBillingStatusFilter,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterClearButtonHeight,
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

class _DashboardBillingStatusFilter extends StatelessWidget {
  const _DashboardBillingStatusFilter({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AdminDropdownFormField<String>(
      initialValue: value == AdminDashboardViewModel.billingStatusAll
          ? null
          : value,
      decoration: adminFormInputDecoration(
        'Billing Status',
        radius: 16,
        minHeight: adminFilterFieldMinHeight,
      ),
      items: const [
        DropdownMenuItem<String>(
          value: AdminDashboardViewModel.billingStatusBilled,
          child: Text('Billed', overflow: TextOverflow.ellipsis),
        ),
        DropdownMenuItem<String>(
          value: AdminDashboardViewModel.billingStatusUnbilled,
          child: Text('Unbilled', overflow: TextOverflow.ellipsis),
        ),
      ],
      onChanged: onChanged,
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
                          : Colors.white,
                      suffixIcon: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _pickDate,
                        child: Icon(
                          Icons.calendar_today_rounded,
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
    required this.onToggleBillingStatus,
    required this.onView,
  });

  static const double _sectionGap = 14;
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
  static const _waybillExtraWidthAllowance = 14.0;
  static const _clientExtraWidthAllowance = 22.0;
  static const _defaultTrailingPadding =
      AdminListMeasurements.defaultTrailingPadding;
  static const _extraWidthAllowance = 18.0;
  static const _maxClientBasisWidth = 380.0;
  static const _responsiveCardsBreakpoint = 980.0;
  static const _wideLayoutOverflowTolerance = 48.0;

  final List<Booking> bookings;
  final AdminDashboardViewModel vm;
  final ValueChanged<Booking> onToggleBillingStatus;
  final ValueChanged<Booking> onView;

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
                bookings.map(AdminDashboardViewModel.dropOffDateDisplay),
              ),
            ),
          ),
        );
        final resolvedWaybillWidth =
            _resolvedColumnWidth(
              _maxTextWidth(
                context,
                textScaler,
                'Waybill No.',
                _longerText(
                  'Waybill No.',
                  _longestText(
                    bookings.map(
                      (booking) => _dashboardDisplayWaybill(
                        AdminDashboardViewModel.waybillNumber(booking),
                      ),
                    ),
                  ),
                ),
              ),
            ) +
            _waybillExtraWidthAllowance;
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
        final resolvedClientWidth =
            _resolvedColumnWidth(
              _cappedBasisWidth(
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
                _maxClientBasisWidth,
              ),
            ) +
            _clientExtraWidthAllowance;
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
        final actionsWidth = _maxValue(
          138,
          AdminListMeasurements.measureTextWidth(
            context,
            textScaler,
            'Actions',
            _headerStyle,
          ),
        );
        final resolvedActionWidth = actionsWidth + _extraWidthAllowance;

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
        final horizontalOverflow = totalMeasuredWidth - constraints.maxWidth;
        final useResponsiveCards =
            constraints.maxWidth < _responsiveCardsBreakpoint &&
            horizontalOverflow > _wideLayoutOverflowTolerance;
        if (useResponsiveCards) {
          return Column(
            children: bookings
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(
                      bottom: entry.key == bookings.length - 1 ? 0 : 12,
                    ),
                    child: _AdminDashboardResponsiveCard(
                      booking: entry.value,
                      vm: vm,
                      clientName: vm.client(entry.value),
                      dateValue: AdminDashboardViewModel.dropOffDateDisplay(
                        entry.value,
                      ),
                      onToggleBillingStatus: () =>
                          onToggleBillingStatus(entry.value),
                      onViewPressed: () => onView(entry.value),
                      onExportPressed: () => _exportBookings(
                        context,
                        vm,
                        bookings: <Booking>[entry.value],
                        singleItem: true,
                        excludedBookingIds: const <String>{},
                        onToggleExcludedSession: (_) {},
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalMeasuredWidth > constraints.maxWidth
                ? totalMeasuredWidth
                : constraints.maxWidth,
            child: Column(
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
                const SizedBox(height: _sectionGap),
                ...bookings.asMap().entries.map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(
                      bottom: entry.key == bookings.length - 1 ? 0 : 12,
                    ),
                    child: _AdminDashboardWideRow(
                      booking: entry.value,
                      vm: vm,
                      clientName: vm.client(entry.value),
                      dateValue: AdminDashboardViewModel.dropOffDateDisplay(
                        entry.value,
                      ),
                      resolvedDeliveryNumberWidth: resolvedDeliveryNumberWidth,
                      resolvedDateWidth: resolvedDateWidth,
                      resolvedWaybillWidth: resolvedWaybillWidth,
                      resolvedVanNumberWidth: resolvedVanNumberWidth,
                      resolvedVanSizeWidth: resolvedVanSizeWidth,
                      resolvedClientWidth: resolvedClientWidth,
                      resolvedAmountWidth: resolvedAmountWidth,
                      resolvedActionWidth: resolvedActionWidth,
                      onToggleBillingStatus: () =>
                          onToggleBillingStatus(entry.value),
                      onViewPressed: () => onView(entry.value),
                      onExportPressed: () => _exportBookings(
                        context,
                        vm,
                        bookings: <Booking>[entry.value],
                        singleItem: true,
                        excludedBookingIds: const <String>{},
                        onToggleExcludedSession: (_) {},
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  static double _maxValue(double first, double second) {
    return first > second ? first : second;
  }

  static double _cappedBasisWidth(double measuredWidth, double maxWidth) {
    return measuredWidth > maxWidth ? maxWidth : measuredWidth;
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
}

class _AdminDashboardBookingDetailHeader extends StatelessWidget {
  const _AdminDashboardBookingDetailHeader({
    required this.booking,
    required this.currentUser,
    required this.onBack,
    this.onEdit,
  });

  final Booking booking;
  final UserModel currentUser;
  final VoidCallback onBack;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Transform.translate(
                offset: const Offset(-8, 0),
                child: IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.primaryColor,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  visualDensity: VisualDensity.compact,
                  splashRadius: 22,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Booking ${booking.id ?? '-'}',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onEdit,
                  tooltip: 'Edit booking',
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  color: AppColors.primaryColor,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  visualDensity: VisualDensity.compact,
                  splashRadius: 22,
                ),
              ],
            ],
          ),
        ),
        BookingSupportButton(
          onPressed: () => openSupportDestination(
            context,
            user: currentUser,
            initialTopicKey: supportTopicBooking,
            initialBookingId: booking.id,
            initialUserId: booking.client?.id,
          ),
        ),
      ],
    );
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
    required this.onToggleBillingStatus,
    required this.onViewPressed,
    required this.onExportPressed,
  });

  final Booking booking;
  final AdminDashboardViewModel vm;
  final String clientName;
  final String dateValue;
  final double resolvedDeliveryNumberWidth;
  final double resolvedDateWidth;
  final double resolvedWaybillWidth;
  final double resolvedVanNumberWidth;
  final double resolvedVanSizeWidth;
  final double resolvedClientWidth;
  final double resolvedAmountWidth;
  final double resolvedActionWidth;
  final VoidCallback? onToggleBillingStatus;
  final VoidCallback? onViewPressed;
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
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          _DashboardFixedSlot(
            width: resolvedDateWidth,
            child: _DashboardBodyCell(
              child: Text(
                dateValue,
                style: _AdminDashboardCompletedBookingsTable._valueStyle,
                maxLines: 1,
                softWrap: false,
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
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          _DashboardFixedSlot(
            width: resolvedVanNumberWidth,
            child: _DashboardBodyCell(
              child: Text(
                AdminDashboardViewModel.vanNumber(booking),
                style: _AdminDashboardCompletedBookingsTable._valueStyle,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          _DashboardFixedSlot(
            width: resolvedVanSizeWidth,
            child: _DashboardBodyCell(
              child: Text(
                vm.vanSize(booking),
                style: _AdminDashboardCompletedBookingsTable._valueStyle,
                maxLines: 1,
                softWrap: false,
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
                maxLines: 2,
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
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          AdminListTrailingActionsLane(
            width: resolvedActionWidth,
            child: _DashboardBodyCell(
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DashboardBillingStatusAction(
                    value: vm.billingStatusValue(booking),
                    onTap: onToggleBillingStatus,
                  ),
                  const SizedBox(width: 8),
                  AdminListActionButton(
                    icon: Icons.visibility_rounded,
                    backgroundColor: Colors.yellow.shade900,
                    onTap: onViewPressed,
                    size: 38,
                  ),
                  const SizedBox(width: 8),
                  AdminListActionButton(
                    icon: Icons.download_rounded,
                    onTap: onExportPressed,
                    size: 38,
                  ),
                ],
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
    required this.onToggleBillingStatus,
    required this.onViewPressed,
    required this.onExportPressed,
  });

  final Booking booking;
  final AdminDashboardViewModel vm;
  final String clientName;
  final String dateValue;
  final VoidCallback? onToggleBillingStatus;
  final VoidCallback? onViewPressed;
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
          ('Date', dateValue),
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
              Row(
                children: [
                  _DashboardBillingStatusAction(
                    value: vm.billingStatusValue(booking),
                    onTap: onToggleBillingStatus,
                  ),
                  const SizedBox(width: 8),
                  AdminListActionButton(
                    icon: Icons.visibility_rounded,
                    backgroundColor: Colors.yellow.shade900,
                    onTap: onViewPressed,
                    size: 38,
                  ),
                  const SizedBox(width: 8),
                  AdminListActionButton(
                    icon: Icons.download_rounded,
                    onTap: onExportPressed,
                    size: 38,
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
            ],
          ),
        );
      },
    );
  }
}

class _DashboardFixedSlot extends StatelessWidget {
  const _DashboardFixedSlot({required this.width, required this.child});

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
    this.trailingPadding = AdminListMeasurements.defaultTrailingPadding,
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
    this.trailingPadding = AdminListMeasurements.defaultTrailingPadding,
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
