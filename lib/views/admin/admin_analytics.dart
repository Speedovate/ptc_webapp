import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/view_models/admin/admin_dashboard.vm.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';

class AdminAnalyticsView extends StatefulWidget {
  const AdminAnalyticsView({super.key});

  @override
  State<AdminAnalyticsView> createState() => _AdminAnalyticsViewState();
}

class _AdminAnalyticsViewState extends State<AdminAnalyticsView> {
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0);
  }

  void _updateStartDate(DateTime value) {
    setState(() {
      _startDate = _dateOnly(value);
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
    });
  }

  void _updateEndDate(DateTime value) {
    setState(() {
      _endDate = _dateOnly(value);
      if (_startDate.isAfter(_endDate)) _startDate = _endDate;
    });
  }

  void _resetCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month + 1, 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Booking>>(
      stream: BookingRequest.instance.watchBookings(),
      initialData: BookingRequest.hydratedBookingsSnapshot,
      builder: (context, snapshot) {
        final bookings = snapshot.data ?? const <Booking>[];
        final isAwaitingInitialData =
            !BookingRequest.hasResolvedBookings && bookings.isEmpty;
        final content = _AnalyticsContent(
          bookings: bookings,
          startDate: _startDate,
          endDate: _endDate,
          onStartDateChanged: _updateStartDate,
          onEndDateChanged: _updateEndDate,
          onClear: _resetCurrentMonth,
        );
        if (!isAwaitingInitialData) {
          return content;
        }
        return AppPageLoadingOverlay(
          isVisible: true,
          message: 'Loading analytics ...',
          child: content,
        );
      },
    );
  }
}

class _AnalyticsContent extends StatelessWidget {
  const _AnalyticsContent({
    required this.bookings,
    required this.startDate,
    required this.endDate,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
    required this.onClear,
  });

  final List<Booking> bookings;
  final DateTime startDate;
  final DateTime endDate;
  final ValueChanged<DateTime> onStartDateChanged;
  final ValueChanged<DateTime> onEndDateChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final filteredBookings = bookings.where((booking) {
      final createdAt = booking.createdAt;
      if (createdAt == null) return false;
      final date = _dateOnly(createdAt);
      return !date.isBefore(startDate) && !date.isAfter(endDate);
    }).toList();
    final deliveredCount = bookings.where(_isDelivered).length;
    final billed = bookings.where((booking) {
      return (booking.billingStatus ?? '').trim().toLowerCase() == 'billed';
    }).toList();
    final unbilled = bookings.where((booking) {
      return (booking.billingStatus ?? '').trim().toLowerCase() == 'unbilled';
    }).toList();
    final billedAmount = billed.fold<double>(
      0,
      (total, booking) => total + _amount(booking),
    );
    final unbilledAmount = unbilled.fold<double>(
      0,
      (total, booking) => total + _amount(booking),
    );
    final filteredAmount = filteredBookings.fold<double>(
      0,
      (total, booking) => total + _amount(booking),
    );
    final points = _buildPoints(startDate, endDate, filteredBookings);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1320 ? 4 : 2;
    final chartWidth = math.max<double>(
      width - 96,
      math.max<double>(680, points.length * 112),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              mainAxisExtent: 154,
            ),
            itemCount: 4,
            itemBuilder: (context, index) {
              final metrics = [
                ('Bookings', '$deliveredCount/${bookings.length}'),
                ('Unbilled', _formatCurrency(unbilledAmount)),
                ('Billed', _formatCurrency(billedAmount)),
                ('Total', _formatCurrency(unbilledAmount + billedAmount)),
              ];
              final metric = metrics[index];
              return _MetricCard(label: metric.$1, value: metric.$2);
            },
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final filters = _AnalyticsFilters(
                iconOnly: constraints.maxWidth < 300,
                startDate: startDate,
                endDate: endDate,
                onStartDateChanged: onStartDateChanged,
                onEndDateChanged: onEndDateChanged,
                onClear: onClear,
              );
              final filtersWidth = adminListFiltersButtonWidth(
                constraints.maxWidth < 300,
              );
              if (constraints.maxWidth < 250) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SalesTitle(),
                    const SizedBox(height: 12),
                    SizedBox(width: filtersWidth, child: filters),
                  ],
                );
              }
              return Row(
                children: [
                  const Expanded(child: _SalesTitle()),
                  SizedBox(width: filtersWidth, child: filters),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primaryBorder),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    color: AppColors.primarySurface,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final amount = Text(
                          _formatCurrency(filteredAmount),
                          style: const TextStyle(
                            color: AppColors.primaryColor,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        );
                        final range = Text(
                          '${_longDate(startDate)} - ${_longDate(endDate)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.primaryColor,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                        );
                        final count = Text(
                          '${filteredBookings.length} ${filteredBookings.length == 1 ? 'booking' : 'bookings'}',
                          style: const TextStyle(
                            color: AppColors.primaryColor,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                          ),
                        );
                        if (constraints.maxWidth < 540) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [amount, const Spacer(), count]),
                              const SizedBox(height: 10),
                              Center(child: range),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: amount,
                              ),
                            ),
                            Expanded(child: range),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: count,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.primaryBorder),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: chartWidth,
                      child: _BookingActivityChart(points: points),
                    ),
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.primaryColor,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: AppColors.primaryColor,
                fontWeight: FontWeight.w800,
                fontSize: MediaQuery.sizeOf(context).width < 700 ? 24 : 32,
                height: 1.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsFilters extends StatelessWidget {
  const _AnalyticsFilters({
    required this.iconOnly,
    required this.startDate,
    required this.endDate,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
    required this.onClear,
  });

  final bool iconOnly;
  final DateTime startDate;
  final DateTime endDate;
  final ValueChanged<DateTime> onStartDateChanged;
  final ValueChanged<DateTime> onEndDateChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AdminListDateFiltersPanel(
      iconOnly: iconOnly,
      alignMenuToButtonRight: true,
      filters: [
        AdminDateFilterConfig(
          label: 'Start Date',
          value: startDate,
          onSelected: (value) {
            if (value != null) onStartDateChanged(value);
          },
        ),
        AdminDateFilterConfig(
          label: 'End Date',
          value: endDate,
          onSelected: (value) {
            if (value != null) onEndDateChanged(value);
          },
        ),
      ],
      onClear: onClear,
    );
  }
}

