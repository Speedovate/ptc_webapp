import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/widgets/admin_modal_shell.dart';
import 'package:webapp/widgets/shared/admin_list_primitives.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';
import 'package:webapp/widgets/shared/app_page_loading_overlay.dart';

/// Read-only, on-demand diagnostics. No background listeners or automatic retries.
class AdminErrorLogsView extends StatefulWidget {
  const AdminErrorLogsView({
    super.key,
    required this.user,
    this.firestore,
    this.onReportsLoaded,
    this.refreshSignal,
  });
  final UserModel user;
  final FirebaseFirestore? firestore;
  final Future<void> Function()? onReportsLoaded;
  final ValueListenable<int>? refreshSignal;

  @override
  State<AdminErrorLogsView> createState() => _AdminErrorLogsViewState();
}

class _AdminErrorLogsViewState extends State<AdminErrorLogsView> {
  final _logs = <Map<String, dynamic>>[];
  final _users = <String, Map<String, dynamic>>{};
  final _expanded = <String>{};
  final _expandedDevices = <String>{};
  final _summaries = <String, int>{};
  final _deviceSummaries = <String, int>{};
  String _deviceKey(String user, String device) => jsonEncode([user, device]);
  final _scroll = ScrollController();
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  bool _copying = false;
  bool get _allowed => widget.user.role?.trim().toLowerCase() == 'admin';
  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_refreshRequested);
    if (_allowed) _load();
  }

  bool _reloadRequested = false;
  void _refreshRequested() {
    if (_loading) {
      _reloadRequested = true;
      return;
    }
    unawaited(_load(refresh: true));
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_refreshRequested);
    _scroll.dispose();
    super.dispose();
  }

  String _errorCountLabel(int? count) =>
      '${count ?? "—"} ${count == 1 ? "Error" : "Errors"}';

  String _owner(Map<String, dynamic> row) =>
      row['user_id']?.toString() ?? 'signed_out';

  Future<int> _summary(String id, {String? deviceId}) async {
    final collection = _db
        .collection('sync_error_logs')
        .where('attention_required', isEqualTo: true);
    final query = id == 'signed_out'
        ? collection.where('user_id', isNull: true)
        : collection.where('user_id', isEqualTo: id);
    final scoped = deviceId == null
        ? query
        : deviceId == 'Device not recorded'
        ? query.where('device_id', isNull: true)
        : query.where('device_id', isEqualTo: deviceId);
    final result = await scoped.count().get().timeout(
      const Duration(seconds: 8),
    );
    return result.count ?? 0;
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
          .where('attention_required', isEqualTo: true)
          .orderBy('last_failed_at', descending: true);
      if (!refresh && _cursor != null) {
        query = query.startAfterDocument(_cursor!);
      }
      QuerySnapshot<Map<String, dynamic>>? fetchedPage;
      try {
        fetchedPage = await query
            .limit(15)
            .get()
            .timeout(const Duration(seconds: 12));
      } on TimeoutException {
        // Verify emptiness independently when the document query stalls.
        // A timeout alone must never hide existing errors as an empty list.
        final count = await _db
            .collection('sync_error_logs')
            .where('attention_required', isEqualTo: true)
            .count()
            .get()
            .timeout(const Duration(seconds: 8));
        if ((count.count ?? -1) != 0) rethrow;
      }
      final page = fetchedPage;
      if (!mounted || !_allowed) return;
      // An empty page is a completed read. Do not wait for user metadata or
      // aggregate counts before settling the empty/end-of-list state.
      if (page == null || page.docs.isEmpty) {
        setState(() {
          if (refresh || page == null) {
            _logs.clear();
            _summaries.clear();
            _deviceSummaries.clear();
            _cursor = null;
          }
          _hasMore = false;
          _loading = false;
        });
        final notify = widget.onReportsLoaded;
        if (notify != null) unawaited(notify());
        return;
      }
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
      final summariesFuture = Future.wait(
        summaryIds.map((id) async {
          try {
            return MapEntry(id, await _summary(id));
          } catch (error) {
            summaryError = 'Could not load user totals: $error';
            return null;
          }
        }),
      );
      final deviceIds = <String, ({String user, String device})>{
        for (final row in rows)
          _deviceKey(
            _owner(row),
            '${row['device_id'] ?? 'Device not recorded'}',
          ): (
            user: _owner(row),
            device: '${row['device_id'] ?? 'Device not recorded'}',
          ),
      };
      final deviceSummaries = await Future.wait(
        deviceIds.entries.map((entry) async {
          try {
            return MapEntry(
              entry.key,
              await _summary(entry.value.user, deviceId: entry.value.device),
            );
          } catch (error) {
            summaryError = 'Could not load device totals: $error';
            return null;
          }
        }),
      );
      final summaries = await summariesFuture;
      if (!mounted || !_allowed) return;
      setState(() {
        if (refresh) {
          _logs.clear();
          _summaries.clear();
          _deviceSummaries.clear();
        }
        _summaries.addEntries(summaries.whereType<MapEntry<String, int>>());
        _deviceSummaries.addEntries(
          deviceSummaries.whereType<MapEntry<String, int>>(),
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
      if (mounted) {
        setState(
          () => _error = error is TimeoutException
              ? 'Unable to load error logs. Please try again.'
              : '$error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_reloadRequested) {
          _reloadRequested = false;
          unawaited(_load(refresh: true));
        }
      }
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
    if (value is Timestamp) {
      return {
        'type': 'Firestore Timestamp',
        'seconds': value.seconds,
        'nanoseconds': value.nanoseconds,
        'iso8601': value.toDate().toUtc().toIso8601String(),
      };
    }
    if (value is GeoPoint) {
      return {'latitude': value.latitude, 'longitude': value.longitude};
    }
    if (value is DocumentReference) return {'document_path': value.path};
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

  Future<void> _copyFirestoreErrors({
    required String user,
    String? device,
    String? id,
  }) async {
    if (!_allowed || _copying) return;
    setState(() => _copying = true);
    final displayed = _logs
        .where(
          (row) =>
              _owner(row) == user &&
              (id == null || row['id'] == id) &&
              (device == null ||
                  '${row['device_id'] ?? 'Device not recorded'}' == device),
        )
        .map(
          (row) => {
            ..._copyData(row),
            'document_path': 'sync_error_logs/${row['id']}',
            'data_source': 'displayed_snapshot',
          },
        )
        .toList();
    Map<String, dynamic> fallback(
      String reason, {
      Object? error,
      StackTrace? stack,
    }) => {
      'report': 'Sync error log copy diagnostics',
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'user_id': user,
      'device_id': device,
      'document_id': id,
      'source': 'admin_error_logs.dart::_copyFirestoreErrors',
      'server_reports_verified': false,
      'reason': reason,
      if (error != null) 'fetch_error': '$error',
      if (stack != null) 'fetch_stack_trace': '$stack',
      'displayed_reports': displayed,
      'page_error': _error,
    };
    try {
      final collection = _db.collection('sync_error_logs');
      Map<String, dynamic> export(DocumentSnapshot<Map<String, dynamic>> doc) =>
          {
            'report': 'Sync error log',
            'document_path': doc.reference.path,
            'document_id': doc.id,
            'user_display': _label(user, doc.data() ?? {}),
            'firestore_data': _serializable(doc.data()),
          };
      Object result;
      if (id != null) {
        final doc = await collection
            .doc(id)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 12));
        if (!doc.exists) {
          throw StateError(
            'This error is no longer in Firestore. Reopen Error Logs.',
          );
        }
        result = export(doc);
      } else {
        Query<Map<String, dynamic>> query = collection.where(
          'attention_required',
          isEqualTo: true,
        );
        query = user == 'signed_out'
            ? query.where('user_id', isNull: true)
            : query.where('user_id', isEqualTo: user);
        if (device != null) {
          query = device == 'Device not recorded'
              ? query.where('device_id', isNull: true)
              : query.where('device_id', isEqualTo: device);
        }
        query = query.orderBy(FieldPath.documentId);
        final records = <Map<String, dynamic>>[];
        DocumentSnapshot<Map<String, dynamic>>? cursor;
        while (mounted && _allowed) {
          final page =
              await (cursor == null ? query : query.startAfterDocument(cursor))
                  .limit(100)
                  .get(const GetOptions(source: Source.server))
                  .timeout(const Duration(seconds: 12));
          records.addAll(page.docs.map(export));
          if (page.docs.length < 100) break;
          cursor = page.docs.last;
          await Future<void>.delayed(Duration.zero);
        }
        result = records.isEmpty
            ? fallback(
                'No matching active reports returned by Firestore; displayed reports may have been resolved or removed.',
              )
            : records;
      }
      if (mounted && _allowed) await _copy(result);
    } catch (error, stack) {
      if (mounted && _allowed) {
        await _copy(
          fallback(
            'Could not fetch current Firestore reports; includes the displayed snapshot only.',
            error: error,
            stack: stack,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
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
          TextButton(
            onPressed: () =>
                _copyFirestoreErrors(user: _owner(row), id: '${row['id']}'),
            child: const Text('Copy'),
          ),
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
    Widget errorState() => AdminListItemCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(_error!),
          TextButton(
            onPressed: _loading ? null : () => _load(refresh: true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
    if (_logs.isEmpty) {
      return AppPageLoadingOverlay(
        isVisible: _loading,
        message: 'Loading error logs ...',
        child: _loading
            ? const SizedBox.expand()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _error != null
                    ? errorState()
                    : const AdminListItemCard(
                        padding: EdgeInsets.all(24),
                        child: AdminListStateText(message: 'No error logs.'),
                      ),
              ),
      );
    }
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in _logs) {
      groups.putIfAbsent(_owner(row), () => []).add(row);
    }
    String device(Map<String, dynamic> log) =>
        '${log['device_id'] ?? 'Device not recorded'}';
    String deviceKey(String user, String id) => _deviceKey(user, id);

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
          wrappingColumn: 3,
          columnExtraWidths: const {3: 24, 4: 100},
          titles: const ['ID', 'Name', 'Role', 'Errors', 'Actions'],
          itemCount: rows.length,
          leadingColumnSpanAt: (i) => rows[i].device != null ? 3 : 1,
          fullWidthRowColumnAt: (i) => rows[i].log != null ? 0 : null,
          rowGroupKey: (i) => rows[i].user,
          dividerAfterRow: (i) {
            final row = rows[i];
            if (row.device == null) return false;
            if (row.log == null) return expanded(row.user, row.device);
            return i + 1 < rows.length &&
                rows[i + 1].user == row.user &&
                rows[i + 1].log == null;
          },
          scrollHeader: const SizedBox.shrink(),
          scrollFooter: _loading
              ? const AppPageLoading(compact: true)
              : _error != null
              ? errorState()
              : null,
          valuesAt: (i) {
            final row = rows[i];
            final log = row.log;
            final first = groups[row.user]!.first;
            final summary = _summaries[row.user];
            if (log == null && row.device != null) {
              return [
                row.device!,
                '',
                '',
                _errorCountLabel(
                  _deviceSummaries[deviceKey(row.user, row.device!)],
                ),
                '',
              ];
            }
            return log == null
                ? [
                    row.user == 'signed_out' ? '—' : row.user,
                    _name(row.user, first),
                    _role(row.user, first),
                    summary == null ? '—' : _errorCountLabel(summary),
                    '',
                  ]
                : [
                    '—',
                    preview('${log['operation'] ?? log['source'] ?? 'Error'}'),
                    '',
                    preview('${log['error'] ?? '—'}'),
                    '',
                  ];
          },
          cellBuilder: (i, col) {
            final row = rows[i];
            final log = row.log;
            if (col == 0 && log != null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    preview('${log['operation'] ?? log['source'] ?? 'Error'}'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(preview('${log['error'] ?? '—'}')),
                ],
              );
            }
            if (col == 3 && log == null) {
              final count = row.device == null
                  ? _summaries[row.user]
                  : _deviceSummaries[deviceKey(row.user, row.device!)];
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.dangerSurfaceAlt,
                  border: Border.all(color: AppColors.dangerBorderAlt),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: SelectableText(
                  _errorCountLabel(count),
                  style: const TextStyle(color: AppColors.danger),
                ),
              );
            }
            if (log == null && col == (row.device == null ? 1 : 0)) {
              return InkWell(
                onTap: () => toggle(row.user, row.device),
                child: Text(
                  row.device == null
                      ? _name(row.user, groups[row.user]!.first)
                      : row.device!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            }
            if (col != 4) return null;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: log == null
                      ? (row.device == null
                            ? 'Copy all user errors'
                            : 'Copy all device errors')
                      : 'Copy error',
                  child: AdminListActionButton(
                    icon: Icons.copy,
                    onTap: _copying
                        ? null
                        : () => _copyFirestoreErrors(
                            user: row.user,
                            device: row.device,
                            id: log?['id']?.toString(),
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
