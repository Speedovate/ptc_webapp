import 'dart:async';
import 'offline_cleanup_queue_service.dart';
import 'sync_error_log_service.dart';

/// Durable cleanup intent is committed with the replacement booking, never
/// before it. History sections count as references too.
class BookingPhotoCleanup {
  static Set<String> references(Object? value) {
    final paths = <String>{};
    void visit(Object? value) {
      if (value is Map) {
        final path = value['storage_path'];
        if (path is String && path.trim().isNotEmpty) paths.add(path.trim());
        for (final entry in value.entries) {
          if (entry.key != 'photo_cleanup_paths') visit(entry.value);
        }
      } else if (value is Iterable) {
        for (final item in value) {
          visit(item);
        }
      }
    }

    visit(value);
    return paths;
  }

  static void prepare(
    Map<String, dynamic> document,
    Map<String, dynamic>? previous,
  ) {
    final claimed =
        (previous?['photo_cleanup_claims'] as List?)
            ?.whereType<String>()
            .toSet() ??
        <String>{};
    if (claimed
        .intersection(references(document['status_outputs']))
        .isNotEmpty) {
      throw StateError(
        'Sync conflict: an old photo is being removed. Refresh and upload the photo again.',
      );
    }
    document['photo_cleanup_claims'] = claimed.toList();
    final candidates = <String>{
      ...references(previous?['status_outputs']),
      ...?((previous?['photo_cleanup_paths'] as List?)?.whereType<String>()),
    }..removeAll(references(document['status_outputs']));
    document['photo_cleanup_paths'] = candidates.toList();
  }

  static void schedule(String bookingId, Map<String, dynamic> document) {
    final paths = document['photo_cleanup_paths'];
    if (paths is! List || paths.isEmpty) return;
    unawaited(() async {
      try {
        for (final path in paths.whereType<String>()) {
          await OfflineCleanupQueueService.instance.queueBookingPhotoDelete(
            bookingId,
            path,
          );
        }
      } catch (error, stack) {
        await SyncErrorLogService.instance.report(
          error,
          stack,
          source: 'booking_photo_cleanup.dart',
          operation: 'schedule committed cleanup',
          target: 'bookings/$bookingId',
        );
      }
    }());
  }
}
