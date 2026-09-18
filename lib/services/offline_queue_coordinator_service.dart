import 'dart:async';

import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_sync_status_service.dart';

class OfflineQueueCoordinatorService {
  OfflineQueueCoordinatorService._();

  static final OfflineQueueCoordinatorService instance =
      OfflineQueueCoordinatorService._();

  bool _isInitialized = false;
  Future<void>? _initializingFuture;

  Future<void> initialize() async {
    final existingInitialization = _initializingFuture;
    if (existingInitialization != null) {
      await existingInitialization;
      return;
    }
    if (_isInitialized) {
      return;
    }
    final initialization = _initializeInternal();
    _initializingFuture = initialization;
    try {
      await initialization;
    } finally {
      _initializingFuture = null;
    }
  }

  Future<void> _initializeInternal() async {
    await BookingOfflineUploadQueueService.instance.initialize();
    await OfflineMediaSyncService.instance.initialize();
    await OfflineMutationQueueService.instance.initialize();
    await OfflineCleanupQueueService.instance.initialize();
    await OfflineSyncStatusService.instance.initialize();
    _isInitialized = true;
    unawaited(flushAll());
  }

  /// Resume does not initialize queues or scan empty queues. Enqueue/startup
  /// and existing periodic processing still discover other stored sessions.
  Future<void> flushPendingOnResume() async {
    if (!_isInitialized) {
      return;
    }
    final mutations = OfflineMutationQueueService.instance;
    final uploads = BookingOfflineUploadQueueService.instance;
    final media = OfflineMediaSyncService.instance;
    final cleanup = OfflineCleanupQueueService.instance;
    if (mutations.currentStatus.pendingCount > 0) {
      await mutations.flushPendingMutations();
    }
    await Future.wait([
      if (uploads.currentStatus.pendingCount > 0) uploads.flushPendingUploads(),
      if (media.currentStatus.pendingCount > 0) media.flushPendingOperations(),
      if (cleanup.currentStatus.pendingCount > 0)
        cleanup.flushPendingCleanups(),
    ]);
  }

  Future<void> flushAll() async {
    // Booking photos patch the booking document after upload, so mutations
    // must be durable before the upload queue begins. The remaining queues
    // are independent and can continue concurrently.
    await OfflineMutationQueueService.instance.flushPendingMutations();
    await Future.wait([
      BookingOfflineUploadQueueService.instance.flushPendingUploads(),
      OfflineMediaSyncService.instance.flushPendingOperations(),
      OfflineCleanupQueueService.instance.flushPendingCleanups(),
    ]);
  }
}
