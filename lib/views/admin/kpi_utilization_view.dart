import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/kpi_utilization.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';

class KpiUtilizationView extends StatefulWidget {
  const KpiUtilizationView({
    super.key,
    required this.makes,
    required this.bookings,
    this.onActions,
    this.onOpenMake,
    this.onOpenBooking,
    this.periodTrailing,
    this.loading = false,
    this.selectedMonth,
    this.onMonthChanged,
  });
  final DateTime? selectedMonth;
  final ValueChanged<DateTime>? onMonthChanged;
  final Widget? periodTrailing;
  final bool loading;
  final List<VehicleMake> makes;
  final List<Booking> bookings;
  final ValueChanged<VehicleMake>? onOpenMake;
  final ValueChanged<Booking>? onOpenBooking;
  final void Function(GlobalKey anchor, KpiPeriod period)? onActions;
  @override
  State<KpiUtilizationView> createState() => _KpiUtilizationViewState();
}

class _KpiUtilizationViewState extends State<KpiUtilizationView> {
  KpiUtilizationMode mode = KpiUtilizationMode.daily;
  late DateTime month = widget.selectedMonth ?? kpiDate(DateTime.now());
  String search = '';
  int visible = 15;
  final toolbarKey = GlobalKey();
  late KpiUtilization result;
  @override
  void initState() {
    super.initState();
    calculate();
  }

  @override
  void didUpdateWidget(covariant KpiUtilizationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incomingMonth = widget.selectedMonth;
    final monthChanged =
        incomingMonth != null &&
        (incomingMonth.year != month.year ||
            incomingMonth.month != month.month);
    if (monthChanged) {
      month = incomingMonth;
      visible = 15;
    }
    if (monthChanged ||
        oldWidget.bookings != widget.bookings ||
        oldWidget.makes != widget.makes) {
      calculate();
    }
  }

  void calculate() {
    result = KpiUtilization.calculate(
      bookings: widget.bookings,
      makes: widget.makes,
      mode: mode,
      year: month.year,
      month: month.month,
    );
  }

  void change(VoidCallback action) {
    final previousMonth = month;
    setState(() {
      action();
      visible = 15;
      calculate();
    });
    if (previousMonth.year != month.year ||
        previousMonth.month != month.month) {
      widget.onMonthChanged?.call(month);
    }
  }

