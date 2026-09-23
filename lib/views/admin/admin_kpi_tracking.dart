import 'package:webapp/views/admin/shared_kpi_rules_dialog.dart';
import 'package:webapp/services/kpi/kpi_period_label.dart';
import 'package:webapp/views/admin/pm_fuel_ledger_dialog.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/views/admin/operations_catalog_dialog.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/kpi_all_time_period.dart';
import 'package:webapp/services/kpi/kpi_rating_rules.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/views/admin/pm_kpi_dialog.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';

class AdminKpiTrackingView extends StatefulWidget {
  const AdminKpiTrackingView({super.key, this.store});
  final PmKpiStore? store;
  @override
  State<AdminKpiTrackingView> createState() => _AdminKpiTrackingViewState();
}

class _AdminKpiTrackingViewState extends State<AdminKpiTrackingView> {
  late final store = widget.store ?? PmKpiStore.instance;
  List<VehicleMake> makes = [];
  List<Booking> bookings = [];
  final data = <String, KpiStoredData>{};
  List<({VehicleMake make, PmKpi report})> reports = [];
  StreamSubscription<List<Booking>>? subscription;
  String mode = 'All Time';
  DateTime month = kpiDate(DateTime.now());
  int week = 1;
  late KpiPeriod range = KpiPeriod.month(month.year, month.month);
  bool loading = true;
  String? error;
  int revision = 0;
  int visible = 15;
  String query = '';
  final toolbarKey = GlobalKey();

  bool matches(VehicleMake make) {
    final text = [
      make.id,
      make.code,
      make.type?.name,
      make.driver?.id,
      make.driver?.name,
      make.helper?.id,
      make.helper?.name,
    ].whereType<String>().join(' ').toLowerCase();
    return query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }

  KpiPeriod get fetchPeriod => mode == 'All Time'
      ? KpiPeriod(DateTime.utc(1900), kpiDate(DateTime.now()))
      : period;

