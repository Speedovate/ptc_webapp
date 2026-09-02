import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/chassis.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/chassis.request.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';
import 'package:webapp/widgets/shared/booking_section_navigation_scope.dart';
import 'package:webapp/widgets/shared/chassis_status_presentation.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

class AdminChassisView extends StatefulWidget {
  const AdminChassisView({super.key});
  @override
  State<AdminChassisView> createState() => _AdminChassisViewState();
}

class _AdminChassisViewState extends State<AdminChassisView> {
  static const _headerStyle = TextStyle(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w700,
  );
  static const _defaultTrailingPadding =
      AdminListMeasurements.defaultTrailingPadding;
  static const _extraWidthAllowance =
      AdminListMeasurements.defaultExtraWidthAllowance;
  String _query = '';
  String _status = 'All';
  String _activeFilter = 'All';
  DateTime? _createdStartDate;
  DateTime? _createdEndDate;
  DateTime? _updatedStartDate;
  DateTime? _updatedEndDate;
  List<Chassis> _items = const <Chassis>[];
  List<Booking> _bookingOptions = const <Booking>[];
  List<UserModel> _driverOptions = const <UserModel>[];
  Future<void>? _editorOptionsFuture;
  StreamSubscription<List<Chassis>>? _chassisSubscription;
  bool _isLoadingChassis = true;
  String? _chassisLoadError;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;

  bool get _canCreateChassis =>
      _roleAccessService.canAccess(DispatcherAccessCapability.chassisCreate);
  bool get _canUpdateChassis =>
      _roleAccessService.canAccess(DispatcherAccessCapability.chassisUpdate);
  bool get _canDeleteChassis =>
      _roleAccessService.canAccess(DispatcherAccessCapability.chassisDelete);

  @override
  void initState() {
    super.initState();
    _editorOptionsFuture = _loadEditorOptions();
    unawaited(_editorOptionsFuture!);
    _chassisSubscription = ChassisRequest.instance.watchChassis().listen((
      items,
    ) {
      if (!mounted || !ChassisRequest.instance.hasResolvedChassis) return;
      setState(() {
        _items = items;
        _isLoadingChassis = false;
        _chassisLoadError = null;
      });
    });
    unawaited(_loadChassis());
  }