  String label(KpiUtilizationMode value) => switch (value) {
    KpiUtilizationMode.daily => 'Daily',
    KpiUtilizationMode.weekly => 'Weekly',
    KpiUtilizationMode.monthly => 'Monthly',
  };
  String tripDateLabel(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String tripDateTimeLabel(DateTime instant) {
    final date = instant.toUtc().add(const Duration(hours: 8));
    String pad(int value) => '$value'.padLeft(2, '0');
    return '${tripDateLabel(date)}\n${pad(date.hour % 12 == 0 ? 12 : date.hour % 12)}:${pad(date.minute)}:${pad(date.second)} ${date.hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> openTrips(
    VehicleMake? make,
    int column, {
    List<VehicleMake>? fleet,
  }) async {
    final trips = <Booking>[
      if (make != null) ...result.trips[make.id]?[column] ?? const [],
      if (fleet != null)
        for (final pm in fleet)
          for (var bucket = 0; bucket < result.columns; bucket++)
            ...result.trips[pm.id]?[bucket] ?? const [],
    ]..sort((a, b) => kpiDeliveredAt(b)!.compareTo(kpiDeliveredAt(a)!));
    final periodTitle = fleet != null
        ? (mode == KpiUtilizationMode.monthly
              ? '${month.year}'
              : MaterialLocalizations.of(context).formatMonthYear(month))
        : switch (mode) {
            KpiUtilizationMode.daily => tripDateLabel(
              DateTime(month.year, month.month, column + 1),
            ),
            KpiUtilizationMode.weekly =>
              'Week ${column + 1} · ${MaterialLocalizations.of(context).formatMonthYear(month)}',
            KpiUtilizationMode.monthly => MaterialLocalizations.of(
              context,
            ).formatMonthYear(DateTime(month.year, column + 1)),
          };
    var visibleTrips = 15;
    final selected = await showAppDialog<Booking>(
      context: context,
      modalKey:
          'utilization-trips:${make?.id ?? 'total'}:${mode.name}:$periodTitle',
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AdminModalShell(
          title: '${make?.code ?? make?.id ?? 'Total'} Trips · $periodTitle',
          maxWidth: AdminModalShell.kpiMaxWidth,
          flexibleBody: true,
          bodyHandlesScrolling: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notice) {
                if (notice.metrics.axis == Axis.vertical &&
                    notice is ScrollUpdateNotification &&
                    (notice.scrollDelta ?? 0) > 0 &&
                    notice.metrics.extentAfter < 200 &&
                    visibleTrips < trips.length) {
                  update(() => visibleTrips += 15);
                }
                return false;
              },
              child: AdminModalRecordList(
                pageSize: null,
                horizontalOnDesktop: true,
                trailingActions: true,
                selectableCells: true,
                titles: const [
                  'Booking',
                  'Client',
                  'Driver',
                  'Helper',
                  'Status',
                  'DateTime',
                  'Actions',
                ],
                cellBuilder: (row, column) => column == 6
                    ? Align(
                        alignment: Alignment.centerRight,
                        child: Tooltip(
                          message: 'View booking',
                          child: AdminListActionButton(
                            icon: Icons.visibility_rounded,
                            backgroundColor: Colors.yellow.shade900,
                            onTap: widget.onOpenBooking == null
                                ? null
                                : () =>
                                      Navigator.pop(dialogContext, trips[row]),
                          ),
                        ),
                      )
                    : null,
                itemCount: trips.length.clamp(0, visibleTrips),
                emptyMessage: 'No trips for this period.',
                valuesAt: (i) {
                  final trip = trips[i];
                  final status = trip.clientStatus ?? '';
                  return [
                    'Booking ${trip.id ?? '—'}',
                    trip.client?.name ?? '—',
                    trip.driver?.name ?? '—',
                    trip.helper?.name ?? '—',
                    status.isEmpty
                        ? '—'
                        : '${status[0].toUpperCase()}${status.substring(1)}',
                    tripDateTimeLabel(kpiDeliveredAt(trip)!),
                    '',
                  ];
                },
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted && selected != null) {
      widget.onOpenBooking?.call(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final periodDays = mode == KpiUtilizationMode.monthly
        ? DateTime.utc(
            month.year + 1,
          ).difference(DateTime.utc(month.year)).inDays
        : DateTime.utc(month.year, month.month + 1, 0).day;
    final matches = widget.makes.where((make) {
      final text =
          '${make.code} ${make.id} ${make.driver?.name ?? ''} ${make.driver?.id ?? ''} ${make.helper?.name ?? ''} ${make.helper?.id ?? ''}'
              .toLowerCase();
      return search
          .toLowerCase()
          .trim()
          .split(RegExp(r'\s+'))
          .every(text.contains);
    }).toList();
    final totalCounts = List<int>.filled(result.columns, 0);
    var totalDays = 0;
    for (final make in matches) {
      final counts = result.counts[make.id];
      for (var column = 0; column < result.columns; column++) {
        totalCounts[column] += counts?[column] ?? 0;
      }
      totalDays += result.totalDays[make.id] ?? 0;
    }
    final titles = <String>[
      'PM',
      ...List.generate(
        result.columns,
        (i) => switch (mode) {
          KpiUtilizationMode.daily => '${i + 1}',
          KpiUtilizationMode.weekly => 'Week ${i + 1}',
          KpiUtilizationMode.monthly => const [
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
          ][i],
        },
      ),
      'Total Days',
      'Total Trips',
    ];
    return Column(
      children: [
        AdminListToolbar(
          key: toolbarKey,
          controlHeight: adminFilterFieldMinHeight,
          surfaceRadius: 16,
          buttonLabel: 'Actions',
          fitButtonLabel: true,
          buttonIcon: Icons.arrow_drop_down_rounded,
          onNewPressed: widget.onActions == null
              ? null
              : () => widget.onActions!(
                  toolbarKey,
                  mode == KpiUtilizationMode.monthly
                      ? KpiPeriod(
                          DateTime.utc(month.year),
                          DateTime.utc(month.year, 12, 31),
                        )
                      : KpiPeriod.month(month.year, month.month),
                ),
          search: AdminListSearchField(
            controlHeight: adminFilterFieldMinHeight,
            surfaceRadius: 16,
            initialValue: search,
            onChanged: (value) => setState(() {
              search = value;
              visible = 15;
            }),
          ),
          filtersBuilder: (_, iconOnly) => AdminListDynamicFiltersPanel(
            iconOnly: iconOnly,
            menuAnchorKey: toolbarKey,
            filters: [
              AdminListDropdownFilterConfig(
                label: 'Display',
                value: label(mode),
                items: KpiUtilizationMode.values.map(label).toList(),
                onChanged: (value) => change(
                  () => mode = KpiUtilizationMode.values.firstWhere(
                    (v) => label(v) == value,
                  ),
                ),
              ),
              if (mode != KpiUtilizationMode.monthly)
                AdminListDropdownFilterConfig(
                  label: 'Month',
                  value: '${month.month}',
                  items: List.generate(12, (i) => '${i + 1}'),
                  displayValue: (v) => MaterialLocalizations.of(context)
                      .formatMonthYear(DateTime(month.year, int.parse(v)))
                      .split(' ')
                      .first,
                  onChanged: (v) => change(
                    () => month = DateTime.utc(month.year, int.parse(v)),
                  ),
                ),
              AdminListDropdownFilterConfig(
                label: 'Year',
                value: '${month.year}',
                items: ({
                  month.year,
                  ...List.generate(30, (i) => 2020 + i),
                }.toList()..sort()).map((v) => '$v').toList(),
                onChanged: (v) => change(
                  () => month = DateTime.utc(int.parse(v), month.month),
                ),
              ),
            ],
            onClear: () => change(() {
              mode = KpiUtilizationMode.daily;
              month = kpiDate(DateTime.now());
            }),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                '${label(mode)} · ${mode == KpiUtilizationMode.monthly ? month.year : MaterialLocalizations.of(context).formatMonthYear(month)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            if (widget.periodTrailing != null) widget.periodTrailing!,
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: widget.loading
              ? const AppPageLoadingOverlay(
                  isVisible: true,
                  message: 'Loading KPI data ...',
                  child: SizedBox.expand(),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (notice) {
                    if (notice.metrics.axis == Axis.vertical &&
                        notice is ScrollUpdateNotification &&
                        (notice.scrollDelta ?? 0) > 0 &&
                        notice.metrics.extentAfter < 200 &&
                        visible < matches.length) {
                      setState(() => visible += 15);
                    }
                    return false;
                  },
                  child: AdminModalRecordList(
                    pageSize: null,
                    horizontalOnDesktop: true,
                    horizontalOnMobile: true,
                    pinFirstColumn: true,
                    squareCorners: true,
                    firstColumnHeaderColor: AppColors.primaryColor,
                    centerFirstColumn: true,
                    fixedFirstColumnWidth: 76,
                    firstColumnBackgroundColor: AppColors.primarySurface,
                    compactLastColumn: true,
                    firstColumnTrailingPadding: 0,
                    selectableCells: true,
                    titles: titles,
                    columnExtraWidths: {
                      for (var column = 1; column <= result.columns; column++)
                        column: 18,
                    },
                    cellBuilder: (row, column) {
                      if (row == 0) {
                        return column == 0
                            ? InkWell(
                                onTap: () => openTrips(null, 0, fleet: matches),
                                child: const Text(
                                  'Total',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.primaryColor,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                    decorationColor: AppColors.primaryColor,
                                  ),
                                ),
                              )
                            : null;
                      }
                      if (column == 0 && widget.onOpenMake != null) {
                        final make = matches[row - 1];
                        return InkWell(
                          onTap: () => widget.onOpenMake!(make),
                          child: Text(
                            make.code ?? make.id ?? '—',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.primaryColor,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.primaryColor,
                            ),
                          ),
                        );
                      }
                      if (column < 1 || column > result.columns) return null;
                      final count =
                          result.counts[matches[row - 1].id]?[column - 1] ?? 0;
                      final cell = Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 18),
                            child: Text(
                              '$count',
                              style: count > 0
                                  ? const TextStyle(
                                      color: AppColors.primaryColor,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline,
                                      decorationColor: AppColors.primaryColor,
                                    )
                                  : null,
                            ),
                          ),
                          if (count > 0)
                            const Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: Colors.green,
                                  semanticLabel: 'Utilized',
                                ),
                              ),
                            ),
                        ],
                      );
                      return count > 0
                          ? InkWell(
                              onTap: () =>
                                  openTrips(matches[row - 1], column - 1),
                              child: cell,
                            )
                          : cell;
                    },
                    titleBuilder: (column) => column == 0
                        ? const Center(
                            child: Tooltip(
                              message: 'Utilization',
                              child: Icon(
                                Icons.bar_chart_rounded,
                                size: 20,
                                color: Colors.white,
                                semanticLabel: 'Utilization',
                              ),
                            ),
                          )
                        : null,
                    itemCount: matches.isEmpty
                        ? 0
                        : matches.length.clamp(0, visible) + 1,
                    emptyMessage: search.trim().isEmpty
                        ? 'No trucks available.'
                        : 'No matching trucks.',
                    valuesAt: (i) {
                      if (i == 0) {
                        return [
                          'Total',
                          ...totalCounts.map((count) => '$count'),
                          '$totalDays/$periodDays',
                          '${totalCounts.fold<int>(0, (a, b) => a + b)}',
                        ];
                      }
                      final make = matches[i - 1];
                      final values =
                          result.counts[make.id] ??
                          List<int>.filled(result.columns, 0);
                      return [
                        make.code ?? make.id ?? '—',
                        ...values.map((v) => '$v'),
                        '${result.totalDays[make.id] ?? 0}/$periodDays',
                        '${values.fold<int>(0, (a, b) => a + b)}',
                      ];
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