  KpiPeriod get period => mode == 'Weekly'
      ? KpiPeriod.week(month.year, month.month, week)
      : mode == 'Range'
      ? range
      : KpiPeriod.month(month.year, month.month);

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    revision++;
    unawaited(subscription?.cancel());
    super.dispose();
  }

  void calculate() {
    final today = kpiDate(DateTime.now());
    reports = [
      for (final make in makes)
        if (data[make.id] case final KpiStoredData stored)
          (
            make: make,
            report: PmKpi.calculate(
              makeId: make.id!,
              period: mode == 'All Time'
                  ? fleetTruckAllTimePeriod(
                      make,
                      makes,
                      bookings,
                      stored,
                      today,
                    )
                  : period,
              bookings: bookings,
              makes: makes,
              records: stored.records,
              fuelEntries: stored.fuel,
              resolveSalary: stored.catalog.resolveSalary,
              ratingRules: KpiRatingRules.fromMap(stored.settings),
            ),
          ),
    ];
  }

  Future<void> load() async {
    final token = ++revision;
    if (!store.canRead || !store.canReadBookings) {
      setState(() {
        loading = false;
        error = 'KPI and booking access are required.';
      });
      return;
    }
    setState(() {
      error = null;
      loading = reports.isEmpty;
    });
    try {
      // Existing requests restore account-scoped local caches when offline.
      final nextMakes = (await store.exportMakes().timeout(
        const Duration(seconds: 15),
      )).where((make) => (make.id ?? '').isNotEmpty).toList();
      final nextBookings =
          store.cachedBookings ??
          await store.bookings().timeout(const Duration(seconds: 15));
      if (!mounted || token != revision) return;
      makes = nextMakes;
      bookings = nextBookings;
      subscription ??= store.watchBookings().listen((value) {
        if (!mounted || !store.canRead) return;
        setState(() {
          bookings = value;
          calculate();
        });
      }, onError: (Object _) {});
      for (final make in makes) {
        final cached = await store
            .readCached(make.id!, fetchPeriod)
            .timeout(const Duration(seconds: 5));
        if (!mounted || token != revision) return;
        if (cached != null) data[make.id!] = cached;
      }
      setState(() {
        calculate();
        loading = makes.isNotEmpty && reports.isEmpty;
      });
      // Sequential refresh avoids a fleet-wide burst of parallel Firestore reads.
      for (final make in makes) {
        final stored = await store
            .load(make.id!, fetchPeriod)
            .timeout(const Duration(seconds: 15));
        if (!mounted || token != revision) return;
        data[make.id!] = stored;
      }
      setState(() {
        calculate();
        loading = false;
      });
    } catch (e) {
      if (!mounted || token != revision) return;
      setState(() {
        loading = false;
        error = e is StateError && e.message.contains('access')
            ? 'Enable KPI, Bookings, and Vehicle Makes access for this role.'
            : e is TimeoutException
            ? 'KPI data took too long to load. Please retry.'
            : 'KPI data could not be loaded. Please retry.';
        calculate();
      });
    }
  }

  void change(VoidCallback action) {
    setState(() {
      action();
      visible = 15;
      calculate();
    });
    unawaited(load());
  }

  Widget toolbar() => AdminListToolbar(
    key: toolbarKey,
    controlHeight: adminFilterFieldMinHeight,
    surfaceRadius: 16,
    search: AdminListSearchField(
      controlHeight: adminFilterFieldMinHeight,
      surfaceRadius: 16,
      initialValue: query,
      onChanged: (value) => setState(() {
        query = value;
        visible = 15;
      }),
    ),
    filtersBuilder: (_, iconOnly) => AdminListDynamicFiltersPanel(
      iconOnly: iconOnly,
      menuAnchorKey: toolbarKey,
      filters: [
        AdminListDropdownFilterConfig(
          label: 'Period',
          value: mode,
          items: const ['Range', 'Weekly', 'Monthly', 'All Time'],
          onChanged: (value) => change(() => mode = value),
        ),
        if (mode == 'Weekly')
          AdminListDropdownFilterConfig(
            label: 'Week',
            value: '$week',
            items: const ['1', '2', '3', '4'],
            displayValue: (value) => 'Week $value',
            onChanged: (value) => change(() => week = int.parse(value)),
          ),
        if (mode == 'Weekly' || mode == 'Monthly') ...[
          AdminListDropdownFilterConfig(
            label: 'Month',
            value: '${month.month}',
            items: List.generate(12, (i) => '${i + 1}'),
            displayValue: (value) => MaterialLocalizations.of(context)
                .formatMonthYear(DateTime(month.year, int.parse(value)))
                .split(' ')
                .first,
            onChanged: (value) => change(
              () => month = DateTime.utc(month.year, int.parse(value)),
            ),
          ),
          AdminListDropdownFilterConfig(
            label: 'Year',
            value: '${month.year}',
            items: ({
              month.year,
              ...List.generate(30, (i) => 2020 + i),
            }.toList()..sort()).map((v) => '$v').toList(),
            onChanged: (value) => change(
              () => month = DateTime.utc(int.parse(value), month.month),
            ),
          ),
        ],
        if (mode == 'Range') ...[
          AdminListDateFilterConfig(
            label: 'From',
            value: range.start,
            onSelected: (value) {
              if (value == null) return;
              final day = DateTime.utc(value.year, value.month, value.day);
              change(
                () => range = KpiPeriod(
                  day,
                  range.end.isBefore(day) ? day : range.end,
                ),
              );
            },
          ),
          AdminListDateFilterConfig(
            label: 'To',
            value: range.end,
            onSelected: (value) {
              if (value == null) return;
              final day = DateTime.utc(value.year, value.month, value.day);
              change(
                () => range = KpiPeriod(
                  range.start.isAfter(day) ? day : range.start,
                  day,
                ),
              );
            },
          ),
        ],
      ],
      onClear: () => change(() {
        mode = 'All Time';
        week = 1;
        month = kpiDate(DateTime.now());
      }),
    ),
    buttonLabel: 'Actions',
    fitButtonLabel: true,
    buttonIcon: Icons.arrow_drop_down_rounded,
    onNewPressed: store.canReadFuel || store.canReadCatalog || store.canEdit
        ? openActions
        : null,
  );

  Future<void> openActions() async {
    final box = toolbarKey.currentContext!.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final edge = box.localToGlobal(
      Offset(box.size.width, box.size.height),
      ancestor: overlay,
    );
    final action = await showMenu<String>(
      context: context,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      position: RelativeRect.fromLTRB(
        edge.dx - 180,
        edge.dy,
        overlay.size.width - edge.dx,
        0,
      ),
      items: [
        if (store.canReadFuel)
          const PopupMenuItem(value: 'Fuel', child: Text('Fuel')),
        if (store.canReadCatalog)
          const PopupMenuItem(value: 'Rates', child: Text('Rates')),
        if (store.canEdit)
          const PopupMenuItem(value: 'Rules', child: Text('Rules')),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'Rates') {
      await showOperationsCatalog(context);
    } else if (action == 'Rules') {
      await showAppDialog<void>(
        context: context,
        modalKey: 'fleet-kpi-rules',
        builder: (dialogContext) => SharedKpiRulesDialog(
          store: store,
          onBack: () => Navigator.pop(dialogContext),
        ),
      );
    } else {
      await pickMake(action);
    }
    if (mounted) unawaited(load());
  }

  Future<void> pickMake(String action) async {
    var search = '';
    Widget? selectedView;
    await showAppDialog<void>(
      context: context,
      modalKey: 'kpi-tracking-pm-$action',
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          if (selectedView != null) return selectedView!;
          void select(VehicleMake make) {
            void goBack() => update(() => selectedView = null);
            final selectedPeriod = mode == 'All Time'
                ? fleetTruckAllTimePeriod(
                    make,
                    makes,
                    bookings,
                    data[make.id] ?? const KpiStoredData([], {}, true),
                    kpiDate(DateTime.now()),
                  )
                : period;
            update(() {
              selectedView = action == 'Fuel'
                  ? PmFuelLedgerDialog(
                      key: ValueKey('fuel-${make.id}'),
                      make: make,
                      period: selectedPeriod,
                      store: store,
                      periodLabel: kpiPeriodLabel(
                        selectedPeriod,
                        mode: mode,
                        week: week,
                      ),
                      initialData: data[make.id],
                      onBack: goBack,
                      backLabel: 'Go Back',
                    )
                  : PmKpiDialog(
                      key: ValueKey('rules-${make.id}'),
                      make: make,
                      store: store,
                      openRules: true,
                      onBack: goBack,
                    );
            });
          }

          final choices = makes
              .where(
                (make) =>
                    '${make.id} ${make.code} ${make.driver?.name ?? ''} ${make.helper?.name ?? ''}'
                        .toLowerCase()
                        .contains(search.toLowerCase().trim()),
              )
              .toList();
          return AdminModalShell(
            title: '$action · Select PM',
            maxWidth: AdminModalShell.kpiMaxWidth,
            flexibleBody: true,
            bodyHandlesScrolling: true,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AdminModalRecordList(
                horizontalOnDesktop: true,
                scrollHeader: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: AdminListSearchField(
                    controlHeight: adminFilterFieldMinHeight,
                    surfaceRadius: 16,
                    initialValue: search,
                    onChanged: (value) => update(() => search = value),
                  ),
                ),
                titles: const ['PM', 'Driver', 'Helper'],
                itemCount: choices.length,
                onRowTap: (i) => select(choices[i]),
                emptyMessage: 'No matching trucks.',
                valuesAt: (i) => [
                  choices[i].code ?? choices[i].id!,
                  choices[i].driver?.name ?? '—',
                  choices[i].helper?.name ?? '—',
                ],
                cellBuilder: (i, col) => col != 0
                    ? null
                    : Text(
                        choices[i].code ?? choices[i].id!,
                        style: const TextStyle(
                          color: AppColors.primaryColor,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  String amount(double value) {
    final parts = value.abs().toStringAsFixed(2).split('.');
    final digits = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final decimals = parts.last == '00' ? '' : '.${parts.last}';
    return '${value < 0 ? '−' : ''}₱$digits$decimals';
  }

  List<double> numbers(PmKpi report) => [
    report.revenue,
    report.fuel,
    report.driverSalary + report.helperSalary,
    report.depreciation,
    report.maintenance,
    report.expenses,
    report.gross,
    report.marginTarget,
    report.marginVariance,
    report.revenueTarget,
    report.profitTarget,
  ];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: RoleAccessService.instance,
    builder: (context, _) {
      if (!store.canRead || !store.canReadBookings) {
        return const Center(
          child: Text('You do not have access to KPI Tracking.'),
        );
      }
      final filtered = reports.where((entry) => matches(entry.make)).toList();
      final totals = List<double>.filled(11, 0);
      for (final entry in filtered) {
        final values = numbers(entry.report);
        for (var i = 0; i < values.length; i++) {
          totals[i] += values[i];
        }
      }
      final count = filtered.length.clamp(0, visible);
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            toolbar(),
            const SizedBox(height: 20),
            if (error != null)
              Row(
                children: [
                  Expanded(child: Text(error!)),
                  TextButton(onPressed: load, child: const Text('Retry')),
                ],
              ),
            Expanded(
              child: loading
                  ? const AppPageLoading()
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notice) {
                        if (notice.metrics.extentAfter < 200 &&
                            visible < filtered.length &&
                            notice is ScrollUpdateNotification &&
                            (notice.scrollDelta ?? 0) > 0) {
                          setState(() => visible += 15);
                        }
                        return false;
                      },
                      child: AdminModalRecordList(
                        horizontalOnDesktop: true,
                        selectableCells: true,
                        titles: const [
                          'PM',
                          'Revenue',
                          'Fuel',
                          'Salary',
                          'Depreciation',
                          'Maintenance',
                          'Expenses',
                          'Income',
                          'Income Target',
                          'Variance',
                          'Revenue Target',
                          'Income Goal',
                          'Rating',
                        ],
                        itemCount: filtered.isEmpty ? 0 : count + 1,
                        emptyMessage: query.trim().isEmpty
                            ? 'No trucks available.'
                            : 'No matching trucks.',
                        valuesAt: (i) => i == 0
                            ? ['Total', ...totals.map(amount), '—']
                            : [
                                filtered[i - 1].make.code ??
                                    filtered[i - 1].make.id!,
                                ...numbers(filtered[i - 1].report).map(amount),
                                filtered[i - 1].report.rating,
                              ],
                        cellBuilder: (i, col) {
                          if (i == 0 && col == 0) {
                            return const Text(
                              'Total',
                              style: TextStyle(
                                color: AppColors.primaryColor,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            );
                          }
                          if (i > 0 && col == 0) {
                            return InkWell(
                              onTap: () async {
                                await showPmKpiDialog(
                                  context,
                                  filtered[i - 1].make,
                                );
                                if (mounted) unawaited(load());
                              },
                              child: Text(
                                filtered[i - 1].make.code ??
                                    filtered[i - 1].make.id!,
                                style: const TextStyle(
                                  color: AppColors.primaryColor,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            );
                          }
                          if (col > 0 && col < 12) {
                            final value = (i == 0
                                ? totals
                                : numbers(filtered[i - 1].report))[col - 1];
                            return Text(
                              amount(value),
                              style: TextStyle(
                                color: value < 0
                                    ? AppColors.dangerStrong
                                    : null,
                                fontWeight: i == 0 ? FontWeight.bold : null,
                              ),
                            );
                          }
                          return null;
                        },
                      ),
                    ),
            ),
          ],
        ),
      );
    },
  );
}
