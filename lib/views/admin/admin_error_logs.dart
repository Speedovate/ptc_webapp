import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';

/// Read-only, on-demand diagnostics. No background listeners or automatic retries.
class AdminErrorLogsView extends StatefulWidget {
  const AdminErrorLogsView({
    super.key,
    required this.user,
    this.firestore,
    this.onReportsLoaded,
  });
  final UserModel user;
  final FirebaseFirestore? firestore;
  final Future<void> Function()? onReportsLoaded;

  @override
  State<AdminErrorLogsView> createState() => _AdminErrorLogsViewState();
}

class _AdminErrorLogsViewState extends State<AdminErrorLogsView> {
  final _logs = <Map<String, dynamic>>[];
  final _users = <String, Map<String, dynamic>>{};
  final _expanded = <String>{};
  final _expandedDevices = <String>{};
  final _summaries = <String, ({int count, Object? first, Object? last})>{};
  final _scroll = ScrollController();
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  bool get _allowed => widget.user.role?.trim().toLowerCase() == 'admin';
  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    if (_allowed) _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _owner(Map<String, dynamic> row) =>
      row['user_id']?.toString() ?? 'signed_out';

  Future<({int count, Object? first, Object? last})> _summary(String id) async {
    final collection = _db.collection('sync_error_logs');
    final query = id == 'signed_out'
        ? collection.where('user_id', isNull: true)
        : collection.where('user_id', isEqualTo: id);
    final results = await Future.wait<Object>([
      query.count().get(),
      query.orderBy('first_failed_at').limit(1).get(),
      query.orderBy('last_failed_at', descending: true).limit(1).get(),
    ]).timeout(const Duration(seconds: 8));
    final first = (results[1] as QuerySnapshot<Map<String, dynamic>>).docs;
    final last = (results[2] as QuerySnapshot<Map<String, dynamic>>).docs;
    return (
      count: (results[0] as AggregateQuerySnapshot).count ?? 0,
      first: first.isEmpty ? null : first.first.data()['first_failed_at'],
      last: last.isEmpty ? null : last.first.data()['last_failed_at'],
    );
  }

