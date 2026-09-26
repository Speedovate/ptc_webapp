import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/services/kpi/crew_kpi_store.dart';
import 'package:webapp/services/kpi/kpi_rating_rules.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/record_text_link.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';

class CrewKpiTrackingView extends StatefulWidget {
  const CrewKpiTrackingView({
    super.key,
    required this.user,
    this.store,
    this.network,
    this.bookingChanges,
    this.allowed,
    this.onOpenBooking,
  });
  final UserModel user;
  final ValueChanged<String>? onOpenBooking;
  final CrewKpiStore? store;
  final Stream<bool>? network;
  final Stream<void>? bookingChanges;
  final bool Function()? allowed;
  @override
  State<CrewKpiTrackingView> createState() => _CrewKpiTrackingViewState();
}

class _CrewKpiTrackingViewState extends State<CrewKpiTrackingView> {
  late final store = widget.store ?? CrewKpiStore();
  Map<String, dynamic>? data;
  List<Map<String, dynamic>> transactions = [];
  StreamSubscription<bool>? network;
  StreamSubscription<void>? bookings;
  Future<void>? loadingFuture;
  bool loading = true, active = true, rerun = false;
  String? error;
  String mode = 'Monthly', search = '';
  bool showingFuel = false;
  DateTime month = kpiDate(DateTime.now());
  int week = 1, visible = 15;
  late KpiPeriod range = KpiPeriod.month(month.year, month.month);
  final expanded = <String>{};
  final toolbarKey = GlobalKey();
  bool get allowed =>
      widget.allowed?.call() ?? CrewKpiStore.canView(widget.user);
  @override
  void initState() {
    super.initState();
    RoleAccessService.instance.addListener(permissionChanged);
    network = (widget.network ?? networkStatusEvents()).distinct().listen(
      (_) => changed(),
    );
    bookings =
        (widget.bookingChanges ??
                BookingRequest.instance.watchBookings().map<void>((_) {}))
            .listen((_) => changed());
    _seedFromMemory();
    unawaited(load());
  }

