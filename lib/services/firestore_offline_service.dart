import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirestoreOfflineService {
  FirestoreOfflineService._();

  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    final firestore = FirebaseFirestore.instance;
    try {
      if (kIsWeb) {
        firestore.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
          webExperimentalAutoDetectLongPolling: true,
          webExperimentalForceLongPolling: true,
        );
      } else {
        firestore.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      }
    } catch (_) {
      // On web hot restart, Firestore may already be live with existing settings.
    }

    _isInitialized = true;
  }
}
