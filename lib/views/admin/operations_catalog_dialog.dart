import 'dart:async';
import 'package:webapp/services/sync_error_log_service.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/admin_modal_form_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/services/kpi/operations_catalog.dart';
import 'package:webapp/services/kpi/operations_catalog_store.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';

Future<void> showOperationsCatalog(BuildContext context) => showAppDialog<void>(
  context: context,
  modalKey: 'operations-catalog',
  builder: (_) => const OperationsCatalogDialog(),
);

class OperationsCatalogDialog extends StatefulWidget {
  const OperationsCatalogDialog({super.key, this.store, this.onBack});
  final VoidCallback? onBack;
  final OperationsCatalogStore? store;
  @override
  State<OperationsCatalogDialog> createState() =>
      _OperationsCatalogDialogState();
}

class _OperationsCatalogDialogState extends State<OperationsCatalogDialog> {
  late final OperationsCatalogStore _store;
  OperationsCatalog? _catalog;
  String _query = '';
  String? _error;
  bool _busy = true;
  DateTime _effective = kpiDate(DateTime.now());
  @override
  void initState() {
    super.initState();
    _store = widget.store ?? OperationsCatalogStore.instance;
    _load();
  }

  Future<void> _load() async {
    try {
      if (!_store.canRead) {
        throw StateError(
          'You do not have access to locations and trip shares.',
        );
      }
      final value = await _store.load(force: true);
      if (mounted) {
        setState(() {
          _catalog = value;
          _busy = false;
        });
      }
    } catch (e, stack) {
      unawaited(
        SyncErrorLogService.instance.report(
          e,
          stack,
          source: 'operations_catalog_dialog.dart',
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

  Future<void> _save(Map<String, dynamic> next) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _store.save(next, _catalog!.document);
      if (mounted) {
        setState(() {
          _catalog = _store.current;
          _busy = false;
        });
      }
    } catch (e, stack) {
      unawaited(
        SyncErrorLogService.instance.report(
          e,
          stack,
          source: 'operations_catalog_dialog.dart',
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

  KpiRate? _rateFor(OperationLocation location, TripMatrixVersion matrix) =>
      matrix.rates
          .where(
            (r) => [r.name, ...r.aliases].any(
              (name) => [
                location.name,
                ...location.aliases,
              ].any((n) => n.toLowerCase() == name.toLowerCase()),
            ),
          )
          .firstOrNull;

  Future<void> _matrixVersion(
    List<KpiRate> rates,
    TripPaySchedule pay, {
    List<OperationLocation>? locations,
  }) async {
    final next = TripMatrixVersion(
      id: DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
      effectiveFrom: _effective,
      rates: rates,
      pay: pay,
    );
    await _save({
      ..._catalog!.withLocations(locations ?? _catalog!.locations),
      'matrix_versions': [
        ...(_catalog!.document['matrix_versions'] as List? ?? []),
        next.toMap(),
      ],
    });
  }

  Future<void> _location([OperationLocation? old]) async {
    final matrix = _catalog!.matrixFor(_effective);
    final rate = old == null ? null : _rateFor(old, matrix);
    final data = await _editValues(
      context,
      title: old == null ? 'Add location' : 'Edit location & trip share',
      values: {
        'Name': old?.name ?? '',
        'Type': old?.kindLabel ?? 'Municipality',
        'Driver amount (optional)': rate?.driver.toString() ?? '',
        'Helper amount (optional)': rate?.helper.toString() ?? '',
        'Distance (km, optional)': rate?.distance?.toString() ?? '',
        'Other matching location names (one per line)':
            OperationsCatalog.unique([
              ...?old?.aliases,
              ...?rate?.aliases,
            ]).join('\n'),
      },
      choices: const {
        'Type': [
          'City',
          'Municipality',
          'Barangay',
          'Area / Route',
          'Rate Category',
        ],
      },
    );
    if (data == null || !mounted) {
      return;
    }
    final name = data['Name']!.trim();
    final driverText = data['Driver amount (optional)']!.trim();
    final helperText = data['Helper amount (optional)']!.trim();
    final hasRate = driverText.isNotEmpty || helperText.isNotEmpty;
    final driver = kpiMoney(driverText);
    final helper = kpiMoney(helperText);
    final distanceText = data['Distance (km, optional)']!.trim();
    final aliases = OperationsCatalog.unique([
      ...data['Other matching location names (one per line)']!.split('\n'),
      if (old != null && old.name != name) old.name,
      if (rate != null && rate.name != name) rate.name,
    ]);
    final identifiers = [name, ...aliases].map((n) => n.toLowerCase()).toSet();
    if (name.isEmpty ||
        (hasRate && (driver == null || helper == null)) ||
        (distanceText.isNotEmpty && kpiMoney(distanceText) == null) ||
        _catalog!.locations.any(
          (l) =>
              l.name != old?.name &&
              [
                l.name,
                ...l.aliases,
              ].any((n) => identifiers.contains(n.toLowerCase())),
        )) {
      setState(
        () => _error =
            'Use a unique location name. Enter both trip amounts, or leave both blank if no rate is set.',
      );
      return;
    }
    final kind = switch (data['Type']) {
      'Barangay' => 'barangay',
      'City' => 'city',
      'Municipality' => 'municipality',
      'Rate Category' => 'rate_category',
      _ => 'location',
    };
    final actionTime = DateTime.now().toUtc();
    final location = OperationLocation(
      name,
      kind,
      active: old?.active ?? true,
      createdAt: old == null ? actionTime : old.createdAt,
      updatedAt: actionTime,
      aliases: aliases,
    );
    await _matrixVersion(
      [
        for (final r in matrix.rates)
          if (r.name != rate?.name) r,
        if (hasRate)
          KpiRate(
            name,
            driver!,
            helper!,
            distance: kpiMoney(distanceText),
            aliases: aliases,
            active: location.active,
            cityProper: rate?.usesCityPremium,
          ),
      ],
      matrix.pay,
      locations: [
        for (final l in _catalog!.locations)
          if (l.name != old?.name) l,
        location,
      ],
    );
  }

  Future<void> _toggle(OperationLocation location) async {
    final matrix = _catalog!.matrixFor(_effective);
    final rate = _rateFor(location, matrix);
    if (rate == null) {
      return;
    }
    final active = _catalog!.hasActiveRate(location, _effective);
    await _matrixVersion(
      [
        for (final r in matrix.rates)
          if (r.name == rate.name)
            KpiRate(
              r.name,
              r.driver,
              r.helper,
              distance: r.distance,
              aliases: r.aliases,
              active: !active,
              cityProper: r.usesCityPremium,
            )
          else
            r,
      ],
      matrix.pay,
      locations: [
        for (final l in _catalog!.locations)
          l.name == location.name
              ? l.copyActive(!active, updatedAt: DateTime.now().toUtc())
              : l,
      ],
    );
  }

  Future<void> _payRules() async {
    final matrix = _catalog!.matrixFor(_effective);
    final p = matrix.pay;
    final values = await _editValues(
      context,
      title: 'Daily pay and trip rules',
      values: {
        'Daily pay per person': '${p.daily}',
        'City Proper premium after trips': '${p.cityAfter}',
        'City Proper premium — driver': '${p.cityDriver}',
        'City Proper premium — helper': '${p.cityHelper}',
        'Hustling full — driver': '${p.fullDriver}',
        'Hustling full — helper': '${p.fullHelper}',
        'Hustling empty — driver': '${p.emptyDriver}',
        'Hustling empty — helper': '${p.emptyHelper}',
      },
    );
    if (values == null || !mounted) {
      return;
    }
    if (values.values.any((v) => kpiMoney(v) == null) ||
        int.tryParse(values.values.elementAt(1)) == null) {
      setState(() {
        _error =
            'Enter non-negative amounts and a whole-number trip threshold.';
      });
      return;
    }
    final v = values.values.map((s) => kpiMoney(s)!).toList();
    await _matrixVersion(
      matrix.rates,
      TripPaySchedule(
        daily: v[0],
        cityAfter: v[1].toInt(),
        cityDriver: v[2],
        cityHelper: v[3],
        fullDriver: v[4],
        fullHelper: v[5],
        emptyDriver: v[6],
        emptyHelper: v[7],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: RoleAccessService.instance,
    builder: (context, _) => !_store.canRead
        ? AdminModalShell(
            actions: [
              TextButton(
                onPressed: widget.onBack ?? () => Navigator.pop(context),
                child: Text(widget.onBack == null ? 'Close' : 'Back to KPI'),
              ),
            ],
            title: 'Trip Rates',
            child: Text('You do not have access to these settings.'),
          )
        : _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final matrix = _catalog?.matrixFor(_effective);
    final locations = (_catalog?.locations ?? <OperationLocation>[])
        .where((location) => location.kind != 'rate_category')
        .where(
          (l) => [
            l.name,
            l.kindLabel,
            ...l.aliases,
          ].any((v) => v.toLowerCase().contains(_query.trim().toLowerCase())),
        )
        .toList();
    return AdminModalShell(
      title: 'Trip Rates',
      maxWidth: 950,
      flexibleBody: true,
      bodyHandlesScrolling: true,
      actions: [
        TextButton(
          onPressed: widget.onBack ?? () => Navigator.pop(context),
          child: Text(widget.onBack == null ? 'Close' : 'Back to KPI'),
        ),
      ],
      child: _busy
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null)
                        Text(
                          _error!,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      TextField(
                        decoration: adminFormInputDecoration(
                          'Search locations',
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today),
                            label: Text(
                              'Rates effective ${kpiDayKey(_effective)}',
                            ),
                            onPressed: () async {
                              final now = kpiDate(DateTime.now());
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _effective,
                                firstDate: now,
                                lastDate: DateTime(2100),
                              );
                              if (picked != null && mounted) {
                                setState(
                                  () => _effective = DateTime.utc(
                                    picked.year,
                                    picked.month,
                                    picked.day,
                                  ),
                                );
                              }
                            },
                          ),
                          if (_store.canEdit)
                            TextButton(
                              onPressed: _payRules,
                              child: const Text(
                                'Daily pay / City Proper / hustling rules',
                              ),
                            ),
                        ],
                      ),
                      if (_store.canEdit)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: SizedBox(
                            width: 170,
                            child: AdminListNewButton(
                              controlHeight: 48,
                              surfaceRadius: 16,
                              iconOnly: false,
                              label: 'Add location',
                              onTap: () => _location(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AdminModalRecordList(
                      trailingActions: true,
                      titles: const [
                        'Location',
                        'Type',
                        'Distance',
                        'Driver',
                        'Helper',
                        'Status',
                        'Created At',
                        'Updated At',
                        'Actions',
                      ],
                      itemCount: locations.length,
                      columnExtraWidths: const {8: 96},
                      horizontalOnDesktop: true,
                      valuesAt: (i) {
                        final location = locations[i];
                        final rate = matrix == null
                            ? null
                            : _rateFor(location, matrix);
                        return [
                          location.name,
                          location.kindLabel,
                          location.isCityProperCategory
                              ? '1–7 km'
                              : rate?.distance == null
                              ? '—'
                              : '${rate!.distance} km',
                          rate == null
                              ? 'Not set'
                              : '₱${rate.driver.toStringAsFixed(2)}',
                          rate == null
                              ? 'Not set'
                              : '₱${rate.helper.toStringAsFixed(2)}',
                          _catalog!.hasActiveRate(location, _effective)
                              ? 'Active'
                              : 'Inactive',
                          location.createdAt == null
                              ? '—'
                              : AdminUsersView.formatCreatedAt(
                                  location.createdAt,
                                ),
                          location.updatedAt == null
                              ? '—'
                              : AdminUsersView.formatCreatedAt(
                                  location.updatedAt,
                                ),
                          '',
                        ];
                      },
                      cellBuilder: (i, col) {
                        if (col != 8 || !_store.canEdit) {
                          return null;
                        }
                        final location = locations[i];
                        final rate = _rateFor(location, matrix!);
                        final active = _catalog!.hasActiveRate(
                          location,
                          _effective,
                        );
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: 'Edit location & trip share',
                              child: AdminListActionButton(
                                icon: Icons.edit_rounded,
                                onTap: () => _location(location),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: rate == null
                                  ? 'Set Driver and Helper amounts before activating'
                                  : active
                                  ? 'Deactivate location'
                                  : 'Activate location',
                              child: AdminListActionButton(
                                icon: active
                                    ? Icons.close_rounded
                                    : Icons.check_rounded,
                                backgroundColor: active
                                    ? AppColors.dangerStrong
                                    : const Color(0xFF2EAD62),
                                onTap: rate == null
                                    ? null
                                    : () => _toggle(location),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

Future<Map<String, String>?> _editValues(
  BuildContext context, {
  required String title,
  required Map<String, String> values,
  Map<String, List<String>> choices = const {},
}) => showAppDialog<Map<String, String>>(
  context: context,
  builder: (_) => _ValuesDialog(title: title, values: values, choices: choices),
);

class _ValuesDialog extends StatefulWidget {
  const _ValuesDialog({
    required this.title,
    required this.values,
    this.choices = const {},
  });
  final Map<String, List<String>> choices;
  final String title;
  final Map<String, String> values;
  @override
  State<_ValuesDialog> createState() => _ValuesDialogState();
}

class _ValuesDialogState extends State<_ValuesDialog> {
  late final Map<String, TextEditingController> controllers;
  @override
  void initState() {
    super.initState();
    controllers = widget.values.map(
      (k, v) => MapEntry(k, TextEditingController(text: v)),
    );
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminModalShell(
    title: widget.title,
    flexibleBody: true,
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          controllers.map((k, v) => MapEntry(k, v.text)),
        ),
        child: const Text('Save'),
      ),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: controllers.entries
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: widget.choices.containsKey(e.key)
                    ? AdminDropdownFormField<String>(
                        decoration: adminFormInputDecoration(e.key),
                        initialValue: e.value.text,
                        items: widget.choices[e.key]!
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            e.value.text = value;
                          }
                        },
                      )
                    : AdminModalTextField(
                        controller: e.value,
                        label: e.key,
                        inputFormatters: const [],
                        maxLines: e.key.contains('one per line') ? 3 : 1,
                      ),
              ),
            )
            .toList(),
      ),
    ),
  );
}
