import 'package:webapp/services/kpi/kpi_calculation_cache.dart';
import 'package:webapp/services/sync_error_log_service.dart';
import 'package:webapp/widgets/shared/admin_action_confirmation.dart';
import 'package:webapp/services/kpi/kpi_incident_summary.dart';
import 'package:webapp/services/kpi/kpi_rating_rules.dart';
import 'package:webapp/widgets/shared/native_date_input.dart';
import 'package:webapp/utils/location_display.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/record_text_link.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/views/admin/operations_catalog_dialog.dart';
import 'package:webapp/views/admin/pm_fuel_ledger_dialog.dart';
import 'package:webapp/services/kpi/kpi_fleet_workbook.dart';
import 'dart:async';
import 'package:webapp/services/export_file_service.dart';
import 'package:flutter/services.dart';
import 'package:webapp/services/kpi/kpi_salary_diagnostics.dart';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/views/admin/admin_bookings.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';

const double _kpiContentSpacing = 24;

class _KpiSectionTitle extends StatelessWidget {
  const _KpiSectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
    ),
  );
}

String _kpiDateLabel(DateTime date) {
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

String _kpiAmount(double amount) {
  final parts = amount.abs().toStringAsFixed(2).split('.');
  final digits = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '${amount < 0 ? "−" : ""}₱$digits.${parts.last}';
}

Future<void> showPmKpiDialog(BuildContext context, VehicleMake make) async {
  final selection = await showAppDialog<Object>(
    context: context,
    modalKey: 'pm-kpi:${make.id}',
    builder: (dialogContext) => PmKpiDialog(
      make: make,
      onOpenBooking: (current, booking) =>
          Navigator.of(dialogContext).pop((current: current, booking: booking)),
      onOpenUser: (current, viewed) =>
          Navigator.of(dialogContext).pop((current: current, viewed: viewed)),
    ),
  );
  if (!context.mounted) return;
  if (selection case (
    current: final UserModel current,
    viewed: final UserModel viewed,
  )) {
    await AdminUsersView.openDetailPage(
      context,
      currentUser: current,
      viewedUser: viewed,
    );
  } else if (selection case (
    current: final UserModel current,
    booking: final Booking booking,
  )) {
    await AdminBookingsView.openDetailPage(
      context,
      currentUser: current,
      booking: booking,
    );
  }
}

class PmKpiDialog extends StatefulWidget {
  const PmKpiDialog({
    super.key,
    required this.make,
    this.store,
    this.onOpenUser,
    this.onOpenBooking,
  });
  final void Function(UserModel current, UserModel viewed)? onOpenUser;
  final void Function(UserModel current, Booking booking)? onOpenBooking;
  final PmKpiStore? store;
  final VehicleMake make;
  @override
  State<PmKpiDialog> createState() => _PmKpiDialogState();
}

class _PmKpiDialogState extends State<PmKpiDialog> {
  late final PmKpiStore _store;
  final _calculations = KpiCalculationCache<PmKpi>();
  final _calculationIssues = <PmKpi, Set<String>>{};
  Object? _lastCalculationRevision;

  PmKpi _calculate(KpiPeriod period) {
    final makes = _store.makes;
    final revision = (
      widget.make.id,
      _bookings,
      _stored,
      _period.start,
      _period.end,
      makes
          .map((m) => '${m.id}:${m.code}:${m.driver?.id}:${m.helper?.id}')
          .join('|'),
    );
    if (_lastCalculationRevision != revision) {
      _lastCalculationRevision = revision;
      _calculationIssues.clear();
    }
    final report = _calculations.get(revision, (period.start, period.end), () {
      final value = PmKpi.calculate(
        makeId: widget.make.id ?? '',
        period: period,
        bookings: _bookings,
        makes: makes,
        records: _stored.records,
        fuelEntries: _stored.fuel,
        resolveSalary: _stored.catalog.resolveSalary,
        ratingRules: KpiRatingRules.fromMap(_stored.settings),
      );
      _calculationIssues[value] = Set.of(value.issues);
      return value;
    });
    // Connectivity/error messages are transient presentation state, not cached
    // calculation errors. A recovered refresh must clear them again.
    report.issues
      ..clear()
      ..addAll(_calculationIssues[report]!);
    return report;
  }

  late DateTime _month;
  late KpiPeriod _period;
  final ScrollController _activityScroll = ScrollController();
  int _visibleActivities = 15;
  final Set<String> _expandedDays = {};
  int _activityCount = 0;
  bool _addingActivityBatch = false;
  String? _activityPeriod;
  bool _showIssues = false;
  bool _exporting = false;
  Widget? _section;
  double _summaryOffset = 0;

  void _openSection(Widget section) {
    _summaryOffset = _activityScroll.hasClients ? _activityScroll.offset : 0;
    setState(() => _section = section);
  }

  void _backToSummary() {
    setState(() => _section = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _activityScroll.hasClients) {
        _activityScroll.jumpTo(
          _summaryOffset.clamp(0, _activityScroll.position.maxScrollExtent),
        );
      }
    });
    _load();
  }

  String _mode = 'Monthly';
  int _week = 1;
  int _generation = 0;
  bool _loading = true;
  String? _error;
  List<Booking> _bookings = [];
  KpiStoredData _stored = const KpiStoredData([], {}, true);
  UserModel? _currentUser;
  StreamSubscription<List<Booking>>? _subscription;
  bool get _canEdit => _store.canEdit;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? PmKpiStore.instance;
    _month = kpiDate(DateTime.now());
    _period = KpiPeriod.month(_month.year, _month.month);
    _load(initial: true);
  }

  @override
  void dispose() {
    _generation++;
    _activityScroll.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  void _loadMoreActivities() {
    if (_addingActivityBatch ||
        !_activityScroll.hasClients ||
        _activityScroll.position.extentAfter >= 240 ||
        _visibleActivities >= _activityCount) {
      return;
    }
    _addingActivityBatch = true;
    setState(
      () => _visibleActivities = (_visibleActivities + 15).clamp(
        0,
        _activityCount,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addingActivityBatch = false;
    });
  }

  Future<void> _load({bool initial = false}) async {
    final generation = ++_generation;
    setState(() {
      _error = null;
    });
    try {
      if (initial) {
        _currentUser = await _store.currentUser();
        if (!_store.canRead || !_store.canReadBookings) {
          throw StateError('You do not have access to booking KPIs.');
        }
        _bookings = _store.cachedBookings ?? await _store.bookings();
        if (!mounted || generation != _generation) {
          return;
        }
      }
      final cached = await _store.readCached(widget.make.id!, _period);
      if (!mounted || generation != _generation) {
        return;
      }
      if (cached != null) {
        setState(() {
          _stored = cached;
          _loading = false;
        });
      }
      var stored = await _store.load(widget.make.id!, _period);
      if (!mounted || generation != _generation) {
        return;
      }
      stored = await _store.learnCityProperDropoffs(_bookings, stored);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _stored = stored;
        _loading = false;
      });
      _subscription ??= _store.watchBookings().listen(
        (bookings) {
          if (mounted) {
            setState(() {
              _bookings = bookings;
            });
          }
        },
        onError: (Object error) {
          if (mounted) {
            setState(() {
              _error = 'Could not refresh bookings. Refresh to try again.';
            });
          }
        },
      );
    } catch (error, stack) {
      unawaited(
        SyncErrorLogService.instance.report(
          error,
          stack,
          source: 'pm_kpi_dialog.dart',
          operation: 'handled operation failure',
        ),
      );
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  void _updatePeriod() {
    _period = _mode == 'Weekly'
        ? KpiPeriod.week(_month.year, _month.month, _week)
        : KpiPeriod.month(_month.year, _month.month);
    _load();
  }

  Future<void> _pickPeriod() async {
    if (_mode == 'Custom range') {
      DateTime? from = _period.start;
      DateTime? to = _period.end;
      final range = await showAppDialog<DateTimeRange>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) {
            final valid =
                from != null &&
                to != null &&
                !to!.isBefore(from!) &&
                from!.year >= 2000 &&
                to!.year <= 2100 &&
                to!.difference(from!).inDays <= 366;
            return AdminModalShell(
              title: 'Date Range',
              maxWidth: 420,
              selectable: false,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: valid
                      ? () => Navigator.pop(
                          dialogContext,
                          DateTimeRange(start: from!, end: to!),
                        )
                      : null,
                  child: const Text('Apply'),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _kpiContentSpacing,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NativeDateInput(
                      label: 'From',
                      value: from,
                      onChanged: (value) => update(() => from = value),
                    ),
                    const SizedBox(height: 16),
                    NativeDateInput(
                      label: 'To',
                      value: to,
                      onChanged: (value) => update(() => to = value),
                    ),
                    if (!valid) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Choose an end date on or after the start date, up to one year apart.',
                        style: TextStyle(color: AppColors.dangerStrong),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
      if (range == null || !mounted) {
        return;
      }
      if (range.end.difference(range.start).inDays > 366) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select up to one year at a time.')),
        );
        return;
      }
      _period = KpiPeriod(
        DateTime.utc(range.start.year, range.start.month, range.start.day),
        DateTime.utc(range.end.year, range.end.month, range.end.day),
      );
      await _load();
    } else {
      var selectedMonth = _month.month;
      var selectedYear = _month.year;
      final date = await showAppDialog<DateTime>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AdminModalShell(
            title: 'Select Month',
            maxWidth: 420,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  DateTime.utc(selectedYear, selectedMonth),
                ),
                child: const Text('Apply'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _kpiContentSpacing,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AdminDropdownFormField<int>(
                    decoration: adminFormInputDecoration('Month'),
                    initialValue: selectedMonth,
                    items: [
                      for (var month = 1; month <= 12; month++)
                        DropdownMenuItem(
                          value: month,
                          child: Text(
                            _kpiDateLabel(
                              DateTime(2000, month),
                            ).split(' ').first,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) update(() => selectedMonth = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  AdminDropdownFormField<int>(
                    decoration: adminFormInputDecoration('Year'),
                    initialValue: selectedYear,
                    items: [
                      for (var year = 2000; year <= 2100; year++)
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: (value) {
                      if (value != null) update(() => selectedYear = value);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (date != null && mounted) {
        _month = date;
        _updatePeriod();
      }
    }
  }

  Future<void> _openUser(UserModel user) async {
    if (_currentUser == null) {
      return;
    }
    widget.onOpenUser?.call(_currentUser!, user);
  }

  Widget _crew(UserModel? user) => RecordTextLink(
    label: '${user?.id ?? "—"} | ${user?.name ?? "Not assigned"}',
    onTap: user != null && _store.canOpenUsers && widget.onOpenUser != null
        ? () => _openUser(user)
        : null,
  );
  Future<void> _editRatingRules() async {
    final current = KpiRatingRules.fromMap(_stored.settings);
    final labels = [
      'Gross income: Satisfactory from (%)',
      'Gross income: Excellent from (%)',
      'Complaints: Excellent up to',
      'Complaints: Satisfactory up to',
      'Accidents: Excellent up to',
      'Gross income target (%)',
    ];
    final controllers = [
      for (final value in [
        current.grossSatisfactoryMin,
        current.grossExcellentMin,
        current.complaintsExcellentMax,
        current.complaintsSatisfactoryMax,
        current.accidentsExcellentMax,
        current.targetPercent,
      ])
        TextEditingController(text: '$value'),
    ];
    String? error;
    final value = await showAppDialog<KpiRatingRules>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AdminModalShell(
          title: 'Rating Rules',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final nums = controllers
                    .map((c) => double.tryParse(c.text.trim()))
                    .toList();
                if (nums.any((n) => n == null || !n.isFinite) ||
                    nums
                        .skip(2)
                        .take(3)
                        .any((n) => n != n!.truncateToDouble())) {
                  update(
                    () => error =
                        'Enter valid percentages and whole-number counts.',
                  );
                  return;
                }
                final rules = KpiRatingRules(
                  grossSatisfactoryMin: nums[0]!,
                  grossExcellentMin: nums[1]!,
                  complaintsExcellentMax: nums[2]!.toInt(),
                  complaintsSatisfactoryMax: nums[3]!.toInt(),
                  accidentsExcellentMax: nums[4]!.toInt(),
                  targetPercent: nums[5]!,
                );
                if (!rules.valid) {
                  update(
                    () => error =
                        'Check threshold order, percentages (0–100), and nonnegative counts.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, rules);
              },
              child: const Text('Save'),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kpiContentSpacing),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final i in [0, 1, 3, 2, 4, 5]) ...[
                  if (i > 0) const SizedBox(height: 16),
                  TextField(
                    controller: controllers[i],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: adminFormInputDecoration(labels[i]),
                  ),
                ],
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: AppColors.dangerStrong),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final controller in controllers) {
      controller.dispose();
    }
    if (value == null || !mounted) return;
    try {
      await _store.save(
        makeId: widget.make.id!,
        data: {
          ..._stored.settings,
          'kind': 'settings',
          'rating_rules': value.toMap(),
        },
        previous: _stored.settings,
      );
      if (mounted) await _load();
    } catch (error, stack) {
      unawaited(
        SyncErrorLogService.instance.report(
          error,
          stack,
          source: 'pm_kpi_dialog.dart',
          operation: 'handled operation failure',
        ),
      );
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _editIncidents({UserModel? initialUser, String? metric}) async {
    final today = kpiDate(DateTime.now());
    final end = _period.end.isAfter(today) ? today : _period.end;
    if (end.isBefore(_period.start)) return;
    final previous = Map<String, dynamic>.from(_stored.settings);
    final rawUsers = previous['user_incident_counts'];
    final userRecords = rawUsers is Map
        ? Map<String, dynamic>.from(rawUsers)
        : <String, dynamic>{};
    final candidates = <String, UserModel>{
      for (final user in [
        ..._store.incidentUsers,
        ?initialUser,
        if (widget.make.driver != null) widget.make.driver!,
        if (widget.make.helper != null) widget.make.helper!,
        for (final booking in _bookings) ...[
          if (booking.driver != null) booking.driver!,
          if (booking.helper != null) booking.helper!,
        ],
      ])
        if (user.id?.isNotEmpty == true &&
            (user.role == 'driver' ||
                user.role == 'helper' ||
                user.id == initialUser?.id))
          user.id!: user,
    };
    // Keep previously recorded replacements selectable after crew assignments change.
    for (final entry in userRecords.entries) {
      if (entry.value is! Map) continue;
      final records = (entry.value as Map).values.whereType<Map>();
      if (records.isEmpty) continue;
      final details = records.last;
      candidates.putIfAbsent(
        entry.key,
        () => UserModel(
          id: entry.key,
          name: details['user_name']?.toString(),
          role: details['user_role']?.toString(),
        ),
      );
    }
    UserModel? selectedUser = initialUser;
    Map<String, dynamic> recordsForUser() {
      final raw = selectedUser == null
          ? previous['incident_counts']
          : userRecords[selectedUser!.id];
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    }

    var records = recordsForUser();
    DateTime? selected = end;
    final complaints = TextEditingController();
    final accidents = TextEditingController();
    void readDay() {
      final record = selected == null ? null : records[kpiDayKey(selected!)];
      complaints.text = record is Map ? '${record['complaints'] ?? ''}' : '';
      accidents.text = record is Map ? '${record['accidents'] ?? ''}' : '';
      if (metric == 'complaints') {
        complaints.text =
            '${(record is Map ? KpiIncidentSummary.count(record['complaints']) ?? 0 : 0) + 1}';
      }
      if (metric == 'accidents') {
        accidents.text =
            '${(record is Map ? KpiIncidentSummary.count(record['accidents']) ?? 0 : 0) + 1}';
      }
    }

    readDay();
    var confirmMissingZero = false;
    String? error;
    final saved = await showAppDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AdminModalShell(
          title: initialUser == null
              ? 'Legacy PM Counts'
              : 'User Complaints & Accidents',
          maxWidth: 480,
          selectable: false,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final complaintCount = int.tryParse(complaints.text.trim());
                final accidentCount = int.tryParse(accidents.text.trim());
                if (selected == null ||
                    selected!.isBefore(_period.start) ||
                    selected!.isAfter(end) ||
                    (initialUser != null && selectedUser == null) ||
                    (complaints.text.trim().isNotEmpty &&
                        (complaintCount == null || complaintCount < 0)) ||
                    (accidents.text.trim().isNotEmpty &&
                        (accidentCount == null || accidentCount < 0)) ||
                    (complaintCount == null && accidentCount == null)) {
                  update(
                    () => error =
                        'Select a date in this period, up to today, and enter nonnegative whole-number counts.',
                  );
                  return;
                }
                final entries = Map<String, dynamic>.from(records);
                final actionTime = DateTime.now().toUtc().toIso8601String();
                if (confirmMissingZero) {
                  for (
                    var day = _period.start;
                    !day.isAfter(end);
                    day = day.add(const Duration(days: 1))
                  ) {
                    final key = kpiDayKey(day);
                    final old = entries[key];
                    final existing = old is Map
                        ? Map<String, dynamic>.from(old)
                        : <String, dynamic>{};
                    if (KpiIncidentSummary.count(existing['complaints']) ==
                            null ||
                        KpiIncidentSummary.count(existing['accidents']) ==
                            null) {
                      entries[key] = {
                        ...existing,
                        'complaints':
                            KpiIncidentSummary.count(existing['complaints']) ??
                            0,
                        'accidents':
                            KpiIncidentSummary.count(existing['accidents']) ??
                            0,
                        'user_id': selectedUser?.id,
                        'user_name': selectedUser?.name,
                        'user_role': selectedUser?.role,
                        'recorded_at': actionTime,
                        'recorded_by': _currentUser?.id,
                      };
                    }
                  }
                }
                final existing = entries[kpiDayKey(selected!)];
                entries[kpiDayKey(selected!)] = {
                  if (existing is Map) ...Map<String, dynamic>.from(existing),
                  'complaints': ?complaintCount,
                  'accidents': ?accidentCount,
                  'user_id': selectedUser?.id,
                  'user_name': selectedUser?.name,
                  'user_role': selectedUser?.role,
                  'recorded_at': actionTime,
                  'recorded_by': _currentUser?.id,
                };
                Navigator.pop(dialogContext, entries);
              },
              child: const Text('Save'),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kpiContentSpacing),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (initialUser != null) ...[
                  AdminDropdownFormField<String>(
                    decoration: adminFormInputDecoration('Driver / Helper'),
                    initialValue: selectedUser?.id,
                    items: [
                      for (final user in candidates.values)
                        DropdownMenuItem(
                          value: user.id,
                          child: Text(
                            '${user.role ?? ''} ${user.id} | ${user.name ?? ''}',
                          ),
                        ),
                    ],
                    onChanged: (id) => update(() {
                      selectedUser = candidates[id];
                      records = recordsForUser();
                      readDay();
                    }),
                  ),
                  const SizedBox(height: 16),
                ],
                Text('${_kpiDateLabel(_period.start)} – ${_kpiDateLabel(end)}'),
                const SizedBox(height: 16),
                NativeDateInput(
                  label: 'Date',
                  value: selected,
                  onChanged: (value) => update(() {
                    selected = value == null
                        ? null
                        : DateTime.utc(value.year, value.month, value.day);
                    readDay();
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: complaints,
                  keyboardType: TextInputType.number,
                  decoration: adminFormInputDecoration('Customer complaints'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: accidents,
                  keyboardType: TextInputType.number,
                  decoration: adminFormInputDecoration('Accidents'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Confirm other unrecorded days in this period as zero (through today)',
                  ),
                  value: confirmMissingZero,
                  onChanged: (value) =>
                      update(() => confirmMissingZero = value ?? false),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: AppColors.dangerStrong),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    complaints.dispose();
    accidents.dispose();
    if (saved == null || !mounted) return;
    try {
      await _store.save(
        makeId: widget.make.id!,
        data: {
          ...previous,
          'kind': 'settings',
          if (selectedUser == null)
            'incident_counts': saved
          else
            'user_incident_counts': {...userRecords, selectedUser!.id!: saved},
        },
        previous: previous,
      );
      if (mounted) await _load();
    } catch (error, stack) {
      unawaited(
        SyncErrorLogService.instance.report(
          error,
          stack,
          source: 'pm_kpi_dialog.dart',
          operation: 'handled operation failure',
        ),
      );
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _editDay(KpiDay day, {KpiTrip? trip}) async {
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (_) => _KpiDayDialog(
        day: day,
        trip: trip,
        makeId: widget.make.id!,
        store: _store,
        matrix: _stored.catalog.matrixFor(day.date),
      ),
    );
    if (saved == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyMedium: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
          bodyLarge: theme.textTheme.bodyLarge?.copyWith(fontSize: 14),
          bodySmall: theme.textTheme.bodySmall?.copyWith(fontSize: 14),
          titleMedium: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
          labelLarge: theme.textTheme.labelLarge?.copyWith(fontSize: 14),
        ),
      ),
      child: AnimatedBuilder(
        animation: RoleAccessService.instance,
        builder: (context, _) => !_store.canRead
            ? const AdminModalShell(
                title: 'PM KPI',
                child: Text('You do not have access to PM KPIs.'),
              )
            : _section ?? _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final result = _calculate(_period);
    if (_stored.fromCache || !_store.bookingsVerified) {
      result.issues.add('Cached data · refresh online to verify');
    }
    if (_stored.catalog.document['local_sync_status'] != null) {
      result.issues.add('Trip-share settings awaiting sync');
    }
    if (_stored.settings['local_sync_status'] != null) {
      result.issues.add('Rating settings awaiting sync');
    }
    if (_error != null) {
      result.issues.add('Data could not be refreshed');
    }
    // Cache verification is background work, not an actionable data issue.
    // Retain it in calculation completeness and copied diagnostics only.
    final visibleIssues = result.issues
        .where((issue) => issue != 'Cached data · refresh online to verify')
        .toList(growable: false);
    final incidents = KpiIncidentSummary(
      _stored.settings,
      _period,
      kpiDate(DateTime.now()),
    );
    final activeDays = result.days
        .where((day) => day.trips.isNotEmpty || day.record.isNotEmpty)
        .toList();
    final activityRows =
        <({KpiDay day, KpiTrip? trip, bool showDailyTotals})>[];
    for (final day in activeDays) {
      final trips = [...day.trips]
        ..sort((a, b) {
          final order = kpiDeliveredAt(
            a.booking,
          )!.compareTo(kpiDeliveredAt(b.booking)!);
          return order == 0 ? a.identity.compareTo(b.identity) : order;
        });
      for (final trip in trips) {
        activityRows.add((day: day, trip: trip, showDailyTotals: false));
      }
      activityRows.add((day: day, trip: null, showDailyTotals: true));
    }
    activityRows.sort((a, b) {
      final aTime = a.trip == null
          ? a.day.date.add(const Duration(days: 1))
          : kpiDeliveredAt(
              a.trip!.booking,
            )!.toUtc().add(const Duration(hours: 8));
      final bTime = b.trip == null
          ? b.day.date.add(const Duration(days: 1))
          : kpiDeliveredAt(
              b.trip!.booking,
            )!.toUtc().add(const Duration(hours: 8));
      final order = bTime.compareTo(aTime);
      return order != 0
          ? order
          : (b.trip?.identity ?? '').compareTo(a.trip?.identity ?? '');
    });
    final activityPeriod = '${_period.start}:${_period.end}';
    if (_activityPeriod != activityPeriod) {
      _activityPeriod = activityPeriod;
      _visibleActivities = 15;
      _expandedDays.clear();
    }
    // Keep the complete transaction set for exports; flatten only expanded days
    // into the lazy viewport. Salary remains grouped by its worked day.
    activeDays.sort((a, b) => b.date.compareTo(a.date));
    final transactionsByDay = <String, List<int>>{};
    for (var i = 0; i < activityRows.length; i++) {
      transactionsByDay
          .putIfAbsent(kpiDayKey(activityRows[i].day.date), () => [])
          .add(i);
    }
    final displayRows = <({KpiDay day, int? transaction})>[];
    for (final day in activeDays) {
      final key = kpiDayKey(day.date);
      displayRows.add((day: day, transaction: null));
      if (_expandedDays.contains(key)) {
        for (final index in transactionsByDay[key] ?? <int>[]) {
          displayRows.add((day: day, transaction: index));
        }
      }
    }
    _activityCount = displayRows.length;
    void toggleDay(KpiDay day) {
      setState(() {
        final key = kpiDayKey(day.date);
        if (!_expandedDays.remove(key)) {
          _expandedDays.add(key);
        }
      });
    }

    String activityDate(int index) {
      final row = activityRows[index];
      if (row.trip == null) {
        final closingDate = row.day.date.add(const Duration(days: 1));
        return '${_kpiDateLabel(closingDate)}\n12:00:00 AM';
      }
      final delivered = kpiDeliveredAt(
        row.trip!.booking,
      )!.toUtc().add(const Duration(hours: 8));
      final hour = (delivered.hour % 12 == 0 ? 12 : delivered.hour % 12)
          .toString()
          .padLeft(2, '0');
      final minute = delivered.minute.toString().padLeft(2, '0');
      final second = delivered.second.toString().padLeft(2, '0');
      final meridiem = delivered.hour < 12 ? 'AM' : 'PM';
      return '${_kpiDateLabel(row.day.date)}\n$hour:$minute:$second $meridiem';
    }

    final relevantBookings =
        _bookings.where((b) => b.vehicleMake?.id == widget.make.id).toList()
          ..sort(Booking.compareCreatedLatestFirst);
    final driver =
        widget.make.driver ??
        relevantBookings
            .map((b) => b.driver)
            .whereType<UserModel>()
            .firstOrNull;
    final helper = widget.make.helper;
    final comparisons = <(String, PmKpi)>[
      (
        _mode == 'Monthly'
            ? 'Month total'
            : _mode == 'Weekly'
            ? 'Week $_week'
            : 'Selected dates',
        result,
      ),
      if (_mode == 'Monthly')
        for (var week = 1; week <= 4; week++)
          (
            'Week $week',
            _calculate(KpiPeriod.week(_month.year, _month.month, week)),
          ),
    ];
    final incidentUsers = <String, UserModel>{
      if (driver?.id != null) driver!.id!: driver,
      if (helper?.id != null) helper!.id!: helper,
    };
    final storedUserIncidents = _stored.settings['user_incident_counts'];
    if (storedUserIncidents is Map) {
      for (final entry in storedUserIncidents.entries) {
        if (entry.value is! Map) continue;
        final dated = (entry.value as Map).entries.where((day) {
          final date = DateTime.tryParse('${day.key}T00:00:00Z');
          return date != null && _period.contains(date) && day.value is Map;
        });
        if (dated.isEmpty) continue;
        final details = dated.last.value as Map;
        incidentUsers.putIfAbsent(
          entry.key.toString(),
          () => UserModel(
            id: entry.key.toString(),
            name: details['user_name']?.toString(),
            role: details['user_role']?.toString(),
          ),
        );
      }
    }
    final incidentRatingRows = <List<String>>[];
    for (final user in incidentUsers.values) {
      // Assigned crew ratings already appear in their summary cards.
      if (user.id == driver?.id || user.id == helper?.id) {
        continue;
      }
      final summary = KpiIncidentSummary.forUser(
        _stored.settings,
        user.id!,
        _period,
        kpiDate(DateTime.now()),
      );
      final person = '${user.role ?? 'User'} ${user.id} | ${user.name ?? ''}';
      incidentRatingRows.add([
        '$person · Complaints',
        '${summary.complaints}',
        result.ratingRules.complaintsRating(summary.complaints),
      ]);
      incidentRatingRows.add([
        '$person · Accidents',
        '${summary.accidents}',
        result.ratingRules.accidentsRating(summary.accidents),
      ]);
    }
    if (_stored.settings['incident_counts'] is Map &&
        (_stored.settings['incident_counts'] as Map).isNotEmpty) {
      incidentRatingRows.add([
        'Unassigned PM complaints',
        '${incidents.complaints}',
        'Needs user attribution',
      ]);
      incidentRatingRows.add([
        'Unassigned PM accidents',
        '${incidents.accidents}',
        'Needs user attribution',
      ]);
    }
    Widget crewSummary(String role, UserModel? user) {
      final userIncidents = user?.id == null
          ? null
          : KpiIncidentSummary.forUser(
              _stored.settings,
              user!.id!,
              _period,
              kpiDate(DateTime.now()),
            );
      final key = role.toLowerCase();
      final total = key == 'driver' ? result.driverSalary : result.helperSalary;
      final shares = result.days.fold<double>(0, (sum, day) {
        final rates =
            (day.estimate?.rates ??
                    day.record['trip_rates'] as List? ??
                    const [])
                .whereType<Map>();
        return sum +
            rates.fold<double>(
              0,
              (amount, rate) => amount + (kpiMoney(rate[key]) ?? 0),
            );
      });
      return AdminListItemCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: AppColors.primaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  role,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 0, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 24),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _crew(user),
                        ),
                      ),
                    ),
                    for (final item in [
                      ('Complaints', 'complaints'),
                      ('Accidents', 'accidents'),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 24),
                          child: Row(
                            children: [
                              Expanded(child: Text(item.$1)),
                              Text(
                                userIncidents == null
                                    ? '—'
                                    : item.$2 == 'complaints'
                                    ? '${userIncidents.complaints} (${result.ratingRules.complaintsRating(userIncidents.complaints)})'
                                    : '${userIncidents.accidents} (${result.ratingRules.accidentsRating(userIncidents.accidents)})',
                              ),
                              if (_canEdit &&
                                  user?.id?.isNotEmpty == true &&
                                  !_period.start.isAfter(
                                    kpiDate(DateTime.now()),
                                  )) ...[
                                const SizedBox(width: 1),
                                Tooltip(
                                  message:
                                      'Add ${item.$1.toLowerCase()} for ${user!.name ?? user.id}',
                                  child: IconButton(
                                    key: ValueKey(
                                      'kpi-add-${item.$2}-${user.id}',
                                    ),
                                    icon: const Icon(Icons.add),
                                    iconSize: 18,
                                    color: AppColors.primaryColor,
                                    padding: EdgeInsets.zero,
                                    alignment: Alignment.centerLeft,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 24,
                                      height: 24,
                                    ),
                                    style: IconButton.styleFrom(
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => _editIncidents(
                                      initialUser: user,
                                      metric: item.$2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                            ],
                          ),
                        ),
                      ),
                    for (final entry in <(String, double)>[
                      ('Shares', shares),
                      ('Salary', total - shares),
                      ('Total', total),
                    ])
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 16, 4),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 24),
                          child: Row(
                            children: [
                              Expanded(child: Text(entry.$1)),
                              Text(
                                _kpiAmount(entry.$2),
                                style: TextStyle(
                                  color: entry.$2 < 0
                                      ? AppColors.dangerStrong
                                      : null,
                                  fontWeight: entry.$1 == 'Total'
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final header = <Widget>[
      Wrap(
        spacing: 8,
        children: [
          if (_store.canReadFuel)
            TextButton.icon(
              icon: const Icon(Icons.local_gas_station_outlined),
              label: const Text('Fuel Requests'),
              onPressed: () async {
                _openSection(
                  PmFuelLedgerDialog(
                    make: widget.make,
                    period: _period,
                    store: _store,
                    onBack: _backToSummary,
                  ),
                );
              },
            ),
          if (_store.canReadCatalog)
            TextButton.icon(
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('Trip Rates'),
              onPressed: () async {
                _openSection(OperationsCatalogDialog(onBack: _backToSummary));
              },
            ),
          if (_canEdit)
            TextButton.icon(
              onPressed: _editRatingRules,
              icon: const Icon(Icons.tune),
              label: const Text('Rating Rules'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 180,
            height: adminModalFieldMinHeight,
            child: AdminDropdownFormField<String>(
              expands: true,
              style: adminFieldValueTextStyle.copyWith(fontSize: 14),
              decoration: adminFormInputDecoration("Period").copyWith(
                constraints: const BoxConstraints.tightFor(
                  height: adminModalFieldMinHeight,
                ),
              ),
              initialValue: _mode,
              items: [
                'Weekly',
                'Monthly',
                'Custom range',
              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _mode = value;
                  });
                  if (value != 'Custom range') {
                    _updatePeriod();
                  } else {
                    _pickPeriod();
                  }
                }
              },
            ),
          ),
          if (_mode == 'Weekly')
            SizedBox(
              width: 140,
              height: adminModalFieldMinHeight,
              child: AdminDropdownFormField<int>(
                expands: true,
                style: adminFieldValueTextStyle.copyWith(fontSize: 14),
                decoration: adminFormInputDecoration('Week').copyWith(
                  constraints: const BoxConstraints.tightFor(
                    height: adminModalFieldMinHeight,
                  ),
                ),
                initialValue: _week,
                items: [1, 2, 3, 4]
                    .map(
                      (w) => DropdownMenuItem(value: w, child: Text('Week $w')),
                    )
                    .toList(),
                onChanged: (w) {
                  if (w != null) {
                    _week = w;
                    _updatePeriod();
                  }
                },
              ),
            ),
          SizedBox(
            width: _mode == 'Custom range' ? 340 : 200,
            height: adminModalFieldMinHeight,
            child: Semantics(
              button: true,
              label: _mode == 'Custom range'
                  ? 'Select date range'
                  : 'Select month',
              child: InkWell(
                onTap: _pickPeriod,
                borderRadius: BorderRadius.circular(16),
                child: InputDecorator(
                  key: const ValueKey('kpi-period-date-field'),
                  expands: true,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    constraints: const BoxConstraints(
                      minHeight: adminModalFieldMinHeight,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primaryBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primaryBorder,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.date_range,
                        size: 24,
                        color: AppColors.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _mode == 'Custom range'
                                ? '${_kpiDateLabel(_period.start)} – ${_kpiDateLabel(_period.end)}'
                                : '${_kpiDateLabel(_month).split(' ').first} ${_month.year}',
                            style: adminFieldValueTextStyle.copyWith(
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            key: const ValueKey('kpi-refresh-control'),
            width: adminModalFieldMinHeight,
            height: adminModalFieldMinHeight,
            child: IconButton(
              tooltip: 'Refresh KPI',
              padding: EdgeInsets.zero,
              alignment: Alignment.center,
              iconSize: 24,
              style: IconButton.styleFrom(
                fixedSize: const Size.square(adminModalFieldMinHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
                alignment: Alignment.center,
                padding: EdgeInsets.zero,
              ),
              onPressed: () {
                _store.invalidateRefreshWindow();
                _load(initial: true);
              },
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      if (_error != null)
        Text(_error!, style: const TextStyle(color: AppColors.danger)),
      const SizedBox(height: 8),
      if (visibleIssues.isNotEmpty) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '${visibleIssues.length} ${visibleIssues.length == 1 ? 'item needs' : 'items need'} checking',
          ),
          trailing: Icon(_showIssues ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() => _showIssues = !_showIssues),
        ),
        if (_showIssues)
          for (final issue in visibleIssues)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(issue),
              ),
            ),
      ],
      const SizedBox(height: 12),
      const _KpiSectionTitle(title: 'Income & Expenses'),

      const SizedBox(height: 12),
      _KpiFinancialTable(columns: comparisons),
      const SizedBox(height: _kpiContentSpacing),
      LayoutBuilder(
        builder: (context, constraints) {
          final driverSummary = crewSummary('Driver', driver);
          final helperSummary = crewSummary('Helper', helper);
          if (constraints.maxWidth >= 640) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: driverSummary),
                const SizedBox(width: _kpiContentSpacing),
                Expanded(child: helperSummary),
              ],
            );
          }
          return Column(
            children: [
              driverSummary,
              const SizedBox(height: _kpiContentSpacing),
              helperSummary,
            ],
          );
        },
      ),
      const SizedBox(height: _kpiContentSpacing),
      const _KpiSectionTitle(title: 'Performance vs Plan'),
      const SizedBox(height: 8),
      _KpiPlanComparison(result: result),
      const SizedBox(height: 12),
      if (_canEdit &&
          _stored.settings['incident_counts'] is Map &&
          (_stored.settings['incident_counts'] as Map).isNotEmpty &&
          !_period.start.isAfter(kpiDate(DateTime.now())))
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _editIncidents,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Review Legacy PM Counts'),
          ),
        ),
      if (incidentRatingRows.isNotEmpty) ...[
        const _KpiSectionTitle(title: 'Other Crew / Unassigned Incidents'),
        const SizedBox(height: 8),
        AdminListItemCard(
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
            },
            children: [
              for (final values in <List<String>>[
                ['Metric', 'Actual', 'Rating'],
                ...incidentRatingRows,
              ])
                TableRow(
                  children: [
                    for (final value in values)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 4,
                        ),
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: values.first == 'Metric'
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      const _KpiSectionTitle(title: 'Transaction History'),
      const SizedBox(height: 12),
    ];
    List<String> transactionValues(int i) {
      final row = activityRows[i];
      final day = row.day;
      final rates =
          (day.estimate?.rates ?? day.record['trip_rates'] as List? ?? [])
              .whereType<Map>();
      final trip = row.trip;
      final rate = trip == null
          ? null
          : rates
                .where((rate) => rate['signature'] == trip.signature)
                .firstOrNull;
      double? expense(String role) {
        if (trip != null) {
          return rate == null ? null : kpiMoney(rate[role]);
        }
        final total = role == 'driver' ? day.driverSalary : day.helperSalary;
        final shares = rates.fold<double>(
          0,
          (sum, rate) => sum + (kpiMoney(rate[role]) ?? 0),
        );
        return total - shares;
      }

      String signedAmount(double? amount) {
        if (amount == null) {
          return 'Rate missing';
        }
        return _kpiAmount(amount);
      }

      final driverExpense = expense('driver');
      final helperExpense = expense('helper');
      final totalExpense = driverExpense == null || helperExpense == null
          ? null
          : driverExpense + helperExpense;

      return [
        trip == null
            ? '${_kpiDateLabel(day.date).split(',').first} Pay'
            : 'Booking ${trip.booking.id ?? trip.identity}',
        signedAmount(driverExpense),
        signedAmount(helperExpense),
        signedAmount(totalExpense),
        trip == null ? 'Salary' : 'Share',
        day.salaryComplete ? 'Confirmed' : 'Unconfirmed',
        activityDate(i),
        '',
      ];
    }

    List<String> displayValues(int i) {
      final row = displayRows[i];
      if (row.transaction != null) return transactionValues(row.transaction!);
      final day = row.day;
      String amount(double value) => _kpiAmount(value);
      return [
        _kpiDateLabel(day.date),
        amount(day.driverSalary),
        amount(day.helperSalary),
        amount(day.driverSalary + day.helperSalary),
        'Total',
        day.salaryComplete ? 'Confirmed' : 'Unconfirmed',
        '',
        '',
      ];
    }

    Future<void> exportReport() async {
      if (_exporting || !_store.canRead || !_store.canReadBookings) return;
      final period = _period;
      final confirmed = await showAdminActionConfirmation(
        context,
        title: 'Export KPI',
        message:
            'Export KPI for all vehicles from ${_kpiDateLabel(period.start)} '
            'to ${_kpiDateLabel(period.end)} as an Excel file?',
        confirmLabel: 'Export',
      );
      if (!confirmed || !mounted || !context.mounted || _exporting) return;
      setState(() => _exporting = true);
      try {
        final bytes = await KpiFleetWorkbook.export(
          store: _store,
          period: period,
        );
        if (!mounted || !context.mounted) return;
        final name = 'KPI-${kpiDayKey(period.start)}-${kpiDayKey(period.end)}'
            .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
        final exported = await ExportFileService.export(
          context,
          bundleFileName: '$name.zip',
          files: {'$name.xlsx': bytes},
        );
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(exported.message)));
        }
      } catch (error, stack) {
        unawaited(
          SyncErrorLogService.instance.report(
            error,
            stack,
            source: 'pm_kpi_dialog.dart',
            operation: 'export KPI workbook',
          ),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
        }
      } finally {
        if (mounted) setState(() => _exporting = false);
      }
    }

    return AdminModalShell(
      title: '${widget.make.code ?? "PM ${widget.make.id}"} KPI',
      maxWidth: 900,
      bodyHandlesScrolling: true,
      flexibleBody: true,
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryColor),
          onPressed:
              _loading ||
                  _exporting ||
                  !_store.canRead ||
                  !_store.canReadBookings ||
                  !_store.canReadFuel ||
                  !_store.canReadIncome
              ? null
              : exportReport,
          child: Text(_exporting ? 'Exporting...' : 'Export'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryColor),
          onPressed: _loading
              ? null
              : () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: kpiSalaryDiagnostics(
                        makeId: widget.make.id ?? '',
                        bookings: _bookings,
                        makes: _store.makes,
                        catalog: _stored.catalog,
                        result: result,
                        verified: _store.bookingsVerified && !_stored.fromCache,
                      ),
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Salary diagnostics copied'),
                      ),
                    );
                  }
                },
          child: const Text('Copy'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _kpiContentSpacing,
              ),
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.axis == Axis.vertical &&
                      ((notification is ScrollUpdateNotification &&
                              (notification.scrollDelta ?? 0) > 0) ||
                          (notification is OverscrollNotification &&
                              notification.overscroll > 0))) {
                    _loadMoreActivities();
                  }
                  return false;
                },
                child: AdminModalRecordList(
                  scrollController: _activityScroll,
                  scrollHeader: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: header,
                  ),
                  scrollFooter: activeDays.isEmpty
                      ? const Text(
                          'No delivered trips or recorded expenses in this period.',
                        )
                      : null,
                  horizontalOnDesktop: true,
                  trailingActions: true,
                  titles: const [
                    'Label',
                    'Driver',
                    'Helper',
                    'Amount',
                    'Type',
                    'Status',
                    'DateTime',
                    'Actions',
                  ],
                  itemCount: displayRows.length.clamp(0, _visibleActivities),
                  columnExtraWidths: const {7: 40},
                  valuesAt: displayValues,
                  rowGroupKey: (i) => kpiDayKey(displayRows[i].day.date),
                  cellBuilder: (i, col) {
                    final displayed = displayRows[i];
                    final day = displayed.day;
                    final transaction = displayed.transaction;
                    if (transaction == null) {
                      if (col == 0) {
                        return InkWell(
                          key: ValueKey('kpi-expand-${kpiDayKey(day.date)}'),
                          onTap: () => toggleDay(day),
                          child: Text(
                            _kpiDateLabel(day.date),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        );
                      }
                      if (col == 7) {
                        final expanded = _expandedDays.contains(
                          kpiDayKey(day.date),
                        );
                        return Tooltip(
                          message: expanded
                              ? 'Collapse transactions'
                              : 'Expand transactions',
                          child: AdminListActionButton(
                            icon: expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            onTap: () => toggleDay(day),
                          ),
                        );
                      }
                      if (col >= 1 && col <= 3) {
                        final text = displayValues(i)[col];
                        return Text(
                          text,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color:
                                (text.startsWith('₱') && text != _kpiAmount(0))
                                ? Colors.green.shade700
                                : text.startsWith('−')
                                ? AppColors.dangerStrong
                                : AppColors.textSecondary,
                          ),
                        );
                      }
                      return null;
                    }
                    final row = activityRows[transaction];
                    if (col == 0 && row.trip == null) {
                      return Text(
                        transactionValues(transaction)[0],
                        style: const TextStyle(
                          color: AppColors.primaryColor,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }
                    if (col == 0 && row.trip != null) {
                      return RecordTextLink(
                        label:
                            'Booking ${row.trip!.booking.id ?? row.trip!.identity}',
                        onTap:
                            _store.canReadBookings &&
                                _currentUser != null &&
                                widget.onOpenBooking != null
                            ? () => widget.onOpenBooking!(
                                _currentUser!,
                                row.trip!.booking,
                              )
                            : null,
                      );
                    }
                    final editable =
                        _canEdit && !day.date.isAfter(kpiDate(DateTime.now()));
                    if (col >= 1 && col <= 3) {
                      final text = transactionValues(transaction)[col];
                      return Text(
                        text,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: (text.startsWith('₱') && text != _kpiAmount(0))
                              ? Colors.green.shade700
                              : text.startsWith('−')
                              ? AppColors.dangerStrong
                              : AppColors.textSecondary,
                        ),
                      );
                    }
                    if (col == 6) {
                      return InkWell(
                        key: ValueKey(
                          row.showDailyTotals
                              ? 'kpi-day-${kpiDayKey(day.date)}'
                              : 'kpi-trip-${row.trip!.identity}',
                        ),
                        onTap: editable
                            ? () => _editDay(day, trip: row.trip)
                            : null,
                        child: Text(
                          activityDate(transaction),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      );
                    }
                    if (col == 7 && editable) {
                      return Tooltip(
                        message: row.trip == null
                            ? 'Edit salary'
                            : 'Edit trip share',
                        child: AdminListActionButton(
                          icon: Icons.edit_outlined,
                          onTap: () => _editDay(day, trip: row.trip),
                        ),
                      );
                    }
                    return null;
                  },
                ),
              ),
            ),
    );
  }
}

class _KpiDayDialog extends StatefulWidget {
  const _KpiDayDialog({
    required this.day,
    required this.makeId,
    required this.store,
    required this.matrix,
    this.trip,
  });
  final KpiTrip? trip;
  final TripMatrixVersion matrix;
  final KpiDay day;
  final String makeId;
  final PmKpiStore store;
  @override
  State<_KpiDayDialog> createState() => _KpiDayDialogState();
}

class _KpiDayDialogState extends State<_KpiDayDialog> {
  late final TextEditingController _fuel;
  late final TextEditingController _ref;
  late final TextEditingController _fulls;
  late final TextEditingController _empties;
  late final List<KpiTrip> _trips;
  late TripMatrixVersion _matrix;
  final Map<String, String> _routes = {};
  bool _fuelConfirmed = false;
  bool _salaryConfirmed = false;
  bool _saving = false;
  bool _salaryChanged = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final record = widget.day.record;
    _matrix = widget.day.salaryComplete && record['matrix_snapshot'] is Map
        ? TripMatrixVersion.fromMap(record['matrix_snapshot'] as Map)
        : widget.matrix;
    _fuel = TextEditingController(text: record['fuel']?.toString() ?? '');
    _ref = TextEditingController(
      text: record['fuel_reference']?.toString() ?? '',
    );
    _fulls = TextEditingController(
      text: (record['hustling_fulls'] ?? 0).toString(),
    );
    _empties = TextEditingController(
      text: (record['hustling_empties'] ?? 0).toString(),
    );
    _fuelConfirmed = widget.day.fuelComplete;
    _salaryConfirmed = widget.day.salaryComplete;
    _trips = [...widget.day.trips]
      ..sort((a, b) {
        final date = (kpiDeliveredAt(
          a.booking,
        )!).compareTo(kpiDeliveredAt(b.booking)!);
        return date != 0 ? date : a.identity.compareTo(b.identity);
      });
    final saved = record['trip_rates'];
    for (final trip in _trips) {
      final match = saved is List
          ? saved
                .whereType<Map>()
                .where((r) => r['signature'] == trip.signature)
                .firstOrNull
          : null;
      final route = match?['route']?.toString();
      final exact = matchKpiTripRate(trip, _matrix.rates).rate;
      if (route != null && _matrix.rates.any((r) => r.name == route)) {
        _routes[trip.identity] = route;
      } else if (exact != null) {
        _routes[trip.identity] = exact.name;
      }
    }
  }

  @override
  void dispose() {
    _fuel.dispose();
    _ref.dispose();
    _fulls.dispose();
    _empties.dispose();
    super.dispose();
  }

  ({double driver, double helper, List<Map<String, dynamic>> rates}) _salary() {
    if (!_salaryChanged && widget.day.salaryComplete) {
      final savedRates = widget.day.record['trip_rates'];
      return (
        driver: widget.day.driverSalary,
        helper: widget.day.helperSalary,
        rates: savedRates is List
            ? savedRates
                  .whereType<Map>()
                  .map((r) => Map<String, dynamic>.from(r))
                  .toList()
            : [],
      );
    }
    return kpiSalary(
      _trips,
      _routes,
      matrix: _matrix.rates,
      dailyRate: _matrix.pay.daily,
      cityAfter: _matrix.pay.cityAfter,
      cityDriverRate: _matrix.pay.cityDriver,
      cityHelperRate: _matrix.pay.cityHelper,
      fullDriverRate: _matrix.pay.fullDriver,
      fullHelperRate: _matrix.pay.fullHelper,
      emptyDriverRate: _matrix.pay.emptyDriver,
      emptyHelperRate: _matrix.pay.emptyHelper,
      fulls: int.tryParse(_fulls.text) ?? 0,
      empties: int.tryParse(_empties.text) ?? 0,
    );
  }

  Future<void> _save() async {
    final fuel = kpiMoney(_fuel.text);
    if ((fuel ?? 0) > 0 &&
        widget.day.record['fuel_source'] != 'ledger' &&
        fuel != kpiMoney(widget.day.record['fuel'])) {
      setState(() {
        _error =
            'Add refueling through Fuel Requests first, then confirm its daily total here.';
      });
      return;
    }
    final fulls = int.tryParse(_fulls.text);
    final empties = int.tryParse(_empties.text);
    final missingCrew = _trips.any(
      (t) =>
          (t.booking.driver?.id ?? '').isEmpty ||
          (t.booking.helper?.id ?? '').isEmpty,
    );
    if ((_fuelConfirmed && fuel == null) ||
        fulls == null ||
        fulls < 0 ||
        empties == null ||
        empties < 0 ||
        (_salaryConfirmed &&
            (_routes.length != _trips.length || missingCrew)) ||
        (_trips.isEmpty && (fulls != 0 || empties != 0))) {
      setState(() {
        _error =
            'Enter valid amounts/counts and select a route and crew for every delivered trip before confirming salary.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final salary = _salary();
    try {
      await widget.store.save(
        makeId: widget.makeId,
        previous: widget.day.record,
        data: {
          'kind': 'day',
          'day': kpiDayKey(widget.day.date),
          'fuel': fuel,
          'fuel_reference': _ref.text.trim(),
          'fuel_confirmed': _fuelConfirmed,
          'salary_confirmed': _salaryConfirmed,
          'driver_salary': salary.driver,
          'helper_salary': salary.helper,
          'daily_rate': _matrix.pay.daily,
          'matrix_version': _matrix.id,
          'matrix_snapshot': _matrix.toMap(),
          if (widget.day.record['fuel_source'] == 'ledger') ...{
            'fuel_source': 'ledger',
            'fuel_signature': widget.day.record['fuel_signature_live'],
          },
          'hustling_fulls': fulls,
          'hustling_empties': empties,
          'trip_signature': widget.day.signature,
          'trip_rates': salary.rates,
        },
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error, stack) {
      unawaited(
        SyncErrorLogService.instance.report(
          error,
          stack,
          source: 'pm_kpi_dialog.dart',
          operation: 'handled operation failure',
        ),
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: RoleAccessService.instance,
    builder: (context, _) => !widget.store.canEdit
        ? const AdminModalShell(
            title: 'Salary & Trip Shares',
            child: Text('You do not have access to edit PM KPIs.'),
          )
        : _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final salary = _salary();
    String locationLabel(List<String> parts) {
      final values = parts
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty && part != '-' && part != '—')
          .toSet();
      if (values.length > 1) {
        values.removeWhere(
          (value) => RegExp(
            r'^Puerto\s+Princesa(?:\s+City)?$',
            caseSensitive: false,
          ).hasMatch(value),
        );
      }
      return values.isEmpty
          ? 'Not recorded'
          : locationDisplayLabel(values.join(', '));
    }

    String shareLabel(KpiTrip trip, String role) {
      final rate = salary.rates
          .where((rate) => rate['signature'] == trip.signature)
          .firstOrNull;
      final amount = rate == null ? null : kpiMoney(rate[role]);
      return amount == null ? 'Select a rate' : _kpiAmount(amount);
    }

    Widget detail(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
    return AdminModalShell(
      title: widget.trip == null
          ? 'Salary · ${_kpiDateLabel(widget.day.date)}'
          : 'Trip Share · Booking ${widget.trip!.booking.id ?? widget.trip!.identity}',
      maxWidth: 560,
      flexibleBody: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
      child: AdminModalFieldsSection(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          for (final trip in _trips.where(
            (trip) => trip.identity == widget.trip?.identity,
          ))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  detail(
                    'Pickup',
                    locationLabel([trip.originBarangay, trip.origin]),
                  ),
                  detail(
                    'Drop-off',
                    locationLabel([trip.destinationBarangay, trip.destination]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Trip-share rate',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  AdminSearchSelectFormField(
                    initialValue: _routes[trip.identity],
                    dialogTitle: 'Trip-share rate',
                    decoration: adminPlainDropdownDecoration(
                      'Select Rate location',
                    ),
                    options: _matrix.rates
                        .where(
                          (r) => r.active || r.name == _routes[trip.identity],
                        )
                        .map((rate) => rate.name)
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _routes[trip.identity] = v;
                          _salaryConfirmed = false;
                          _salaryChanged = true;
                        });
                      }
                    },
                  ),
                  detail('Driver', trip.booking.driver?.name ?? 'Not assigned'),
                  detail('Driver share', shareLabel(trip, 'driver')),
                  detail('Helper', trip.booking.helper?.name ?? 'Not assigned'),
                  detail('Helper share', shareLabel(trip, 'helper')),
                ],
              ),
            ),
          if (widget.trip == null) ...[
            AdminModalValueTextField(
              initialValue: _fulls.text,
              keyboardType: TextInputType.number,
              label: 'Additional hustling — full trips',
              onChanged: (value) => setState(() {
                _fulls.text = value;
                _salaryConfirmed = false;
                _salaryChanged = true;
              }),
            ),
            AdminModalValueTextField(
              initialValue: _empties.text,
              keyboardType: TextInputType.number,
              label: 'Additional hustling — empty trips',
              onChanged: (value) => setState(() {
                _empties.text = value;
                _salaryConfirmed = false;
                _salaryChanged = true;
              }),
            ),
            const SizedBox(height: 12),
            Text(
              'Driver: ₱${(salary.driver - salary.rates.fold<double>(0, (sum, rate) => sum + (kpiMoney(rate['driver']) ?? 0))).toStringAsFixed(2)} · Helper: ₱${(salary.helper - salary.rates.fold<double>(0, (sum, rate) => sum + (kpiMoney(rate['helper']) ?? 0))).toStringAsFixed(2)}',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Confirm daily salary and trip totals'),
              value: _salaryConfirmed,
              onChanged: (v) => setState(() {
                _salaryConfirmed = v ?? false;
              }),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mirrors the workbook: consistent line items, selected total, then weeks.
class _KpiFinancialTable extends StatelessWidget {
  const _KpiFinancialTable({
    required this.columns,
    this.showAllColumns = false,
  });
  final bool showAllColumns;
  final List<(String, PmKpi)> columns;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, double Function(PmKpi), bool)>[
      ('Revenue', (r) => r.revenue, true),
      ('Fuel', (r) => r.fuel, false),
      ('Total salary', (r) => r.driverSalary + r.helperSalary, false),
      ('Truck depreciation', (r) => r.depreciation, false),
      ('Maintenance', (r) => r.maintenance, false),
      ('Total expenses', (r) => r.expenses, true),
      ('Gross income (actual)', (r) => r.gross, true),
      (
        'Target gross income (${columns.first.$2.ratingRules.targetLabel}%)',
        (r) => r.marginTarget,
        false,
      ),
      ('Favorable / Unfavorable', (r) => r.marginVariance, true),
    ];
    Widget cell(
      String text, {
      bool heading = false,
      bool label = false,
      bool negative = false,
      bool header = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text,
        textAlign: label ? TextAlign.left : TextAlign.right,
        style: TextStyle(
          fontSize: 14,
          fontWeight: heading ? FontWeight.w700 : FontWeight.w500,
          color: header
              ? Colors.white
              : negative
              ? AppColors.dangerStrong
              : heading
              ? AppColors.primaryColor
              : AppColors.textPrimary,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600 &&
            columns.length > 1 &&
            !showAllColumns) {
          return Column(
            children: [
              _KpiFinancialTable(columns: [columns.first]),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Compare Week 1–4'),
                children: [
                  _KpiFinancialTable(
                    columns: columns.skip(1).toList(),
                    showAllColumns: true,
                  ),
                ],
              ),
            ],
          );
        }
        final wide = columns.length > 1;
        final tableWidth = wide
            ? 210.0 + columns.length * 128
            : constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                width: tableWidth,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  columnWidths: {
                    0: wide
                        ? const FixedColumnWidth(210)
                        : const FlexColumnWidth(1.25),
                    for (var i = 0; i < columns.length; i++)
                      i + 1: wide
                          ? const FixedColumnWidth(128)
                          : const FlexColumnWidth(),
                  },
                  border: const TableBorder(
                    horizontalInside: BorderSide(
                      color: AppColors.primaryBorder,
                    ),
                  ),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(
                        color: AppColors.primaryColor,
                      ),
                      children: [
                        cell('Item', heading: true, label: true, header: true),
                        for (final column in columns)
                          cell(column.$1, heading: true, header: true),
                      ],
                    ),
                    for (final row in rows)
                      TableRow(
                        decoration: BoxDecoration(
                          color:
                              const {
                                'Revenue',
                                'Total expenses',
                                'Gross income (actual)',
                                'Favorable / Unfavorable',
                              }.contains(row.$1)
                              ? AppColors.primarySurface
                              : Colors.white,
                        ),
                        children: [
                          cell(row.$1, heading: row.$3, label: true),
                          for (final column in columns)
                            cell(
                              _kpiAmount(row.$2(column.$2)),
                              heading: row.$3,
                              negative: row.$2(column.$2) < 0,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KpiPlanComparison extends StatelessWidget {
  const _KpiPlanComparison({required this.result});
  final PmKpi result;

  @override
  Widget build(BuildContext context) {
    final ratingLabel = result.revenue > 0
        ? '${(result.gross / result.revenue * 100).toStringAsFixed(2)}% (${result.rating})'
        : result.rating;
    final rows = [
      ('Revenue', result.revenue, result.revenueTarget),
      ('Gross Income', result.gross, result.profitTarget),
    ];
    Widget cell(String value, {bool heading = false, bool metric = false}) =>
        Container(
          color: metric
              ? AppColors.primarySurface
              : heading
              ? AppColors.primaryColor
              : Colors.white,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: heading ? FontWeight.w700 : FontWeight.w500,
              color: heading && !metric
                  ? Colors.white
                  : value.startsWith('−') || value.startsWith('-')
                  ? AppColors.dangerStrong
                  : metric
                  ? AppColors.primaryColor
                  : null,
            ),
          ),
        );
    return AdminListItemCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cell(ratingLabel, heading: true),
                  for (final row in rows) ...[
                    if (row != rows.first)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.primaryBorder,
                      ),
                    cell(row.$1, heading: true, metric: true),
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(),
                        1: FlexColumnWidth(2),
                      },
                      children: [
                        for (final value in [
                          ('Target', row.$3),
                          ('Current', row.$2),
                          ('Difference', row.$2 - row.$3),
                        ])
                          TableRow(
                            children: [
                              TableCell(
                                verticalAlignment:
                                    TableCellVerticalAlignment.fill,
                                child: cell(value.$1, heading: true),
                              ),
                              cell(_kpiAmount(value.$2)),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              );
            }
            return Table(
              border: const TableBorder(
                horizontalInside: BorderSide(color: AppColors.primaryBorder),
              ),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: const BoxDecoration(
                    color: AppColors.primaryColor,
                  ),
                  children: [
                    for (final title in [
                      ratingLabel,
                      'Target',
                      'Current',
                      'Difference',
                    ])
                      cell(title, heading: true),
                  ],
                ),
                for (final row in rows)
                  TableRow(
                    children: [
                      TableCell(
                        verticalAlignment: TableCellVerticalAlignment.fill,
                        child: cell(row.$1, heading: true, metric: true),
                      ),
                      cell(_kpiAmount(row.$3)),
                      cell(_kpiAmount(row.$2)),
                      cell(_kpiAmount(row.$2 - row.$3)),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
