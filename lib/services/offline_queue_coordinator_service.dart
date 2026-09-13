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
