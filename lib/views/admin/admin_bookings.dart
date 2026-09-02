import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/constants/palawan_locations.dart';
import 'package:webapp/constants/puerto_princesa_barangays.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/status.request.dart';
import 'package:webapp/requests/chassis.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/services/local_form_draft_service.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/services/status_form_engine.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/utils/performance_trace.dart';
import 'package:webapp/view_models/admin/admin_bookings.vm.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/views/client/client_booking_home_view.dart';
import 'package:webapp/views/shared/booking_workflow_view.dart';
import 'package:webapp/views/shared/support_center_view.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_image_source_picker.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';
import 'package:webapp/widgets/shared/chassis_status_presentation.dart';

class AdminBookingsView extends StatefulWidget {
  const AdminBookingsView({
    super.key,
    required this.user,
    this.initialBooking,
    this.onInitialBookingHandled,
  });

  final UserModel user;
  final Booking? initialBooking;
  final VoidCallback? onInitialBookingHandled;

  static Future<Booking?> showEditBookingDialog(
    BuildContext context, {
    required Booking booking,
    required UserModel currentUser,
  }) async {
    if (!RoleAccessService.instance.canAccess(
      DispatcherAccessCapability.bookingsUpdate,
      role: RoleAccessService.instance.effectiveRoleKey(currentUser.role),
    )) {
      throw Exception('You do not have access to edit bookings.');
    }
    final vm = AdminBookingsViewModel();
    try {
      if (!_hasReadyEditDialogSeedData(vm)) {
        await vm.load();
        if (vm.errorMessage != null) {
          throw Exception(vm.errorMessage!);
        }
      }
      if (!context.mounted) {
        return null;
      }
      final requirements = await _resolveEditBookingRequirements();
      final chassis = await _resolveActiveChassis(booking.chassisId);
      if (!context.mounted) {
        return null;
      }
      return showAppDialog<Booking>(
        context: context,
        modalKey: 'booking-edit:${booking.id ?? "-"}',
        builder: (dialogContext) => _EditAdminBookingDialog(
          booking: booking,
          currentUser: currentUser,
          onSave: vm.saveEditedBooking,
          currentStatusLabel: vm.clientStatusLabel(booking),
          clientUsers: vm.clientUsers(),
          statuses: vm.activeStatuses(),
          drivers: vm.roleUsers('driver'),
          helpers: vm.roleUsers('helper'),
          vehicleSizes: vm.activeVehicleSizes(),
          chassis: chassis,
          originBarangayRequired: requirements.originBarangayRequired,
          destinationBarangayRequired: requirements.destinationBarangayRequired,
        ),
      );
    } finally {
      vm.dispose();
    }
  }

  static Future<Booking?> showNewBookingDialog(
    BuildContext context, {
    required UserModel currentUser,
  }) async {
    if (!RoleAccessService.instance.canAccess(
      DispatcherAccessCapability.bookingsCreate,
      role: RoleAccessService.instance.effectiveRoleKey(currentUser.role),
    )) {
      throw Exception('You do not have access to create bookings.');
    }
    final vm = AdminBookingsViewModel();
    try {
      await vm.load();
      if (vm.errorMessage != null) {
        throw Exception(vm.errorMessage!);
      }
      if (!context.mounted) {
        return null;
      }
      return showAppDialog<Booking>(
        context: context,
        modalKey: 'booking-new',
        builder: (dialogContext) => _NewAdminBookingDialog(
          currentUser: currentUser,
          clientUsers: vm.clientUsers(),
          onBookingSubmitted: (booking) {
            Navigator.of(dialogContext).pop(booking);
          },
        ),
      );
    } finally {
      vm.dispose();
    }
  }

  static Future<List<Chassis>> _resolveActiveChassis(
    String? selectedChassisId,
  ) async {
    const lookupTimeout = Duration(seconds: 2);
    final request = ChassisRequest.instance;
    try {
      final all = await request.getChassis().timeout(lookupTimeout);
      return all
          .where(
            (item) => item.isActive || item.id.toString() == selectedChassisId,
          )
          .toList(growable: false);
    } catch (_) {
      // Opening the edit modal must not wait for a slow catalog request.
      // The realtime/cache refresh can fill the catalog for the next open.
      unawaited(request.getChassis().catchError((_) => <Chassis>[]));
      return request.hydratedChassisSnapshot
          .where(
            (item) => item.isActive || item.id.toString() == selectedChassisId,
          )
          .toList(growable: false);
    }
  }

  static List<Chassis> hydratedActiveChassis(String? selectedChassisId) {
    return ChassisRequest.instance.hydratedChassisSnapshot
        .where(
          (item) => item.isActive || item.id.toString() == selectedChassisId,
        )
        .toList(growable: false);
  }

  @override
  State<AdminBookingsView> createState() => _AdminBookingsViewState();
}

String _chassisLabel(Chassis chassis) {
  final name = chassis.name.trim();
  return name.isEmpty ? 'Chassis ${chassis.id}' : name;
}

class _AdminBookingsViewState extends State<AdminBookingsView> {
  static const _toolbarControlHeight = 52.0;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  final AdminBookingsViewModel _viewModel = AdminBookingsViewModel();
  Booking? _selectedBooking;
  late final ScrollController _detailScrollController;

  String? get _effectiveRole =>
      _roleAccessService.effectiveRoleKey(widget.user.role);

  bool get _canCreateBookings => _roleAccessService.canAccess(
    DispatcherAccessCapability.bookingsCreate,
    role: _effectiveRole,
  );

  bool get _canUpdateBookings => _roleAccessService.canAccess(
    DispatcherAccessCapability.bookingsUpdate,
    role: _effectiveRole,
  );

