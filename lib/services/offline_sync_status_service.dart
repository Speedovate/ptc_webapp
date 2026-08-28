import 'dart:async';
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
    if (_isInitialized) {
      return;
    }
    await _authStorage.initialize();
    _isInitialized = true;
    _bookingStatus = BookingOfflineUploadQueueService.instance.currentStatus;
    _mediaStatus = OfflineMediaSyncService.instance.currentStatus;
    _mutationStatus = OfflineMutationQueueService.instance.currentStatus;
    _cleanupStatus = OfflineCleanupQueueService.instance.currentStatus;
    _recompute();
    unawaited(_refreshKnownSessionSnapshot());
    networkStatusEvents().listen((isOnline) {
      _isOnline = isOnline;
      _recompute();
      unawaited(_refreshKnownSessionSnapshot());
    });
    BookingOfflineUploadQueueService.instance.statusStream.listen((status) {
      _bookingStatus = status;
      _recompute();
      unawaited(_refreshKnownSessionSnapshot());
    });
    OfflineMediaSyncService.instance.statusStream.listen((status) {
      _mediaStatus = status;
      _recompute();
      unawaited(_refreshKnownSessionSnapshot());
    });
    OfflineMutationQueueService.instance.statusStream.listen((status) {
      _mutationStatus = status;
      _recompute();
      unawaited(_refreshKnownSessionSnapshot());
    });
    OfflineCleanupQueueService.instance.statusStream.listen((status) {
      _cleanupStatus = status;
      _recompute();
      unawaited(_refreshKnownSessionSnapshot());
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
    final knownUsers = await _authStorage.readStringList(_knownSessionUserIdsKey);
    return readSnapshotForUserScopes(
      userIds: knownUsers,
      includeSignedOut: includeSignedOut,
    );
  }

  Future<List<AdminOfflineQueueScopeSnapshot>> readKnownSessionScopeDetails({
    bool includeSignedOut = true,
  }) async {
    await initialize();
    final knownUsers = await _authStorage.readStringList(_knownSessionUserIdsKey);
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

    final details = scopeKeys.map((scopeKey) {
      final isSignedOut = scopeKey == 'signed_out';
      final userId = isSignedOut ? null : normalizeId(scopeKey);
      final userData = userId == null ? null : usersById[userId];
      final mergedSnapshot = _mergeStatuses(
        isOnline: _isOnline,
        bookingStatus:
            bookingStatuses[scopeKey] ?? const OfflineQueueStatusSnapshot.idle(),
        mediaStatus:
            mediaStatuses[scopeKey] ?? const OfflineQueueStatusSnapshot.idle(),
        mutationStatus:
            mutationStatuses[scopeKey] ??
            const OfflineQueueStatusSnapshot.idle(),
        cleanupStatus:
            cleanupStatuses[scopeKey] ?? const OfflineQueueStatusSnapshot.idle(),
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
    }).where((detail) {
      return detail.snapshot.pendingActions > 0 || detail.snapshot.isSyncing;
    }).toList()
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
    _snapshot = _mergeStatuses(
      isOnline: _isOnline,
      bookingStatus: _bookingStatus,
      mediaStatus: _mediaStatus,
      mutationStatus: _mutationStatus,
      cleanupStatus: _cleanupStatus,
    );
    notifyListeners();
  }

  Future<void> _refreshKnownSessionSnapshot() async {
    final nextSnapshot = await readKnownSessionSnapshot();
    if (_sameSnapshot(_knownSessionSnapshot, nextSnapshot)) {
      return;
    }
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
    final lastSyncCandidates = items
        .map((status) => status.lastSyncAt)
        .whereType<DateTime>()
        .toList()
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
