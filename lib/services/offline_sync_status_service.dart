import 'package:webapp/services/sync_error_log_service.dart';
import 'dart:async';
import 'package:webapp/utils/latest_value_worker.dart';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/utils/functions.dart';

@immutable
class OfflineQueueStatusSnapshot {
  const OfflineQueueStatusSnapshot({
    required this.pendingCount,
    required this.isSyncing,
    required this.processedInBatch,
    required this.totalInBatch,
    this.failedCount = 0,
    this.lastSyncAt,
  });

  const OfflineQueueStatusSnapshot.idle({
    this.pendingCount = 0,
    this.failedCount = 0,
  }) : isSyncing = false,
       processedInBatch = 0,
       totalInBatch = 0,
       lastSyncAt = null;

  final int pendingCount;
  final bool isSyncing;
  final int processedInBatch;
  final int totalInBatch;
  final int failedCount;
  final DateTime? lastSyncAt;

  OfflineQueueStatusSnapshot copyWith({
    int? pendingCount,
    bool? isSyncing,
    int? processedInBatch,
    int? totalInBatch,
    int? failedCount,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
  }) {
    return OfflineQueueStatusSnapshot(
      pendingCount: pendingCount ?? this.pendingCount,
      isSyncing: isSyncing ?? this.isSyncing,
      processedInBatch: processedInBatch ?? this.processedInBatch,
      totalInBatch: totalInBatch ?? this.totalInBatch,
      failedCount: failedCount ?? this.failedCount,
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
    );
  }
}

@immutable
class OfflineSyncStatusSnapshot {
  const OfflineSyncStatusSnapshot({
    required this.isOnline,
    required this.pendingActions,
    required this.failedActions,
    required this.isSyncing,
    required this.processedActions,
    required this.totalActionsInBatch,
    this.lastSyncAt,
  });

  const OfflineSyncStatusSnapshot.initial()
    : isOnline = true,
      pendingActions = 0,
      failedActions = 0,
      isSyncing = false,
      processedActions = 0,
      totalActionsInBatch = 0,
      lastSyncAt = null;

  final bool isOnline;
  final int pendingActions;
  final int failedActions;
  final bool isSyncing;
  final int processedActions;
  final int totalActionsInBatch;
  final DateTime? lastSyncAt;

  bool get hasPendingActions => pendingActions > 0;
  bool get hasFailedActions => failedActions > 0;
}

@immutable
class AdminOfflineQueueScopeSnapshot {
  const AdminOfflineQueueScopeSnapshot({
    required this.scopeKey,
    required this.userId,
    required this.userLabel,
    required this.roleLabel,
    required this.snapshot,
  });

  final String scopeKey;
  final String? userId;
  final String userLabel;
  final String roleLabel;
  final OfflineSyncStatusSnapshot snapshot;
}

class OfflineSyncStatusService extends ChangeNotifier {
  OfflineSyncStatusService._();

  static final OfflineSyncStatusService instance = OfflineSyncStatusService._();
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';

  bool _isInitialized = false;
  bool _isOnline = currentNetworkStatus();
  final AuthStorageBackend _authStorage = createAuthStorageBackend();
  OfflineQueueStatusSnapshot _bookingStatus =
      const OfflineQueueStatusSnapshot.idle();
  OfflineQueueStatusSnapshot _mediaStatus =
      const OfflineQueueStatusSnapshot.idle();
  OfflineQueueStatusSnapshot _mutationStatus =
      const OfflineQueueStatusSnapshot.idle();
  OfflineQueueStatusSnapshot _cleanupStatus =
      const OfflineQueueStatusSnapshot.idle();
  OfflineSyncStatusSnapshot _snapshot =
      const OfflineSyncStatusSnapshot.initial();
  OfflineSyncStatusSnapshot _knownSessionSnapshot =
      const OfflineSyncStatusSnapshot.initial();

  OfflineSyncStatusSnapshot get snapshot => _snapshot;
  OfflineSyncStatusSnapshot get knownSessionSnapshot => _knownSessionSnapshot;

  Future<void> initialize() async {
    unawaited(SyncErrorLogService.instance.flush());
    if (_isInitialized) {
      return;
    }
    await _authStorage.initialize();
    _isInitialized = true;
    unawaited(SyncErrorLogService.instance.start());
    _bookingStatus = BookingOfflineUploadQueueService.instance.currentStatus;
    _mediaStatus = OfflineMediaSyncService.instance.currentStatus;
    _mutationStatus = OfflineMutationQueueService.instance.currentStatus;
    _cleanupStatus = OfflineCleanupQueueService.instance.currentStatus;
    _recompute();
    _knownSessionRefresh.add(true);
    networkStatusEvents().listen((isOnline) {
      _isOnline = isOnline;
      _recompute();
      _knownSessionRefresh.add(true);
    });
    BookingOfflineUploadQueueService.instance.statusStream.listen((status) {
      _bookingStatus = status;
      _recompute();
      _knownSessionRefresh.add(true);
    });
    OfflineMediaSyncService.instance.statusStream.listen((status) {
      _mediaStatus = status;
      _recompute();
      _knownSessionRefresh.add(true);
    });
    OfflineMutationQueueService.instance.statusStream.listen((status) {
      _mutationStatus = status;
      _recompute();
      _knownSessionRefresh.add(true);
    });
    OfflineCleanupQueueService.instance.statusStream.listen((status) {
      _cleanupStatus = status;
      _recompute();
      _knownSessionRefresh.add(true);
    });
  }