  Future<void> _load({bool refresh = false}) async {
    if (!_allowed || _loading || (!refresh && !_hasMore)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Query<Map<String, dynamic>> query = _db
          .collection('sync_error_logs')
          .orderBy('last_failed_at', descending: true);
      if (!refresh && _cursor != null) {
        query = query.startAfterDocument(_cursor!);
      }
      final page = await query
          .limit(15)
          .get()
          .timeout(const Duration(seconds: 12));
      final rows = page.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList();
      final ids = rows
          .map(_owner)
          .where((id) => id != 'signed_out' && !_users.containsKey(id))
          .toSet();
      // Resolve names for old reports which only captured a user ID.
      final names = await Future.wait(
        ids.map((id) async {
          try {
            final doc = await _db
                .collection('users')
                .doc(id)
                .get()
                .timeout(const Duration(seconds: 5));
            return MapEntry(id, doc.data() ?? <String, dynamic>{});
          } catch (_) {
            return MapEntry(id, <String, dynamic>{});
          }
        }),
      );
      final summaryIds = rows
          .map(_owner)
          .toSet()
          .where((id) => refresh || !_summaries.containsKey(id));
      String? summaryError;
      final summaries = await Future.wait(
        summaryIds.map((id) async {
          try {
            return MapEntry(id, await _summary(id));
          } catch (error) {
            summaryError = 'Could not load user totals: $error';
            return null;
          }
        }),
      );
      if (!mounted || !_allowed) return;
      setState(() {
        if (refresh) {
          _logs.clear();
          _summaries.clear();
        }
        _summaries.addEntries(
          summaries
              .whereType<
                MapEntry<String, ({int count, Object? first, Object? last})>
              >(),
        );
        _error = summaryError;
        final byId = {for (final row in _logs) row['id']: row};
        for (final row in rows) {
          byId[row['id']] = row;
        }
        _logs
          ..clear()
          ..addAll(byId.values);
        _users.addEntries(names);
        _cursor = page.docs.isEmpty
            ? (refresh ? null : _cursor)
            : page.docs.last;
        _hasMore = page.docs.length == 15;
      });
      final notify = widget.onReportsLoaded;
      if (notify != null) unawaited(notify());
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _name(String id, Map<String, dynamic> row) => id == 'signed_out'
      ? 'Signed out'
      : '${_users[id]?['name'] ?? row['user_name'] ?? '—'}';

  String _role(String id, Map<String, dynamic> row) {
    final role = '${_users[id]?['role'] ?? row['role'] ?? ''}'.trim();
    return role.isEmpty || role == 'unknown'
        ? '—'
        : '${role[0].toUpperCase()}${role.substring(1)}';
  }

  String _label(String id, Map<String, dynamic> row) {
    if (id == 'signed_out') return 'Signed out';
    final user = _users[id];
    final name = user?['name'] ?? row['user_name'];
    final role = user?['role'] ?? row['role'];
    final prefix = role == null || role.toString().isEmpty || role == 'unknown'
        ? 'User'
        : '${role.toString()[0].toUpperCase()}${role.toString().substring(1)}';
    return '$prefix $id${name == null || name.toString().isEmpty ? '' : ' | $name'}';
  }

  String _json(Object value) =>
      const JsonEncoder.withIndent('  ').convert(value);

  Map<String, dynamic> _copyData(Map<String, dynamic> row) => {
    'report': 'Sync error log',
    'user_display': _label(_owner(row), row),
    ...row.map((key, value) => MapEntry(key, _serializable(value))),
  };

  Object? _serializable(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', _serializable(value)));
    }
    if (value is Iterable) return value.map(_serializable).toList();
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    return '$value';
  }

  Future<void> _copy(Object data) async {
    try {
      await Clipboard.setData(ClipboardData(text: _json(data)));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Copied')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Copy failed: $error')));
      }
    }
  }

  String _date(Object? value) {
    final date = value is Timestamp
        ? value.toDate()
        : DateTime.tryParse('$value');
    return date == null ? '—' : AdminUsersView.formatCreatedAt(date.toLocal());
  }

  void _details(Map<String, dynamic> row) {
    final data = _copyData(row);
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AdminModalShell(
        title: 'Error Details',
        maxWidth: 800,
        actions: [
          TextButton(onPressed: () => _copy(data), child: const Text('Copy')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(_json(data)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) return const Center(child: Text('Admin access required'));
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in _logs) {
      groups.putIfAbsent(_owner(row), () => []).add(row);
    }
    String device(Map<String, dynamic> log) =>
        '${log['device_id'] ?? 'Device not recorded'}';
    String deviceKey(String user, String id) => jsonEncode([user, id]);
    final devices = <String, List<Map<String, dynamic>>>{};
    final rows = <({String user, String? device, Map<String, dynamic>? log})>[];
    for (final group in groups.entries) {
      rows.add((user: group.key, device: null, log: null));
      if (!_expanded.contains(group.key)) continue;
      final ids = <String>{};
      for (final log in group.value) {
        final id = device(log);
        ids.add(id);
        devices.putIfAbsent(deviceKey(group.key, id), () => []).add(log);
      }
      for (final id in ids) {
        rows.add((user: group.key, device: id, log: null));
        if (_expandedDevices.contains(deviceKey(group.key, id))) {
          rows.addAll(
            devices[deviceKey(group.key, id)]!.map(
              (log) => (user: group.key, device: id, log: log),
            ),
          );
        }
      }
    }
    void toggle(String id, String? device) => setState(() {
      final expanded = device == null ? _expanded : _expandedDevices;
      final key = device == null ? id : deviceKey(id, device);
      if (!expanded.remove(key)) expanded.add(key);
    });
    bool expanded(String id, String? device) => device == null
        ? _expanded.contains(id)
        : _expandedDevices.contains(deviceKey(id, device));
    String preview(String text) {
      final single = text.replaceAll(RegExp(r'\s+'), ' ');
      return single.length > 110 ? '${single.substring(0, 110)}…' : single;
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: NotificationListener<ScrollNotification>(
        onNotification: (event) {
          if (((event is ScrollUpdateNotification &&
                      (event.scrollDelta ?? 0) > 0) ||
                  (event is OverscrollNotification && event.overscroll > 0)) &&
              event.metrics.axis == Axis.vertical &&
              event.metrics.extentAfter < 240 &&
              _error == null) {
            _load();
          }
          return false;
        },
        child: AdminModalRecordList(
          scrollController: _scroll,
          scrollPhysics: const AlwaysScrollableScrollPhysics(),
          horizontalOnDesktop: true,
          trailingActions: true,
          selectableCells: true,
          wrappingColumn: 4,
          columnExtraWidths: const {7: 100},
          titles: const [
            'ID',
            'Name',
            'Role',
            'Device ID',
            'Errors',
            'Created',
            'Updated',
            'Actions',
          ],
          itemCount: rows.length,
          rowGroupKey: (i) => rows[i].user,
          scrollHeader: Row(
            children: [
              Expanded(
                child: Text(
                  '${_logs.length} loaded reports',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              Tooltip(
                message: 'Refresh',
                child: AdminListActionButton(
                  icon: Icons.refresh,
                  onTap: _loading ? null : () => _load(refresh: true),
                ),
              ),
            ],
          ),
          scrollFooter: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Column(
                    children: [
                      SelectableText(_error!),
                      TextButton(
                        onPressed: () => _load(refresh: true),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : Text(
                    _logs.isEmpty
                        ? 'No error logs'
                        : _hasMore
                        ? 'Pull up to load more'
                        : 'All reports loaded',
                  ),
          ),
          valuesAt: (i) {
            final row = rows[i];
            final log = row.log;
            final first = groups[row.user]!.first;
            final summary = _summaries[row.user];
            if (log == null && row.device != null) {
              final reports = devices[deviceKey(row.user, row.device!)]!;
              final dates =
                  reports
                      .map((r) => DateTime.tryParse('${r['first_failed_at']}'))
                      .whereType<DateTime>()
                      .toList()
                    ..sort();
              final latest =
                  reports
                      .map((r) => DateTime.tryParse('${r['last_failed_at']}'))
                      .whereType<DateTime>()
                      .toList()
                    ..sort();
              return [
                '—',
                'Device',
                '—',
                row.device!,
                '${reports.length} loaded',
                dates.isEmpty
                    ? '—'
                    : '${_date(dates.first.toIso8601String())}*',
                latest.isEmpty
                    ? '—'
                    : '${_date(latest.last.toIso8601String())}*',
                '',
              ];
            }
            return log == null
                ? [
                    row.user == 'signed_out' ? '—' : row.user,
                    _name(row.user, first),
                    _role(row.user, first),
                    '—',
                    summary == null ? '—' : '${summary.count}',
                    _date(summary?.first),
                    _date(summary?.last),
                    '',
                  ]
                : [
                    '—',
                    preview('${log['operation'] ?? log['source'] ?? 'Error'}'),
                    _role(row.user, log),
                    '${log['device_id'] ?? '—'}',
                    preview('${log['error'] ?? '—'}'),
                    _date(log['first_failed_at']),
                    _date(log['last_failed_at']),
                    '',
                  ];
          },
          cellBuilder: (i, col) {
            final row = rows[i];
            final log = row.log;
            if (col == 1 && log == null) {
              return InkWell(
                onTap: () => toggle(row.user, row.device),
                child: Text(
                  row.device == null
                      ? _name(row.user, groups[row.user]!.first)
                      : 'Device',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            }
            if (log == null && row.device != null && (col == 5 || col == 6)) {
              final reports = devices[deviceKey(row.user, row.device!)]!;
              final key = col == 5 ? 'first_failed_at' : 'last_failed_at';
              final dates =
                  reports
                      .map((r) => DateTime.tryParse('${r[key]}'))
                      .whereType<DateTime>()
                      .toList()
                    ..sort();
              return Tooltip(
                message: 'Based on loaded reports for this device',
                child: SelectableText(
                  dates.isEmpty
                      ? '—'
                      : '${_date((col == 5 ? dates.first : dates.last).toIso8601String())}*',
                ),
              );
            }
            if (col != 7) return null;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: log == null
                      ? (row.device == null
                            ? 'Copy loaded user errors'
                            : 'Copy loaded device errors')
                      : 'Copy error',
                  child: AdminListActionButton(
                    icon: Icons.copy,
                    onTap: () => _copy(
                      log == null
                          ? (row.device == null
                                    ? groups[row.user]!
                                    : devices[deviceKey(
                                        row.user,
                                        row.device!,
                                      )]!)
                                .map(_copyData)
                                .toList()
                          : _copyData(log),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: log == null
                      ? (expanded(row.user, row.device)
                            ? (row.device == null
                                  ? 'Collapse errors'
                                  : 'Collapse device errors')
                            : (row.device == null
                                  ? 'Expand errors'
                                  : 'Expand device errors'))
                      : 'View error details',
                  child: AdminListActionButton(
                    icon: log == null
                        ? (expanded(row.user, row.device)
                              ? Icons.expand_less
                              : Icons.expand_more)
                        : Icons.visibility_outlined,
                    onTap: () => log == null
                        ? toggle(row.user, row.device)
                        : _details(log),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