  /// Show the numbers this device already loaded on the very first frame. The
  /// load below still refreshes from cache and then the server, so reopening the
  /// screen never flashes a spinner over data that is already in hand.
  void _seedFromMemory() {
    if (!allowed) return;
    final snapshot = CrewKpiStore.peek(widget.user);
    if (snapshot == null) return;
    final rows = (snapshot['records'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (rows.isEmpty) return;
    data = Map<String, dynamic>.from(snapshot);
    transactions = rows;
    loading = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasActive = active;
    active = TickerMode.valuesOf(context).enabled;
    if (active && !wasActive) changed();
  }

  void permissionChanged() {
    if (!mounted) return;
    if (!allowed) {
      setState(() {
        data = null;
        transactions = [];
        loading = false;
      });
    } else {
      changed();
    }
  }

  void changed() {
    if (!active || !allowed) return;
    if (loadingFuture != null) {
      rerun = true;
      return;
    }
    unawaited(load());
  }

  @override
  void dispose() {
    RoleAccessService.instance.removeListener(permissionChanged);
    unawaited(network?.cancel());
    unawaited(bookings?.cancel());
    super.dispose();
  }

  Future<void> load() => loadingFuture ??= _load().whenComplete(() {
    loadingFuture = null;
    if (rerun && mounted && allowed && active) {
      rerun = false;
      unawaited(load());
    }
  });
  Future<void> _load() async {
    if (!allowed) {
      if (mounted) setState(() => loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        error = null;
        loading = data == null;
      });
    }
    void apply(Map<String, dynamic> next) {
      final rows = crewKpiTransactions(widget.user, next);
      if (mounted && allowed) {
        setState(() {
          data = next;
          transactions = rows;
          loading = false;
        });
      }
    }

    try {
      final cached = await store
          .readCached(widget.user)
          .timeout(const Duration(seconds: 5));
      if (!mounted || !allowed) return;
      if (cached != null) apply(cached);
      final fresh = await store
          .load(widget.user)
          .timeout(const Duration(seconds: 30));
      if (!mounted || !allowed) return;
      if (fresh != null) apply(fresh);
    } catch (e) {
      if (mounted && allowed) {
        setState(
          () => error = e is TimeoutException
              ? 'KPI data is taking longer to load. Please try again.'
              : 'Could not refresh your KPI. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  KpiPeriod? get period => switch (mode) {
    'All Time' => null,
    'Range' => range,
    'Weekly' => KpiPeriod.week(month.year, month.month, week),
    _ => KpiPeriod.month(month.year, month.month),
  };
  void filter(VoidCallback change) => setState(() {
    change();
    visible = 15;
    expanded.clear();
  });
  Widget toolbar() => LayoutBuilder(
    builder: (context, constraints) => Row(
      key: toolbarKey,
      children: [
        Expanded(
          child: AdminListSearchField(
            controlHeight: adminFilterFieldMinHeight,
            surfaceRadius: 16,
            onChanged: (value) => filter(() => search = value),
          ),
        ),
        const SizedBox(width: 12),
        AdminListNewButton(
          controlHeight: adminFilterFieldMinHeight,
          surfaceRadius: 16,
          iconOnly: constraints.maxWidth < 520,
          label: showingFuel ? 'Transactions' : 'Fuel',
          icon: showingFuel ? Icons.receipt_long : Icons.local_gas_station,
          onTap: () => filter(() {
            showingFuel = !showingFuel;
            search = '';
          }),
        ),
        const SizedBox(width: 12),
        AdminListDynamicFiltersPanel(
          iconOnly: constraints.maxWidth < 520,
          menuAnchorKey: toolbarKey,
          filters: [
            AdminListDropdownFilterConfig(
              label: 'Period',
              value: mode,
              items: const ['Range', 'Weekly', 'Monthly', 'All Time'],
              onChanged: (v) => filter(() => mode = v),
            ),
            if (mode == 'Weekly')
              AdminListDropdownFilterConfig(
                label: 'Week',
                value: '$week',
                items: const ['1', '2', '3', '4'],
                displayValue: (v) => 'Week $v',
                onChanged: (v) => filter(() => week = int.parse(v)),
              ),
            if (mode == 'Monthly' || mode == 'Weekly') ...[
              AdminListDropdownFilterConfig(
                label: 'Month',
                value: '${month.month}',
                items: List.generate(12, (i) => '${i + 1}'),
                displayValue: (v) => _months[int.parse(v) - 1],
                onChanged: (v) => filter(
                  () => month = DateTime.utc(month.year, int.parse(v)),
                ),
              ),
              AdminListDropdownFilterConfig(
                label: 'Year',
                value: '${month.year}',
                items: ({
                  month.year,
                  ...List.generate(40, (i) => 2020 + i),
                }.toList()..sort()).map((v) => '$v').toList(),
                onChanged: (v) => filter(
                  () => month = DateTime.utc(int.parse(v), month.month),
                ),
              ),
            ],
            if (mode == 'Range') ...[
              AdminListDateFilterConfig(
                label: 'From',
                value: range.start,
                onSelected: (v) {
                  if (v != null) {
                    filter(() {
                      final d = DateTime.utc(v.year, v.month, v.day);
                      range = KpiPeriod(
                        d,
                        range.end.isBefore(d) ? d : range.end,
                      );
                    });
                  }
                },
              ),
              AdminListDateFilterConfig(
                label: 'To',
                value: range.end,
                onSelected: (v) {
                  if (v != null) {
                    filter(() {
                      final d = DateTime.utc(v.year, v.month, v.day);
                      range = KpiPeriod(
                        range.start.isAfter(d) ? d : range.start,
                        d,
                      );
                    });
                  }
                },
              ),
            ],
          ],
          onClear: () => filter(() {
            mode = 'Monthly';
            month = kpiDate(DateTime.now());
            week = 1;
          }),
        ),
      ],
    ),
  );
  String money(num value) {
    final parts = value.abs().toStringAsFixed(2).split('.');
    final digits = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '${value < 0 ? '−' : ''}₱$digits${parts[1] == '00' ? '' : '.${parts[1]}'}';
  }

  @override
  Widget build(BuildContext context) {
    if (!allowed) {
      return const Center(
        child: AdminListStateText(
          message: 'You do not have access to KPI Tracking.',
        ),
      );
    }
    if (loading) return const AppPageLoading(message: 'Loading KPI ...');
    final selected = transactions
        .where(
          (r) =>
              period?.contains(DateTime.parse('${r['day']}T00:00:00Z')) ?? true,
        )
        .toList();
    final shares = selected
        .where((r) => r['type'] == 'Share')
        .fold<double>(0, (s, r) => s + (r['amount'] as num? ?? 0));
    final salary = selected
        .where((r) => r['type'] == 'Salary')
        .fold<double>(0, (s, r) => s + (r['amount'] as num? ?? 0));
    final activePeriod = period;
    final bookingProgress = activePeriod == null
        ? (delivered: 0, total: 0)
        : kpiBookingProgress(
            (data?['bookings'] as List? ?? const []).whereType<Map>().map(
              (row) => Map<String, dynamic>.from(row),
            ),
            period: activePeriod,
            role: widget.user.role,
            userId: widget.user.id,
          );
    final periodFuel =
        (data?['fuel'] as List? ?? []).whereType<Map>().where((r) {
          final date = DateTime.tryParse('${r['day']}T00:00:00Z');
          return date != null && (period?.contains(date) ?? true);
        }).toList()..sort(
          (a, b) => '${b['day']} ${b['created_at']} ${b['id']}'.compareTo(
            '${a['day']} ${a['created_at']} ${a['id']}',
          ),
        );
    final fuelRows = periodFuel
        .where(
          (r) =>
              search.trim().isEmpty ||
              ['pm', 'day', 'reference', 'supplier', 'notes', 'status']
                  .map((key) => r[key])
                  .join(' ')
                  .toLowerCase()
                  .contains(search.trim().toLowerCase()),
        )
        .toList();
    final incidents = (data?['incidents'] as List? ?? [])
        .whereType<Map>()
        .where((r) {
          final d = DateTime.tryParse('${r['day']}T00:00:00Z');
          return d != null &&
              !d.isAfter(kpiDate(DateTime.now())) &&
              (period?.contains(d) ?? true);
        })
        .toList();
    int count(String key) =>
        incidents.fold(0, (s, r) => s + ((r[key] as num?)?.toInt() ?? 0));
    final rules = KpiRatingRules.fromMap({
      'rating_rules': data?['rating_rules'] ?? {},
    });
    final days = <String, List<Map<String, dynamic>>>{};
    for (final row in selected) {
      days.putIfAbsent('${row['day']}', () => []).add(row);
    }
    final matches = days.entries
        .where(
          (d) =>
              search.trim().isEmpty ||
              '${d.key} ${d.value.map((r) => r['label']).join(' ')}'
                  .toLowerCase()
                  .contains(search.trim().toLowerCase()),
        )
        .toList();
    final rows = <({String day, Map<String, dynamic>? transaction})>[];
    for (final day in matches.take(visible)) {
      rows.add((day: day.key, transaction: null));
      if (expanded.contains(day.key)) {
        rows.addAll(day.value.map((r) => (day: day.key, transaction: r)));
      }
    }
    String date(String day) => _date(DateTime.parse(day));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical &&
              n.metrics.extentAfter < 240 &&
              n is ScrollUpdateNotification &&
              (n.scrollDelta ?? 0) > 0 &&
              visible < (showingFuel ? fuelRows.length : matches.length)) {
            setState(() => visible += 15);
          }
          return false;
        },
        child: AdminModalRecordList(
          horizontalOnDesktop: true,
          selectableCells: true,
          trailingActions: !showingFuel,
          showTitlesRow: MediaQuery.sizeOf(context).width >= 900,
          scrollHeader: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              toolbar(),
              const SizedBox(height: 20),
              AdminListItemCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${widget.user.id} | ${widget.user.name ?? ''}',
                      style: const TextStyle(
                        color: AppColors.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final row in [
                      [
                        'Complaints',
                        '${count('complaints')} (${rules.complaintsRating(count('complaints'))})',
                      ],
                      [
                        'Accidents',
                        '${count('accidents')} (${rules.accidentsRating(count('accidents'))})',
                      ],
                      [
                        'Bookings',
                        '${bookingProgress.delivered}/${bookingProgress.total}',
                      ],
                      ['Shares', money(shares)],
                      ['Salary', money(salary)],
                      ['Total', money(shares + salary)],
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(row[0])),
                            Text(row[1]),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: AdminListItemCard(
                    child: Column(
                      children: [
                        Text(error!),
                        TextButton(
                          onPressed: () => load(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
          emptyMessage: data == null && error == null
              ? 'No cached KPI data. Connect online to load your KPI.'
              : search.isNotEmpty
              ? (showingFuel
                    ? 'No matching fuel requests.'
                    : 'No matching transactions.')
              : showingFuel
              ? 'No fuel requests in this period.'
              : 'No delivered trips in this period.',
          titles: showingFuel
              ? const [
                  'PM',
                  'Date',
                  'Reference',
                  'Supplier',
                  'Liters',
                  'Price / Liter',
                  'Amount',
                  'Notes / Route',
                  'Status',
                ]
              : const [
                  'Label',
                  'Amount',
                  'Type',
                  'Status',
                  'DateTime',
                  'Actions',
                ],
          itemCount: showingFuel
              ? fuelRows.length.clamp(0, visible)
              : rows.length,
          columnExtraWidths: showingFuel ? const {} : const {5: 48},
          rowGroupKey: showingFuel ? null : (i) => rows[i].day,
          valuesAt: (i) {
            if (showingFuel) {
              final r = fuelRows[i];
              return [
                '${r['pm'] ?? '—'}',
                date('${r['day']}'),
                '${r['reference'] ?? '—'}',
                '${r['supplier'] ?? '—'}',
                '${r['liters'] ?? '—'}',
                kpiMoney(r['price_per_liter']) == null
                    ? '—'
                    : money(kpiMoney(r['price_per_liter'])!),
                kpiMoney(r['amount']) == null
                    ? '—'
                    : money(kpiMoney(r['amount'])!),
                '${r['notes'] ?? '—'}',
                '${r['status'] ?? 'active'}',
              ];
            }
            final row = rows[i];
            final tx = row.transaction;
            final group = days[row.day]!;
            return tx == null
                ? [
                    date(row.day),
                    money(
                      group.fold<double>(
                        0,
                        (s, r) => s + (r['amount'] as num? ?? 0),
                      ),
                    ),
                    'Total',
                    group.any((r) => r['status'] == 'Missing rate')
                        ? 'Missing rate'
                        : group.every((r) => r['status'] == 'Confirmed')
                        ? 'Confirmed'
                        : 'Unconfirmed',
                    '',
                    '',
                  ]
                : [
                    tx['type'] == 'Salary'
                        ? '${_date(DateTime.parse(row.day)).split(',').first} Pay'
                        : '${tx['label']}',
                    tx['amount'] == null ? '—' : money(tx['amount'] as num),
                    '${tx['type']}',
                    '${tx['status']}',
                    _dateTime(DateTime.parse('${tx['at']}')),
                    '',
                  ];
          },
          cellBuilder: (i, col) {
            if (showingFuel) return null;
            final row = rows[i];
            final tx = row.transaction;
            if (col == 0 &&
                tx?['booking_id'] != null &&
                widget.onOpenBooking != null) {
              return RecordTextLink(
                label: '${tx!['label']}',
                onTap: () => widget.onOpenBooking!('${tx['booking_id']}'),
              );
            }
            if (col == 5 && row.transaction == null) {
              return AdminListActionButton(
                icon: expanded.contains(row.day)
                    ? Icons.expand_less
                    : Icons.expand_more,
                onTap: () => setState(() {
                  if (!expanded.remove(row.day)) expanded.add(row.day);
                }),
                animateInteraction: false,
              );
            }
            return null;
          },
        ),
      ),
    );
  }
}

const _months = [
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
String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';
String _dateTime(DateTime d) {
  String two(int v) => '$v'.padLeft(2, '0');
  return '${_date(d)}\n${two(d.hour % 12 == 0 ? 12 : d.hour % 12)}:${two(d.minute)}:${two(d.second)} ${d.hour >= 12 ? 'PM' : 'AM'}';
}
