import 'dart:convert';
import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scenario in ['reassigned', 'unknown owner', 'different photo']) {
    test('reported booking 86 retry: $scenario', () async {
      final fixture = jsonDecode(
        File(
          'test/fixtures/booking_86_uploaded_delivery_retry.json',
        ).readAsStringSync(),
      );
      final pending = Map<String, dynamic>.from(fixture['pending']);
      final server = Map<String, dynamic>.from(fixture['server']);
      if (scenario == 'different photo') {
        server['status_outputs']['ongoing__1789815511495000']['fields']['delivery_form_photo']['size'] =
            999;
      }
      final db = FakeFirebaseFirestore();
      await db.collection('bookings').doc('86').set(server);
      final chassis = {
        'id': '8',
        'current_status': 'loaded',
        'current_booking_id': scenario == 'unknown owner' ? null : '999',
      };
      await db.collection('chassis').doc('8').set(chassis);
      final backend = MemoryBackend();
      await backend.writeStringList(storageKey, [
        jsonEncode({
          'id': 'vehicle_upsert_1789815511694000_a186c673',
          'kind': 'collectionDocumentUpsert',
          'target_id': '86',
          'collection_key': 'bookings',
          'payload': pending,
          'base_updated_at': fixture['base'],
          'created_at': fixture['action_at'],
          'retry_count': 1,
          'is_blocked': true,
          'conflict_recovery_attempted': true,
          'booking_edit_archive_rechecked': true,
          'booking_photo_rechecked': true,
          'booking_metadata_rechecked': true,
          'booking_history_rechecked': true,
          'last_error':
              'Bad state: Sync conflict: booking changed remotely before applying this edit.',
        }),
      ]);
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      await queue.initialize();
      await queue.flushPendingMutations();
      final saved = await backend.readStringList(storageKey);
      if (scenario == 'reassigned') {
        expect(saved, isEmpty);
      } else {
        expect(saved, hasLength(1));
        expect(jsonDecode(saved.single)['is_blocked'], true);
      }
      expect((await db.collection('bookings').doc('86').get()).data(), server);
      expect((await db.collection('chassis').doc('8').get()).data(), chassis);
      await queue.flushPendingMutations();
      expect(await backend.readStringList(storageKey), saved);
    });
  }
}
