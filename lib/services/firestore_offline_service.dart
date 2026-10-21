import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirestoreOfflineService {
  FirestoreOfflineService._();

  static bool _isInitialized = false;
  static bool _settingsApplied = false;
  static String? _settingsError;

  /// Mobile web networks may buffer streaming responses. Use the SDK's
  /// supported long-polling transport while retaining persistent Firestore data.
  static Settings settingsForPlatform({
    required bool web,
    required TargetPlatform platform,
  }) {
    if (web &&
        (platform == TargetPlatform.android ||
            platform == TargetPlatform.iOS)) {
      return const Settings(
        persistenceEnabled: true,
        webExperimentalForceLongPolling: true,
        webExperimentalAutoDetectLongPolling: false,
        webExperimentalLongPollingOptions: WebExperimentalLongPollingOptions(
          timeoutDuration: Duration(seconds: 25),
        ),
      );
    }
    return const Settings(persistenceEnabled: true);
  }

  static Map<String, dynamic> get transportEvidence {
    final settings = settingsForPlatform(
      web: kIsWeb,
      platform: defaultTargetPlatform,
    );
    return {
      'requested_mode': settings.webExperimentalForceLongPolling == true
          ? 'mobile_web_long_polling'
          : 'sdk_default',
      'settings_applied': _settingsApplied,
      'persistence_enabled': true,
      'long_polling_timeout_seconds': settings
          .webExperimentalLongPollingOptions
          ?.timeoutDuration
          ?.inSeconds,
      if (_settingsError != null) 'settings_error': _settingsError,
      'server_reachability_verified': false,
    };
  }

  static Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    final firestore = FirebaseFirestore.instance;
    try {
      // Keep Firestore's read cache durable across a fully closed browser.
      // Mutations are still tracked by the app's explicit offline queue, while
      // this gives every collection a second cache-first read source.
      firestore.settings = settingsForPlatform(
        web: kIsWeb,
        platform: defaultTargetPlatform,
      );
      _settingsApplied = true;
    } catch (error) {
      _settingsError = error.toString();
      // On web hot restart, Firestore may already be live with existing settings.
    }

    _isInitialized = true;
  }
}
