@TestOn('browser')
@Timeout(Duration(minutes: 1))
library;

// Real browser plugin registration is intentionally explicit in emulator tests.
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'SDK repeated network disable/enable with no application services',
    () async {
      FirebaseCoreWeb.registerWith(webPluginRegistrar);
      FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'emulator-only-api-key',
          appId: '1:123456789:web:emulator',
          messagingSenderId: '123456789',
          projectId: 'demo-paltranco-regression',
        ),
      );
      final db = FirebaseFirestore.instance;
      db.settings = const Settings(persistenceEnabled: false);
      db.useFirestoreEmulator('127.0.0.1', 18081);
      for (var i = 0; i < 10; i++) {
        printOnFailure('SDK-only cycle $i');
        final ref = db.collection('network_probe').doc('$i');
        await ref.set({'cycle': i}).timeout(const Duration(seconds: 5));
        await db.disableNetwork().timeout(const Duration(seconds: 5));
        await db.enableNetwork().timeout(const Duration(seconds: 5));
        await db
            .runTransaction((tx) async {
              final before = await tx.get(ref);
              tx.set(ref, {...before.data()!, 'committed': true});
            })
            .timeout(const Duration(seconds: 5));
        final snapshot = await ref
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));
        expect(snapshot.data()?['cycle'], i);
      }
    },
    skip: const bool.fromEnvironment('PALTRANCO_EMULATOR_TEST')
        ? false
        : 'Requires local demo emulator',
  );
}
