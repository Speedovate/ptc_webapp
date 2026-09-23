import 'package:webapp/services/sync_error_log_service.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/kpi_workbook_import.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';

Future<void> showKpiImport(
  BuildContext context,
  VehicleMake make,
  PmKpiStore store,
  List<Booking> bookings,
) => showAppDialog<void>(
  context: context,
  builder: (_) => KpiImportDialog(make: make, store: store, bookings: bookings),
);

class KpiImportDialog extends StatefulWidget {
  const KpiImportDialog({
    super.key,
    required this.make,
    required this.store,
    this.onBack,
    required this.bookings,
    this.pickWorkbook,
  });
  final VehicleMake make;
  final PmKpiStore store;
  final VoidCallback? onBack;
  final List<Booking> bookings;
  final Future<Uint8List?> Function()? pickWorkbook;
  @override
  State<KpiImportDialog> createState() => _KpiImportDialogState();
}

class _KpiImportDialogState extends State<KpiImportDialog> {
  List<KpiImportRow> _rows = [];
  final _scroll = ScrollController();
  int _visible = 15;
  bool _addingRows = false;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _busy = false;
  String? _error;
  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Uint8List? bytes;
      if (widget.pickWorkbook != null) {
        bytes = await widget.pickWorkbook!();
      } else {
        final file = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          withData: true,
        );
        if (file == null) return;
        bytes = file.files.single.bytes;
      }
      if (bytes == null) return;
      final rows = KpiWorkbookImport.parse(bytes, widget.make.code ?? '');
      if (mounted) {
        setState(() {
          _visible = 15;
          _rows = rows
              .where(
                (r) => r.kind == 'Fuel'
                    ? widget.store.canEditFuel
                    : widget.store.canEdit,
              )
              .toList();
          if (_rows.isEmpty) {
            _error =
                'No ledger rows found for ${widget.make.code}. Use the PALTRANCO monthly ledger workbook.';
          }
        });
      }
    } catch (error, stack) {
      unawaited(
        SyncErrorLogService.instance.report(
          error,
          stack,
          source: 'kpi_import_dialog.dart',
          operation: 'handled operation failure',
        ),
      );
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(KpiImportRow row) async {
    final date = TextEditingController(
      text: row.date == null ? '' : kpiDayKey(row.date!),
    );
    final driver = TextEditingController(
      text: row.driver?.toStringAsFixed(2) ?? '',
    );
    final helper = TextEditingController(
      text: row.helper?.toStringAsFixed(2) ?? '',
    );
    String? error;
    await showAppDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AdminModalShell(
          title: '${row.kind} · ${row.sheet} row ${row.row}',
          maxWidth: 520,
          flexibleBody: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final parsed = DateTime.tryParse(
                  '${date.text.trim()}T00:00:00Z',
                );
                final d = kpiMoney(driver.text), h = kpiMoney(helper.text);
                if (parsed == null ||
                    kpiDayKey(parsed) != date.text.trim() ||
                    parsed.isAfter(kpiDate(DateTime.now())) ||
                    (row.kind == 'Salary' &&
                        (d == null ||
                            h == null ||
                            (d + h - row.amount).abs() >= 0.005))) {
                  update(
                    () => error =
                        'Enter a valid date. Driver + Helper must equal the source salary amount.',
                  );
                  return;
                }
                row.date = parsed;
                row.driver = d;
                row.helper = h;
                row.selected = true;
                row.error = null;
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
          child: AdminModalFieldsSection(
            children: [
              Text('${row.period} · PHP ${row.amount.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              TextField(
                controller: date,
                decoration: adminFormInputDecoration(
                  row.kind == 'Fuel'
                      ? 'Fuel date (YYYY-MM-DD)'
                      : 'Payroll posting date (YYYY-MM-DD)',
                ),
                readOnly: true,
                onTap: () async {
                  final chosen = await showDatePicker(
                    context: ctx,
                    initialDate: row.date ?? kpiDate(DateTime.now()),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (chosen != null) date.text = kpiDayKey(chosen);
                },
              ),
              if (row.kind == 'Salary') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: driver,
                  keyboardType: TextInputType.number,
                  decoration: adminFormInputDecoration(
                    'Driver total (including shares)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: helper,
                  keyboardType: TextInputType.number,
                  decoration: adminFormInputDecoration(
                    'Helper total (including shares)',
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final chosen = DateTime.tryParse('${date.text}T00:00:00Z');
                    if (chosen == null) {
                      update(() => error = 'Select a date first.');
                      return;
                    }
                    final stored = await widget.store.load(
                      widget.make.id!,
                      KpiPeriod(chosen, chosen),
                    );
                    final report = PmKpi.calculate(
                      makeId: widget.make.id!,
                      period: KpiPeriod(chosen, chosen),
                      bookings: widget.bookings,
                      makes: widget.store.makes,
                      records: stored.records,
                      resolveSalary: stored.catalog.resolveSalary,
                    );
                    if (!ctx.mounted) return;
                    driver.text = report.driverSalary.toStringAsFixed(2);
                    helper.text = report.helperSalary.toStringAsFixed(2);
                    update(() => error = null);
                  },
                  child: const Text('Use booking totals for this date'),
                ),
              ],
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
    );
    // Controllers may still be referenced during the dialog exit animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    date.dispose();
    driver.dispose();
    helper.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final row in _rows.where(
        (r) => r.selected && r.valid && !r.imported,
      )) {
        try {
          final period = KpiPeriod.month(row.date!.year, row.date!.month);
          final stored = await widget.store.load(widget.make.id!, period);
          if (row.kind == 'Fuel') {
            if (!widget.store.canEditFuel) {
              throw StateError('Fuel edit access required.');
            }
            if (!stored.fuel.any((r) => r['import_key'] == row.key)) {
              await widget.store.saveFuel(
                makeId: widget.make.id!,
                previous: {},
                data: {
                  'day': kpiDayKey(row.date!),
                  'amount': row.amount,
                  'liters': row.liters,
                  'price_per_liter': row.price,
                  'reference': row.reference,
                  'notes': row.notes,
                  'import_key': row.key,
                  'import_source': '${row.sheet}!${row.row}',
                  'voided': false,
                },
              );
            }
          } else {
            if (!widget.store.canEdit) {
              throw StateError('KPI edit access required.');
            }
            if (!stored.records.any((r) => r['import_key'] == row.key)) {
              final monthReport = PmKpi.calculate(
                makeId: widget.make.id!,
                period: period,
                bookings: widget.bookings,
                makes: widget.store.makes,
                records: stored.records,
              );
              if (monthReport.days.any((d) => d.trips.isNotEmpty)) {
                throw StateError(
                  'This month already has delivered-trip payroll. Use its existing salary editor to avoid counting the imported payroll twice.',
                );
              }
              if (stored.records.any((r) => r['day'] == kpiDayKey(row.date!))) {
                throw StateError(
                  'This date already has a KPI record. Review it in the existing editor; import will not overwrite it.',
                );
              }
              final report = PmKpi.calculate(
                makeId: widget.make.id!,
                period: KpiPeriod(row.date!, row.date!),
                bookings: widget.bookings,
                makes: widget.store.makes,
                records: [],
                resolveSalary: stored.catalog.resolveSalary,
              );
              final day = report.days.single;
              final rates =
                  day.estimate?.rates ?? const <Map<String, dynamic>>[];
              final ds = rates.fold<double>(
                0,
                (s, r) => s + (kpiMoney(r['driver']) ?? 0),
              );
              final hs = rates.fold<double>(
                0,
                (s, r) => s + (kpiMoney(r['helper']) ?? 0),
              );
              if (row.driver! < ds || row.helper! < hs) {
                throw StateError(
                  'Imported totals cannot be less than recorded trip shares.',
                );
              }
              await widget.store.save(
                makeId: widget.make.id!,
                previous: {},
                data: {
                  'kind': 'day',
                  'day': kpiDayKey(row.date!),
                  'salary_confirmed': true,
                  'driver_salary': row.driver,
                  'helper_salary': row.helper,
                  'trip_signature': day.signature,
                  'trip_rates': rates,
                  'matrix_snapshot': stored.catalog
                      .matrixFor(row.date!)
                      .toMap(),
                  'import_key': row.key,
                  'import_source': '${row.sheet}!${row.row}',
                  'import_payroll_period': row.period,
                },
              );
            }
          }
          row.imported = true;
          row.selected = false;
          row.error = null;
        } catch (error, stack) {
          unawaited(
            SyncErrorLogService.instance.report(
              error,
              stack,
              source: 'kpi_import_dialog.dart',
              operation: 'handled operation failure',
            ),
          );
          row.error = '$error';
        }
        if (!mounted) return;
        setState(() {});
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminModalShell(
    title: '${widget.make.code} Excel Import',
    maxWidth: 1100,
    flexibleBody: true,
    bodyHandlesScrolling: true,
    actions: [
      TextButton(
        onPressed: _busy ? null : _pick,
        child: const Text('Choose Excel'),
      ),
      TextButton(
        onPressed:
            _busy || !_rows.any((r) => r.selected && r.valid && !r.imported)
            ? null
            : _import,
        child: Text(_busy ? 'Working...' : 'Import Selected'),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : (widget.onBack ?? () => Navigator.pop(context)),
        child: Text(widget.onBack == null ? 'Close' : 'Back to KPI'),
      ),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_rows.isEmpty)
            const Text(
              'Choose a PALTRANCO ledger workbook to preview. No records are saved until Import Selected.',
            ),
          if (_rows.isNotEmpty)
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  final down =
                      notification is ScrollUpdateNotification &&
                          (notification.scrollDelta ?? 0) > 0 ||
                      notification is OverscrollNotification &&
                          notification.overscroll > 0;
                  if (notification.metrics.axis == Axis.vertical &&
                      down &&
                      !_addingRows &&
                      notification.metrics.extentAfter < 240 &&
                      _visible < _rows.length) {
                    _addingRows = true;
                    setState(
                      () => _visible = (_visible + 15).clamp(0, _rows.length),
                    );
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _addingRows = false,
                    );
                  }
                  return false;
                },
                child: AdminModalRecordList(
                  scrollController: _scroll,
                  scrollHeader: const SizedBox.shrink(),
                  scrollFooter: _visible < _rows.length
                      ? Text(
                          'Showing $_visible of ${_rows.length} · Pull up to load more',
                        )
                      : null,
                  horizontalOnDesktop: true,
                  titles: const [
                    'Select',
                    'Source',
                    'Type',
                    'Date / Period',
                    'Amount',
                    'Status',
                    'Actions',
                  ],
                  itemCount: _rows.length.clamp(0, _visible),
                  wrappingColumn: 5,
                  trailingActions: true,
                  columnExtraWidths: const {0: 48, 6: 40},
                  valuesAt: (i) {
                    final r = _rows[i];
                    return [
                      '',
                      '${r.sheet} row ${r.row}',
                      r.kind,
                      r.date == null ? r.period : kpiDayKey(r.date!),
                      'PHP ${r.amount.toStringAsFixed(2)}',
                      r.error ??
                          (r.imported
                              ? 'Imported'
                              : r.valid
                              ? 'Ready'
                              : 'Set date${r.kind == 'Salary' ? ' and salary split' : ''}'),
                      '',
                    ];
                  },
                  cellBuilder: (i, col) {
                    final row = _rows[i];
                    if (col == 0) {
                      return Checkbox(
                        value: row.selected,
                        onChanged: _busy || !row.valid || row.imported
                            ? null
                            : (v) => setState(() => row.selected = v ?? false),
                      );
                    }
                    if (col == 6) {
                      return AdminListActionButton(
                        icon: Icons.edit,
                        onTap: _busy || row.imported ? null : () => _edit(row),
                      );
                    }
                    return null;
                  },
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
