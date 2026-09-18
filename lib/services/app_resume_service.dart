import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_queue_coordinator_service.dart';

class AppResumeService {
  static Future<void>? _activeRecovery;

  static Future<void> recover() {
    return _activeRecovery ??= _recover().whenComplete(() {
      _activeRecovery = null;
    });
  }

  static Future<void> _recover() async {
    if (Firebase.apps.isEmpty || !currentNetworkStatus()) return;
    await Future.wait([
      _bestEffort(BookingRequest.instance.refreshAfterResume),
      _bestEffort(OfflineQueueCoordinatorService.instance.flushPendingOnResume),
    ]);
  }

  static Future<void> _bestEffort(Future<void> Function() operation) async {
    try {
      await operation().timeout(const Duration(seconds: 35));
    } catch (_) {
      // Existing request/queue guards retain ownership of unfinished work.
      // A later resume may try again without cancelling or duplicating writes.
    }
  }
}
