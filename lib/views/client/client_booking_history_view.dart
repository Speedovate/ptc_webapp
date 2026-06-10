import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/view_models/client/client_booking_history.vm.dart';
import 'package:webapp/views/shared/booking_workflow_view.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
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
  String _searchQuery = '';
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
          return SingleChildScrollView(
            key: PageStorageKey(
              'client-booking-detail-${selectedBooking.id ?? ''}',
            ),
            controller: _detailScrollController,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.translate(
                  offset: const Offset(-12, 0),
                  child: _BookingDetailHeader(
                    booking: selectedBooking,
                    onBack: () {
                      setState(() {
                        _selectedBooking = null;
                      });
                    },
                  ),
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
          );
        }

        final filteredBookings = vm.bookings
            .where((booking) => vm.matchesBooking(booking, _searchQuery))
            .toList();

        if (vm.errorMessage != null) {
          return _HistoryScaffold(
            toolbar: _HistoryToolbar(
              searchQuery: _searchQuery,
              onSearchChanged: _handleSearchChanged,
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
          );
        }

        if (vm.bookings.isEmpty) {
          return _HistoryScaffold(
            toolbar: _HistoryToolbar(
              searchQuery: _searchQuery,
              onSearchChanged: _handleSearchChanged,
              onNewPressed: widget.onNewPressed,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppRefreshStrip(isVisible: vm.isLoading),
                Text(
                  vm.isLoading ? 'Preparing bookings...' : 'No bookings yet.',
                  style: TextStyle(
                    color: AppColors.primaryColor.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        return _HistoryScaffold(
          toolbar: _HistoryToolbar(
            searchQuery: _searchQuery,
            onSearchChanged: _handleSearchChanged,
            onNewPressed: widget.onNewPressed,
          ),
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
        );
      },
    );
  }

  void _handleSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
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
  const _HistoryToolbar({
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onNewPressed,
  });

  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onNewPressed;

  @override
  Widget build(BuildContext context) {
    return AdminListToolbar(
      controlHeight: 52,
      surfaceRadius: 16,
      search: AdminListSearchField(
        controlHeight: 52,
        surfaceRadius: 16,
        initialValue: searchQuery,
        onChanged: onSearchChanged,
      ),
      filtersBuilder: (context, iconOnly) =>
          _HistoryFiltersButton(iconOnly: iconOnly),
      onNewPressed: onNewPressed,
    );
  }
}

class _HistoryFiltersButton extends StatelessWidget {
  const _HistoryFiltersButton({required this.iconOnly});

  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    return AdminListFiltersButton(
      controlHeight: 52,
      surfaceRadius: 16,
      iconOnly: iconOnly,
      menuChildren: const [
        SizedBox(
          width: 200,
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'No filters available.',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ),
        ),
      ],
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
