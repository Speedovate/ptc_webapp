import 'sync_diagnostic_outbox.dart';
import 'diagnostic_write_lock.dart';
import 'sync_error_environment.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/network_status_events.dart';

/// Independent diagnostic outbox. Never uses a business queue, deletes resolved queue diagnostics only for this installation. A single maintenance timer retries diagnostics and checks stalls.
class SyncErrorLogService {
  SyncErrorLogService({
    BookingStorageBackend? backend,
    Future<void> Function(String id, Map<String, dynamic> data)? writer,
    Future<Map<String, dynamic>> Function(String? owner)? metadata,
    Future<void> Function(String id)? deleter,
    bool Function()? online,
    DateTime Function()? now,
    this.automaticMaintenance = false,
    this.localPersistenceTimeout = const Duration(seconds: 2),
    this.uploadTimeout = const Duration(seconds: 30),
    this.stallAfter = const Duration(seconds: 90),
  }) : _backend = backend ?? createBookingStorageBackend(),
       _writer = writer ?? _write,
       _deleter =
           deleter ??
           ((id) => FirebaseFirestore.instance
               .collection(collection)
               .doc(id)
               .delete()),
       _metadata = metadata ?? _context,
       _online = online ?? currentNetworkStatus,
       _now = now ?? DateTime.now;
  static final instance = SyncErrorLogService(automaticMaintenance: true);
  static const collection = 'sync_error_logs';
  static const storageKey = 'sync_error_log_outbox_v1';
  final BookingStorageBackend _backend;
  final Future<void> Function(String, Map<String, dynamic>) _writer;
  final Future<void> Function(String) _deleter;
  final Future<Map<String, dynamic>> Function(String?) _metadata;
  final bool Function() _online;
  final DateTime Function() _now;
  final bool automaticMaintenance;
  final Duration uploadTimeout, stallAfter, localPersistenceTimeout;
  Timer? _maintenance;
  StreamSubscription<bool>? _networkSubscription;
  final Map<String, _QueueProgress> _progress = {};
  final List<Map<String, dynamic>> _transitions = [];
  Future<void>? _starting;
  bool? _lastOnline;
  Future<void> _serial = Future.value();
  Future<void>? _flushing;
  Future<void>? _boundedFlush;
  DateTime? _retryAfter;
  bool _enabled = false;
  static Future<PackageInfo>? _package;
  late final _outbox = SyncDiagnosticOutbox(_backend);
  bool _migrated = false;

  Future<void> _prepareOutbox() async {
    if (_migrated) return;
    await _backend.initialize();
    for (final row in await _readLegacy()) {
      final existing = await _outbox.get(row['fingerprint'] as String);
      if (existing == null || existing['occurrences'] < row['occurrences']) {
        await _outbox.put(row);
      }
      await Future<void>.delayed(Duration.zero);
    }
    // Only discard the legacy container once every valid report is durable.
    await _backend.writeStringList(storageKey, []);
    _migrated = true;
  }