  @override
  void dispose() {
    _chassisSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadChassis() async {
    if (mounted) {
      setState(() {
        _isLoadingChassis = true;
        _chassisLoadError = null;
      });
    }
    try {
      final items = await ChassisRequest.instance.getChassis();
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoadingChassis = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingChassis = false;
        _chassisLoadError = 'We could not load chassis from Firestore.';
      });
    }
  }

  Future<void> _loadEditorOptions() async {
    try {
      final results = await Future.wait<Object>([
        BookingRequest.instance.getBookings(),
        AuthRequest.instance.getUsers(),
      ]);
      if (!mounted) return;
      final bookings = results[0] as List<Booking>;
      final users = results[1] as List<UserModel>;
      setState(() {
        _bookingOptions = bookings;
        _driverOptions = users
            .where((user) => user.role?.trim().toLowerCase() == 'driver')
            .toList();
      });
    } catch (_) {
      // The editor remains usable offline with any options already in memory.
    }
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) {
      final items = List<Chassis>.from(_items);
      items.sort((a, b) => b.id.compareTo(a.id));
      final visible = items
          .where(
            (item) =>
                (_status == 'All' || item.currentStatus == _status) &&
                (_activeFilter == 'All' ||
                    (_activeFilter == 'Active' && item.isActive) ||
                    (_activeFilter == 'Inactive' && !item.isActive)) &&
                _isWithinRange(
                  item.createdAt,
                  _createdStartDate,
                  _createdEndDate,
                ) &&
                _isWithinRange(
                  item.updatedAt,
                  _updatedStartDate,
                  _updatedEndDate,
                ) &&
                '${item.id} ${item.name}'.toLowerCase().contains(
                  _query.toLowerCase(),
                ),
          )
          .toList();
      return LayoutBuilder(
        builder: (context, constraints) {
          final useWideTable = constraints.maxWidth >= 940;
          final textScaler = MediaQuery.textScalerOf(context);
          final sampleId = visible
              .map((item) => '${item.id}')
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleName = visible
              .map((item) => item.name)
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleClient = visible
              .map(
                (item) =>
                    _clientContactForBooking(item.currentBookingId).display,
              )
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleDriver = visible
              .map((item) => _driverContactForId(item.currentDriverId).display)
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleBooking = visible
              .map((item) => item.currentBookingId?.toString() ?? '-')
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleLocation = visible
              .map((item) => item.location ?? '-')
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleStatus = visible
              .map((item) => chassisStatusLabel(item.currentStatus))
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleCreated = visible
              .map((item) => AdminUsersView.formatCreatedAt(item.createdAt))
              .fold<String>('-', AdminListMeasurements.longerText);
          final sampleUpdated = visible
              .map((item) => AdminUsersView.formatUpdatedAt(item.updatedAt))
              .fold<String>('-', AdminListMeasurements.longerText);
          final idWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'ID',
            sampleId,
            _ChassisStyles.value,
          );
          final nameWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Name',
            sampleName,
            _ChassisStyles.title,
          );
          final clientWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Client',
            sampleClient,
            _ChassisStyles.value,
          );
          final driverWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Driver',
            sampleDriver,
            _ChassisStyles.value,
          );
          final bookingWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Booking',
            sampleBooking,
            _ChassisStyles.value,
          );
          final locationWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Location',
            sampleLocation,
            _ChassisStyles.value,
          );
          final createdWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Created',
            sampleCreated,
            _ChassisStyles.value,
          );
          final statusWidth = _resolvedChassisStatusColumnWidth(
            context,
            textScaler,
            sampleStatus,
          );
          final updatedWidth = _resolvedChassisColumnWidth(
            context,
            textScaler,
            'Updated',
            sampleUpdated,
            _ChassisStyles.value,
          );
          final actionsWidth =
              AdminListMeasurements.maxValue(
                192,
                AdminListMeasurements.measureTextWidth(
                  context,
                  textScaler,
                  'Actions',
                  _headerStyle,
                ),
              ) +
              _extraWidthAllowance;
          return AppPageLoadingOverlay(
            isVisible: _isLoadingChassis && _items.isEmpty,
            message: 'Loading chassis ...',
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdminListToolbar(
                    controlHeight: 52,
                    surfaceRadius: 16,
                    search: AdminListSearchField(
                      controlHeight: 52,
                      surfaceRadius: 16,
                      initialValue: _query,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    filtersBuilder: (_, iconOnly) => _ChassisFiltersPanel(
                      iconOnly: iconOnly,
                      status: _status,
                      active: _activeFilter,
                      createdStart: _createdStartDate,
                      createdEnd: _createdEndDate,
                      updatedStart: _updatedStartDate,
                      updatedEnd: _updatedEndDate,
                      onStatusChanged: (value) =>
                          setState(() => _status = value),
                      onActiveChanged: (value) =>
                          setState(() => _activeFilter = value),
                      onCreatedStartChanged: (value) =>
                          setState(() => _createdStartDate = value),
                      onCreatedEndChanged: (value) =>
                          setState(() => _createdEndDate = value),
                      onUpdatedStartChanged: (value) =>
                          setState(() => _updatedStartDate = value),
                      onUpdatedEndChanged: (value) =>
                          setState(() => _updatedEndDate = value),
                      onClear: () => setState(() {
                        _status = 'All';
                        _activeFilter = 'All';
                        _createdStartDate = null;
                        _createdEndDate = null;
                        _updatedStartDate = null;
                        _updatedEndDate = null;
                      }),
                    ),
                    onNewPressed: _canCreateChassis ? _openEditor : null,
                  ),
                  const SizedBox(height: 12),
                  if (_chassisLoadError != null && _items.isEmpty)
                    _ChassisLoadErrorState(
                      message: _chassisLoadError!,
                      onRetry: _loadChassis,
                    )
                  else if (_items.isEmpty)
                    const _ChassisEmptyState(message: 'No chassis yet.')
                  else if (visible.isEmpty)
                    const _ChassisEmptyState(
                      message: 'No chassis matched your current search.',
                    )
                  else ...[
                    if (useWideTable)
                      _ChassisHeaderRow(
                        idWidth: idWidth,
                        nameWidth: nameWidth,
                        clientWidth: clientWidth,
                        driverWidth: driverWidth,
                        bookingWidth: bookingWidth,
                        locationWidth: locationWidth,
                        statusWidth: statusWidth,
                        createdWidth: createdWidth,
                        updatedWidth: updatedWidth,
                        actionsWidth: actionsWidth,
                      ),
                    if (useWideTable) const SizedBox(height: 14),
                    ...visible.asMap().entries.map((entry) {
                      final client = _clientContactForBooking(
                        entry.value.currentBookingId,
                      );
                      final driver = _driverContactForId(
                        entry.value.currentDriverId,
                      );
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: entry.key == visible.length - 1 ? 0 : 12,
                        ),
                        child: useWideTable
                            ? _ChassisDesktopRow(
                                item: entry.value,
                                client: client,
                                driver: driver,
                                idWidth: idWidth,
                                nameWidth: nameWidth,
                                clientWidth: clientWidth,
                                driverWidth: driverWidth,
                                bookingWidth: bookingWidth,
                                locationWidth: locationWidth,
                                statusWidth: statusWidth,
                                createdWidth: createdWidth,
                                updatedWidth: updatedWidth,
                                actionsWidth: actionsWidth,
                                actions: _chassisActions(entry.value),
                                onOpenBooking: () =>
                                    _openBooking(entry.value.currentBookingId),
                              )
                            : _ChassisResponsiveCard(
                                item: entry.value,
                                client: client,
                                driver: driver,
                                actions: _chassisActions(entry.value),
                                onOpenBooking: () =>
                                    _openBooking(entry.value.currentBookingId),
                              ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );

  List<Widget> _chassisActions(Chassis item) => [
    AdminListActionButton(
      icon: Icons.visibility_rounded,
      backgroundColor: Colors.yellow.shade900,
      onTap: () => _openEditor(item: item, readOnly: true),
    ),
    if (_canUpdateChassis)
      AdminListActionButton(
        icon: Icons.edit_rounded,
        onTap: () => _openEditor(item: item),
      ),
    if (_canUpdateChassis)
      AdminListActionButton(
        icon: item.isActive ? Icons.close_rounded : Icons.check_rounded,
        backgroundColor: item.isActive
            ? AppColors.dangerStrong
            : const Color(0xFF2EAD62),
        onTap: () => _toggleActive(item),
      ),
    if (_canDeleteChassis)
      AdminListActionButton(
        icon: Icons.delete_rounded,
        isDanger: true,
        onTap: () => _deleteChassis(item),
      ),
  ];

  Future<void> _toggleActive(Chassis item) async {
    if (!_canUpdateChassis) return;
    final willBeActive = !item.isActive;
    await showAdminActionConfirmation(
      context,
      title: '${willBeActive ? 'Activate' : 'Deactivate'} Chassis ${item.id}',
      message:
          'Are you sure you want to ${willBeActive ? 'activate' : 'deactivate'} ${item.name}?',
      confirmLabel: willBeActive ? 'Activate' : 'Deactivate',
      onConfirmAsync: () async {
        try {
          await ChassisRequest.instance.saveChassis(
            item.copyWith(isActive: willBeActive),
            previousBookingId: item.currentBookingId,
          );
          if (!mounted) return false;
          AppSnackbar.showSuccess(
            context,
            willBeActive ? 'Chassis activated.' : 'Chassis deactivated.',
          );
          return true;
        } catch (_) {
          if (!mounted) return false;
          AppSnackbar.showError(context, 'We could not update the chassis.');
          return false;
        }
      },
    );
  }

  Future<void> _deleteChassis(Chassis item) async {
    if (!_canDeleteChassis) return;
    await showAdminActionConfirmation(
      context,
      title: 'Delete Chassis ${item.id}',
      message: 'Are you sure you want to delete ${item.name}?',
      confirmLabel: 'Delete',
      isDanger: true,
      onConfirmAsync: () async {
        try {
          await ChassisRequest.instance.deleteChassis(item);
          if (!mounted) return false;
          AppSnackbar.showSuccess(context, 'Chassis deleted.');
          return true;
        } catch (_) {
          if (!mounted) return false;
          AppSnackbar.showError(context, 'We could not delete the chassis.');
          return false;
        }
      },
    );
  }

  Future<void> _openEditor({Chassis? item, bool readOnly = false}) async {
    await (_editorOptionsFuture ??= _loadEditorOptions());
    if (!mounted) return;
    final name = TextEditingController(text: item?.name ?? '');
    final location = TextEditingController(text: item?.location ?? '');
    final isActive = ValueNotifier<bool>(item?.isActive ?? true);
    var selectedStatus = item?.currentStatus ?? Chassis.ready;
    var selectedBookingId = item?.currentBookingId?.toString();
    var selectedDriverId = item?.currentDriverId?.toString();
    var isSaving = false;
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AdminModalShell(
          title: readOnly
              ? 'Chassis ${item?.id ?? '-'}'
              : item == null
              ? 'New Chassis'
              : 'Edit Chassis',
          contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 14),
          actions: readOnly
              ? [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final resolvedName = name.text.trim();
                            if (resolvedName.isEmpty) {
                              AppSnackbar.showError(
                                dialogContext,
                                'Name is required.',
                              );
                              return;
                            }
                            setDialogState(() => isSaving = true);
                            final now = DateTime.now();
                            final next = Chassis(
                              id: item?.id ?? 0,
                              name: resolvedName,
                              isActive: isActive.value,
                              currentStatus: selectedStatus,
                              currentBookingId: _optionalId(selectedBookingId),
                              currentDriverId: _optionalId(selectedDriverId),
                              location: location.text.trim().isEmpty
                                  ? null
                                  : location.text.trim(),
                              createdAt: item?.createdAt ?? now,
                              updatedAt: now,
                            );
                            try {
                              await ChassisRequest.instance.saveChassis(
                                next,
                                previousBookingId: item?.currentBookingId,
                              );
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop(true);
                              }
                            } catch (_) {
                              if (!dialogContext.mounted) return;
                              setDialogState(() => isSaving = false);
                              AppSnackbar.showError(
                                dialogContext,
                                'We could not save the chassis right now.',
                              );
                            }
                          },
                    child: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Save'),
                  ),
                ],
          child: IgnorePointer(
            ignoring: readOnly,
            child: AdminModalFormBody(
              children: [
                AdminModalFieldsSection(
                  children: [
                    AdminModalTextField(
                      controller: name,
                      label: 'Name',
                      textInputAction: TextInputAction.next,
                    ),
                    AdminDropdownFormField<String>(
                      initialValue: item == null ? null : selectedStatus,
                      iconEnabledColor: AppColors.primaryColor,
                      style: adminDropdownDisplayTextStyle,
                      decoration: adminFormInputDecoration(
                        'Status',
                        radius: 16,
                        minHeight: adminModalFieldMinHeight,
                      ),
                      items: Chassis.statuses
                          .map(
                            (status) => DropdownMenuItem<String>(
                              value: status,
                              child: Text(
                                chassisStatusLabel(status),
                                style: adminDropdownDisplayTextStyle,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) selectedStatus = value;
                      },
                    ),
                    const SizedBox(height: 6),
                    AdminDropdownFormField<String>(
                      initialValue: selectedBookingId,
                      iconEnabledColor: AppColors.primaryColor,
                      style: adminDropdownDisplayTextStyle,
                      decoration: adminFormInputDecoration(
                        'Booking',
                        radius: 16,
                        minHeight: adminModalFieldMinHeight,
                      ),
                      items: _bookingDropdownItems(),
                      onChanged: (value) => selectedBookingId = value,
                    ),
                    const SizedBox(height: 6),
                    AdminDropdownFormField<String>(
                      initialValue: selectedDriverId,
                      iconEnabledColor: AppColors.primaryColor,
                      style: adminDropdownDisplayTextStyle,
                      decoration: adminFormInputDecoration(
                        'Driver',
                        radius: 16,
                        minHeight: adminModalFieldMinHeight,
                      ),
                      items: _driverDropdownItems(),
                      onChanged: (value) => selectedDriverId = value,
                    ),
                    const SizedBox(height: 6),
                    AdminModalTextField(
                      controller: location,
                      label: 'Location',
                      bottomPadding: 0,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<bool>(
                      valueListenable: isActive,
                      builder: (context, value, _) => AdminModalToggleRow(
                        title: 'Active',
                        value: value,
                        onChanged: (nextValue) => isActive.value = nextValue,
                        leftInset: 0,
                        rightInset: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // A dialog result can resolve while its exit animation is still rebuilding
    // its fields. Dispose external notifiers only after that route is gone.
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      name.dispose();
      location.dispose();
      isActive.dispose();
    });
    if (saved != true) return;
  }

  Future<void> _openBooking(int? bookingId) async {
    final bookingIdText = bookingId?.toString();
    if (bookingIdText == null) return;
    final booking = _bookingOptions.where((item) => item.id == bookingIdText);
    if (booking.isEmpty) return;
    if (!mounted) return;
    BookingSectionNavigationScope.maybeOf(context)?.openBooking(booking.first);
  }

  int? _optionalId(String? value) => int.tryParse(value?.trim() ?? '');

  _ChassisContact _clientContactForBooking(int? bookingId) {
    final bookingIdText = bookingId?.toString();
    for (final booking in _bookingOptions) {
      if (booking.id != bookingIdText) continue;
      return _ChassisContact.fromValues(
        BookingRecordCard.outputFieldDisplayValue(
          booking.statusOutputs,
          'representative_name',
        ),
        BookingRecordCard.outputFieldDisplayValue(
          booking.statusOutputs,
          'representative_phone',
        ),
      );
    }
    return const _ChassisContact.empty();
  }

  _ChassisContact _driverContactForId(int? driverId) {
    final driverIdText = driverId?.toString();
    for (final driver in _driverOptions) {
      if (driver.id == driverIdText) return _ChassisContact.fromUser(driver);
    }
    return const _ChassisContact.empty();
  }

  List<DropdownMenuItem<String>> _bookingDropdownItems() => _bookingOptions
      .where((booking) => booking.id?.trim().isNotEmpty == true)
      .map(
        (booking) => DropdownMenuItem<String>(
          value: booking.id,
          child: Text(
            _bookingOptionLabel(booking),
            overflow: TextOverflow.ellipsis,
            style: adminDropdownDisplayTextStyle,
          ),
        ),
      )
      .toList();

  List<DropdownMenuItem<String>> _driverDropdownItems() => _driverOptions
      .where((driver) => driver.id?.trim().isNotEmpty == true)
      .map(
        (driver) => DropdownMenuItem<String>(
          value: driver.id,
          child: Text(
            _driverOptionLabel(driver),
            overflow: TextOverflow.ellipsis,
            style: adminDropdownDisplayTextStyle,
          ),
        ),
      )
      .toList();

  String _bookingOptionLabel(Booking booking) {
    final id = booking.id ?? '-';
    final clientName = booking.client?.name?.trim();
    return clientName == null || clientName.isEmpty
        ? 'Booking $id'
        : 'Booking $id | $clientName';
  }

  String _driverOptionLabel(UserModel driver) {
    final name = driver.name?.trim();
    return name == null || name.isEmpty
        ? 'Driver ${driver.id ?? '-'}'
        : '${driver.id ?? '-'} | $name';
  }

  bool _isWithinRange(DateTime? value, DateTime? start, DateTime? end) {
    if (value == null) return true;
    final day = DateTime(value.year, value.month, value.day);
    if (start != null) {
      final first = DateTime(start.year, start.month, start.day);
      if (day.isBefore(first)) return false;
    }
    if (end != null) {
      final last = DateTime(end.year, end.month, end.day);
      if (day.isAfter(last)) return false;
    }
    return true;
  }

  double _resolvedChassisColumnWidth(
    BuildContext context,
    TextScaler textScaler,
    String header,
    String sample,
    TextStyle valueStyle,
  ) {
    final measured = AdminListMeasurements.maxTextWidth(
      context,
      textScaler,
      header,
      _headerStyle,
      sample,
      valueStyle,
    );
    return AdminListMeasurements.resolvedColumnWidth(
      measured,
      trailingPadding: _defaultTrailingPadding,
      extraWidthAllowance: _extraWidthAllowance,
    );
  }

  double _resolvedChassisStatusColumnWidth(
    BuildContext context,
    TextScaler textScaler,
    String sample,
  ) {
    const pillTextStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);
    final headerWidth = AdminListMeasurements.measureTextWidth(
      context,
      textScaler,
      'Status',
      _headerStyle,
    );
    final pillWidth =
        AdminListMeasurements.measureTextWidth(
          context,
          textScaler,
          sample,
          pillTextStyle,
        ) +
        26; // Meta pill: 12px on each side plus its 1px borders.
    return AdminListMeasurements.resolvedColumnWidth(
      AdminListMeasurements.maxValue(headerWidth, pillWidth),
      trailingPadding: _defaultTrailingPadding,
      extraWidthAllowance: _extraWidthAllowance,
    );
  }
}

class _ChassisHeaderRow extends StatelessWidget {
  const _ChassisHeaderRow({
    required this.idWidth,
    required this.nameWidth,
    required this.clientWidth,
    required this.driverWidth,
    required this.bookingWidth,
    required this.locationWidth,
    required this.statusWidth,
    required this.createdWidth,
    required this.updatedWidth,
    required this.actionsWidth,
  });

  final double idWidth;
  final double nameWidth;
  final double clientWidth;
  final double driverWidth;
  final double bookingWidth;
  final double locationWidth;
  final double statusWidth;
  final double createdWidth;
  final double updatedWidth;
  final double actionsWidth;

  @override
  Widget build(BuildContext context) {
    return AdminListHeaderBar(
      minHeight: 52,
      borderRadius: 16,
      horizontalPadding: 16,
      child: Row(
        children: [
          AdminListFixedSlot(
            width: idWidth,
            child: const AdminListHeaderCell(label: 'ID'),
          ),
          AdminListFixedSlot(
            width: nameWidth,
            child: const AdminListHeaderCell(label: 'Name'),
          ),
          AdminListFixedSlot(
            width: clientWidth,
            child: const AdminListHeaderCell(label: 'Client'),
          ),
          AdminListFixedSlot(
            width: driverWidth,
            child: const AdminListHeaderCell(label: 'Driver'),
          ),
          AdminListFixedSlot(
            width: bookingWidth,
            child: const AdminListHeaderCell(label: 'Booking'),
          ),
          AdminListFixedSlot(
            width: locationWidth,
            child: const AdminListHeaderCell(label: 'Location'),
          ),
          AdminListFixedSlot(
            width: statusWidth,
            child: const AdminListHeaderCell(label: 'Status'),
          ),
          AdminListFixedSlot(
            width: createdWidth,
            child: const AdminListHeaderCell(label: 'Created'),
          ),
          AdminListFixedSlot(
            width: updatedWidth,
            child: const AdminListHeaderCell(label: 'Updated'),
          ),
          AdminListTrailingActionsLane(
            width: actionsWidth,
            child: const AdminListHeaderCell(
              label: 'Actions',
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChassisDesktopRow extends StatelessWidget {
  const _ChassisDesktopRow({
    required this.item,
    required this.client,
    required this.driver,
    required this.idWidth,
    required this.nameWidth,
    required this.clientWidth,
    required this.driverWidth,
    required this.bookingWidth,
    required this.locationWidth,
    required this.statusWidth,
    required this.createdWidth,
    required this.updatedWidth,
    required this.actionsWidth,
    required this.actions,
    required this.onOpenBooking,
  });

  final Chassis item;
  final _ChassisContact client;
  final _ChassisContact driver;
  final double idWidth;
  final double nameWidth;
  final double clientWidth;
  final double driverWidth;
  final double bookingWidth;
  final double locationWidth;
  final double statusWidth;
  final double createdWidth;
  final double updatedWidth;
  final double actionsWidth;
  final List<Widget> actions;
  final VoidCallback onOpenBooking;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      child: Row(
        children: [
          AdminListFixedSlot(
            width: idWidth,
            child: AdminListBodyCell(
              child: Text('${item.id}', style: _ChassisStyles.value),
            ),
          ),
          AdminListFixedSlot(
            width: nameWidth,
            child: AdminListBodyCell(
              child: Text(item.name, style: _ChassisStyles.title),
            ),
          ),
          AdminListFixedSlot(
            width: clientWidth,
            child: AdminListBodyCell(
              child: _ChassisContactText(contact: client),
            ),
          ),
          AdminListFixedSlot(
            width: driverWidth,
            child: AdminListBodyCell(
              child: _ChassisContactText(contact: driver),
            ),
          ),
          AdminListFixedSlot(
            width: bookingWidth,
            child: AdminListBodyCell(
              child: _ChassisBookingLink(
                bookingId: item.currentBookingId,
                onOpen: onOpenBooking,
              ),
            ),
          ),
          AdminListFixedSlot(
            width: locationWidth,
            child: AdminListBodyCell(
              child: Text(item.location ?? '-', style: _ChassisStyles.value),
            ),
          ),
          AdminListFixedSlot(
            width: statusWidth,
            child: AdminListBodyCell(
              child: ChassisStatusPill(status: item.currentStatus),
            ),
          ),
          AdminListFixedSlot(
            width: createdWidth,
            child: AdminListBodyCell(
              child: Text(
                AdminUsersView.formatCreatedAt(item.createdAt),
                style: _ChassisStyles.value,
                softWrap: true,
              ),
            ),
          ),
          AdminListFixedSlot(
            width: updatedWidth,
            child: AdminListBodyCell(
              child: Text(
                AdminUsersView.formatUpdatedAt(item.updatedAt),
                style: _ChassisStyles.value,
                softWrap: true,
              ),
            ),
          ),
          AdminListTrailingActionsLane(
            width: actionsWidth,
            child: AdminListBodyCell(
              trailingPadding: 0,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions
                    .expand<Widget>(
                      (action) => [
                        action,
                        if (action != actions.last) const SizedBox(width: 8),
                      ],
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChassisResponsiveCard extends StatelessWidget {
  const _ChassisResponsiveCard({
    required this.item,
    required this.client,
    required this.driver,
    required this.actions,
    required this.onOpenBooking,
  });

  final Chassis item;
  final _ChassisContact client;
  final _ChassisContact driver;
  final List<Widget> actions;
  final VoidCallback onOpenBooking;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final singleColumn = constraints.maxWidth < 520;
          final fields = [
            ('ID', '${item.id}', false),
            ('Name', item.name, true),
            ('Client', client.display, false),
            ('Driver', driver.display, false),
            ('Location', item.location ?? '-', false),
            ('Created', AdminUsersView.formatCreatedAt(item.createdAt), false),
            ('Updated', AdminUsersView.formatUpdatedAt(item.updatedAt), false),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Wrap(spacing: 8, children: actions),
                ],
              ),
              const SizedBox(height: 18),
              _ChassisBookingLink(
                bookingId: item.currentBookingId,
                onOpen: onOpenBooking,
                showLabel: true,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  ...fields.map(
                    (field) => AdminListResponsiveField(
                      title: field.$1,
                      value: field.$2,
                      isTitle: field.$3,
                      centered: false,
                      width: singleColumn
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 16) / 2,
                    ),
                  ),
                  SizedBox(
                    width: singleColumn
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 16) / 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status',
                          style: TextStyle(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.72,
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ChassisStatusPill(status: item.currentStatus),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChassisContact {
  const _ChassisContact({required this.name, required this.phone});

  const _ChassisContact.empty() : name = '-', phone = '-';

  final String name;
  final String phone;

  bool get isEmpty => name == '-' && phone == '-';

  String get display => isEmpty ? '-' : '$name\n$phone';

  factory _ChassisContact.fromUser(UserModel? user) {
    if (user == null) return const _ChassisContact.empty();
    return _ChassisContact.fromValues(user.name, user.phone);
  }

  factory _ChassisContact.fromValues(String? nameValue, String? phoneValue) {
    final name = nameValue?.trim();
    final phone = phoneValue?.trim();
    if ((name == null || name.isEmpty) && (phone == null || phone.isEmpty)) {
      return const _ChassisContact.empty();
    }
    return _ChassisContact(
      name: name == null || name.isEmpty || name == '-' ? '-' : name,
      phone: phone == null || phone.isEmpty || phone == '-' ? '-' : phone,
    );
  }
}

class _ChassisContactText extends StatelessWidget {
  const _ChassisContactText({required this.contact});

  final _ChassisContact contact;

  @override
  Widget build(BuildContext context) {
    return Text(contact.display, softWrap: true, style: _ChassisStyles.value);
  }
}

class _ChassisBookingLink extends StatelessWidget {
  const _ChassisBookingLink({
    required this.bookingId,
    required this.onOpen,
    this.showLabel = false,
  });

  final int? bookingId;
  final VoidCallback onOpen;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final value = bookingId?.toString() ?? '-';
    final canOpen = bookingId != null;
    final link = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: _ChassisStyles.value),
        if (canOpen) ...[
          const SizedBox(width: 6),
          Icon(
            Icons.open_in_new_rounded,
            size: 16,
            color: AppColors.primaryColor,
          ),
        ],
      ],
    );
    final interactiveLink = canOpen
        ? InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: link,
            ),
          )
        : link;
    if (!showLabel) return interactiveLink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Booking',
          style: TextStyle(
            color: AppColors.primaryColor.withValues(alpha: 0.72),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        interactiveLink,
      ],
    );
  }
}

class _ChassisStyles {
  static const title = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const value = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}

class _ChassisLoadErrorState extends StatelessWidget {
  const _ChassisLoadErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.primaryColor.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ChassisEmptyState extends StatelessWidget {
  const _ChassisEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AdminListItemCard(
      padding: const EdgeInsets.all(18),
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChassisFiltersPanel extends StatefulWidget {
  const _ChassisFiltersPanel({
    required this.iconOnly,
    required this.status,
    required this.active,
    required this.createdStart,
    required this.createdEnd,
    required this.updatedStart,
    required this.updatedEnd,
    required this.onStatusChanged,
    required this.onActiveChanged,
    required this.onCreatedStartChanged,
    required this.onCreatedEndChanged,
    required this.onUpdatedStartChanged,
    required this.onUpdatedEndChanged,
    required this.onClear,
  });

  final bool iconOnly;
  final String status;
  final String active;
  final DateTime? createdStart;
  final DateTime? createdEnd;
  final DateTime? updatedStart;
  final DateTime? updatedEnd;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onActiveChanged;
  final ValueChanged<DateTime?> onCreatedStartChanged;
  final ValueChanged<DateTime?> onCreatedEndChanged;
  final ValueChanged<DateTime?> onUpdatedStartChanged;
  final ValueChanged<DateTime?> onUpdatedEndChanged;
  final VoidCallback onClear;

  @override
  State<_ChassisFiltersPanel> createState() => _ChassisFiltersPanelState();
}

class _ChassisFiltersPanelState extends State<_ChassisFiltersPanel> {
  @override
  Widget build(BuildContext context) => AdminListDynamicFiltersPanel(
    iconOnly: widget.iconOnly,
    filters: [
      AdminListDropdownFilterConfig(
        label: 'Status',
        value: widget.status,
        items: ['All', ...Chassis.statuses],
        onChanged: widget.onStatusChanged,
        itemBuilder: (status) => status == 'All'
            ? Text('All', style: adminDropdownDisplayTextStyle)
            : ChassisStatusOptionLabel(
                label: chassisStatusLabel(status),
                status: status,
              ),
      ),
      AdminListDropdownFilterConfig(
        label: 'Is Active',
        value: widget.active,
        items: const ['All', 'Active', 'Inactive'],
        onChanged: widget.onActiveChanged,
      ),
      AdminListDateFilterConfig(
        label: 'Created Start',
        value: widget.createdStart,
        onSelected: widget.onCreatedStartChanged,
        formatter: _formatChassisFilterDateValue,
      ),
      AdminListDateFilterConfig(
        label: 'Created End',
        value: widget.createdEnd,
        onSelected: widget.onCreatedEndChanged,
        formatter: _formatChassisFilterDateValue,
      ),
      AdminListDateFilterConfig(
        label: 'Updated Start',
        value: widget.updatedStart,
        onSelected: widget.onUpdatedStartChanged,
        formatter: _formatChassisFilterDateValue,
      ),
      AdminListDateFilterConfig(
        label: 'Updated End',
        value: widget.updatedEnd,
        onSelected: widget.onUpdatedEndChanged,
        formatter: _formatChassisFilterDateValue,
      ),
    ],
    onClear: widget.onClear,
  );
}

String _formatChassisFilterDateValue(DateTime? value) {
  if (value == null) return '';
  const months = [
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
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}
