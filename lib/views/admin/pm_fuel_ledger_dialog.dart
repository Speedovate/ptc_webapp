import 'dart:async';
import 'package:webapp/services/sync_error_log_service.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';

Future<void> showFuelLedger(
  BuildContext context, {
  required VehicleMake make,
  required KpiPeriod period,
  required PmKpiStore store,
}) => showAppDialog<void>(
  context: context,
  modalKey: 'fuel-ledger:${make.id}',
  builder: (_) => PmFuelLedgerDialog(make: make, period: period, store: store),
);

class PmFuelLedgerDialog extends StatefulWidget {
  const PmFuelLedgerDialog({
    super.key,
    required this.make,
    required this.period,
    required this.store,
    this.onBack,
  });
  final VehicleMake make;
  final KpiPeriod period;
  final PmKpiStore store;
  final VoidCallback? onBack;
  @override
  State<PmFuelLedgerDialog> createState() => _PmFuelLedgerDialogState();
}

class _PmFuelLedgerDialogState extends State<PmFuelLedgerDialog> {
  KpiStoredData? _data;
  bool _busy = true;
  int _visibleRows = 15;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!widget.store.canReadFuel) {
        throw StateError('You do not have access to fuel requests.');
      }
      final data = await widget.store.load(widget.make.id!, widget.period);
      if (mounted) {
        setState(() {
          _data = data;
          _busy = false;
          _error = null;
        });
      }
    } catch (e, stack) {
      unawaited(
        SyncErrorLogService.instance.report(
          e,
          stack,
          source: 'pm_fuel_ledger_dialog.dart',
          operation: 'handled operation failure',
        ),
      );
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _edit([Map<String, dynamic> entry = const {}]) async {
    final saved = await showAppDialog<bool>(
      context: context,
      builder: (_) => FuelEntryDialog(
        makeId: widget.make.id!,
        entry: entry,
        store: widget.store,
        days: _data?.records ?? [],
        initialDate: widget.period.contains(kpiDate(DateTime.now()))
            ? kpiDate(DateTime.now())
            : widget.period.start,
      ),
    );
    if (saved == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: RoleAccessService.instance,
    builder: (context, _) => !widget.store.canReadFuel
        ? AdminModalShell(
            actions: [
              TextButton(
                onPressed: widget.onBack ?? () => Navigator.pop(context),
                child: Text(widget.onBack == null ? 'Close' : 'Back to KPI'),
              ),
            ],
            title: 'Fuel Requests',
            child: Text('You do not have access to fuel requests.'),
          )
        : _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final rows =
        (_data?.fuel ?? []).where((r) {
            final date = DateTime.tryParse('${r['day']}T00:00:00Z');
            return date != null && widget.period.contains(date);
          }).toList()
          ..sort((a, b) => b['day'].toString().compareTo(a['day'].toString()));
    return AdminModalShell(
      title: '${widget.make.code ?? "PM"} Fuel Requests',
      maxWidth: 1200,
      flexibleBody: true,
      bodyHandlesScrolling: true,
      actions: [
        if (widget.store.canEditFuel && !_busy && _data != null)
          FilledButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Add fuel'),
          ),
        TextButton(
          onPressed: widget.onBack ?? () => Navigator.pop(context),
          child: Text(widget.onBack == null ? 'Close' : 'Back to KPI'),
        ),
      ],
      child: _busy
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.axis == Axis.vertical &&
                      notification.metrics.extentAfter < 240 &&
                      ((notification is ScrollUpdateNotification &&
                              (notification.scrollDelta ?? 0) > 0) ||
                          (notification is OverscrollNotification &&
                              notification.overscroll > 0)) &&
                      _visibleRows < rows.length) {
                    setState(
                      () => _visibleRows = (_visibleRows + 15).clamp(
                        0,
                        rows.length,
                      ),
                    );
                  }
                  return false;
                },
                child: AdminModalRecordList(
                  scrollHeader: _error == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: AppColors.danger),
                          ),
                        ),
                  scrollFooter: rows.isEmpty
                      ? const Text('No fuel requests in this period.')
                      : _visibleRows < rows.length
                      ? Text(
                          'Showing $_visibleRows of ${rows.length} · Pull up to load more',
                        )
                      : null,
                  titles: const [
                    'Date',
                    'Reference',
                    'Supplier',
                    'Liters',
                    'Price / Liter',
                    'Amount',
                    'Notes / Route',
                    'Status',
                    'Actions',
                  ],
                  itemCount: rows.length.clamp(0, _visibleRows),
                  trailingActions: true,
                  horizontalOnDesktop: true,
                  wrappingColumn: 6,
                  columnExtraWidths: const {8: 40},
                  valuesAt: (i) {
                    final r = rows[i];
                    return [
                      AdminUsersView.formatCreatedAt(
                        DateTime.tryParse('${r['day']}T00:00:00'),
                      ),
                      '${r['reference'] ?? "—"}',
                      '${r['supplier'] ?? "—"}',
                      '${r['liters'] ?? "—"}',
                      kpiMoney(r['price_per_liter']) == null
                          ? '—'
                          : '₱${kpiMoney(r['price_per_liter'])!.toStringAsFixed(2)}',
                      '₱${(kpiMoney(r['amount']) ?? 0).toStringAsFixed(2)}',
                      '${r['notes'] ?? '—'}',
                      r['voided'] == true
                          ? 'Voided'
                          : r['local_sync_status'] != null
                          ? 'Queued'
                          : 'Active',
                      '',
                    ];
                  },
                  cellBuilder: (i, column) => column == 8
                      ? Tooltip(
                          message: 'View fuel entry',
                          child: AdminListActionButton(
                            icon: Icons.visibility_outlined,
                            onTap: () => _edit(rows[i]),
                          ),
                        )
                      : null,
                ),
              ),
            ),
    );
  }
}

