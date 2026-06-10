import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/view_models/admin/admin_dashboard.vm.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';

class AdminDashboardView extends StatelessWidget {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AdminDashboardViewModel>.reactive(
      viewModelBuilder: AdminDashboardViewModel.new,
      onViewModelReady: (vm) => vm.load(),
      builder: (context, vm, child) {
        if (vm.isBusy) {
          return const Center(child: CircularProgressIndicator());
        }

        if (vm.errorMessage != null) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: AdminListItemCard(
              padding: const EdgeInsets.all(24),
              child: AdminListStateText(message: vm.errorMessage!),
            ),
          );
        }

        if (vm.completedBookings.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: AdminListItemCard(
              padding: EdgeInsets.all(24),
              child: AdminListStateText(message: 'No completed bookings yet.'),
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: _AdminDashboardCompletedBookingsTable(
            bookings: vm.completedBookings,
            vm: vm,
          ),
        );
      },
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
            'DR NO',
            _longerText(
              'DR NO',
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
            'DATE',
            _longerText(
              'DATE',
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
            'WAYBILL NO',
            _longerText(
              'WAYBILL NO',
              _longestText(bookings.map(AdminDashboardViewModel.waybillNumber)),
            ),
          ),
        );
        final resolvedVanNumberWidth = _resolvedColumnWidth(
          _maxTextWidth(
            context,
            textScaler,
            'VAN NO',
            _longerText(
              'VAN NO',
              _longestText(bookings.map(AdminDashboardViewModel.vanNumber)),
            ),
          ),
        );
        final resolvedVanSizeWidth = _resolvedColumnWidth(
          _maxTextWidth(
            context,
            textScaler,
            'VAN SIZE',
            _longerText(
              'VAN SIZE',
              _longestText(bookings.map(AdminDashboardViewModel.vanSize)),
            ),
          ),
        );
        final resolvedClientWidth = _resolvedColumnWidth(
          _maxTextWidth(
            context,
            textScaler,
            'CLIENT',
            _longerText('CLIENT', _longestText(bookings.map(vm.client))),
          ),
        );
        final resolvedAmountWidth = _resolvedColumnWidth(
          _maxTextWidth(
            context,
            textScaler,
            'AMOUNT',
            _longerText(
              'AMOUNT',
              _longestText(bookings.map(AdminDashboardViewModel.amount)),
            ),
          ),
        );

        final totalMeasuredWidth =
            resolvedDeliveryNumberWidth +
            resolvedDateWidth +
            resolvedWaybillWidth +
            resolvedVanNumberWidth +
            resolvedVanSizeWidth +
            resolvedClientWidth +
            resolvedAmountWidth +
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
                      clientName: vm.client(booking),
                      dateValue: booking.createdAt,
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
                    child: const _DashboardHeaderCell(label: 'DR NO'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedDateWidth,
                    child: const _DashboardHeaderCell(label: 'DATE'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedWaybillWidth,
                    child: const _DashboardHeaderCell(label: 'WAYBILL NO'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedVanNumberWidth,
                    child: const _DashboardHeaderCell(label: 'VAN NO'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedVanSizeWidth,
                    child: const _DashboardHeaderCell(label: 'VAN SIZE'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedClientWidth,
                    child: const _DashboardHeaderCell(label: 'CLIENT'),
                  ),
                  _DashboardFixedSlot(
                    width: resolvedAmountWidth,
                    child: const _DashboardHeaderCell(label: 'AMOUNT'),
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
                  clientName: vm.client(booking),
                  dateValue: booking.createdAt,
                  resolvedDeliveryNumberWidth: resolvedDeliveryNumberWidth,
                  resolvedDateWidth: resolvedDateWidth,
                  resolvedWaybillWidth: resolvedWaybillWidth,
                  resolvedVanNumberWidth: resolvedVanNumberWidth,
                  resolvedVanSizeWidth: resolvedVanSizeWidth,
                  resolvedClientWidth: resolvedClientWidth,
                  resolvedAmountWidth: resolvedAmountWidth,
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
    return '${value.month}/${value.day}/${value.year}';
  }
}

class _AdminDashboardWideRow extends StatelessWidget {
  const _AdminDashboardWideRow({
    required this.booking,
    required this.clientName,
    required this.dateValue,
    required this.resolvedDeliveryNumberWidth,
    required this.resolvedDateWidth,
    required this.resolvedWaybillWidth,
    required this.resolvedVanNumberWidth,
    required this.resolvedVanSizeWidth,
    required this.resolvedClientWidth,
    required this.resolvedAmountWidth,
  });

  final Booking booking;
  final String clientName;
  final DateTime? dateValue;
  final double resolvedDeliveryNumberWidth;
  final double resolvedDateWidth;
  final double resolvedWaybillWidth;
  final double resolvedVanNumberWidth;
  final double resolvedVanSizeWidth;
  final double resolvedClientWidth;
  final double resolvedAmountWidth;

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
                AdminDashboardViewModel.waybillNumber(booking),
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
                AdminDashboardViewModel.vanSize(booking),
                style: _AdminDashboardCompletedBookingsTable._valueStyle,
                softWrap: true,
              ),
            ),
          ),
          _DashboardFixedSlot(
            width: resolvedClientWidth,
            child: _DashboardBodyCell(
              child: Text(
                clientName,
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
        ],
      ),
    );
  }
}

class _AdminDashboardResponsiveCard extends StatelessWidget {
  const _AdminDashboardResponsiveCard({
    required this.booking,
    required this.clientName,
    required this.dateValue,
  });

  final Booking booking;
  final String clientName;
  final DateTime? dateValue;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        final spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        final items = [
          ('DR NO', AdminDashboardViewModel.deliveryFormNumber(booking)),
          (
            'DATE',
            _AdminDashboardCompletedBookingsTable._formatBookingDateTime(
              dateValue,
            ),
          ),
          ('WAYBILL NO', AdminDashboardViewModel.waybillNumber(booking)),
          ('VAN NO', AdminDashboardViewModel.vanNumber(booking)),
          ('VAN SIZE', AdminDashboardViewModel.vanSize(booking)),
          ('CLIENT', clientName),
          ('AMOUNT', AdminDashboardViewModel.amount(booking)),
        ];

        return AdminListItemCard(
          padding: const EdgeInsets.all(20),
          child: Wrap(
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
  const _DashboardHeaderCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return AdminListHeaderCell(
      label: label,
      trailingPadding: 20,
      alignment: Alignment.centerLeft,
      textAlign: TextAlign.left,
    );
  }
}

class _DashboardBodyCell extends StatelessWidget {
  const _DashboardBodyCell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AdminListBodyCell(
      trailingPadding: 20,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}