  @override
  void initState() {
    super.initState();
    _detailScrollController = ScrollController();
    _selectedBooking = widget.initialBooking;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onInitialBookingHandled?.call();
      _viewModel.load();
    });
  }

  @override
  void didUpdateWidget(covariant AdminBookingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final initialBooking = widget.initialBooking;
    if (initialBooking == null || initialBooking.id == _selectedBooking?.id) {
      return;
    }
    setState(() {
      _selectedBooking = initialBooking;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onInitialBookingHandled?.call();
    });
  }

  @override
  void dispose() {
    _detailScrollController.dispose();
    super.dispose();
  }

  Future<void> _openNewBookingDialog(AdminBookingsViewModel vm) async {
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => _NewAdminBookingDialog(
        currentUser: widget.user,
        clientUsers: vm.clientUsers(),
        onBookingSubmitted: (booking) async {
          if (!mounted) {
            return;
          }
          vm.ingestSubmittedBooking(booking);
          Navigator.of(dialogContext).pop();
          setState(() {
            _selectedBooking = booking;
          });
        },
      ),
    );
  }

  Future<void> _openEditBookingDialog(
    AdminBookingsViewModel vm,
    Booking booking,
  ) async {
    final stopwatch = Stopwatch()..start();
    PerformanceTrace.event(
      'admin-bookings-view',
      'edit open start booking=${booking.id ?? '-'}',
    );
    try {
      // The editor must open from the hydrated app state. Catalog refreshes
      // stay in the background rather than blocking the user's tap.
      final requirements =
          _resolveEditBookingRequirementsFromForms(
            StatusRequest.hasResolvedForms
                ? StatusRequest.hydratedFormsSnapshot
                : const [],
          ) ??
          const _EditBookingRequirements();
      final chassis = AdminBookingsView.hydratedActiveChassis(
        booking.chassisId,
      );
      unawaited(
        ChassisRequest.instance.getChassis().catchError((_) => <Chassis>[]),
      );
      final updatedBooking = await showAppDialog<Booking>(
        context: context,
        modalKey: 'booking-edit:${booking.id ?? "-"}',
        builder: (dialogContext) => _EditAdminBookingDialog(
          booking: booking,
          currentUser: widget.user,
          onSave: vm.saveEditedBooking,
          currentStatusLabel: vm.clientStatusLabel(booking),
          clientUsers: vm.clientUsers(),
          statuses: vm.activeStatuses(),
          drivers: vm.roleUsers('driver'),
          helpers: vm.roleUsers('helper'),
          vehicleSizes: vm.activeVehicleSizes(),
          chassis: chassis,
          originBarangayRequired: requirements.originBarangayRequired,
          destinationBarangayRequired: requirements.destinationBarangayRequired,
        ),
      );
      if (updatedBooking == null) {
        return;
      }
      vm.ingestSubmittedBooking(updatedBooking);
      if (_selectedBooking?.id == updatedBooking.id) {
        setState(() {
          _selectedBooking = updatedBooking;
        });
      }
    } catch (error) {
      if (mounted) {
        AppSnackbar.showError(
          context,
          userFacingErrorMessage(
            error,
            fallback: 'We could not open the booking editor.',
          ),
        );
      }
    } finally {
      PerformanceTrace.event(
        'admin-bookings-view',
        'edit open finish booking=${booking.id ?? '-'} elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    PerformanceTrace.build('admin-bookings-view');
    return ViewModelBuilder<AdminBookingsViewModel>.reactive(
      viewModelBuilder: () => _viewModel,
      builder: (context, vm, child) {
        final selectedBooking = _selectedBooking == null
            ? null
            : vm.bookings
                      .where((booking) => booking.id == _selectedBooking!.id)
                      .firstOrNull ??
                  _selectedBooking;
        final filteredBookings = vm.filteredBookings();
        final showInitialLoading =
            !vm.hasResolvedInitialBookings &&
            selectedBooking == null &&
            vm.errorMessage == null &&
            vm.bookings.isEmpty;

        if (selectedBooking != null) {
          return AppPageLoadingOverlay(
            isVisible: false,
            message: vm.busyMessage,
            child: SingleChildScrollView(
              key: PageStorageKey(
                'admin-booking-detail-${selectedBooking.id ?? ''}',
              ),
              controller: _detailScrollController,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AdminBookingDetailHeader(
                    booking: selectedBooking,
                    user: widget.user,
                    onBack: () {
                      setState(() {
                        _selectedBooking = null;
                      });
                    },
                    onEdit: !_canUpdateBookings
                        ? null
                        : () => unawaited(
                            _openEditBookingDialog(vm, selectedBooking),
                          ),
                  ),
                  const SizedBox(height: 16),
                  BookingWorkflowView(
                    key: ValueKey(
                      'admin-booking-workflow-${selectedBooking.id ?? ''}',
                    ),
                    user: widget.user,
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

        return AppPageLoadingOverlay(
          isVisible: showInitialLoading,
          message: vm.busyMessage,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppRefreshStrip(isVisible: vm.isBusy),
                AdminListToolbar(
                  controlHeight: _toolbarControlHeight,
                  surfaceRadius: 16,
                  search: AdminListSearchField(
                    controlHeight: _toolbarControlHeight,
                    surfaceRadius: 16,
                    initialValue: vm.searchQuery,
                    onChanged: vm.setSearchQuery,
                  ),
                  filtersBuilder: (context, iconOnly) =>
                      AdminListDynamicFiltersPanel(
                        iconOnly: iconOnly,
                        filters: [
                          AdminListDropdownFilterConfig(
                            label: 'Status',
                            value: vm.statusFilter,
                            items: vm.statusOptions,
                            onChanged: vm.setStatusFilter,
                          ),
                          AdminListDateFilterConfig(
                            label: 'Created Start',
                            value: vm.startDate,
                            onSelected: vm.updateStartDate,
                            formatter: vm.formatDate,
                          ),
                          AdminListDateFilterConfig(
                            label: 'Created End',
                            value: vm.endDate,
                            onSelected: vm.updateEndDate,
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
                  onNewPressed: _canCreateBookings
                      ? () => _openNewBookingDialog(vm)
                      : null,
                ),
                const SizedBox(height: 12),
                if (vm.errorMessage != null)
                  _AdminBookingsStateCard(
                    child: AdminListStateText(message: vm.errorMessage!),
                  )
                else if (vm.bookings.isEmpty)
                  _AdminBookingsStateCard(
                    child: const AdminListStateText(
                      message: 'No bookings yet.',
                    ),
                  )
                else if (filteredBookings.isEmpty)
                  _AdminBookingsStateCard(
                    child: const AdminListStateText(
                      message: 'No bookings matched your current search.',
                    ),
                  )
                else
                  _AdminBookingsTable(
                    bookings: filteredBookings,
                    vm: vm,
                    onView: (booking) {
                      setState(() {
                        _selectedBooking = booking;
                      });
                    },
                    onEdit: _canUpdateBookings
                        ? (booking) {
                            unawaited(_openEditBookingDialog(vm, booking));
                          }
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

bool _hasReadyEditDialogSeedData(AdminBookingsViewModel vm) {
  return vm.clientUsers().isNotEmpty &&
      vm.activeStatuses().isNotEmpty &&
      vm.activeVehicleSizes().isNotEmpty;
}

Future<_EditBookingRequirements> _resolveEditBookingRequirements() async {
  final shared = _resolveEditBookingRequirementsFromForms(
    StatusRequest.hasResolvedForms
        ? StatusRequest.hydratedFormsSnapshot
        : const [],
  );
  if (shared != null) {
    return shared;
  }
  final bookForms = await StatusRequest.instance.getStatusFormsByRoleAndStatus(
    'client',
    'book',
  );
  return _resolveEditBookingRequirementsFromForms(bookForms) ??
      const _EditBookingRequirements();
}

_EditBookingRequirements? _resolveEditBookingRequirementsFromForms(
  List<StatusForm> forms,
) {
  final activeBookForm = forms
      .where((form) => form.resolvedIsMainForm && form.isActive != false)
      .firstOrNull;
  if (activeBookForm == null) {
    return null;
  }
  final originBarangayField = activeBookForm.fields
      .cast<StatusField?>()
      .firstWhere(
        (field) => (field?.key ?? '').trim() == 'origin_barangay',
        orElse: () => null,
      );
  final destinationBarangayField = activeBookForm.fields
      .cast<StatusField?>()
      .firstWhere(
        (field) => (field?.key ?? '').trim() == 'destination_barangay',
        orElse: () => null,
      );
  final originRequired =
      originBarangayField != null &&
      (activeBookForm.fieldOverrides[originBarangayField.id]?.required ??
          originBarangayField.required ??
          false);
  final destinationRequired =
      destinationBarangayField != null &&
      (activeBookForm.fieldOverrides[destinationBarangayField.id]?.required ??
          destinationBarangayField.required ??
          false);
  return _EditBookingRequirements(
    originBarangayRequired: originRequired,
    destinationBarangayRequired: destinationRequired,
  );
}

class _EditBookingRequirements {
  const _EditBookingRequirements({
    this.originBarangayRequired = false,
    this.destinationBarangayRequired = false,
  });

  final bool originBarangayRequired;
  final bool destinationBarangayRequired;
}

class _EditAdminBookingDialog extends StatefulWidget {
  const _EditAdminBookingDialog({
    required this.booking,
    required this.currentUser,
    required this.onSave,
    required this.currentStatusLabel,
    required this.clientUsers,
    required this.statuses,
    required this.drivers,
    required this.helpers,
    required this.vehicleSizes,
    required this.chassis,
    required this.originBarangayRequired,
    required this.destinationBarangayRequired,
  });

  final Booking booking;
  final UserModel currentUser;
  final Future<Booking> Function(Booking booking) onSave;
  final String currentStatusLabel;
  final List<UserModel> clientUsers;
  final List<Status> statuses;
  final List<UserModel> drivers;
  final List<UserModel> helpers;
  final List<VehicleCatalogItem> vehicleSizes;
  final List<Chassis> chassis;
  final bool originBarangayRequired;
  final bool destinationBarangayRequired;

  @override
  State<_EditAdminBookingDialog> createState() =>
      _EditAdminBookingDialogState();
}

class _EditAdminBookingDialogState extends State<_EditAdminBookingDialog> {
  late final TextEditingController _pickUpDateController;
  late final TextEditingController _pickUpTimeController;
  late final TextEditingController _dropOffDateController;
  late final TextEditingController _dropOffTimeController;
  late final TextEditingController _deliveryFormNumberController;
  late final TextEditingController _waybillNumberController;
  late final TextEditingController _vanNumberController;
  late final TextEditingController _amountController;
  late final TextEditingController _originController;
  late final TextEditingController _originBarangayController;
  late final TextEditingController _destinationController;
  late final TextEditingController _destinationBarangayController;
  late final TextEditingController _representativeNameController;
  late final TextEditingController _representativePhoneController;
  final FocusNode _representativeNameFocusNode = FocusNode();
  final FocusNode _representativePhoneFocusNode = FocusNode();
  final FocusNode _waybillPhotoFocusNode = FocusNode();
  final FocusNode _waybillNumberFocusNode = FocusNode();
  final FocusNode _vanNumberFocusNode = FocusNode();
  final FocusNode _vanSizeFocusNode = FocusNode();
  final FocusNode _amountFocusNode = FocusNode();
  final FocusNode _pickUpDateFocusNode = FocusNode();
  final FocusNode _pickUpTimeFocusNode = FocusNode();
  final FocusNode _dropOffDateFocusNode = FocusNode();
  final FocusNode _dropOffTimeFocusNode = FocusNode();
  final FocusNode _originFocusNode = FocusNode();
  final FocusNode _originBarangayFocusNode = FocusNode();
  final FocusNode _destinationFocusNode = FocusNode();
  final FocusNode _destinationBarangayFocusNode = FocusNode();
  final FocusNode _deliveryFormPhotoFocusNode = FocusNode();
  final FocusNode _deliveryFormNumberFocusNode = FocusNode();
  final FocusNode _statusFocusNode = FocusNode();
  final FocusNode _driverFocusNode = FocusNode();
  final FocusNode _helperFocusNode = FocusNode();
  final FocusNode _chassisFocusNode = FocusNode();
  late String _selectedBookerId;
  late String _statusKey;
  String? _driverId;
  String? _helperId;
  String? _chassisId;
  String? _vanSize;
  dynamic _waybillPhotoValue;
  dynamic _deliveryFormPhotoValue;
  String? _originErrorText;
  String? _originBarangayErrorText;
  String? _destinationErrorText;
  String? _destinationBarangayErrorText;
  List<VehicleCatalogItem> _vehicleSizes = const [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _vehicleSizes = List<VehicleCatalogItem>.from(widget.vehicleSizes);
    final initialPickUpDate = _existingFieldValue('pick_up_date');
    final initialPickUpTime = _existingFieldValue('pick_up_time');
    final initialDropOffDate = _existingFieldValue('drop_off_date');
    final initialDropOffTime = _existingFieldValue('drop_off_time');
    final initialDeliveryFormNumber = _existingFieldValue(
      'delivery_form_number',
    );
    final initialWaybill = _existingFieldValue('waybill_number');
    final initialVanNumber = _existingFieldValue('van_number');
    final initialAmount = _existingFieldValue('amount');
    final initialOrigin = _existingFieldValue('origin');
    final initialOriginBarangay = _existingFieldValue('origin_barangay');
    final initialDestination = _existingFieldValue('destination');
    final initialDestinationBarangay = _existingFieldValue(
      'destination_barangay',
    );
    final initialRepresentativeName = _existingFieldValue(
      'representative_name',
    );
    final initialRepresentativePhone = _existingFieldValue(
      'representative_phone',
    );
    _pickUpDateController = TextEditingController(
      text: initialPickUpDate ?? '',
    );
    _pickUpTimeController = TextEditingController(
      text: initialPickUpTime ?? '',
    );
    _dropOffDateController = TextEditingController(
      text: initialDropOffDate ?? '',
    );
    _dropOffTimeController = TextEditingController(
      text: initialDropOffTime ?? '',
    );
    _deliveryFormNumberController = TextEditingController(
      text: initialDeliveryFormNumber ?? '',
    );
    _waybillNumberController = TextEditingController(
      text: initialWaybill ?? '',
    );
    _vanNumberController = TextEditingController(text: initialVanNumber ?? '');
    _amountController = TextEditingController(text: initialAmount ?? '');
    _originController = TextEditingController(text: initialOrigin ?? '');
    _originBarangayController = TextEditingController(
      text: initialOriginBarangay ?? '',
    );
    _destinationController = TextEditingController(
      text: initialDestination ?? '',
    );
    _destinationBarangayController = TextEditingController(
      text: initialDestinationBarangay ?? '',
    );
    _representativeNameController = TextEditingController(
      text: initialRepresentativeName ?? '',
    );
    _representativePhoneController = TextEditingController(
      text: initialRepresentativePhone ?? '',
    );
    _selectedBookerId = widget.booking.client?.id?.trim() ?? '';
    _statusKey = widget.booking.clientStatus ?? '';
    _driverId = widget.booking.driver?.id;
    _helperId = widget.booking.helper?.id;
    _chassisId = widget.booking.chassisId;
    final rawVanSize = _existingFieldValue('van_size');
    _vanSize = _normalizeVehicleSizeId(rawVanSize?.toString());
    _waybillPhotoValue = BookingRecordCard.outputFieldValue(
      widget.booking.statusOutputs,
      'waybill_photo',
    );
    _deliveryFormPhotoValue = BookingRecordCard.outputFieldValue(
      widget.booking.statusOutputs,
      'delivery_form_photo',
    );
    if (_vehicleSizes.isEmpty) {
      unawaited(_loadVehicleSizesFallback());
    }
  }

  Future<void> _loadVehicleSizesFallback() async {
    try {
      final resolvedSizes = await VehicleRequest.instance.getSizes();
      if (!mounted) {
        return;
      }
      setState(() {
        _vehicleSizes = resolvedSizes
            .where((size) => size.isActive != false)
            .toList(growable: false);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _pickUpDateController.dispose();
    _pickUpTimeController.dispose();
    _dropOffDateController.dispose();
    _dropOffTimeController.dispose();
    _deliveryFormNumberController.dispose();
    _waybillNumberController.dispose();
    _vanNumberController.dispose();
    _amountController.dispose();
    _originController.dispose();
    _originBarangayController.dispose();
    _destinationController.dispose();
    _destinationBarangayController.dispose();
    _representativeNameController.dispose();
    _representativePhoneController.dispose();
    _representativeNameFocusNode.dispose();
    _representativePhoneFocusNode.dispose();
    _waybillPhotoFocusNode.dispose();
    _waybillNumberFocusNode.dispose();
    _vanNumberFocusNode.dispose();
    _vanSizeFocusNode.dispose();
    _amountFocusNode.dispose();
    _pickUpDateFocusNode.dispose();
    _pickUpTimeFocusNode.dispose();
    _dropOffDateFocusNode.dispose();
    _dropOffTimeFocusNode.dispose();
    _originFocusNode.dispose();
    _originBarangayFocusNode.dispose();
    _destinationFocusNode.dispose();
    _destinationBarangayFocusNode.dispose();
    _deliveryFormPhotoFocusNode.dispose();
    _deliveryFormNumberFocusNode.dispose();
    _statusFocusNode.dispose();
    _driverFocusNode.dispose();
    _helperFocusNode.dispose();
    _chassisFocusNode.dispose();
    super.dispose();
  }

  void _focusNext(FocusNode focusNode) {
    if (!mounted) {
      return;
    }
    FocusScope.of(context).requestFocus(focusNode);
  }

  void _unfocusCurrentField() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus) {
      currentFocus.unfocus();
    }
  }

  Widget _buildPhotoUploadField({
    required String label,
    required FocusNode focusNode,
    required FocusNode nextFocusNode,
    required dynamic value,
    required ValueChanged<dynamic> onChanged,
    double bottomPadding = 4,
  }) {
    return AdminModalActionField(
      label: label,
      focusNode: focusNode,
      valueText: _photoDisplayValue(value),
      hintText: '',
      bottomPadding: bottomPadding,
      onTap: () => _pickPhotoFieldImage(
        nextFocusNode: nextFocusNode,
        onChanged: onChanged,
      ),
      onSubmitted: () => _pickPhotoFieldImage(
        nextFocusNode: nextFocusNode,
        onChanged: onChanged,
      ),
      suffixIcon: const Padding(
        padding: EdgeInsets.only(right: 6),
        child: Icon(Icons.upload_rounded, color: AppColors.primaryColor),
      ),
    );
  }

  Future<void> _pickPhotoFieldImage({
    required FocusNode nextFocusNode,
    required ValueChanged<dynamic> onChanged,
  }) async {
    final image = await showAppImageSourcePicker(context);
    if (image == null || !mounted) {
      return;
    }
    onChanged(<String, dynamic>{
      'name': image.fileName,
      'bytes': image.bytes,
      'size': image.size,
      'mime_type': image.mimeType,
    });
    _focusNext(nextFocusNode);
  }

  static String _photoDisplayValue(dynamic value) {
    if (value is Map) {
      final name = value['name']?.toString().trim();
      if (name?.isNotEmpty == true) {
        return name!;
      }
    }
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return '';
    }
    final normalized = raw.split('?').first;
    final lastSegment = normalized.split('/').last.trim();
    return lastSegment.isNotEmpty ? lastSegment : raw;
  }

  String? _pendingFieldValue(String key) {
    final outputs = widget.booking.statusOutputs;
    if (outputs == null || outputs.isEmpty) {
      return null;
    }
    final pendingSection = outputs['pending'];
    if (pendingSection is! Map || pendingSection['fields'] is! Map) {
      return null;
    }
    final fields = Map<String, dynamic>.from(pendingSection['fields'] as Map);
    final rawValue = fields[key]?.toString().trim();
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    return rawValue;
  }

  String? _existingFieldValue(String key) {
    final preferredPendingValue = _pendingFieldValue(key);
    if (preferredPendingValue != null) {
      return preferredPendingValue;
    }
    final rawValue = BookingRecordCard.outputFieldValue(
      widget.booking.statusOutputs,
      key,
    );
    final normalized = rawValue?.toString().trim();
    if (normalized == null || normalized.isEmpty || normalized == '-') {
      return null;
    }
    return normalized;
  }

  bool get _showsOriginBarangayField =>
      _originController.text.trim().toLowerCase() == 'puerto princesa city';

  bool get _showsDestinationBarangayField =>
      _destinationController.text.trim().toLowerCase() ==
      'puerto princesa city';

  List<DropdownMenuItem<String>> _buildVanSizeItems() {
    final items = <DropdownMenuItem<String>>[];
    final seenValues = <String>{};

    void addItem(String value, String label) {
      final normalizedValue = value.trim();
      if (normalizedValue.isEmpty || !seenValues.add(normalizedValue)) {
        return;
      }
      items.add(
        DropdownMenuItem<String>(
          value: normalizedValue,
          child: Text(
            label.trim().isNotEmpty ? label : normalizedValue,
            overflow: TextOverflow.ellipsis,
            style: adminDropdownDisplayTextStyle,
          ),
        ),
      );
    }

    if (_vanSize?.trim().isNotEmpty == true) {
      addItem(
        _vanSize!,
        VehicleRequest.instance.displayVehicleSizeLabel(_vanSize!),
      );
    }

    for (final size in _vehicleSizes) {
      final value = size.id?.trim();
      final label = size.name?.trim().isNotEmpty == true
          ? size.name!.trim()
          : (size.slug?.trim() ?? '-');
      if (value != null && value.isNotEmpty) {
        addItem(value, label);
      }
    }

    return items;
  }

  List<DropdownMenuItem<String>> _buildStatusItems() {
    final items = <DropdownMenuItem<String>>[];
    final seenValues = <String>{};

    String labelForStatusValue(String value) {
      final normalizedValue = value.trim();
      for (final status in widget.statuses) {
        if ((status.key?.trim() ?? '') != normalizedValue) {
          continue;
        }
        final label = status.label?.trim();
        if (label != null && label.isNotEmpty) {
          return label;
        }
        break;
      }
      if ((widget.booking.clientStatus?.trim() ?? '') == normalizedValue) {
        return widget.currentStatusLabel;
      }
      return normalizedValue;
    }

    void addItem(String value, String label) {
      final normalizedValue = value.trim();
      if (normalizedValue.isEmpty || !seenValues.add(normalizedValue)) {
        return;
      }
      items.add(
        DropdownMenuItem<String>(
          value: normalizedValue,
          child: Text(
            label.trim().isNotEmpty ? label : normalizedValue,
            overflow: TextOverflow.ellipsis,
            style: adminDropdownDisplayTextStyle,
          ),
        ),
      );
    }

    for (final status in widget.statuses) {
      final value = status.key?.trim();
      final label = status.label?.trim().isNotEmpty == true
          ? status.label!.trim()
          : (status.key?.trim() ?? '-');
      if (value != null && value.isNotEmpty) {
        addItem(value, label);
      }
    }

    if (_statusKey.trim().isNotEmpty &&
        !seenValues.contains(_statusKey.trim())) {
      addItem(_statusKey, labelForStatusValue(_statusKey));
    }

    return items;
  }

  List<DropdownMenuItem<String>> _buildRoleUserItems({
    required String? selectedUserId,
    required List<UserModel> activeUsers,
    required String fallbackRole,
  }) {
    final items = <DropdownMenuItem<String>>[];
    final seenValues = <String>{};

    void addUserItem(String value, String label, {UserModel? user}) {
      final normalizedValue = value.trim();
      if (normalizedValue.isEmpty || !seenValues.add(normalizedValue)) {
        return;
      }
      items.add(
        DropdownMenuItem<String>(
          value: normalizedValue,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: adminDropdownDisplayTextStyle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                user?.isOnline == true ? 'Online' : 'Offline',
                style: TextStyle(
                  color: user?.isOnline == true
                      ? const Color(0xFF218A4B)
                      : AppColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (selectedUserId?.trim().isNotEmpty == true) {
      addUserItem(
        selectedUserId!,
        _fallbackUserLabel(selectedUserId, fallbackRole),
        user: _userForId(selectedUserId),
      );
    }

    for (final user in activeUsers) {
      final value = user.id?.trim();
      if (value != null && value.isNotEmpty) {
        addUserItem(value, _userLabel(user), user: user);
      }
    }

    return items;
  }

  List<DropdownMenuItem<String>> _buildChassisItems() {
    final items = <DropdownMenuItem<String>>[];
    final seenIds = <String>{};

    void addItem(String? id, String label) {
      final normalizedId = id?.trim() ?? '';
      if (normalizedId.isEmpty || !seenIds.add(normalizedId)) {
        return;
      }
      items.add(
        DropdownMenuItem<String>(
          value: normalizedId,
          child: ChassisStatusOptionLabel(
            label: label,
            status:
                widget.chassis
                    .where((chassis) => chassis.id.toString() == normalizedId)
                    .firstOrNull
                    ?.currentStatus ??
                '',
          ),
        ),
      );
    }

    for (final chassis in widget.chassis) {
      addItem(chassis.id.toString(), _chassisLabel(chassis));
    }
    return items;
  }

  UserModel? _userForId(String? userId) {
    final normalizedUserId = userId?.trim();
    if (normalizedUserId == null || normalizedUserId.isEmpty) {
      return null;
    }
    for (final user in [...widget.drivers, ...widget.helpers]) {
      if (user.id?.trim() == normalizedUserId) {
        return user;
      }
    }
    return null;
  }

  String _fallbackUserLabel(String userId, String fallbackRole) {
    for (final user in [
      ...widget.drivers,
      ...widget.helpers,
      if (widget.booking.client != null) widget.booking.client!,
      if (widget.booking.driver != null) widget.booking.driver!,
      if (widget.booking.helper != null) widget.booking.helper!,
    ]) {
      if (user.id == userId) {
        return _userLabel(user);
      }
    }
    return fallbackRole;
  }

  Future<void> _pickDateForController(
    TextEditingController controller,
    FocusNode nextFocusNode,
  ) async {
    final now = DateTime.now();
    final initialDate = DateTime.tryParse(controller.text.trim()) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      controller.text = picked.toIso8601String().split('T').first;
    });
    _focusNext(nextFocusNode);
  }

  Future<void> _pickTimeForController(
    TextEditingController controller,
    FocusNode nextFocusNode,
  ) async {
    final localizations = MaterialLocalizations.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      controller.text = localizations.formatTimeOfDay(picked);
    });
    _focusNext(nextFocusNode);
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: 'Edit Booking',
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      actionsInset: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _handleSave,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Save Changes'),
        ),
      ],
      child: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: AdminModalFormBody(
            children: [
              AdminModalFieldsSection(
                children: [
                  AdminModalDropdownField<String>(
                    label: 'Booked By',
                    hintText: 'Select Client',
                    initialValue: _selectedBookerId.isEmpty
                        ? null
                        : _selectedBookerId,
                    bottomPadding: 8,
                    isExpanded: true,
                    disabledTapMessage: 'No client accounts available yet.',
                    items: widget.clientUsers.map((user) {
                      return DropdownMenuItem<String>(
                        value: user.id,
                        child: Text(
                          _bookerLabel(user),
                          overflow: TextOverflow.ellipsis,
                          style: adminDropdownDisplayTextStyle,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedBookerId = value ?? '';
                      });
                      _focusNext(_representativeNameFocusNode);
                    },
                  ),
                  AdminModalTextField(
                    controller: _representativeNameController,
                    focusNode: _representativeNameFocusNode,
                    label: 'Representative Name',
                    bottomPadding: 8,
                    hintText: 'Enter Representative Name',
                    onSubmitted: (_) =>
                        _focusNext(_representativePhoneFocusNode),
                  ),
                  AdminModalTextField(
                    controller: _representativePhoneController,
                    focusNode: _representativePhoneFocusNode,
                    label: 'Representative Phone',
                    bottomPadding: 8,
                    hintText: 'Enter Representative Phone',
                    keyboardType: TextInputType.phone,
                    inputFormatters: const <TextInputFormatter>[
                      PhilippinesPhoneInputFormatter(),
                    ],
                    onSubmitted: (_) => _focusNext(_waybillPhotoFocusNode),
                  ),
                  _buildPhotoUploadField(
                    label: 'Waybill Photo',
                    focusNode: _waybillPhotoFocusNode,
                    nextFocusNode: _waybillNumberFocusNode,
                    value: _waybillPhotoValue,
                    onChanged: (value) {
                      setState(() {
                        _waybillPhotoValue = value;
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  AdminModalTextField(
                    controller: _waybillNumberController,
                    focusNode: _waybillNumberFocusNode,
                    label: 'Waybill Number',
                    bottomPadding: 6,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _focusNext(_vanNumberFocusNode),
                  ),
                  AdminModalTextField(
                    controller: _vanNumberController,
                    focusNode: _vanNumberFocusNode,
                    label: 'Van Number',
                    bottomPadding: 6,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _focusNext(_vanSizeFocusNode),
                  ),
                  AdminModalDropdownField<String>(
                    focusNode: _vanSizeFocusNode,
                    label: 'Van Size',
                    initialValue: _vanSize,
                    bottomPadding: 8,
                    isExpanded: true,
                    disabledTapMessage: 'No active vehicle sizes available.',
                    items: _buildVanSizeItems(),
                    onChanged: (value) {
                      setState(() {
                        _vanSize = value;
                      });
                      _focusNext(_amountFocusNode);
                    },
                  ),
                  AdminModalTextField(
                    controller: _amountController,
                    focusNode: _amountFocusNode,
                    label: 'Amount',
                    keyboardType: TextInputType.number,
                    bottomPadding: 6,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _focusNext(_pickUpDateFocusNode),
                  ),
                  AdminModalActionField(
                    label: 'Pick Up Date',
                    focusNode: _pickUpDateFocusNode,
                    valueText: _pickUpDateController.text.trim().isEmpty
                        ? null
                        : _pickUpDateController.text.trim(),
                    hintText: adminSelectPlaceholder('Pick Up Date'),
                    bottomPadding: 6,
                    onTap: () => _pickDateForController(
                      _pickUpDateController,
                      _pickUpTimeFocusNode,
                    ),
                    onSubmitted: () => _pickDateForController(
                      _pickUpDateController,
                      _pickUpTimeFocusNode,
                    ),
                  ),
                  AdminModalActionField(
                    label: 'Pick Up Time',
                    focusNode: _pickUpTimeFocusNode,
                    valueText: _pickUpTimeController.text.trim().isEmpty
                        ? null
                        : _pickUpTimeController.text.trim(),
                    hintText: adminSelectPlaceholder('Pick Up Time'),
                    bottomPadding: 6,
                    onTap: () => _pickTimeForController(
                      _pickUpTimeController,
                      _dropOffDateFocusNode,
                    ),
                    onSubmitted: () => _pickTimeForController(
                      _pickUpTimeController,
                      _dropOffDateFocusNode,
                    ),
                  ),
                  AdminModalActionField(
                    label: 'Drop Off Date',
                    focusNode: _dropOffDateFocusNode,
                    valueText: _dropOffDateController.text.trim().isEmpty
                        ? null
                        : _dropOffDateController.text.trim(),
                    hintText: adminSelectPlaceholder('Drop Off Date'),
                    bottomPadding: 6,
                    onTap: () => _pickDateForController(
                      _dropOffDateController,
                      _dropOffTimeFocusNode,
                    ),
                    onSubmitted: () => _pickDateForController(
                      _dropOffDateController,
                      _dropOffTimeFocusNode,
                    ),
                  ),
                  AdminModalActionField(
                    label: 'Drop Off Time',
                    focusNode: _dropOffTimeFocusNode,
                    valueText: _dropOffTimeController.text.trim().isEmpty
                        ? null
                        : _dropOffTimeController.text.trim(),
                    hintText: adminSelectPlaceholder('Drop Off Time'),
                    bottomPadding: 6,
                    onTap: () => _pickTimeForController(
                      _dropOffTimeController,
                      _originFocusNode,
                    ),
                    onSubmitted: () => _pickTimeForController(
                      _dropOffTimeController,
                      _originFocusNode,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: AdminSearchSelectFormField(
                      initialValue: _originController.text.trim().isEmpty
                          ? null
                          : _originController.text.trim(),
                      focusNode: _originFocusNode,
                      decoration: adminFormInputDecoration(
                        'Origin',
                        hintText: adminSelectPlaceholder('Origin'),
                      ).copyWith(errorText: _originErrorText),
                      options: palawanLocationOptions,
                      onChanged: (value) {
                        setState(() {
                          _originController.text = value ?? '';
                          _originErrorText = null;
                          if (!_showsOriginBarangayField) {
                            _originBarangayController.clear();
                            _originBarangayErrorText = null;
                          }
                        });
                      },
                    ),
                  ),
                  if (_showsOriginBarangayField)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AdminSearchSelectFormField(
                        initialValue:
                            _originBarangayController.text.trim().isEmpty
                            ? null
                            : _originBarangayController.text.trim(),
                        focusNode: _originBarangayFocusNode,
                        decoration: adminFormInputDecoration(
                          widget.originBarangayRequired
                              ? 'Origin Barangay *'
                              : 'Origin Barangay',
                          hintText: adminSelectPlaceholder('Origin Barangay'),
                        ).copyWith(errorText: _originBarangayErrorText),
                        options: puertoPrincesaBarangayOptions,
                        onChanged: (value) {
                          setState(() {
                            _originBarangayController.text = value ?? '';
                            _originBarangayErrorText = null;
                          });
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: AdminSearchSelectFormField(
                      initialValue: _destinationController.text.trim().isEmpty
                          ? null
                          : _destinationController.text.trim(),
                      focusNode: _destinationFocusNode,
                      decoration: adminFormInputDecoration(
                        'Destination',
                        hintText: adminSelectPlaceholder('Destination'),
                      ).copyWith(errorText: _destinationErrorText),
                      options: palawanLocationOptions,
                      onChanged: (value) {
                        setState(() {
                          _destinationController.text = value ?? '';
                          _destinationErrorText = null;
                          if (!_showsDestinationBarangayField) {
                            _destinationBarangayController.clear();
                            _destinationBarangayErrorText = null;
                          }
                        });
                      },
                    ),
                  ),
                  if (_showsDestinationBarangayField)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AdminSearchSelectFormField(
                        initialValue:
                            _destinationBarangayController.text.trim().isEmpty
                            ? null
                            : _destinationBarangayController.text.trim(),
                        focusNode: _destinationBarangayFocusNode,
                        decoration: adminFormInputDecoration(
                          widget.destinationBarangayRequired
                              ? 'Destination Barangay *'
                              : 'Destination Barangay',
                          hintText: adminSelectPlaceholder(
                            'Destination Barangay',
                          ),
                        ).copyWith(errorText: _destinationBarangayErrorText),
                        options: puertoPrincesaBarangayOptions,
                        onChanged: (value) {
                          setState(() {
                            _destinationBarangayController.text = value ?? '';
                            _destinationBarangayErrorText = null;
                          });
                        },
                      ),
                    ),
                  _buildPhotoUploadField(
                    label: 'Delivery Form Photo',
                    focusNode: _deliveryFormPhotoFocusNode,
                    nextFocusNode: _deliveryFormNumberFocusNode,
                    value: _deliveryFormPhotoValue,
                    onChanged: (value) {
                      setState(() {
                        _deliveryFormPhotoValue = value;
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  AdminModalTextField(
                    controller: _deliveryFormNumberController,
                    focusNode: _deliveryFormNumberFocusNode,
                    label: 'Delivery Form Number',
                    keyboardType: TextInputType.number,
                    bottomPadding: 6,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _focusNext(_statusFocusNode),
                  ),
                  AdminModalDropdownField<String>(
                    focusNode: _statusFocusNode,
                    label: 'Status',
                    initialValue: _statusKey.isEmpty ? null : _statusKey,
                    isExpanded: true,
                    bottomPadding: 8,
                    disabledTapMessage: 'No active statuses available.',
                    items: _buildStatusItems(),
                    onChanged: (value) {
                      setState(() {
                        _statusKey = value ?? '';
                      });
                      _unfocusCurrentField();
                    },
                  ),
                  AdminModalDropdownField<String>(
                    focusNode: _driverFocusNode,
                    label: 'Driver',
                    initialValue: _driverId,
                    isExpanded: true,
                    bottomPadding: 8,
                    disabledTapMessage: 'No active drivers available.',
                    items: _buildRoleUserItems(
                      selectedUserId: _driverId,
                      activeUsers: widget.drivers,
                      fallbackRole: 'Driver',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _driverId = value;
                      });
                      _unfocusCurrentField();
                    },
                  ),
                  AdminModalDropdownField<String>(
                    focusNode: _helperFocusNode,
                    label: 'Helper',
                    initialValue: _helperId,
                    isExpanded: true,
                    bottomPadding: 0,
                    disabledTapMessage: 'No active helpers available.',
                    items: _buildRoleUserItems(
                      selectedUserId: _helperId,
                      activeUsers: widget.helpers,
                      fallbackRole: 'Helper',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _helperId = value;
                      });
                      _unfocusCurrentField();
                    },
                  ),
                  const SizedBox(height: 8),
                  AdminModalDropdownField<String>(
                    focusNode: _chassisFocusNode,
                    label: 'Chassis',
                    initialValue: _chassisId,
                    isExpanded: true,
                    bottomPadding: 0,
                    disabledTapMessage: 'No active chassis available.',
                    items: _buildChassisItems(),
                    onChanged: (value) {
                      setState(() {
                        _chassisId = value;
                      });
                      _unfocusCurrentField();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final draftBooking = _buildDraftBooking();
    if (draftBooking == null) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      final savedBooking = await widget.onSave(draftBooking);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(savedBooking);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppSnackbar.showError(context, error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Booking? _buildDraftBooking() {
    final origin = _originController.text.trim();
    final originBarangay = _originBarangayController.text.trim();
    final destination = _destinationController.text.trim();
    final destinationBarangay = _destinationBarangayController.text.trim();
    final originIsValid =
        origin.isEmpty || isValidPalawanLocationOption(origin);
    final originBarangayIsValid =
        !_showsOriginBarangayField ||
        ((widget.originBarangayRequired ? originBarangay.isNotEmpty : true) &&
            (originBarangay.isEmpty ||
                puertoPrincesaBarangayOptions.any(
                  (item) => item.toLowerCase() == originBarangay.toLowerCase(),
                )));
    final destinationIsValid =
        destination.isEmpty || isValidPalawanLocationOption(destination);
    final destinationBarangayIsValid =
        !_showsDestinationBarangayField ||
        ((widget.destinationBarangayRequired
                ? destinationBarangay.isNotEmpty
                : true) &&
            (destinationBarangay.isEmpty ||
                puertoPrincesaBarangayOptions.any(
                  (item) =>
                      item.toLowerCase() == destinationBarangay.toLowerCase(),
                )));

    if (!originIsValid ||
        !originBarangayIsValid ||
        !destinationIsValid ||
        !destinationBarangayIsValid) {
      setState(() {
        _originErrorText = originIsValid ? null : 'Select a valid Origin.';
        _originBarangayErrorText = originBarangayIsValid
            ? null
            : (originBarangay.isEmpty && widget.originBarangayRequired)
            ? 'Origin Barangay is required.'
            : 'Select a valid Origin Barangay.';
        _destinationErrorText = destinationIsValid
            ? null
            : 'Select a valid Destination.';
        _destinationBarangayErrorText = destinationBarangayIsValid
            ? null
            : (destinationBarangay.isEmpty &&
                  widget.destinationBarangayRequired)
            ? 'Destination Barangay is required.'
            : 'Select a valid Destination Barangay.';
      });
      return null;
    }

    final currentOutputs = Map<String, dynamic>.from(
      widget.booking.statusOutputs ?? const <String, dynamic>{},
    );
    final latestStoredFields = _latestOutputFieldValues(currentOutputs);
    final editedFields = <String, dynamic>{};

    _setOrRemoveField(
      editedFields,
      'representative_name',
      _representativeNameController.text.trim(),
    );
    _setOrRemoveField(
      editedFields,
      'representative_phone',
      normalizePhilippinePhone(_representativePhoneController.text) ?? '',
    );
    _setOrRemovePhotoField(editedFields, 'waybill_photo', _waybillPhotoValue);
    _setOrRemoveField(
      editedFields,
      'waybill_number',
      _waybillNumberController.text.trim(),
    );
    _setOrRemoveField(
      editedFields,
      'van_number',
      _vanNumberController.text.trim(),
    );
    _setOrRemoveField(editedFields, 'van_size', _vanSize?.trim() ?? '');
    _setOrRemoveField(editedFields, 'amount', _amountController.text.trim());
    _setOrRemoveField(
      editedFields,
      'pick_up_date',
      _pickUpDateController.text.trim(),
    );
    _setOrRemoveField(
      editedFields,
      'pick_up_time',
      _pickUpTimeController.text.trim(),
    );
    _setOrRemoveField(
      editedFields,
      'drop_off_date',
      _dropOffDateController.text.trim(),
    );
    _setOrRemoveField(
      editedFields,
      'drop_off_time',
      _dropOffTimeController.text.trim(),
    );
    _setOrRemoveField(editedFields, 'origin', _originController.text.trim());
    _setOrRemoveField(
      editedFields,
      'origin_barangay',
      _originBarangayController.text.trim(),
    );
    _setOrRemoveField(
      editedFields,
      'destination',
      _destinationController.text.trim(),
    );
    _setOrRemoveField(
      editedFields,
      'destination_barangay',
      _destinationBarangayController.text.trim(),
    );
    _setOrRemovePhotoField(
      editedFields,
      'delivery_form_photo',
      _deliveryFormPhotoValue,
    );
    _setOrRemoveField(
      editedFields,
      'delivery_form_number',
      _deliveryFormNumberController.text.trim(),
    );
    _setOrRemoveField(editedFields, 'chassis_id', _chassisId?.trim() ?? '');

    final previousStatusKey = (widget.booking.clientStatus ?? '').trim();
    final nextStatusKey = _statusKey.trim();
    final displayStatusKeyForAppend = nextStatusKey.isNotEmpty
        ? nextStatusKey
        : previousStatusKey;
    final statusChangeFields = _changedStatusFields(
      before: latestStoredFields,
      after: editedFields,
    );
    if (displayStatusKeyForAppend.isNotEmpty) {
      final appendedOutputs = StatusFormEngine.appendStatusOutputSection(
        currentOutputs,
        displayStatusKey: displayStatusKeyForAppend,
        statusFormReference: null,
        submittedRole: widget.currentUser.role,
        submittedRoles: [
          if ((widget.currentUser.role ?? '').trim().isNotEmpty)
            widget.currentUser.role!.trim(),
        ],
        submittedBy: widget.currentUser.id ?? '',
        fields: statusChangeFields,
      );
      currentOutputs
        ..clear()
        ..addAll(appendedOutputs);
    }

    return widget.booking.copyWith(
      client: widget.clientUsers
          .where((user) => user.id == _selectedBookerId)
          .firstOrNull,
      clientStatus: _statusKey.isEmpty
          ? widget.booking.clientStatus
          : _statusKey,
      driverStatus: _statusKey.isEmpty
          ? widget.booking.driverStatus
          : _statusKey,
      helperStatus: _statusKey.isEmpty
          ? widget.booking.helperStatus
          : _statusKey,
      driver: _resolveSelectedUser(_driverId, widget.drivers),
      helper: _resolveSelectedUser(_helperId, widget.helpers),
      chassisId: _chassisId?.trim().isEmpty == true ? null : _chassisId?.trim(),
      statusOutputs: currentOutputs,
    );
  }

  Map<String, dynamic> _latestOutputFieldValues(Map<String, dynamic> outputs) {
    if (outputs.isEmpty) {
      return const <String, dynamic>{};
    }

    final sections = outputs.entries.where((entry) => entry.value is Map).map((
      entry,
    ) {
      final raw = Map<String, dynamic>.from(entry.value as Map);
      return (
        entryKey: entry.key,
        submittedAt: DateTime.tryParse(raw['submitted_at']?.toString() ?? ''),
        fields: raw['fields'] is Map
            ? Map<String, dynamic>.from(raw['fields'] as Map)
            : const <String, dynamic>{},
      );
    }).toList();

    sections.sort((a, b) {
      final aSubmittedAt = a.submittedAt;
      final bSubmittedAt = b.submittedAt;
      if (aSubmittedAt != null && bSubmittedAt != null) {
        return bSubmittedAt.compareTo(aSubmittedAt);
      }
      if (aSubmittedAt != null) {
        return -1;
      }
      if (bSubmittedAt != null) {
        return 1;
      }
      return b.entryKey.compareTo(a.entryKey);
    });

    final latestValues = <String, dynamic>{};
    for (final section in sections) {
      section.fields.forEach((key, value) {
        latestValues.putIfAbsent(key, () => value);
      });
    }
    return latestValues;
  }

  Map<String, dynamic> _changedStatusFields({
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
  }) {
    final changed = <String, dynamic>{};
    final candidateKeys = <String>{...before.keys, ...after.keys};
    for (final key in candidateKeys) {
      final previousValue = before[key];
      final nextValue = after[key];
      if (_normalizedFieldValue(previousValue) ==
          _normalizedFieldValue(nextValue)) {
        continue;
      }
      if (_isEmptyFieldValue(nextValue)) {
        continue;
      }
      changed[key] = nextValue;
    }
    return changed;
  }

  dynamic _normalizedFieldValue(dynamic value) {
    if (value is String) {
      return value.trim();
    }
    if (value is List) {
      return value.map(_normalizedFieldValue).toList();
    }
    if (value is Map) {
      final entries = Map<String, dynamic>.from(value);
      final normalized = <String, dynamic>{};
      for (final entry in entries.entries) {
        normalized[entry.key] = _normalizedFieldValue(entry.value);
      }
      return normalized;
    }
    return value;
  }

  bool _isEmptyFieldValue(dynamic value) {
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

  UserModel? _resolveSelectedUser(String? userId, List<UserModel> users) {
    final normalizedId = userId?.trim();
    if (normalizedId == null || normalizedId.isEmpty) {
      return null;
    }
    for (final user in users) {
      if (user.id == normalizedId) {
        return user;
      }
    }
    if (widget.booking.driver?.id == normalizedId) {
      return widget.booking.driver;
    }
    if (widget.booking.helper?.id == normalizedId) {
      return widget.booking.helper;
    }
    return null;
  }

  static void _setOrRemoveField(
    Map<String, dynamic> fields,
    String key,
    String value,
  ) {
    if (value.isEmpty) {
      fields.remove(key);
      return;
    }
    fields[key] = value;
  }

  static void _setOrRemovePhotoField(
    Map<String, dynamic> fields,
    String key,
    dynamic value,
  ) {
    if (value == null) {
      fields.remove(key);
      return;
    }
    if (value is String && value.trim().isEmpty) {
      fields.remove(key);
      return;
    }
    if (value is Map && value.isEmpty) {
      fields.remove(key);
      return;
    }
    fields[key] = value;
  }

  static String _userLabel(UserModel user) {
    final name = (user.name ?? '').trim();
    final phone = (user.phone ?? '').trim();
    if (name.isNotEmpty && phone.isNotEmpty) {
      return '$name | $phone';
    }
    if (name.isNotEmpty) {
      return name;
    }
    if (phone.isNotEmpty) {
      return phone;
    }
    final role = (user.role ?? '').trim();
    return role.isNotEmpty ? humanizeDropdownValue(role) : 'User';
  }

  String _bookerLabel(UserModel user) {
    final name = (user.name ?? '').trim();
    final phone = (user.phone ?? '').trim();
    if (name.isNotEmpty && phone.isNotEmpty) {
      return '$name | $phone';
    }
    if (name.isNotEmpty) {
      return name;
    }
    if (phone.isNotEmpty) {
      return phone;
    }
    return 'Client';
  }

  String? _normalizeVehicleSizeId(String? rawValue) {
    final normalized = VehicleRequest.instance.normalizeVehicleSizeId(rawValue);
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    final matchesKnownSize = widget.vehicleSizes.any(
      (size) => size.id == normalized,
    );
    return matchesKnownSize ? normalized : null;
  }
}

class _NewAdminBookingDialog extends StatefulWidget {
  const _NewAdminBookingDialog({
    required this.currentUser,
    required this.clientUsers,
    required this.onBookingSubmitted,
  });

  final UserModel currentUser;
  final List<UserModel> clientUsers;
  final ValueChanged<Booking> onBookingSubmitted;

  @override
  State<_NewAdminBookingDialog> createState() => _NewAdminBookingDialogState();
}

class _NewAdminBookingDialogState extends State<_NewAdminBookingDialog> {
  static const String _draftStorageKeyPrefix = 'admin_new_booking_draft_v1';
  static const UserModel _placeholderClientUser = UserModel(role: 'client');
  late String _selectedBookerId;
  String? _bookerErrorText;
  bool _isRestoringDraft = true;
  late final FocusNode _bookedByFocusNode;
  final LocalFormDraftService _draftService = LocalFormDraftService.instance;

  @override
  void initState() {
    super.initState();
    _selectedBookerId = '';
    _bookedByFocusNode = FocusNode();
    _log(
      'init currentUser=${widget.currentUser.id ?? "-"} role=${widget.currentUser.role ?? "-"} clients=${widget.clientUsers.length}',
    );
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _bookedByFocusNode.dispose();
    super.dispose();
  }

  void _openBookedByOptions() {
    if (mounted) {
      setState(() {
        _bookerErrorText = 'Client is required.';
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      FocusScope.of(context).requestFocus(_bookedByFocusNode);
      final targetContext =
          FocusManager.instance.primaryFocus?.context ??
          _bookedByFocusNode.context;
      if (targetContext != null) {
        Actions.maybeInvoke(targetContext, const ActivateIntent());
      }
    });
  }

  String get _draftStorageKey {
    final currentUserId = widget.currentUser.id?.trim() ?? '';
    return '$_draftStorageKeyPrefix:$currentUserId';
  }

  Future<void> _restoreDraft() async {
    try {
      final draft = await _draftService.readMap(_draftStorageKey);
      if (!mounted || draft == null) {
        _log('restore draft key=$_draftStorageKey found=false');
        return;
      }
      final restoredId = draft['selected_booker_id']?.toString() ?? '';
      setState(() {
        _selectedBookerId = restoredId;
      });
      _log(
        'restore draft key=$_draftStorageKey found=true selected=$restoredId',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRestoringDraft = false;
        });
      }
    }
  }

  Future<void> _persistDraft() async {
    await _draftService.writeMap(_draftStorageKey, <String, dynamic>{
      'selected_booker_id': _selectedBookerId,
    });
    _log('persist draft key=$_draftStorageKey selected=$_selectedBookerId');
  }

  Future<void> _clearDraft() async {
    await _draftService.remove(_draftStorageKey);
  }

  Future<void> _handleBookingSubmitted(Booking booking) async {
    _log(
      'submit success bookingId=${booking.id ?? "-"} selectedClient=${_selectedUser?.id ?? "-"}',
    );
    await _clearDraft();
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedBookerId = '';
      _bookerErrorText = null;
    });
    widget.onBookingSubmitted(booking);
  }

  String? _resolveSubmitBlockMessage() {
    if (_selectedUser != null) {
      if (_bookerErrorText != null && mounted) {
        setState(() {
          _bookerErrorText = null;
        });
      }
      return null;
    }
    if (mounted) {
      setState(() {
        _bookerErrorText = 'Client is required.';
      });
    }
    _log('submit blocked reason=no-client-selected');
    return 'Client is required.';
  }

  @override
  Widget build(BuildContext context) {
    final selectedUser = _selectedUser;
    _log(
      'build selectedClient=${selectedUser?.id ?? "-"} hasPlaceholder=${selectedUser == null} error=${_bookerErrorText ?? "-"}',
    );

    return AdminModalShell(
      title: 'New Booking',
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      actionsInset: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
      child: SizedBox(
        width: 760,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final formVisibleHeight = (MediaQuery.sizeOf(context).height * 0.6)
                .clamp(280.0, 700.0)
                .toDouble();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminModalFormBody(
                  children: [
                    AdminModalFieldsSection(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: AdminModalDropdownField<String>(
                            label: 'Booked By',
                            hintText: 'Select Client',
                            errorText: _bookerErrorText,
                            focusNode: _bookedByFocusNode,
                            initialValue: _selectedBookerId.isEmpty
                                ? null
                                : _selectedBookerId,
                            bottomPadding: 0,
                            isExpanded: true,
                            disabledTapMessage:
                                'No client accounts available yet.',
                            items: widget.clientUsers
                                .map(
                                  (user) => DropdownMenuItem<String>(
                                    value: user.id,
                                    child: Text(
                                      _bookerLabel(user),
                                      overflow: TextOverflow.ellipsis,
                                      style: adminDropdownDisplayTextStyle,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedBookerId = value ?? '';
                                _bookerErrorText = null;
                              });
                              _log('client changed next=${value ?? "-"}');
                              unawaited(_persistDraft());
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_isRestoringDraft)
                  SizedBox(
                    height: formVisibleHeight,
                    child: const SizedBox.shrink(),
                  )
                else
                  ClientBookingHomeView(
                    user: selectedUser ?? _placeholderClientUser,
                    bookingClientUser: selectedUser,
                    submittedByUserId: widget.currentUser.id,
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                    scrollable: false,
                    loadingPlaceholderMinHeight: formVisibleHeight,
                    submitBlockMessage: _resolveSubmitBlockMessage,
                    onRepresentativeTapWithoutClient: _openBookedByOptions,
                    onBookingSubmitted: (booking) {
                      unawaited(_handleBookingSubmitted(booking));
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  UserModel? get _selectedUser {
    if (_selectedBookerId.isEmpty) {
      return null;
    }
    return widget.clientUsers.cast<UserModel?>().firstWhere(
      (user) => user?.id == _selectedBookerId,
      orElse: () => null,
    );
  }

  String _bookerLabel(UserModel user) {
    final name = (user.name ?? '').trim();
    final role = (user.role ?? '').trim();
    final roleLabel = role.isEmpty
        ? ''
        : '${role[0].toUpperCase()}${role.substring(1)}';
    if (roleLabel.isNotEmpty && name.isNotEmpty) {
      return '$roleLabel | $name';
    }
    if (name.isNotEmpty) {
      return name;
    }
    if (roleLabel.isNotEmpty) {
      return roleLabel;
    }
    return 'Client';
  }

  void _log(String message) {
    // Temporary diagnostics removed.
  }
}

class _AdminBookingsTable extends StatelessWidget {
  const _AdminBookingsTable({
    required this.bookings,
    required this.vm,
    required this.onView,
    this.onEdit,
  });

  final List<Booking> bookings;
  final AdminBookingsViewModel vm;
  final ValueChanged<Booking> onView;
  final ValueChanged<Booking>? onEdit;

  static const _headerStyle = TextStyle(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w700,
  );

  static const _valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const _defaultTrailingPadding =
      AdminListMeasurements.defaultTrailingPadding;
  static const _extraWidthAllowance =
      AdminListMeasurements.defaultExtraWidthAllowance;

  @override
  Widget build(BuildContext context) {
    final longestIdValue = _longestText(
      bookings.map((booking) => booking.id ?? '-'),
    );
    final longestCreatedValue = _longestText(
      bookings.map((booking) => _formatBookingDateTime(booking.createdAt)),
    );
    final longestUpdatedValue = _longestText(
      bookings.map((booking) => _formatBookingDateTime(booking.updatedAt)),
    );
    final longestWaybillNumber = _longestText(
      bookings.map((booking) => _waybillNumber(booking)),
    );
    final longestVanNumber = _longestText(
      bookings.map((booking) => _vanNumber(booking)),
    );
    final longestVanSize = _longestText(
      bookings.map((booking) => _vanSize(booking)),
    );
    final longestAmount = _longestText(
      bookings.map((booking) => _amount(booking)),
    );
    final longestStatusValue = _longestText(
      bookings.map((booking) => vm.clientStatusLabel(booking)),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final idWidth = _maxTextWidth(
          context,
          textScaler,
          'ID',
          longestIdValue,
        );
        final createdWidth = _maxTextWidth(
          context,
          textScaler,
          'Created',
          longestCreatedValue,
        );
        final updatedWidth = _maxTextWidth(
          context,
          textScaler,
          'Updated',
          longestUpdatedValue,
        );
        final waybillWidth = _maxTextWidth(
          context,
          textScaler,
          'Waybill Number',
          longestWaybillNumber,
        );
        final vanNumberWidth = _maxTextWidth(
          context,
          textScaler,
          'Van Number',
          longestVanNumber,
        );
        final vanSizeWidth = _maxTextWidth(
          context,
          textScaler,
          'Van Size',
          longestVanSize,
        );
        final amountWidth = _maxTextWidth(
          context,
          textScaler,
          'Amount',
          longestAmount,
        );
        final statusTextWidth = AdminListMeasurements.measureTextWidth(
          context,
          textScaler,
          longestStatusValue,
          _valueStyle,
        );
        final statusHeaderWidth = AdminListMeasurements.measureTextWidth(
          context,
          textScaler,
          'Status',
          _headerStyle,
        );
        final statusWidth = _maxValue(statusTextWidth + 32, statusHeaderWidth);
        final actionsWidth = _maxValue(
          88,
          AdminListMeasurements.measureTextWidth(
            context,
            textScaler,
            'Actions',
            _headerStyle,
          ),
        );

        final resolvedIdWidth = _resolvedColumnWidth(idWidth);
        final resolvedCreatedWidth = _resolvedColumnWidth(createdWidth);
        final resolvedUpdatedWidth = _resolvedColumnWidth(updatedWidth);
        final resolvedWaybillWidth = _resolvedColumnWidth(waybillWidth);
        final resolvedVanNumberWidth = _resolvedColumnWidth(vanNumberWidth);
        final resolvedVanSizeWidth = _resolvedColumnWidth(vanSizeWidth);
        final resolvedAmountWidth = _resolvedColumnWidth(amountWidth);
        final resolvedStatusWidth = _resolvedColumnWidth(statusWidth);
        final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;
        final totalMeasuredWidth =
            resolvedIdWidth +
            resolvedWaybillWidth +
            resolvedVanNumberWidth +
            resolvedVanSizeWidth +
            resolvedAmountWidth +
            resolvedStatusWidth +
            resolvedCreatedWidth +
            resolvedUpdatedWidth +
            resolvedActionsWidth +
            40;
        final useResponsiveCards = totalMeasuredWidth > constraints.maxWidth;

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
                    child: _AdminBookingResponsiveCard(
                      booking: entry.value,
                      statusLabel: vm.clientStatusLabel(entry.value),
                      onView: () => onView(entry.value),
                      onEdit: onEdit == null
                          ? null
                          : () => onEdit!(entry.value),
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
                  _AdminBookingsFixedSlot(
                    width: resolvedIdWidth,
                    child: const _AdminBookingsHeaderCell(label: 'ID'),
                  ),
                  _AdminBookingsFixedSlot(
                    width: resolvedWaybillWidth,
                    child: const _AdminBookingsHeaderCell(
                      label: 'Waybill Number',
                    ),
                  ),
                  _AdminBookingsFixedSlot(
                    width: resolvedVanNumberWidth,
                    child: const _AdminBookingsHeaderCell(label: 'Van Number'),
                  ),
                  _AdminBookingsFixedSlot(
                    width: resolvedVanSizeWidth,
                    child: const _AdminBookingsHeaderCell(label: 'Van Size'),
                  ),
                  _AdminBookingsFixedSlot(
                    width: resolvedAmountWidth,
                    child: const _AdminBookingsHeaderCell(label: 'Amount'),
                  ),
                  _AdminBookingsFixedSlot(
                    width: resolvedStatusWidth,
                    child: const _AdminBookingsHeaderCell(label: 'Status'),
                  ),
                  _AdminBookingsFixedSlot(
                    width: resolvedCreatedWidth,
                    child: const _AdminBookingsHeaderCell(label: 'Created'),
                  ),
                  _AdminBookingsFixedSlot(
                    width: resolvedUpdatedWidth,
                    child: const _AdminBookingsHeaderCell(label: 'Updated'),
                  ),
                  AdminListTrailingActionsLane(
                    width: resolvedActionsWidth,
                    child: const _AdminBookingsHeaderCell(
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
            ...bookings.asMap().entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == bookings.length - 1 ? 0 : 12,
                ),
                child: _AdminBookingWideRow(
                  booking: entry.value,
                  statusLabel: vm.clientStatusLabel(entry.value),
                  resolvedIdWidth: resolvedIdWidth,
                  resolvedWaybillWidth: resolvedWaybillWidth,
                  resolvedVanNumberWidth: resolvedVanNumberWidth,
                  resolvedVanSizeWidth: resolvedVanSizeWidth,
                  resolvedAmountWidth: resolvedAmountWidth,
                  resolvedStatusWidth: resolvedStatusWidth,
                  resolvedCreatedWidth: resolvedCreatedWidth,
                  resolvedUpdatedWidth: resolvedUpdatedWidth,
                  resolvedActionsWidth: resolvedActionsWidth,
                  onView: () => onView(entry.value),
                  onEdit: onEdit == null ? null : () => onEdit!(entry.value),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static double _maxValue(double first, double second) {
    return first > second ? first : second;
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

  static String _waybillNumber(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'waybill_number',
      );

  static String _vanNumber(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'van_number',
      );

  static String _vanSize(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'van_size',
      );

  static String _amount(Booking booking) =>
      BookingRecordCard.outputFieldDisplayValue(
        booking.statusOutputs,
        'amount',
      );

  static String _formatBookingDateTime(DateTime? value) {
    return AdminUsersView.formatCreatedAt(value);
  }

  static String _formatBookingDateTimeSingleLine(DateTime? value) {
    return AdminUsersView.formatCreatedAtSingleLine(value);
  }
}

class _AdminBookingWideRow extends StatelessWidget {
  const _AdminBookingWideRow({
    required this.booking,
    required this.statusLabel,
    required this.resolvedIdWidth,
    required this.resolvedWaybillWidth,
    required this.resolvedVanNumberWidth,
    required this.resolvedVanSizeWidth,
    required this.resolvedAmountWidth,
    required this.resolvedStatusWidth,
    required this.resolvedCreatedWidth,
    required this.resolvedUpdatedWidth,
    required this.resolvedActionsWidth,
    required this.onView,
    this.onEdit,
  });

  final Booking booking;
  final String statusLabel;
  final double resolvedIdWidth;
  final double resolvedWaybillWidth;
  final double resolvedVanNumberWidth;
  final double resolvedVanSizeWidth;
  final double resolvedAmountWidth;
  final double resolvedStatusWidth;
  final double resolvedCreatedWidth;
  final double resolvedUpdatedWidth;
  final double resolvedActionsWidth;
  final VoidCallback onView;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _AdminBookingsFixedSlot(
            width: resolvedIdWidth,
            child: _AdminBookingsBodyCell(
              child: Text(
                booking.id ?? '-',
                style: _AdminBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _AdminBookingsFixedSlot(
            width: resolvedWaybillWidth,
            child: _AdminBookingsBodyCell(
              child: Text(
                _AdminBookingsTable._waybillNumber(booking),
                style: _AdminBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _AdminBookingsFixedSlot(
            width: resolvedVanNumberWidth,
            child: _AdminBookingsBodyCell(
              child: Text(
                _AdminBookingsTable._vanNumber(booking),
                style: _AdminBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _AdminBookingsFixedSlot(
            width: resolvedVanSizeWidth,
            child: _AdminBookingsBodyCell(
              child: Text(
                _AdminBookingsTable._vanSize(booking),
                style: _AdminBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _AdminBookingsFixedSlot(
            width: resolvedAmountWidth,
            child: _AdminBookingsBodyCell(
              child: Text(
                _AdminBookingsTable._amount(booking),
                style: _AdminBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _AdminBookingsFixedSlot(
            width: resolvedStatusWidth,
            child: _AdminBookingsBodyCell(child: adminMetaPill(statusLabel)),
          ),
          _AdminBookingsFixedSlot(
            width: resolvedCreatedWidth,
            child: _AdminBookingsBodyCell(
              child: Text(
                _AdminBookingsTable._formatBookingDateTime(booking.createdAt),
                style: _AdminBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _AdminBookingsFixedSlot(
            width: resolvedUpdatedWidth,
            child: _AdminBookingsBodyCell(
              child: Text(
                _AdminBookingsTable._formatBookingDateTime(booking.updatedAt),
                style: _AdminBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          AdminListTrailingActionsLane(
            width: resolvedActionsWidth,
            child: _AdminBookingsBodyCell(
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AdminListActionButton(
                    icon: Icons.visibility_rounded,
                    backgroundColor: Colors.yellow.shade900,
                    onTap: onView,
                  ),
                  const SizedBox(width: 8),
                  AdminListActionButton(
                    icon: Icons.edit_outlined,
                    onTap: onEdit,
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

class _AdminBookingResponsiveCard extends StatelessWidget {
  const _AdminBookingResponsiveCard({
    required this.booking,
    required this.statusLabel,
    required this.onView,
    this.onEdit,
  });

  final Booking booking;
  final String statusLabel;
  final VoidCallback onView;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        final spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        final items = [
          ('ID', booking.id ?? '-'),
          ('Waybill Number', _AdminBookingsTable._waybillNumber(booking)),
          ('Van Number', _AdminBookingsTable._vanNumber(booking)),
          ('Van Size', _AdminBookingsTable._vanSize(booking)),
          ('Amount', _AdminBookingsTable._amount(booking)),
          ('Status', statusLabel),
          (
            'Created',
            _AdminBookingsTable._formatBookingDateTimeSingleLine(
              booking.createdAt,
            ),
          ),
          (
            'Updated',
            _AdminBookingsTable._formatBookingDateTimeSingleLine(
              booking.updatedAt,
            ),
          ),
        ];

        return AdminListItemCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, headerConstraints) {
                  final useStackedHeader = headerConstraints.maxWidth < 180;
                  final actions = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AdminListActionButton(
                        icon: Icons.visibility_rounded,
                        backgroundColor: Colors.yellow.shade900,
                        onTap: onView,
                        size: useStackedHeader ? 36 : 40,
                        iconSize: useStackedHeader ? 16 : 18,
                      ),
                      const SizedBox(width: 8),
                      AdminListActionButton(
                        icon: Icons.edit_outlined,
                        onTap: onEdit,
                        size: useStackedHeader ? 36 : 40,
                        iconSize: useStackedHeader ? 16 : 18,
                      ),
                    ],
                  );

                  if (useStackedHeader) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        adminMetaPill(statusLabel),
                        const SizedBox(height: 10),
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: adminMetaPill(statusLabel),
                        ),
                      ),
                      const SizedBox(width: 8),
                      actions,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
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

class _AdminBookingsFixedSlot extends StatelessWidget {
  const _AdminBookingsFixedSlot({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdminListFixedSlot(width: width, child: child);
  }
}

class _AdminBookingsHeaderCell extends StatelessWidget {
  const _AdminBookingsHeaderCell({
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

class _AdminBookingsBodyCell extends StatelessWidget {
  const _AdminBookingsBodyCell({
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

class _AdminBookingDetailHeader extends StatelessWidget {
  const _AdminBookingDetailHeader({
    required this.booking,
    required this.user,
    required this.onBack,
    this.onEdit,
  });

  final Booking booking;
  final UserModel user;
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
            user: user,
            initialTopicKey: supportTopicBooking,
            initialBookingId: booking.id,
            initialUserId: booking.client?.id,
          ),
        ),
      ],
    );
  }
}

class _AdminBookingsStateCard extends StatelessWidget {
  const _AdminBookingsStateCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(padding: const EdgeInsets.all(24), child: child);
  }
}