class FuelEntryDialog extends StatefulWidget {
  const FuelEntryDialog({
    super.key,
    required this.makeId,
    required this.entry,
    required this.store,
    required this.days,
    required this.initialDate,
  });
  final String makeId;
  final Map<String, dynamic> entry;
  final PmKpiStore store;
  final List<Map<String, dynamic>> days;
  final DateTime initialDate;
  @override
  State<FuelEntryDialog> createState() => _FuelEntryDialogState();
}

class _FuelEntryDialogState extends State<FuelEntryDialog> {
  final _form = GlobalKey<FormState>();
  late DateTime _date;
  late final Map<String, TextEditingController> _fields;
  bool _saving = false;
  bool _voided = false;
  String? _error;
  static const labels = {
    'reference': 'PO / receipt reference',
    'supplier': 'Supplier / station',
    'liters': 'Liters (optional)',
    'price_per_liter': 'Price per liter (optional)',
    'amount': 'Amount',
    'odometer': 'Odometer (optional)',
    'notes': 'Notes',
  };
  @override
  void initState() {
    super.initState();
    _date =
        DateTime.tryParse('${widget.entry['day']}T00:00:00Z') ??
        widget.initialDate;
    if (_date.isAfter(kpiDate(DateTime.now()))) {
      _date = kpiDate(DateTime.now());
    }
    _voided = widget.entry['voided'] == true;
    _fields = {
      for (final key in labels.keys)
        key: TextEditingController(text: widget.entry[key]?.toString() ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _calculate() {
    final liters = kpiMoney(_fields['liters']!.text);
    final price = kpiMoney(_fields['price_per_liter']!.text);
    if (liters != null && price != null) {
      _fields['amount']!.text = (liters * price).toStringAsFixed(2);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final day = kpiDayKey(_date);
      final previousDay =
          widget.days.where((d) => d['day'] == day).firstOrNull ??
          <String, dynamic>{};
      await widget.store.saveFuel(
        makeId: widget.makeId,
        previous: widget.entry,
        legacyDay: previousDay,
        data: {
          'day': day,
          'voided': _voided,
          'kind': widget.entry['kind'] ?? 'fuel',
          for (final e in _fields.entries)
            e.key:
                const [
                  'liters',
                  'price_per_liter',
                  'amount',
                  'odometer',
                ].contains(e.key)
                ? kpiMoney(e.value.text)
                : e.value.text.trim(),
        },
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e, stack) {
      unawaited(
        SyncErrorLogService.instance.report(
          e,
          stack,
          source: 'pm_fuel_ledger_dialog.dart',
          operation: 'handled operation failure',
        ),
      );
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: RoleAccessService.instance,
    builder: (context, _) => !widget.store.canReadFuel
        ? const AdminModalShell(
            title: 'Fuel Entry',
            child: Text('You do not have access to fuel requests.'),
          )
        : _buildContent(context),
  );

  Widget _buildContent(BuildContext context) => AdminModalShell(
    title: widget.entry.isEmpty ? 'Add Fuel' : 'Fuel Entry',
    flexibleBody: true,
    maxWidth: 700,
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      if (widget.store.canEditFuel)
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text('Fuel date: ${kpiDayKey(_date)}'),
              onPressed: widget.entry.isNotEmpty || !widget.store.canEditFuel
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: kpiDate(DateTime.now()),
                      );
                      if (picked != null && mounted) {
                        setState(() {
                          _date = DateTime.utc(
                            picked.year,
                            picked.month,
                            picked.day,
                          );
                        });
                      }
                    },
            ),
            for (final e in _fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextFormField(
                  controller: e.value,
                  readOnly: !widget.store.canEditFuel,
                  style: adminFieldValueTextStyle,
                  decoration: adminFormInputDecoration(labels[e.key]!),
                  keyboardType:
                      const [
                        'liters',
                        'price_per_liter',
                        'amount',
                        'odometer',
                      ].contains(e.key)
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  onChanged: e.key == 'liters' || e.key == 'price_per_liter'
                      ? (_) => _calculate()
                      : null,
                  validator: (v) =>
                      const [
                            'liters',
                            'price_per_liter',
                            'amount',
                            'odometer',
                          ].contains(e.key) &&
                          (e.key == 'amount' ||
                              (v?.trim().isNotEmpty ?? false)) &&
                          kpiMoney(v) == null
                      ? 'Enter a valid non-negative amount.'
                      : null,
                ),
              ),
            if (widget.entry.isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Voided (excluded from expenses)'),
                value: _voided,
                onChanged: widget.store.canEditFuel
                    ? (v) => setState(() {
                        _voided = v;
                      })
                    : null,
              ),
            if (widget.entry['updated_at'] != null)
              Text(
                'Updated: ${AdminUsersView.formatUpdatedAtSingleLine(DateTime.tryParse(widget.entry['updated_at'].toString()))} · User ${widget.entry['updated_by']}',
              ),
            if (widget.entry['revisions'] is List &&
                (widget.entry['revisions'] as List).isNotEmpty) ...[
              const Divider(),
              const AdminSectionTitle(title: 'Previous Versions'),
              const SizedBox(height: 12),
              SizedBox(
                height: 280,
                child: AdminModalRecordList(
                  titles: const [
                    'DateTime',
                    'Reference',
                    'Amount',
                    'Status',
                    'Details',
                  ],
                  itemCount: (widget.entry['revisions'] as List)
                      .whereType<Map>()
                      .length,
                  wrappingColumn: 4,
                  valuesAt: (i) {
                    final r = (widget.entry['revisions'] as List)
                        .whereType<Map>()
                        .elementAt(i);
                    return [
                      AdminUsersView.formatUpdatedAtSingleLine(
                        DateTime.tryParse('${r['updated_at']}'),
                      ),
                      '${r['reference'] ?? "—"}',
                      '₱${r['amount']}',
                      r['voided'] == true ? 'Voided' : 'Active',
                      '${r['day']} · ${r['supplier'] ?? "—"}\n${r['liters'] ?? "—"} L · ${r['price_per_liter'] ?? "—"}/L\nUser ${r['updated_by']}\n${r['notes'] ?? ""}',
                    ];
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
