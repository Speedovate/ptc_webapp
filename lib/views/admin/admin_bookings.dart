import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/status.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/admin/admin_bookings.vm.dart';
import 'package:webapp/views/client/client_booking_home_view.dart';
import 'package:webapp/views/shared/booking_workflow_view.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

class AdminBookingsView extends StatefulWidget {
  const AdminBookingsView({super.key, required this.user});

  final UserModel user;

  @override
  State<AdminBookingsView> createState() => _AdminBookingsViewState();
}

class _AdminBookingsViewState extends State<AdminBookingsView> {
  Booking? _selectedBooking;
  late final ScrollController _detailScrollController;

  @override
  void initState() {
    super.initState();
    _detailScrollController = ScrollController();
  }

  @override
  void dispose() {
    _detailScrollController.dispose();
    super.dispose();
  }

  Future<void> _openNewBookingDialog(AdminBookingsViewModel vm) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _NewAdminBookingDialog(
        currentUser: widget.user,
        clientUsers: vm.clientUsers(),
        onBookingSubmitted: (booking) async {
          if (!mounted) {
            return;
          }
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
    final updatedBooking = await showDialog<Booking>(
      context: context,
      builder: (dialogContext) => _EditAdminBookingDialog(
        booking: booking,
        currentStatusLabel: vm.clientStatusLabel(booking),
        statuses: vm.activeStatuses(),
        drivers: vm.roleUsers('driver'),
        helpers: vm.roleUsers('helper'),
        vehicleSizes: vm.activeVehicleSizes(),
      ),
    );
    if (updatedBooking == null) {
      return;
    }
    await vm.saveEditedBooking(updatedBooking);
    if (!mounted) {
      return;
    }
    if (_selectedBooking?.id == updatedBooking.id) {
      setState(() {
        _selectedBooking = updatedBooking;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AdminBookingsViewModel>.reactive(
      viewModelBuilder: AdminBookingsViewModel.new,
      onViewModelReady: (vm) => vm.load(),
      builder: (context, vm, child) {
        final selectedBooking = _selectedBooking == null
            ? null
            : vm.bookings
                      .where((booking) => booking.id == _selectedBooking!.id)
                      .firstOrNull ??
                  _selectedBooking;
        final filteredBookings = vm.filteredBookings();

        if (selectedBooking != null) {
          return SingleChildScrollView(
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
                  onBack: () {
                    setState(() {
                      _selectedBooking = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                BookingWorkflowView(
                  key: ValueKey(
                    'admin-booking-workflow-${selectedBooking.id ?? ''}-${selectedBooking.updatedAt?.toIso8601String() ?? ''}',
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
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppRefreshStrip(isVisible: vm.isBusy),
              AdminListToolbar(
                controlHeight: 52,
                surfaceRadius: 16,
                search: AdminListSearchField(
                  controlHeight: 52,
                  surfaceRadius: 16,
                  initialValue: vm.searchQuery,
                  onChanged: vm.setSearchQuery,
                ),
                filtersBuilder: (context, iconOnly) =>
                    _BookingsFiltersPanel(vm: vm, iconOnly: iconOnly),
                onNewPressed: () => _openNewBookingDialog(vm),
              ),
              const SizedBox(height: 14),
              if (vm.errorMessage != null)
                _AdminBookingsStateCard(
                  child: AdminListStateText(message: vm.errorMessage!),
                )
              else if (vm.bookings.isEmpty)
                _AdminBookingsStateCard(
                  child: const AdminListStateText(message: 'No bookings yet.'),
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
                  onEdit: (booking) {
                    _openEditBookingDialog(vm, booking);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EditAdminBookingDialog extends StatefulWidget {
  const _EditAdminBookingDialog({
    required this.booking,
    required this.currentStatusLabel,
    required this.statuses,
    required this.drivers,
    required this.helpers,
    required this.vehicleSizes,
  });

  final Booking booking;
  final String currentStatusLabel;
  final List<Status> statuses;
  final List<UserModel> drivers;
  final List<UserModel> helpers;
  final List<VehicleCatalogItem> vehicleSizes;

  @override
  State<_EditAdminBookingDialog> createState() =>
      _EditAdminBookingDialogState();
}

class _EditAdminBookingDialogState extends State<_EditAdminBookingDialog> {
  late final TextEditingController _waybillNumberController;
  late final TextEditingController _vanNumberController;
  late final TextEditingController _amountController;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late String _statusKey;
  String? _driverId;
  String? _helperId;
  String? _vanSize;

  @override
  void initState() {
    super.initState();
    final initialWaybill = _existingFieldValue('waybill_number');
    final initialVanNumber = _existingFieldValue('van_number');
    final initialAmount = _existingFieldValue('amount');
    final initialStart = _existingFieldValue('start');
    final initialEnd = _existingFieldValue('end');
    _waybillNumberController = TextEditingController(
      text: initialWaybill ?? '',
    );
    _vanNumberController = TextEditingController(text: initialVanNumber ?? '');
    _amountController = TextEditingController(text: initialAmount ?? '');
    _startController = TextEditingController(text: initialStart ?? '');
    _endController = TextEditingController(text: initialEnd ?? '');
    _statusKey = widget.booking.clientStatus ?? '';
    _driverId = widget.booking.driver?.id;
    _helperId = widget.booking.helper?.id;
    final rawVanSize = _existingFieldValue('van_size');
    final normalizedVanSize = rawVanSize?.toString().trim();
    final matchesKnownSize =
        normalizedVanSize != null &&
        normalizedVanSize.isNotEmpty &&
        widget.vehicleSizes.any(
          (size) =>
              (size.name?.trim() ?? '') == normalizedVanSize ||
              (size.slug?.trim() ?? '') == normalizedVanSize,
        );
    _vanSize = matchesKnownSize ? normalizedVanSize : null;
  }

  @override
  void dispose() {
    _waybillNumberController.dispose();
    _vanNumberController.dispose();
    _amountController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
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
      addItem(_vanSize!, _vanSize!);
    }

    for (final size in widget.vehicleSizes) {
      final value = size.name?.trim();
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

    if (_statusKey.trim().isNotEmpty) {
      addItem(_statusKey, widget.currentStatusLabel);
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

    return items;
  }

  List<DropdownMenuItem<String>> _buildRoleUserItems({
    required String? selectedUserId,
    required List<UserModel> activeUsers,
    required String fallbackRole,
  }) {
    final items = <DropdownMenuItem<String>>[];
    final seenValues = <String>{};

    void addUserItem(String value, String label) {
      final normalizedValue = value.trim();
      if (normalizedValue.isEmpty || !seenValues.add(normalizedValue)) {
        return;
      }
      items.add(
        DropdownMenuItem<String>(
          value: normalizedValue,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: adminDropdownDisplayTextStyle,
          ),
        ),
      );
    }

    if (selectedUserId?.trim().isNotEmpty == true) {
      addUserItem(
        selectedUserId!,
        _fallbackUserLabel(selectedUserId, fallbackRole),
      );
    }

    for (final user in activeUsers) {
      final value = user.id?.trim();
      if (value != null && value.isNotEmpty) {
        addUserItem(value, _userLabel(user));
      }
    }

    return items;
  }

  String _fallbackUserLabel(String userId, String fallbackRole) {
    for (final user in [
      ...widget.drivers,
      ...widget.helpers,
      if (widget.booking.driver != null) widget.booking.driver!,
      if (widget.booking.helper != null) widget.booking.helper!,
    ]) {
      if (user.id == userId) {
        return _userLabel(user);
      }
    }
    return fallbackRole;
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalShell(
      title: 'Edit Booking',
      contentInset: const EdgeInsets.fromLTRB(0, 16, 0, 16),
      actionsInset: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _handleSave,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save Changes'),
        ),
      ],
      child: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: AdminModalFormBody(
            children: [
              AdminModalFieldsSection(
                children: [
                  AdminModalTextField(
                    controller: _waybillNumberController,
                    label: 'Waybill Number',
                    bottomPadding: 6,
                  ),
                  AdminModalTextField(
                    controller: _vanNumberController,
                    label: 'Van Number',
                    bottomPadding: 6,
                  ),
                  AdminModalDropdownField<String>(
                    label: 'Van Size',
                    initialValue: _vanSize,
                    bottomPadding: 10,
                    isExpanded: true,
                    disabledTapMessage: 'No active vehicle sizes available.',
                    items: _buildVanSizeItems(),
                    onChanged: (value) {
                      setState(() {
                        _vanSize = value;
                      });
                    },
                  ),
                  AdminModalTextField(
                    controller: _amountController,
                    label: 'Amount',
                    keyboardType: TextInputType.number,
                    bottomPadding: 6,
                  ),
                  AdminModalTextField(
                    controller: _startController,
                    label: 'Start',
                    bottomPadding: 6,
                  ),
                  AdminModalTextField(
                    controller: _endController,
                    label: 'End',
                    bottomPadding: 6,
                  ),
                  AdminModalDropdownField<String>(
                    label: 'Status',
                    initialValue: _statusKey.isEmpty ? null : _statusKey,
                    isExpanded: true,
                    disabledTapMessage: 'No active statuses available.',
                    items: _buildStatusItems(),
                    onChanged: (value) {
                      setState(() {
                        _statusKey = value ?? '';
                      });
                    },
                  ),
                  AdminModalDropdownField<String>(
                    label: 'Driver',
                    initialValue: _driverId,
                    isExpanded: true,
                    disabledTapMessage: 'No online drivers available.',
                    items: _buildRoleUserItems(
                      selectedUserId: _driverId,
                      activeUsers: widget.drivers,
                      fallbackRole: 'Driver',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _driverId = value;
                      });
                    },
                  ),
                  AdminModalDropdownField<String>(
                    label: 'Helper',
                    initialValue: _helperId,
                    isExpanded: true,
                    bottomPadding: 0,
                    disabledTapMessage: 'No online helpers available.',
                    items: _buildRoleUserItems(
                      selectedUserId: _helperId,
                      activeUsers: widget.helpers,
                      fallbackRole: 'Helper',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _helperId = value;
                      });
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

  void _handleSave() {
    final currentOutputs = Map<String, dynamic>.from(
      widget.booking.statusOutputs ?? const <String, dynamic>{},
    );
    final pendingSection = Map<String, dynamic>.from(
      currentOutputs['pending'] is Map
          ? currentOutputs['pending'] as Map
          : const <String, dynamic>{},
    );
    final pendingFields = Map<String, dynamic>.from(
      pendingSection['fields'] is Map
          ? pendingSection['fields'] as Map
          : const <String, dynamic>{},
    );

    _setOrRemoveField(
      pendingFields,
      'waybill_number',
      _waybillNumberController.text.trim(),
    );
    _setOrRemoveField(
      pendingFields,
      'van_number',
      _vanNumberController.text.trim(),
    );
    _setOrRemoveField(pendingFields, 'van_size', _vanSize?.trim() ?? '');
    _setOrRemoveField(pendingFields, 'amount', _amountController.text.trim());
    _setOrRemoveField(pendingFields, 'start', _startController.text.trim());
    _setOrRemoveField(pendingFields, 'end', _endController.text.trim());

    if (pendingFields.isEmpty) {
      currentOutputs.remove('pending');
    } else {
      pendingSection['fields'] = pendingFields;
      currentOutputs['pending'] = pendingSection;
    }

    Navigator.of(context).pop(
      widget.booking.copyWith(
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
        statusOutputs: currentOutputs,
      ),
    );
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
  late String _selectedBookerId;

  @override
  void initState() {
    super.initState();
    _selectedBookerId = widget.currentUser.id ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final selectedUser = _selectedUser;

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
        child: SizedBox(
          height: 700,
          child: SingleChildScrollView(
            child: Column(
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
                            initialValue: _selectedBookerId.isEmpty
                                ? null
                                : _selectedBookerId,
                            bottomPadding: 0,
                            isExpanded: true,
                            items: [
                              DropdownMenuItem<String>(
                                value: widget.currentUser.id,
                                child: Text(
                                  _bookerLabel(
                                    widget.currentUser,
                                    isCurrentUser: true,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  style: adminDropdownDisplayTextStyle.copyWith(
                                    color: AppColors.primaryColor,
                                  ),
                                ),
                              ),
                              ...widget.clientUsers.map(
                                (user) => DropdownMenuItem<String>(
                                  value: user.id,
                                  child: Text(
                                    _bookerLabel(user),
                                    overflow: TextOverflow.ellipsis,
                                    style: adminDropdownDisplayTextStyle,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedBookerId = value ?? '';
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClientBookingHomeView(
                  user: selectedUser,
                  bookingClientUser: selectedUser,
                  submittedByUserId: widget.currentUser.id,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                  scrollable: false,
                  onBookingSubmitted: widget.onBookingSubmitted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  UserModel get _selectedUser {
    if ((_selectedBookerId).isEmpty ||
        _selectedBookerId == widget.currentUser.id) {
      return widget.currentUser;
    }
    return widget.clientUsers.firstWhere(
      (user) => user.id == _selectedBookerId,
      orElse: () => widget.currentUser,
    );
  }

  String _bookerLabel(UserModel user, {bool isCurrentUser = false}) {
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
    return isCurrentUser ? 'User' : 'Client';
  }
}

class _AdminBookingsTable extends StatelessWidget {
  const _AdminBookingsTable({
    required this.bookings,
    required this.vm,
    required this.onView,
    required this.onEdit,
  });

  final List<Booking> bookings;
  final AdminBookingsViewModel vm;
  final ValueChanged<Booking> onView;
  final ValueChanged<Booking> onEdit;

  static const _headerStyle = TextStyle(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w700,
  );

  static const _valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const _defaultTrailingPadding = 20.0;
  static const _extraWidthAllowance = 16.0;

  @override
  Widget build(BuildContext context) {
    final longestIdValue = _longestText(
      bookings.map((booking) => booking.id ?? '-'),
    );
    final longestDateValue = _longestText(
      bookings.map((booking) => _formatBookingDateTime(booking.createdAt)),
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
        final dateWidth = _maxTextWidth(
          context,
          textScaler,
          'Date Time',
          longestDateValue,
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
        final resolvedDateWidth = _resolvedColumnWidth(dateWidth);
        final resolvedWaybillWidth = _resolvedColumnWidth(waybillWidth);
        final resolvedVanNumberWidth = _resolvedColumnWidth(vanNumberWidth);
        final resolvedVanSizeWidth = _resolvedColumnWidth(vanSizeWidth);
        final resolvedAmountWidth = _resolvedColumnWidth(amountWidth);
        final resolvedStatusWidth = _resolvedColumnWidth(statusWidth);
        final resolvedActionsWidth = actionsWidth + _extraWidthAllowance;
        final totalMeasuredWidth =
            resolvedIdWidth +
            resolvedDateWidth +
            resolvedWaybillWidth +
            resolvedVanNumberWidth +
            resolvedVanSizeWidth +
            resolvedAmountWidth +
            resolvedStatusWidth +
            resolvedActionsWidth +
            40;
        final useResponsiveCards = totalMeasuredWidth > constraints.maxWidth;

        if (useResponsiveCards) {
          return Column(
            children: bookings
                .map(
                  (booking) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AdminBookingResponsiveCard(
                      booking: booking,
                      statusLabel: vm.clientStatusLabel(booking),
                      onView: () => onView(booking),
                      onEdit: () => onEdit(booking),
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
                    width: resolvedDateWidth,
                    child: const _AdminBookingsHeaderCell(label: 'Date Time'),
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
            ...bookings.map(
              (booking) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AdminBookingWideRow(
                  booking: booking,
                  statusLabel: vm.clientStatusLabel(booking),
                  resolvedIdWidth: resolvedIdWidth,
                  resolvedDateWidth: resolvedDateWidth,
                  resolvedWaybillWidth: resolvedWaybillWidth,
                  resolvedVanNumberWidth: resolvedVanNumberWidth,
                  resolvedVanSizeWidth: resolvedVanSizeWidth,
                  resolvedAmountWidth: resolvedAmountWidth,
                  resolvedStatusWidth: resolvedStatusWidth,
                  resolvedActionsWidth: resolvedActionsWidth,
                  onView: () => onView(booking),
                  onEdit: () => onEdit(booking),
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
    if (value == null) {
      return '-';
    }
    final monthNames = const [
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
    final month = monthNames[value.month - 1];
    final hour = value.hour == 0
        ? 12
        : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$month ${value.day}, ${value.year} | $hour:$minute $period';
  }
}

class _AdminBookingWideRow extends StatelessWidget {
  const _AdminBookingWideRow({
    required this.booking,
    required this.statusLabel,
    required this.resolvedIdWidth,
    required this.resolvedDateWidth,
    required this.resolvedWaybillWidth,
    required this.resolvedVanNumberWidth,
    required this.resolvedVanSizeWidth,
    required this.resolvedAmountWidth,
    required this.resolvedStatusWidth,
    required this.resolvedActionsWidth,
    required this.onView,
    required this.onEdit,
  });

  final Booking booking;
  final String statusLabel;
  final double resolvedIdWidth;
  final double resolvedDateWidth;
  final double resolvedWaybillWidth;
  final double resolvedVanNumberWidth;
  final double resolvedVanSizeWidth;
  final double resolvedAmountWidth;
  final double resolvedStatusWidth;
  final double resolvedActionsWidth;
  final VoidCallback onView;
  final VoidCallback onEdit;

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
            width: resolvedDateWidth,
            child: _AdminBookingsBodyCell(
              child: Text(
                _AdminBookingsTable._formatBookingDateTime(booking.createdAt),
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
    required this.onEdit,
  });

  final Booking booking;
  final String statusLabel;
  final VoidCallback onView;
  final VoidCallback onEdit;

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
          (
            'Date Time',
            _AdminBookingsTable._formatBookingDateTime(booking.createdAt),
          ),
          ('Waybill Number', _AdminBookingsTable._waybillNumber(booking)),
          ('Van Number', _AdminBookingsTable._vanNumber(booking)),
          ('Van Size', _AdminBookingsTable._vanSize(booking)),
          ('Amount', _AdminBookingsTable._amount(booking)),
        ];

        return AdminListItemCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  adminMetaPill(statusLabel),
                  const Spacer(),
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

class _AdminBookingsBodyCell extends StatelessWidget {
  const _AdminBookingsBodyCell({
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

class _AdminBookingDetailHeader extends StatelessWidget {
  const _AdminBookingDetailHeader({
    required this.booking,
    required this.onBack,
  });

  final Booking booking;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.primaryColor,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          visualDensity: VisualDensity.compact,
          splashRadius: 22,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Booking ${booking.id ?? '-'}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        BookingSupportButton(onPressed: () => launchBookingSupport(context)),
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

class _BookingsFiltersPanel extends StatefulWidget {
  const _BookingsFiltersPanel({required this.vm, required this.iconOnly});

  final AdminBookingsViewModel vm;
  final bool iconOnly;

  @override
  State<_BookingsFiltersPanel> createState() => _BookingsFiltersPanelState();
}

class _BookingsFiltersPanelState extends State<_BookingsFiltersPanel> {
  final FocusNode _statusFocusNode = FocusNode();

  void _unfocusFilterFields() {
    _statusFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _statusFocusNode.dispose();
    super.dispose();
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
      controlHeight: 52,
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
                    height: 52,
                    child: _BookingsFilterDropdown(
                      label: 'Status',
                      value: widget.vm.statusFilter,
                      focusNode: _statusFocusNode,
                      items: widget.vm.statusOptions,
                      onChanged: widget.vm.setStatusFilter,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: itemWidth,
                    height: 52,
                    child: _BookingsDateFilter(
                      label: 'Start Date',
                      value: widget.vm.startDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateStartDate,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: itemWidth,
                    height: 52,
                    child: _BookingsDateFilter(
                      label: 'End Date',
                      value: widget.vm.endDate,
                      formatter: widget.vm.formatDate,
                      onSelected: widget.vm.updateEndDate,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: itemWidth,
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        _unfocusFilterFields();
                        widget.vm.clearFilters();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD94B4B),
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

class _BookingsDateFilter extends StatelessWidget {
  const _BookingsDateFilter({
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
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (context.mounted) {
            onSelected(picked);
          }
        },
        child: InputDecorator(
          isEmpty: value == null,
          isFocused: false,
          decoration: adminFormInputDecoration(label, radius: 16).copyWith(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
            ),
            suffixIcon: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: value == null ? null : () => onSelected(null),
              child: Icon(
                value == null
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
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              value == null ? '' : formatter(value),
              overflow: TextOverflow.ellipsis,
              style: adminDropdownDisplayTextStyle,
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingsFilterDropdown extends StatelessWidget {
  const _BookingsFilterDropdown({
    required this.label,
    required this.value,
    required this.focusNode,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final FocusNode focusNode;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AdminDropdownFormField<String>(
      initialValue: value == 'All' ? null : value,
      focusNode: focusNode,
      iconEnabledColor: AppColors.primaryColor,
      style: adminDropdownDisplayTextStyle,
      decoration: adminFormInputDecoration(label, radius: 16),
      items: items
          .where((item) => item != 'All')
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
                style: adminDropdownDisplayTextStyle,
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
        focusNode.unfocus();
      },
    );
  }
}