class _SalesTitle extends StatelessWidget {
  const _SalesTitle();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Sales',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: AppColors.primaryColor,
        fontWeight: FontWeight.w800,
        height: 1.15,
      ),
    );
  }
}

class _BookingActivityChart extends StatelessWidget {
  const _BookingActivityChart({required this.points});

  final List<_BookingActivityPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxBookings = points.fold<int>(
      0,
      (maxValue, point) => math.max(maxValue, point.count),
    );
    return Column(
      children: [
        SizedBox(
          height: 250,
          child: CustomPaint(
            size: const Size(double.infinity, 250),
            painter: _BookingActivityChartPainter(
              points: points,
              maxBookings: maxBookings,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final point in points)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Text(
                        _shortDateLabel(point.date),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${point.count} ${point.count == 1 ? 'Booking' : 'Bookings'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatCurrency(point.amount),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.primaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BookingActivityChartPainter extends CustomPainter {
  const _BookingActivityChartPainter({
    required this.points,
    required this.maxBookings,
  });

  final List<_BookingActivityPoint> points;
  final int maxBookings;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 16.0;
    const right = 16.0;
    const top = 12.0;
    const bottom = 24.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;
    if (width <= 0 || height <= 0 || points.isEmpty) {
      return;
    }
    final grid = Paint()
      ..color = AppColors.primaryBorder
      ..strokeWidth = 1;
    final line = Paint()
      ..color = AppColors.primaryColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = AppColors.primaryColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final dot = Paint()
      ..color = AppColors.primaryColor
      ..style = PaintingStyle.fill;
    for (var index = 0; index < 4; index++) {
      final y = top + (height / 3) * index;
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
    }
    final cap = maxBookings <= 0 ? 1 : maxBookings;
    final linePath = Path();
    final fillPath = Path();
    for (var index = 0; index < points.length; index++) {
      final x =
          left +
          (points.length == 1
              ? width / 2
              : width / (points.length - 1) * index);
      final y = top + height - height * (points[index].count / cap);
      if (index == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, top + height);
      }
      linePath.lineTo(x, y);
      fillPath.lineTo(x, y);
      canvas.drawCircle(Offset(x, y), 3.5, dot);
    }
    final lastX =
        left +
        (points.length == 1
            ? width / 2
            : width / (points.length - 1) * (points.length - 1));
    fillPath.lineTo(lastX, top + height);
    fillPath.close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(linePath, line);
  }

  @override
  bool shouldRepaint(covariant _BookingActivityChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.maxBookings != maxBookings;
  }
}

class _BookingActivityPoint {
  const _BookingActivityPoint({
    required this.date,
    required this.count,
    required this.amount,
  });

  final DateTime date;
  final int count;
  final double amount;
}

List<_BookingActivityPoint> _buildPoints(
  DateTime startDate,
  DateTime endDate,
  List<Booking> bookings,
) {
  final counts = <DateTime, int>{};
  final amounts = <DateTime, double>{};
  for (final booking in bookings) {
    final createdAt = booking.createdAt;
    if (createdAt != null) {
      final day = _dateOnly(createdAt);
      counts[day] = (counts[day] ?? 0) + 1;
      amounts[day] = (amounts[day] ?? 0) + _amount(booking);
    }
  }
  final points = <_BookingActivityPoint>[];
  for (
    var day = startDate;
    !day.isAfter(endDate);
    day = day.add(const Duration(days: 1))
  ) {
    points.add(
      _BookingActivityPoint(
        date: day,
        count: counts[day] ?? 0,
        amount: amounts[day] ?? 0,
      ),
    );
  }
  return points;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isDelivered(Booking booking) {
  return Booking.isDeliveredWorkflowStatus(booking.clientStatus);
}

double _amount(Booking booking) {
  final value = AdminDashboardViewModel.amount(booking);
  return double.tryParse(value.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
}

String _formatCurrency(double value) {
  final formatted = value.toStringAsFixed(
    value.truncateToDouble() == value ? 0 : 2,
  );
  final parts = formatted.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '\u20B1$whole${parts.length == 2 ? '.${parts.last}' : ''}';
}

String _longDate(DateTime value) {
  const months = [
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

String _shortDateLabel(DateTime value) {
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
  return '${months[value.month - 1]} ${value.day}';
}