  Future<OfflineSyncStatusSnapshot> readSnapshotForUserScopes({
    Iterable<String> userIds = const [],
    bool includeSignedOut = true,
  }) async {
    await initialize();
    final normalizedUserIds = userIds
        .map(normalizeId)
        .whereType<String>()
        .toSet()
        .toList();
    final bookingStatuses = await BookingOfflineUploadQueueService.instance
        .readScopedStatuses(
          userIds: normalizedUserIds,
          includeSignedOut: includeSignedOut,
        );
    final mediaStatuses = await OfflineMediaSyncService.instance
        .readScopedStatuses(
          userIds: normalizedUserIds,
          includeSignedOut: includeSignedOut,
        );
    final mutationStatuses = await OfflineMutationQueueService.instance
        .readScopedStatuses(
          userIds: normalizedUserIds,
          includeSignedOut: includeSignedOut,
        );
    final cleanupStatuses = await OfflineCleanupQueueService.instance
        .readScopedStatuses(
          userIds: normalizedUserIds,
          includeSignedOut: includeSignedOut,
        );

    final bookingAggregate = _aggregateQueueStatuses(bookingStatuses.values);
    final mediaAggregate = _aggregateQueueStatuses(mediaStatuses.values);
    final mutationAggregate = _aggregateQueueStatuses(mutationStatuses.values);
    final cleanupAggregate = _aggregateQueueStatuses(cleanupStatuses.values);

    return _mergeStatuses(
      isOnline: _isOnline,
      bookingStatus: bookingAggregate,
      mediaStatus: mediaAggregate,
      mutationStatus: mutationAggregate,
      cleanupStatus: cleanupAggregate,
    );
  }

  Future<OfflineSyncStatusSnapshot> readKnownSessionSnapshot({
    bool includeSignedOut = true,
  }) async {
    await initialize();
    final knownUsers = await _authStorage.readStringList(
      _knownSessionUserIdsKey,
    );
    return readSnapshotForUserScopes(
      userIds: knownUsers,
      includeSignedOut: includeSignedOut,
    );
  }

  Future<List<AdminOfflineQueueScopeSnapshot>> readKnownSessionScopeDetails({
    bool includeSignedOut = true,
  }) async {
    await initialize();
    final knownUsers = await _authStorage.readStringList(
      _knownSessionUserIdsKey,
    );
    final normalizedUserIds = knownUsers
        .map(normalizeId)
        .whereType<String>()
        .toSet()
        .toList();
    final userDocuments =
        await FirestoreCacheStore.instance.readDocumentMaps('users') ??
        const <Map<String, dynamic>>[];
    final usersById = <String, Map<String, dynamic>>{};
    for (final document in userDocuments) {
      final userId = normalizeId(document['id']?.toString());
      if (userId != null) {
        usersById[userId] = document;
      }
    }

    final bookingStatuses = await BookingOfflineUploadQueueService.instance
        .readScopedStatuses(
          userIds: normalizedUserIds,
          includeSignedOut: includeSignedOut,
        );
    final mediaStatuses = await OfflineMediaSyncService.instance
        .readScopedStatuses(
          userIds: normalizedUserIds,
          includeSignedOut: includeSignedOut,
        );
    final mutationStatuses = await OfflineMutationQueueService.instance
        .readScopedStatuses(
          userIds: normalizedUserIds,
          includeSignedOut: includeSignedOut,
        );
    final cleanupStatuses = await OfflineCleanupQueueService.instance
        .readScopedStatuses(
          userIds: normalizedUserIds,
          includeSignedOut: includeSignedOut,
        );

    final scopeKeys = <String>{
      ...bookingStatuses.keys,
      ...mediaStatuses.keys,
      ...mutationStatuses.keys,
      ...cleanupStatuses.keys,
    };

    final details =
        scopeKeys
            .map((scopeKey) {
              final isSignedOut = scopeKey == 'signed_out';
              final userId = isSignedOut ? null : normalizeId(scopeKey);
              final userData = userId == null ? null : usersById[userId];
              final mergedSnapshot = _mergeStatuses(
                isOnline: _isOnline,
                bookingStatus:
                    bookingStatuses[scopeKey] ??
                    const OfflineQueueStatusSnapshot.idle(),
                mediaStatus:
                    mediaStatuses[scopeKey] ??
                    const OfflineQueueStatusSnapshot.idle(),
                mutationStatus:
                    mutationStatuses[scopeKey] ??
                    const OfflineQueueStatusSnapshot.idle(),
                cleanupStatus:
                    cleanupStatuses[scopeKey] ??
                    const OfflineQueueStatusSnapshot.idle(),
              );
              return AdminOfflineQueueScopeSnapshot(
                scopeKey: scopeKey,
                userId: userId,
                userLabel: isSignedOut
                    ? 'Signed-out queue'
                    : _userLabelFromMap(userData, fallbackUserId: userId),
                roleLabel: isSignedOut
                    ? 'Local device'
                    : _roleLabelFromMap(userData),
                snapshot: mergedSnapshot,
              );
            })
            .where((detail) {
              return detail.snapshot.pendingActions > 0 ||
                  detail.snapshot.isSyncing;
            })
            .toList()
          ..sort((left, right) {
            final byCount = right.snapshot.pendingActions.compareTo(
              left.snapshot.pendingActions,
            );
            if (byCount != 0) {
              return byCount;
            }
            return left.userLabel.toLowerCase().compareTo(
              right.userLabel.toLowerCase(),
            );
          });

    return details;
  }