  static Future<void> _write(String id, Map<String, dynamic> data) =>
      FirebaseFirestore.instance.collection(collection).doc(id).set({
        ...data,
        'received_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  static Future<Map<String, dynamic>> _context(String? owner) async {
    final auth = createAuthStorageBackend();
    await auth.initialize();
    final session = await auth.readString('paltranco_current_user_id');
    final userId = owner ?? session;
    final users =
        await FirestoreCacheStore.instance.readDocumentMaps('users') ?? [];
    final user = users.where((u) => '${u['id']}' == userId).firstOrNull;
    String? version;
    String? build;
    try {
      final info = await (_package ??= PackageInfo.fromPlatform());
      version = info.version;
      build = info.buildNumber;
    } catch (_) {
      /* Metadata availability must not lose the error. */
    }
    return {
      'user_id': userId,
      'user_name': user?['name']?.toString(),
      'role': user?['role']?.toString() ?? 'unknown',
      'session_user_id': session,
      'app_version': version,
      'build_number': build,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'environment': syncErrorEnvironment(),
      'build_commit': const String.fromEnvironment(
        'APP_BUILD_COMMIT',
        defaultValue: 'not supplied',
      ),
      'build_mode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      'app_origin': kIsWeb ? Uri.base.origin : null,
    };
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _serial.then((_) => action());
    _serial = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    // Bound callers, but retain the actual lock until storage settles. A late
    // write must never overwrite a newer outbox snapshot.
    return result.timeout(localPersistenceTimeout);
  }

  Future<List<Map<String, dynamic>>> _readLegacy() async {
    await _backend.initialize();
    final rows = <Map<String, dynamic>>[];
    final corrupt = <String>[];
    for (final raw in await _backend.readStringList(storageKey)) {
      try {
        final row = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (row['id'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch('${row['fingerprint']}') ||
            row['occurrences'] is! int ||
            row['occurrences'] < 0) {
          throw const FormatException('Invalid diagnostic row');
        }
        rows.add(row);
      } catch (_) {
        corrupt.add(raw);
      }
    }
    if (corrupt.isNotEmpty) {
      // Quarantine is best effort; damaged data cannot reject healthy reports.
      try {
        await _backend.writeStringList(
          '${storageKey}_quarantine',
          corrupt
              .take(100)
              .map(
                (raw) => sanitize(
                  raw.length > 64000 ? raw.substring(0, 64000) : raw,
                ),
              )
              .toList(),
        );
      } catch (_) {}
    }
    return rows;
  }

  /// Credentials are redacted even when a SDK embeds a URL in its exception.
  static String sanitize(String value) => value
      .replaceAllMapped(
        RegExp(
          r'data:([^;,\s]+);base64,([A-Za-z0-9+/=\r\n]+)',
          caseSensitive: false,
        ),
        (m) =>
            '[INLINE MEDIA OMITTED: ${m[1]}; encoded_chars=${m[2]!.length}; sha256=${sha256.convert(utf8.encode(m[2]!))}]',
      )
      .replaceAllMapped(
        RegExp(
          r'''(token|password|authorization|api[_-]?key|secret)(["'\s]*[=:]["'\s]*)([^\s&,}"']+)''',
          caseSensitive: false,
        ),
        (m) => '${m[1]}${m[2]}[REDACTED]',
      )
      .replaceAll(
        RegExp(r'Bearer\s+[^\s,]+', caseSensitive: false),
        'Bearer [REDACTED]',
      );

  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    _enabled = true;
    _lastOnline = _online();
    if (automaticMaintenance) {
      _networkSubscription ??= networkStatusEvents().listen(observeNetwork);
      _maintenance ??= Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(checkForStalls());
        unawaited(flush());
      });
    }
    await refreshQueueDiagnostics();
    await flush();
  }

  Future<void> report(
    Object error,
    StackTrace stack, {
    required String source,
    required String operation,
    String target = '',
    String? owner,
    String kind = 'foreground_failure',
    Map<String, dynamic> details = const {},
  }) => capture(
    source: source,
    operation: operation,
    entryId: target.isEmpty ? operation : target,
    target: target,
    owner: owner,
    error: error.toString(),
    stack: stack.toString(),
    attempt: _now().microsecondsSinceEpoch,
    kind: kind,
    details: {
      ...details,
      'error_type': error.runtimeType.toString(),
      'suspected_layer': classify(error),
      if (error is FirebaseException) 'firebase_code': error.code,
      if (error is FirebaseException) 'firebase_plugin': error.plugin,
    },
  );

  static String classify(Object error) {
    if (error is TimeoutException) return 'timeout_or_network';
    if (error is FirebaseException) return error.plugin;
    if (error is FormatException || error is TypeError) return 'data_structure';
    if ('$error'.toLowerCase().contains('sync conflict')) {
      return 'version_or_assignment_conflict';
    }
    return 'frontend_or_unknown';
  }

  void observeNetwork(bool online) {
    final previous = _lastOnline;
    _lastOnline = online;
    if (previous == online) return;
    final transition = {
      'from_online': previous,
      'to_online': online,
      'at': _now().toUtc().toIso8601String(),
    };
    _transitions.add(transition);
    if (_transitions.length > 12) _transitions.removeAt(0);
    // Reconnection starts a fresh observation window, not a false instant stall.
    for (final state in _progress.values) {
      state.since = _now();
      state.reportedAt = null;
    }
    unawaited(
      capture(
        source: 'network_status_events_web.dart',
        operation: 'connection transition',
        entryId: '${transition['at']}',
        target: 'connectivity',
        error: 'Network connection state changed',
        stack: '',
        attempt: 1,
        kind: 'network_transition',
        details: transition,
      ),
    );
    if (online) {
      unawaited(refreshQueueDiagnostics());
      _retryAfter = null;
      unawaited(flush());
    }
  }

  void observeQueue(
    String source, {
    required int pending,
    required int failed,
    required bool syncing,
    required int processed,
    required int total,
  }) {
    final previous = _progress[source];
    if (failed > 0) _attentionSources.add(source);
    if (_enabled && !syncing && _attentionSources.contains(source)) {
      if (failed == 0) _attentionSources.remove(source);
      unawaited(refreshQueueDiagnostics());
    }
    if (pending == 0 && !syncing) {
      if (previous?.reportedAt != null) {
        unawaited(
          capture(
            source: source,
            operation: 'queue recovered',
            entryId: previous!.since.toIso8601String(),
            target: source,
            error: 'Previously stalled queue has completed',
            stack: '',
            attempt: 1,
            kind: 'queue_recovered',
          ),
        );
      }
      _progress.remove(source);
      return;
    }
    final state = previous ?? _QueueProgress(_now());
    if (previous != null &&
        (pending < state.pending || processed > state.processed)) {
      state.since = _now();
      state.reportedAt = null;
    }
    state.pending = pending;
    state.failed = failed;
    state.syncing = syncing;
    state.processed = processed;
    state.total = total;
    _progress[source] = state;
  }

  Future<void> checkForStalls() async {
    if (!_online()) return;
    final now = _now();
    for (final entry in _progress.entries.toList()) {
      final state = entry.value;
      if (now.difference(state.since) < stallAfter ||
          (state.reportedAt != null &&
              now.difference(state.reportedAt!) < const Duration(minutes: 5))) {
        continue;
      }
      state.reportedAt = now;
      await capture(
        source: entry.key,
        operation: 'queue progress watchdog',
        entryId: state.since.toUtc().toIso8601String(),
        target: entry.key,
        error: 'Queue has no observed progress while browser reports online',
        stack: '',
        attempt: now.millisecondsSinceEpoch,
        kind: 'queue_stalled',
        details: {
          'pending': state.pending,
          'failed': state.failed,
          'syncing': state.syncing,
          'processed': state.processed,
          'total': state.total,
          'no_progress_seconds': now.difference(state.since).inSeconds,
          'note':
              'Observation, not a confirmed cause. Check errors, retry deadlines and connectivity.',
        },
      );
    }
  }

  void dispose() {
    _maintenance?.cancel();
    _networkSubscription?.cancel();
  }

  Future<void>? _refreshingQueueDiagnostics;
  final _attentionSources = <String>{};
  bool _refreshAgain = false;

  /// Coalesce queue-settled/reconnect events; never add a polling listener.
  Future<void> refreshQueueDiagnostics() {
    _refreshAgain = true;
    return _refreshingQueueDiagnostics ??= (() async {
      try {
        do {
          _refreshAgain = false;
          await _backfill();
        } while (_refreshAgain);
      } finally {
        _refreshingQueueDiagnostics = null;
      }
    })();
  }

  static bool requiresAttention(String prefix, Map<String, dynamic> entry) {
    if (prefix == 'offline_mutation_queue_v1') {
      return entry['is_blocked'] == true;
    }
    // A photo wait is normally informational, but once the queue has recorded a
    // retryable error it is no longer silent. Keep it in the review stream just
    // like cleanup/media failures.
    return entry['last_error'] != null;
  }

  static String _actionFingerprint(String scope, String entryId) => sha256
      .convert(utf8.encode(jsonEncode(['queue_action_v2', scope, entryId])))
      .toString();

  Future<void> _clearAttention(String scope, String entryId) async {
    var changed = false;
    await _locked(() async {
      await _prepareOutbox();
      await _outbox.update(_actionFingerprint(scope, entryId), (row) async {
        if (row == null || row['attention_required'] != true) return null;
        changed = true;
        row['attention_required'] = false;
        row['dirty'] = true;
        row.remove('last_uploaded_at');
        return row;
      });
    });
    if (changed) unawaited(flush());
  }

  Future<void> _backfill() async {
    try {
      await _backend.initialize();
      final auth = createAuthStorageBackend();
      await auth.initialize();
      final scopes = <String>{
        'signed_out',
        ...await auth.readStringList('paltranco_known_session_user_ids'),
        if (await auth.readString('paltranco_current_user_id')
            case final String id)
          id,
      };
      for (final prefix in [
        'offline_mutation_queue_v1',
        'offline_media_sync_queue_v1',
        'offline_cleanup_queue_v1',
        'booking_pending_upload_queue_v1',
      ]) {
        for (final owner in scopes) {
          for (final raw in await _backend.readStringList('$prefix::$owner')) {
            try {
              final entry = Map<String, dynamic>.from(jsonDecode(raw) as Map);
              final attention = requiresAttention(prefix, entry);
              if (!attention && '${entry['last_error'] ?? ''}'.isEmpty) {
                await _clearAttention('$prefix::$owner', '${entry['id']}');
                continue;
              }
              await capture(
                source: prefix,
                operation: '${entry['kind'] ?? 'bookingPhotoUpload'}',
                entryId: '${entry['id']}',
                target:
                    '${entry['collection_key'] ?? ''}/${entry['target_id'] ?? entry['booking_id'] ?? entry['thread_id'] ?? entry['target_path'] ?? ''}',
                owner: owner,
                actionAt: entry['created_at']?.toString(),
                error:
                    '${entry['last_error'] ?? 'Queued action needs review; original error was not recorded.'}',
                stack:
                    '${entry['error_diagnostics'] ?? 'Original stack trace was not recorded by this app version.'}',
                attempt: (entry['retry_count'] as num?)?.toInt() ?? 0,
                failedAt: RegExp(
                  r'Failed at \(UTC\): ([^\n]+)',
                ).firstMatch('${entry['error_diagnostics'] ?? ''}')?.group(1),
                kind: 'persisted_queue_failure',
                attentionRequired: attention,
                details: {
                  ..._persistedConflictContext(entry['error_diagnostics']),
                  'queue_snapshot': pendingMutationSnapshot(entry),
                  'base_updated_at': entry['base_updated_at'],
                  'pending_updated_at':
                      (entry['payload'] as Map?)?['updated_at'],
                  'payload_keys': (entry['payload'] as Map?)?.keys
                      .map((key) => '$key')
                      .toList(),
                  'blocked': entry['is_blocked'],
                  'next_retry_at': entry['next_retry_at'],
                  'recovered_from_device': true,
                },
              );
            } catch (_) {
              /* Skip only malformed legacy entries, never delete them. */
            }
          }
        }
      }
    } catch (_) {
      /* Live failures are still captured if legacy scanning fails. */
    }
  }

  static String? queuePrefix(String source) {
    if (source.contains('offline_mutation_queue')) {
      return 'offline_mutation_queue_v1';
    }
    if (source.contains('offline_media_sync')) {
      return 'offline_media_sync_queue_v1';
    }
    if (source.contains('offline_cleanup_queue')) {
      return 'offline_cleanup_queue_v1';
    }
    if (source.contains('booking_offline_upload_queue') ||
        source == 'booking_pending_upload_queue_v1') {
      return 'booking_pending_upload_queue_v1';
    }
    return null;
  }

  /// Call only after the specific action has successfully completed.
  Future<void> resolveQueueEntries(String scope, Set<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _locked(() async {
        await _prepareOutbox();
        // Confirmed success is necessary but insufficient: a newer edit or an
        // in-progress retry may still retain the same action in durable storage.
        final pending = <String>{};
        for (final raw in await _backend.readStringList(scope)) {
          pending.add('${(jsonDecode(raw) as Map)['id']}');
        }
        final completed = ids.difference(pending);
        if (completed.isEmpty) return;
        await _outbox.resolveEntries(
          scope,
          completed,
          _now().toUtc().toIso8601String(),
        );
      });
      unawaited(flush());
    } catch (_) {}
  }

  static bool _isSyncError(Object? kind) => const {
    'queue_failure',
    'persisted_queue_failure',
    'queue_stalled',
    'kpi_diagnostic',
    // A discarded or stalled queue cycle is a sync failure the user must be
    // able to see. Without this the report is dropped before it is persisted.
    'queue_reclaimed',
    'mutation_flush_timeout',
    'cleanup_flush_timeout',
    'media_flush_timeout',
    'queue_status_read_failed',
    // A queued edit that was retired because a newer server version won. No
    // write happened, so this report is the only record that it was dropped.
    'queue_edit_superseded',
  }.contains(kind);

  Future<void> capture({
    required String source,
    required String operation,
    required String entryId,
    required String target,
    required String error,
    required String stack,
    required int attempt,
    String? owner,
    String? actionAt,
    String? failedAt,
    String kind = 'queue_failure',
    bool? attentionRequired,
    Map<String, dynamic> details = const {},
  }) async {
    if (!_isSyncError(kind)) return;
    try {
      Map<String, dynamic> metadata;
      try {
        metadata = await _metadata(owner).timeout(const Duration(seconds: 2));
      } catch (_) {
        metadata = {'user_id': owner, 'role': 'unknown'};
      }
      if (const {
        'online_queue_activity',
        'queue_stalled',
        'network_transition',
      }.contains(kind)) {
        try {
          final baseDetails = details;
          details = await (() async {
            final scope =
                owner ?? metadata['user_id']?.toString() ?? 'signed_out';
            final queued = <Map<String, dynamic>>[];
            final scopes = <String>{scope, 'signed_out'};
            final auth = createAuthStorageBackend();
            await auth.initialize();
            scopes.addAll(
              await auth.readStringList('paltranco_known_session_user_ids'),
            );
            await _backend.initialize();
            for (final prefix in [
              'offline_mutation_queue_v1',
              'offline_media_sync_queue_v1',
              'offline_cleanup_queue_v1',
              'booking_pending_upload_queue_v1',
            ]) {
              for (final queueOwner in scopes) {
                for (final raw in await _backend.readStringList(
                  '$prefix::$queueOwner',
                )) {
                  try {
                    final q = jsonDecode(raw) as Map;
                    queued.add({
                      'queue': prefix,
                      'owner': queueOwner,
                      'last_error': sanitize('${q['last_error'] ?? ''}'),
                      'next_retry_at': q['next_retry_at'],
                      'entry_id': q['id'],
                      'operation': q['kind'],
                      'target_id':
                          q['target_id'] ?? q['booking_id'] ?? q['thread_id'],
                      'collection': q['collection_key'],
                      'action_at': q['created_at'],
                      'retry_count': q['retry_count'],
                      'blocked': q['is_blocked'],
                    });
                  } catch (_) {
                    /* A malformed item cannot prevent other logs. */
                  }
                }
              }
            }
            return {
              ...baseDetails,
              'queue_items': queued.take(100).toList(),
              'queue_item_count': queued.length,
              'queue_snapshot_truncated': queued.length > 100,
            };
          })().timeout(localPersistenceTimeout);
        } catch (error) {
          details = {...details, 'queue_snapshot_error': sanitize('$error')};
        }
      }
      final safeError = sanitize(error);
      final safeStack = sanitize(stack);
      final prefix =
          (kind == 'queue_failure' || kind == 'persisted_queue_failure')
          ? queuePrefix(source)
          : null;
      final scope = prefix == null
          ? null
          : '$prefix::${owner ?? metadata['user_id'] ?? 'signed_out'}';
      final fingerprint = scope != null
          ? _actionFingerprint(scope, entryId)
          : sha256
                .convert(
                  utf8.encode(
                    jsonEncode([
                      owner ?? metadata['user_id'],
                      source,
                      operation,
                      entryId,
                      safeError,
                      safeStack,
                    ]),
                  ),
                )
                .toString();
      await _locked(() async {
        await _prepareOutbox();
        final time = failedAt ?? _now().toUtc().toIso8601String();
        await _outbox.update(fingerprint, (row) async {
          if (scope != null && await _outbox.isResolved(scope, entryId)) {
            return null;
          }
          if (row != null && row['last_attempt'] == attempt) {
            final storedDetails = Map<String, dynamic>.from(
              row['details'] as Map? ?? {},
            );
            final incomingDetails = sanitizeDetails(details);
            if (storedDetails['details_truncated'] == true &&
                incomingDetails['queue_snapshot'] is Map) {
              storedDetails.remove('details_truncated');
              storedDetails.remove('summary');
            }
            final additions = {
              for (final entry in incomingDetails.entries)
                if (!storedDetails.containsKey(entry.key) ||
                    (entry.key == 'queue_snapshot' &&
                        jsonEncode(storedDetails[entry.key]) !=
                            jsonEncode(entry.value)))
                  entry.key: entry.value,
            };
            final attentionChanged =
                attentionRequired != null &&
                row['attention_required'] != attentionRequired;
            if (!attentionChanged && additions.isEmpty) return null;
            if (attentionChanged) row['attention_required'] = attentionRequired;
            row['details'] = sanitizeDetails({...storedDetails, ...additions});
            row['dirty'] = true;
            row.remove('last_uploaded_at');
            return row;
          }
          if (row == null) {
            final installation = await _backend.readStringList(
              '${storageKey}_device',
            );
            final device = installation.isNotEmpty
                ? installation.first
                : '${_now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
            if (installation.isEmpty) {
              await _backend.writeStringList('${storageKey}_device', [device]);
            }
            row = {
              'id': '${device}_$fingerprint',
              'fingerprint': fingerprint,
              'device_id': device,
              'first_failed_at': time,
              'occurrences': 0,
            };
          }
          if (attentionRequired != null &&
              row['attention_required'] != attentionRequired) {
            // Count transitions must not wait for the repeated-error throttle.
            row.remove('last_uploaded_at');
          }
          row.addAll({
            ...metadata,
            'queue_scope': ?scope,
            'schema_version': 2,
            'attention_required':
                attentionRequired ?? row['attention_required'] ?? false,
            'kind': kind,
            'source': source,
            'operation': operation,
            'queue_entry_id': entryId,
            'target': sanitize(target),
            'action_at': actionAt,
            'last_failed_at': time,
            'captured_at': _now().toUtc().toIso8601String(),
            'last_attempt': attempt,
            'occurrences': (row['occurrences'] as int) + 1,
            'error': safeError.length > 16000
                ? safeError.substring(0, 16000)
                : safeError,
            'stack_trace': safeStack.length > 48000
                ? safeStack.substring(0, 48000)
                : safeStack,
            'diagnostic_truncated':
                safeError.length > 16000 || safeStack.length > 48000,
            'online_at_failure': _online(),
            'details': sanitizeDetails({
              ...details,
              'recent_network_transitions': List.of(_transitions),
            }),
            'dirty': true,
          });
          return row;
        });
      });
      unawaited(flush());
    } catch (_) {
      // Diagnostic storage failures must not change the original queue outcome.
    }
  }

  static Map<String, dynamic> _persistedConflictContext(Object? diagnostic) {
    if (diagnostic is! String) return {};
    final marker = diagnostic.indexOf('Context:\n');
    if (marker < 0) return {};
    try {
      final decoded = jsonDecode(
        diagnostic.substring(marker + 9).split('\n').first,
      );
      if (decoded is! Map || decoded['details_truncated'] == true) return {};
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return {};
    }
  }

  /// Read-only evidence from the durable queue. A version timestamp is not a
  /// historical document snapshot; older queues never retained that document.
  static Map<String, dynamic> pendingMutationSnapshot(
    Map<String, dynamic> entry,
  ) => {
    'schema_version': 1,
    'queue_entry_id': entry['id'],
    'operation': entry['kind'],
    'collection': entry['collection_key'],
    'target_id': entry['target_id'],
    'action_at': entry['created_at'],
    'base_updated_at': entry['base_updated_at'],
    'original_document_available': false,
    'original_document_unavailable_reason':
        'The queue retains the original version timestamp, not the pre-edit document.',
    'pending_payload_available': entry['payload'] is Map,
    if (entry['payload'] is Map) 'pending_payload': entry['payload'],
  };

  static Map<String, dynamic> sanitizeDetails(Map<String, dynamic> details) {
    Object? clean(Object? value) {
      if (value is Map) {
        return {
          for (final e in value.entries)
            e.key.toString():
                RegExp(
                  r'password|authorization|token|secret|api.?key',
                  caseSensitive: false,
                ).hasMatch('${e.key}')
                ? '[REDACTED]'
                : clean(e.value),
        };
      }
      if (value is Iterable) return value.map(clean).toList();
      if (value is String) return sanitize(value);
      if (value == null || value is num || value is bool) return value;
      return sanitize('$value');
    }

    final safe = clean(details) as Map<String, dynamic>;
    final encoded = jsonEncode(safe);
    return encoded.length <= 32000
        ? safe
        : {'details_truncated': true, 'summary': encoded.substring(0, 32000)};
  }

  Future<void> flush() {
    if (!_enabled || !_online() || (_retryAfter?.isAfter(_now()) ?? false)) {
      return Future.value();
    }
    if (_flushing != null) return _boundedFlush!;
    final future = _flushing = _flush();
    future.then((_) {
      if (identical(_flushing, future)) {
        _flushing = null;
        _boundedFlush = null;
      }
    });
    // A hung upload owns one actual operation and one bounded caller future.
    // Maintenance ticks must not accumulate waiting writes or callbacks.
    return _boundedFlush = future.timeout(uploadTimeout, onTimeout: () {});
  }

  Future<void> _flush() async {
    try {
      while (_online()) {
        final ready = await _locked(() async {
          await _prepareOutbox();
          return _outbox.ready(_now());
        });
        if (ready.isEmpty) break;
        for (final row in ready) {
          if (!_online()) return;
          // Cross-tab ordering includes the actual SDK future, even if this
          // caller times out. A late upload cannot run after its deletion.
          await withDiagnosticWriteLock(() async {
            final current = await _outbox.get(row['fingerprint'] as String);
            if (current == null || current['dirty'] != true) return;
            if (!_isSyncError(current['kind'])) {
              // Older app versions may have queued informational/general logs.
              // Suppress only their diagnostic upload, never business actions.
              await _outbox.update(current['fingerprint'] as String, (
                saved,
              ) async {
                if (saved == null || _isSyncError(saved['kind'])) return null;
                saved['dirty'] = false;
                saved['suppressed_at'] = _now().toUtc().toIso8601String();
                return saved;
              });
              return;
            }
            final scope = current['queue_scope'] as String?;
            final resolved =
                current['resolved_at'] != null ||
                (scope != null &&
                    await _outbox.isResolved(
                      scope,
                      current['queue_entry_id'] as String,
                    ));
            if (resolved) {
              if (scope == null) {
                throw StateError('Missing completed queue scope');
              }
              for (final raw in await _backend.readStringList(scope)) {
                if ('${(jsonDecode(raw) as Map)['id']}' ==
                    current['queue_entry_id']) {
                  throw StateError(
                    'Error cleanup deferred: action is still queued or syncing',
                  );
                }
              }
              final device = await _backend.readStringList(
                '${storageKey}_device',
              );
              if (device.isEmpty ||
                  current['device_id'] != device.first ||
                  !('${current['id']}'.startsWith('${device.first}_'))) {
                throw StateError(
                  'Refusing to delete a report from another device',
                );
              }
              await _deleter(current['id'] as String);
            } else {
              final data = Map<String, dynamic>.from(current)
                ..remove('dirty')
                ..remove('last_uploaded_at');
              data['copy_report'] = const JsonEncoder.withIndent(
                '  ',
              ).convert(data);
              await _writer(current['id'] as String, data);
            }
            await _outbox.update(current['fingerprint'] as String, (
              saved,
            ) async {
              if (saved == null) return null;
              if (saved['occurrences'] == current['occurrences'] &&
                  saved['resolved_at'] == current['resolved_at']) {
                saved['last_uploaded_at'] = _now().toUtc().toIso8601String();
                saved['dirty'] = false;
              }
              return saved;
            });
          }, name: 'paltranco_sync_diagnostic_remote_v1');
        }
        await Future<void>.delayed(Duration.zero);
      }
    } catch (_) {
      _retryAfter = _now().add(const Duration(minutes: 1));
      // Never report logger failures back through itself or a business queue.
    }
  }
}

class _QueueProgress {
  _QueueProgress(this.since);
  DateTime since;
  DateTime? reportedAt;
  int pending = 0, failed = 0, processed = 0, total = 0;
  bool syncing = false;
}
