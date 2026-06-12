import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/view_models/client/client_booking_history.vm.dart';
import 'package:webapp/views/shared/booking_workflow_view.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/widgets/shared/app_refresh_strip.dart';
import 'package:webapp/widgets/shared/booking_record_card.dart';

class ClientBookingHistoryView extends StatefulWidget {
  const ClientBookingHistoryView({
    super.key,
    required this.user,
    required this.onNewPressed,
    this.initialSelectedBooking,
  });

  final UserModel user;
  final VoidCallback onNewPressed;
  final Booking? initialSelectedBooking;

  @override
  State<ClientBookingHistoryView> createState() =>
      _ClientBookingHistoryViewState();
}

class _ClientBookingHistoryViewState extends State<ClientBookingHistoryView> {
  Booking? _selectedBooking;
  late final ScrollController _detailScrollController;

  @override
  void initState() {
    super.initState();
    _selectedBooking = widget.initialSelectedBooking;
    _detailScrollController = ScrollController();
  }

  @override
  void dispose() {
    _detailScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ClientBookingHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextInitialBooking = widget.initialSelectedBooking;
    if (_selectedBooking != null) {
      return;
    }
    if (nextInitialBooking?.id != oldWidget.initialSelectedBooking?.id &&
        nextInitialBooking != null) {
      _selectedBooking = nextInitialBooking;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<ClientBookingHistoryViewModel>.reactive(
      viewModelBuilder: ClientBookingHistoryViewModel.new,
      onViewModelReady: (vm) => vm.load(widget.user),
      builder: (context, vm, _) {
        final selectedBooking = _selectedBooking == null
            ? null
            : vm.bookings
                      .where((booking) => booking.id == _selectedBooking!.id)
                      .firstOrNull ??
                  _selectedBooking;
        if (selectedBooking != null) {
          return AppPageLoadingOverlay(
            isVisible: vm.isLoading,
            message: 'Loading bookings ...',
            child: SingleChildScrollView(
              key: PageStorageKey(
                'client-booking-detail-${selectedBooking.id ?? ''}',
              ),
              controller: _detailScrollController,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BookingDetailHeader(
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
                      'history-booking-workflow-${selectedBooking.id ?? ''}-${selectedBooking.updatedAt?.toIso8601String() ?? ''}',
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

        final filteredBookings = vm.filteredBookings();

        if (vm.errorMessage != null) {
          return AppPageLoadingOverlay(
            isVisible: vm.isLoading,
            message: 'Loading bookings ...',
            child: _HistoryScaffold(
              toolbar: _HistoryToolbar(
                vm: vm,
                onNewPressed: widget.onNewPressed,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppRefreshStrip(isVisible: vm.isLoading),
                  Text(
                    vm.errorMessage!,
                    style: TextStyle(
                      color: AppColors.primaryColor.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (vm.bookings.isEmpty) {
          return AppPageLoadingOverlay(
            isVisible: vm.isLoading,
            message: 'Loading bookings ...',
            child: _HistoryScaffold(
              toolbar: _HistoryToolbar(
                vm: vm,
                onNewPressed: widget.onNewPressed,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppRefreshStrip(isVisible: vm.isLoading),
                  Text(
                    vm.isLoading ? 'Preparing bookings ...' : 'No bookings yet.',
                    style: TextStyle(
                      color: AppColors.primaryColor.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return AppPageLoadingOverlay(
          isVisible: vm.isLoading,
          message: 'Loading bookings ...',
          child: _HistoryScaffold(
            toolbar: _HistoryToolbar(vm: vm, onNewPressed: widget.onNewPressed),
            framed: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppRefreshStrip(isVisible: vm.isLoading),
                if (filteredBookings.isEmpty)
                  Text(
                    'No bookings matched your current search.',
                    style: TextStyle(
                      color: AppColors.primaryColor.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: filteredBookings
                        .map(
                          (booking) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _BookingHistoryCard(
                              userRole: widget.user.role,
                              booking: booking,
                              vm: vm,
                              onOpen: () {
                                setState(() {
                                  _selectedBooking = booking;
                                });
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryScaffold extends StatelessWidget {
  const _HistoryScaffold({
    required this.toolbar,
    required this.child,
    this.framed = true,
  });

  final Widget toolbar;
  final Widget child;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          toolbar,
          const SizedBox(height: 14),
          if (framed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.primaryBorder),
              ),
              child: child,
            )
          else
            child,
        ],
      ),
    );
  }
}

class _HistoryToolbar extends StatelessWidget {
  const _HistoryToolbar({required this.vm, required this.onNewPressed});

  final ClientBookingHistoryViewModel vm;
  final VoidCallback onNewPressed;

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
          _HistoryFiltersPanel(vm: vm, iconOnly: iconOnly),
      onNewPressed: onNewPressed,
    );
  }
}

class _HistoryFiltersPanel extends StatefulWidget {
  const _HistoryFiltersPanel({required this.vm, required this.iconOnly});

  final ClientBookingHistoryViewModel vm;
  final bool iconOnly;

  @override
  State<_HistoryFiltersPanel> createState() => _HistoryFiltersPanelState();
}

class _HistoryFiltersPanelState extends State<_HistoryFiltersPanel> {
  late final FocusNode _statusFocusNode;

  @override
  void initState() {
    super.initState();
    _statusFocusNode = FocusNode()..canRequestFocus = false;
  }

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
                    child: _HistoryFilterDropdown(
                      label: 'Status',
                      value: widget.vm.statusFilter,
                      focusNode: _statusFocusNode,
                      items: widget.vm.statusOptions,
                      onChanged: widget.vm.setStatusFilter,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: itemWidth,
                    height: adminFilterFieldMinHeight,
                    child: _HistoryDateFilter(
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
                    child: _HistoryDateFilter(
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

class _HistoryDateFilter extends StatefulWidget {
  const _HistoryDateFilter({
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
  State<_HistoryDateFilter> createState() => _HistoryDateFilterState();
}

class _HistoryDateFilterState extends State<_HistoryDateFilter> {
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
  void didUpdateWidget(covariant _HistoryDateFilter oldWidget) {
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

class _HistoryFilterDropdown extends StatelessWidget {
  const _HistoryFilterDropdown({
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
      decoration: adminFormInputDecoration(
        label,
        radius: 16,
        minHeight: adminFilterFieldMinHeight,
      ),
      items: items
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

class _BookingHistoryCard extends StatelessWidget {
  const _BookingHistoryCard({
    required this.userRole,
    required this.booking,
    required this.vm,
    required this.onOpen,
  });

  final String? userRole;
  final Booking booking;
  final ClientBookingHistoryViewModel vm;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return BookingRecordCard(
      booking: booking,
      onTap: onOpen,
      headlineStatusLabel: vm.statusLabelForRole(userRole, booking),
      statusLabelForKey: vm.statusLabelForKey,
      showStatusSubmissions: false,
      clientName: vm.clientName(booking),
      clientPhone: vm.clientPhone(booking),
      driverName: vm.driverName(booking),
      driverPhone: vm.driverPhone(booking),
      helperName: vm.helperName(booking),
      helperPhone: vm.helperPhone(booking),
    );
  }
}

class _BookingDetailHeader extends StatelessWidget {
  const _BookingDetailHeader({required this.booking, required this.onBack});

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