  void _recompute() {
    final logger = SyncErrorLogService.instance;
    for (final entry in {
      'booking_offline_upload_queue_service.dart': _bookingStatus,
      'offline_media_sync_service.dart': _mediaStatus,
      'offline_mutation_queue_service.dart': _mutationStatus,
      'offline_cleanup_queue_service.dart': _cleanupStatus,
    }.entries) {
      final state = entry.value;
      logger.observeQueue(
        entry.key,
        pending: state.pendingCount,
        failed: state.failedCount,
        syncing: state.isSyncing,
        processed: state.processedInBatch,
        total: state.totalInBatch,
      );
    }
    unawaited(SyncErrorLogService.instance.flush());
    final next = _mergeStatuses(
      isOnline: _isOnline,
      bookingStatus: _bookingStatus,
      mediaStatus: _mediaStatus,
      mutationStatus: _mutationStatus,
      cleanupStatus: _cleanupStatus,
    );
    if (_sameSnapshot(_snapshot, next)) {
      return;
    }
    if (next.isOnline &&
        next.isSyncing &&
        (!_snapshot.isOnline || !_snapshot.isSyncing)) {
      unawaited(
        SyncErrorLogService.instance.capture(
          source: 'offline_sync_status_service.dart',
          operation: 'onlineQueueActivity',
          entryId: 'online-${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
          target: 'sync_status',
          error: 'Queue syncing while network reports online',
          stack: StackTrace.current.toString(),
          attempt: 1,
          kind: 'online_queue_activity',
          details: {
            'pending_actions': next.pendingActions,
            'failed_actions': next.failedActions,
            'previous_online': _snapshot.isOnline,
            'booking_syncing': _bookingStatus.isSyncing,
            'media_syncing': _mediaStatus.isSyncing,
            'mutation_syncing': _mutationStatus.isSyncing,
            'cleanup_syncing': _cleanupStatus.isSyncing,
            'note':
                'May be expected reconnect replay; inspect associated queue failures.',
          },
        ),
      );
    }
    _snapshot = next;
    notifyListeners();
  }

  // Queue events also signal changes in other stored account scopes. Keep those
  // events even if this account's counts match, but coalesce their disk scans.
  // Queue bursts request one running scan and at most one latest follow-up.
  late final _knownSessionRefresh = LatestValueWorker<bool>(
    apply: (_) => _refreshKnownSessionSnapshot(),
    onError: (_, _) {},
  );

  Future<void> _refreshKnownSessionSnapshot() async {
    final nextSnapshot = await readKnownSessionSnapshot();
    if (_sameSnapshot(_knownSessionSnapshot, nextSnapshot)) {
      return;
    }
    if (nextSnapshot.isOnline &&
        nextSnapshot.isSyncing &&
        (!_knownSessionSnapshot.isOnline || !_knownSessionSnapshot.isSyncing) &&
        !_snapshot.isSyncing) {
      unawaited(
        SyncErrorLogService.instance.capture(
          source: 'offline_sync_status_service.dart',
          operation: 'savedAccountOnlineQueueActivity',
          entryId: 'online-${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
          target: 'known_session_sync_status',
          error: 'Saved account queue syncing while network reports online',
          stack: StackTrace.current.toString(),
          attempt: 1,
          kind: 'online_queue_activity',
          details: {
            'pending_actions': nextSnapshot.pendingActions,
            'failed_actions': nextSnapshot.failedActions,
            'previous_online': _knownSessionSnapshot.isOnline,
            'scope': 'all_saved_accounts',
            'note':
                'Aggregate observation; use queue failure user_id for the affected account.',
          },
        ),
      );
    }
    SyncErrorLogService.instance.observeQueue(
      'saved_account_queues',
      pending: nextSnapshot.pendingActions,
      failed: nextSnapshot.failedActions,
      syncing: nextSnapshot.isSyncing,
      processed: nextSnapshot.processedActions,
      total: nextSnapshot.totalActionsInBatch,
    );
    _knownSessionSnapshot = nextSnapshot;
    notifyListeners();
  }

