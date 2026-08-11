import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_media_sync_service.dart';

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

class OfflineSyncStatusService extends ChangeNotifier {
  OfflineSyncStatusService._();

  static final OfflineSyncStatusService instance = OfflineSyncStatusService._();

  bool _isInitialized = false;
  bool _isOnline = currentNetworkStatus();
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

  OfflineSyncStatusSnapshot get snapshot => _snapshot;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    _isInitialized = true;
    _bookingStatus = BookingOfflineUploadQueueService.instance.currentStatus;
    _mediaStatus = OfflineMediaSyncService.instance.currentStatus;
    _mutationStatus = OfflineMutationQueueService.instance.currentStatus;
    _cleanupStatus = OfflineCleanupQueueService.instance.currentStatus;
    _recompute();
    networkStatusEvents().listen((isOnline) {
      _isOnline = isOnline;
      _recompute();
    });
    BookingOfflineUploadQueueService.instance.statusStream.listen((status) {
      _bookingStatus = status;
      _recompute();
    });
    OfflineMediaSyncService.instance.statusStream.listen((status) {
      _mediaStatus = status;
      _recompute();
    });
    OfflineMutationQueueService.instance.statusStream.listen((status) {
      _mutationStatus = status;
      _recompute();
    });
    OfflineCleanupQueueService.instance.statusStream.listen((status) {
      _cleanupStatus = status;
      _recompute();
    });
  }

  void _recompute() {
    final pendingActions =
        _bookingStatus.pendingCount +
        _mediaStatus.pendingCount +
        _mutationStatus.pendingCount +
        _cleanupStatus.pendingCount;
    final failedActions =
        _bookingStatus.failedCount +
        _mediaStatus.failedCount +
        _mutationStatus.failedCount +
        _cleanupStatus.failedCount;
    final isSyncing =
        _bookingStatus.isSyncing ||
        _mediaStatus.isSyncing ||
        _mutationStatus.isSyncing ||
        _cleanupStatus.isSyncing;
    final processedActions =
        _bookingStatus.processedInBatch +
        _mediaStatus.processedInBatch +
        _mutationStatus.processedInBatch +
        _cleanupStatus.processedInBatch;
    final totalActionsInBatch =
        _bookingStatus.totalInBatch +
        _mediaStatus.totalInBatch +
        _mutationStatus.totalInBatch +
        _cleanupStatus.totalInBatch;
    final lastSyncCandidates = [
      _bookingStatus.lastSyncAt,
      _mediaStatus.lastSyncAt,
      _mutationStatus.lastSyncAt,
      _cleanupStatus.lastSyncAt,
    ].whereType<DateTime>().toList()..sort();
    _snapshot = OfflineSyncStatusSnapshot(
      isOnline: _isOnline,
      pendingActions: pendingActions,
      failedActions: failedActions,
      isSyncing: isSyncing,
      processedActions: processedActions,
      totalActionsInBatch: totalActionsInBatch,
      lastSyncAt: lastSyncCandidates.isEmpty ? null : lastSyncCandidates.last,
    );
    notifyListeners();
  }
}
