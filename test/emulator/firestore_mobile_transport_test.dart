@TestOn('browser')
@Timeout(Duration(minutes: 1))
library;

// Explicit real plugin registration for the isolated local demo emulator.
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/firestore_offline_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'mobile transport: actual SDK reservations, writes and transactions',
    () async {
      FirebaseCoreWeb.registerWith(webPluginRegistrar);
      FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
      final app = await Firebase.initializeApp(
        name: 'mobile-transport',
        options: const FirebaseOptions(
          apiKey: 'emulator-only-api-key',
          appId: '1:123456789:web:emulator',
          messagingSenderId: '123456789',
          projectId: 'demo-paltranco-regression',
        ),
      );
      final db = FirebaseFirestore.instanceFor(app: app);
      expect(app.options.projectId, 'demo-paltranco-regression');
      db.settings = FirestoreOfflineService.settingsForPlatform(
        web: true,
        platform: TargetPlatform.android,
      );
      db.useFirestoreEmulator('127.0.0.1', 18081);
      for (var i = 0; i < 5; i++) {
        final id = 'mobile_${DateTime.now().microsecondsSinceEpoch}_$i';
        final absent = await db
            .collection('manage_id')
            .doc(id)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        expect(absent.exists, false);
        final ref = db.collection('network_probe').doc(id);
        await ref
            .set({'original_action_at': '2026-10-13T22:06:16.112Z'})
            .timeout(const Duration(seconds: 10));
        await db
            .runTransaction((tx) async {
              final snap = await tx.get(ref);
              tx.update(ref, {...snap.data()!, 'confirmed': true});
            })
            .timeout(const Duration(seconds: 10));
        final saved = await ref
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        expect(saved.data()?['confirmed'], true);
        expect(saved.data()?['original_action_at'], '2026-10-13T22:06:16.112Z');
      }
    },
    skip: const bool.fromEnvironment('PALTRANCO_EMULATOR_TEST')
        ? false
        : 'Requires local demo emulator',
  );
}