  bool _sameSnapshot(
    OfflineSyncStatusSnapshot left,
    OfflineSyncStatusSnapshot right,
  ) {
    return left.isOnline == right.isOnline &&
        left.pendingActions == right.pendingActions &&
        left.failedActions == right.failedActions &&
        left.isSyncing == right.isSyncing &&
        left.processedActions == right.processedActions &&
        left.totalActionsInBatch == right.totalActionsInBatch &&
        left.lastSyncAt == right.lastSyncAt;
  }

  OfflineQueueStatusSnapshot _aggregateQueueStatuses(
    Iterable<OfflineQueueStatusSnapshot> statuses,
  ) {
    final items = statuses.toList();
    final lastSyncCandidates =
        items.map((status) => status.lastSyncAt).whereType<DateTime>().toList()
          ..sort();
    return OfflineQueueStatusSnapshot(
      pendingCount: items.fold(0, (sum, item) => sum + item.pendingCount),
      failedCount: items.fold(0, (sum, item) => sum + item.failedCount),
      isSyncing: items.any((item) => item.isSyncing),
      processedInBatch: items.fold(
        0,
        (sum, item) => sum + item.processedInBatch,
      ),
      totalInBatch: items.fold(0, (sum, item) => sum + item.totalInBatch),
      lastSyncAt: lastSyncCandidates.isEmpty ? null : lastSyncCandidates.last,
    );
  }

  OfflineSyncStatusSnapshot _mergeStatuses({
    required bool isOnline,
    required OfflineQueueStatusSnapshot bookingStatus,
    required OfflineQueueStatusSnapshot mediaStatus,
    required OfflineQueueStatusSnapshot mutationStatus,
    required OfflineQueueStatusSnapshot cleanupStatus,
  }) {
    final pendingActions =
        bookingStatus.pendingCount +
        mediaStatus.pendingCount +
        mutationStatus.pendingCount +
        cleanupStatus.pendingCount;
    final failedActions =
        bookingStatus.failedCount +
        mediaStatus.failedCount +
        mutationStatus.failedCount +
        cleanupStatus.failedCount;
    final isSyncing =
        bookingStatus.isSyncing ||
        mediaStatus.isSyncing ||
        mutationStatus.isSyncing ||
        cleanupStatus.isSyncing;
    final processedActions =
        bookingStatus.processedInBatch +
        mediaStatus.processedInBatch +
        mutationStatus.processedInBatch +
        cleanupStatus.processedInBatch;
    final reportedTotalActionsInBatch =
        bookingStatus.totalInBatch +
        mediaStatus.totalInBatch +
        mutationStatus.totalInBatch +
        cleanupStatus.totalInBatch;
    final inferredTotalActionsInBatch =
        processedActions + pendingActions + failedActions;
    final totalActionsInBatch = isSyncing
        ? max(reportedTotalActionsInBatch, inferredTotalActionsInBatch)
        : reportedTotalActionsInBatch;
    final lastSyncCandidates = [
      bookingStatus.lastSyncAt,
      mediaStatus.lastSyncAt,
      mutationStatus.lastSyncAt,
      cleanupStatus.lastSyncAt,
    ].whereType<DateTime>().toList()..sort();
    return OfflineSyncStatusSnapshot(
      isOnline: isOnline,
      pendingActions: pendingActions,
      failedActions: failedActions,
      isSyncing: isSyncing,
      processedActions: processedActions,
      totalActionsInBatch: totalActionsInBatch,
      lastSyncAt: lastSyncCandidates.isEmpty ? null : lastSyncCandidates.last,
    );
  }

  String _userLabelFromMap(
    Map<String, dynamic>? userData, {
    required String? fallbackUserId,
  }) {
    final rawName = userData?['name']?.toString().trim() ?? '';
    if (rawName.isNotEmpty) {
      return rawName;
    }
    if (fallbackUserId != null) {
      return 'User $fallbackUserId';
    }
    return 'Unknown user';
  }

  String _roleLabelFromMap(Map<String, dynamic>? userData) {
    final role = userData?['role']?.toString().trim() ?? '';
    if (role.isEmpty) {
      return 'Unknown role';
    }
    return humanizeDropdownValue(role);
  }
}
