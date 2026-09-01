import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreOfflineService {
  FirestoreOfflineService._();

  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    final firestore = FirebaseFirestore.instance;
    try {
      // Offline data is owned by the app's cache and mutation queues. Keeping
      // a second Firestore SDK queue can replay stale writes after restart.
      firestore.settings = const Settings(persistenceEnabled: false);
    } catch (_) {
      // On web hot restart, Firestore may already be live with existing settings.
    }

    _isInitialized = true;
  }
}
