import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/kpi/crew_kpi_store.dart';
import 'package:webapp/services/kpi/kpi_period_label.dart';
import 'package:webapp/services/kpi/kpi_rating_rules.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';

/// Metrics for the current month shown on a crew member's profile.
///
/// The same personal projection used by the full KPI screen is used here. No
/// fleet-wide data is calculated for the profile summary.
class CrewKpiSummaryMetrics {
  const CrewKpiSummaryMetrics({
    required this.period,
    required this.complaints,
    required this.accidents,
    required this.bookings,
    required this.shares,
    required this.salary,
    required this.complaintsRating,
    required this.accidentsRating,
  });

  factory CrewKpiSummaryMetrics.fromData({
    required UserModel user,
    required Map<String, dynamic> data,
    DateTime? now,
  }) {
    final today = kpiDate(now ?? DateTime.now());
    final period = KpiPeriod.month(today.year, today.month);
    final rows = crewKpiTransactions(user, data)
        .where((row) {
          final day = DateTime.tryParse('${row['day']}T00:00:00Z');
          return day != null && !day.isAfter(today) && period.contains(day);
        })
        .toList(growable: false);

    double amountFor(Map<String, dynamic> row) =>
        (row['amount'] as num?)?.toDouble() ?? 0;
    final shares = rows
        .where((row) => row['type'] == 'Share')
        .fold<double>(0, (sum, row) => sum + amountFor(row));
    final salary = rows
        .where((row) => row['type'] == 'Salary')
        .fold<double>(0, (sum, row) => sum + amountFor(row));
    final bookings = rows
        .where((row) => row['type'] == 'Share')
        .map((row) => row['booking_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;

    var complaints = 0;
    var accidents = 0;
    for (final raw
        in (data['incidents'] as List? ?? const []).whereType<Map>()) {
      final day = DateTime.tryParse('${raw['day']}T00:00:00Z');
      if (day == null || day.isAfter(today) || !period.contains(day)) {
        continue;
      }
      complaints += (raw['complaints'] as num?)?.toInt() ?? 0;
      accidents += (raw['accidents'] as num?)?.toInt() ?? 0;
    }

    final rules = KpiRatingRules.fromMap({
      'rating_rules': data['rating_rules'] ?? const <String, dynamic>{},
    });
    return CrewKpiSummaryMetrics(
      period: period,
      complaints: complaints,
      accidents: accidents,
      bookings: bookings,
      shares: shares,
      salary: salary,
      complaintsRating: rules.complaintsRating(complaints),
      accidentsRating: rules.accidentsRating(accidents),
    );
  }

  final KpiPeriod period;
  final int complaints;
  final int accidents;
  final int bookings;
  final double shares;
  final double salary;
  final String complaintsRating;
  final String accidentsRating;

  double get total => shares + salary;
}

/// A compact, read-only KPI summary embedded in a driver's or helper's profile.
class CrewKpiProfileSummary extends StatefulWidget {
  const CrewKpiProfileSummary({
    super.key,
    required this.user,
    this.store,
    this.network,
    this.allowed,
    this.onOpenTracking,
  });

  final UserModel user;
  final CrewKpiStore? store;
  final Stream<bool>? network;
  final bool Function()? allowed;
  final VoidCallback? onOpenTracking;

  @override
  State<CrewKpiProfileSummary> createState() => _CrewKpiProfileSummaryState();
}

class _CrewKpiProfileSummaryState extends State<CrewKpiProfileSummary> {
  late final CrewKpiStore _defaultStore = CrewKpiStore();
  CrewKpiSummaryMetrics? _metrics;
  StreamSubscription<bool>? _networkSubscription;
  Future<void>? _loadingFuture;
  int _loadGeneration = 0;
  bool _loading = true;
  bool _active = true;
  bool _rerun = false;
  String? _error;

  CrewKpiStore get _store => widget.store ?? _defaultStore;

  bool get _allowed =>
      widget.allowed?.call() ?? CrewKpiStore.canView(widget.user);

  @override
  void initState() {
    super.initState();
    RoleAccessService.instance.addListener(_permissionChanged);
    _networkSubscription = (widget.network ?? networkStatusEvents())
        .distinct()
        .listen((_) => _changed());
    unawaited(load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasActive = _active;
    _active = TickerMode.valuesOf(context).enabled;
    if (_active && !wasActive) {
      _changed();
    }
  }

  @override
  void didUpdateWidget(covariant CrewKpiProfileSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.user.role != widget.user.role ||
        oldWidget.store != widget.store) {
      _metrics = null;
      _error = null;
      _loading = true;
      _restartLoad();
    }
  }

  void _restartLoad() {
    _loadGeneration++;
    _loadingFuture = null;
    _rerun = false;
    unawaited(load());
  }

  void _permissionChanged() {
    if (!mounted) return;
    if (!_allowed) {
      _loadGeneration++;
      setState(() {
        _metrics = null;
        _loading = false;
        _error = null;
        _rerun = false;
      });
    } else {
      _changed();
    }
  }

  void _changed() {
    if (!_active || !_allowed) return;
    if (_loadingFuture != null) {
      _rerun = true;
      return;
    }
    unawaited(load());
  }

  @override
  void dispose() {
    _loadGeneration++;
    RoleAccessService.instance.removeListener(_permissionChanged);
    unawaited(_networkSubscription?.cancel());
    super.dispose();
  }

  Future<void> load() {
    final existing = _loadingFuture;
    if (existing != null) return existing;
    final future = _load();
    _loadingFuture = future;
    unawaited(
      future.whenComplete(() {
        if (!identical(_loadingFuture, future)) return;
        _loadingFuture = null;
        if (_rerun && mounted && _allowed && _active) {
          _rerun = false;
          unawaited(load());
        }
      }),
    );
    return future;
  }

  Future<void> _load() async {
    final user = widget.user;
    final store = _store;
    final generation = _loadGeneration;
    bool isCurrent() =>
        mounted &&
        _loadGeneration == generation &&
        identical(_store, store) &&
        widget.user.id == user.id &&
        widget.user.role == user.role &&
        _allowed;

    if (!_allowed) {
      if (mounted) {
        setState(() {
          _loading = false;
          _metrics = null;
        });
      }
      return;
    }

    setState(() {
      _error = null;
      _loading = _metrics == null;
    });

    void apply(Map<String, dynamic> next) {
      if (!isCurrent()) return;
      final metrics = CrewKpiSummaryMetrics.fromData(user: user, data: next);
      if (!isCurrent()) return;
      setState(() {
        _metrics = metrics;
        _loading = false;
      });
    }

    // A broken or slow cache must not prevent a fresh online read. The store
    // still performs its own current-user authorization checks.
    try {
      final cached = await store
          .readCached(user)
          .timeout(const Duration(seconds: 5));
      if (!isCurrent()) return;
      if (cached != null) apply(cached);
    } catch (_) {
      // Continue with the network read below.
    }

    try {
      final fresh = await store.load(user).timeout(const Duration(seconds: 30));
      if (!isCurrent()) return;
      if (fresh != null) apply(fresh);
    } catch (error) {
      if (isCurrent()) {
        setState(() {
          _error = error is TimeoutException
              ? 'KPI data is taking longer to load. Please try again.'
              : 'Could not refresh your KPI. Please try again.';
        });
      }
    } finally {
      if (isCurrent()) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return AdminListItemCard(
        child: Text(
          'You do not have access to KPI Tracking.',
          style: TextStyle(
            color: AppColors.primaryColor.withValues(alpha: 0.72),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final metrics = _metrics;
    if (metrics == null) {
      return AdminListItemCard(
        child: Row(
          children: [
            if (_loading) ...[
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                _loading
                    ? 'Loading KPI summary...'
                    : _error ?? 'No KPI data is available yet.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (!_loading)
              TextButton(onPressed: load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final metricsList = <({String label, String value})>[
      (
        label: 'Complaints',
        value: '${metrics.complaints} (${metrics.complaintsRating})',
      ),
      (
        label: 'Accidents',
        value: '${metrics.accidents} (${metrics.accidentsRating})',
      ),
      (label: 'Bookings', value: '${metrics.bookings}'),
      (label: 'Shares', value: _formatMoney(metrics.shares)),
      (label: 'Salary', value: _formatMoney(metrics.salary)),
      (label: 'Total', value: _formatMoney(metrics.total)),
    ];

    return AdminListItemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KPI summary',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      kpiPeriodLabel(metrics.period, mode: 'Monthly'),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onOpenTracking != null)
                TextButton(
                  onPressed: widget.onOpenTracking,
                  child: const Text('View full KPI'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760
                  ? 3
                  : constraints.maxWidth >= 480
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final metric in metricsList)
                    SizedBox(
                      width: width,
                      child: _CrewKpiMetricTile(
                        label: metric.label,
                        value: metric.value,
                      ),
                    ),
                ],
              );
            },
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Refreshing KPI...'),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
                TextButton(onPressed: load, child: const Text('Retry')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CrewKpiMetricTile extends StatelessWidget {
  const _CrewKpiMetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.primaryColor.withValues(alpha: 0.72),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMoney(num value) {
  final parts = value.abs().toStringAsFixed(2).split('.');
  final digits = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
  return '${value < 0 ? '−' : ''}₱$digits${parts.last == '00' ? '' : '.${parts.last}'}';
}
