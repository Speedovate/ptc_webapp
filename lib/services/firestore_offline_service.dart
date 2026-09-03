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
      // Keep Firestore's read cache durable across a fully closed browser.
      // Mutations are still tracked by the app's explicit offline queue, while
      // this gives every collection a second cache-first read source.
      firestore.settings = const Settings(persistenceEnabled: true);
    } catch (_) {
      // On web hot restart, Firestore may already be live with existing settings.
    }

    _isInitialized = true;
  }
}
