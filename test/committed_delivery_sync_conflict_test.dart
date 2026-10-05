import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_status_continuation.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';

import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/committed_delivery_sync_conflict.json',
            ).readAsStringSync(),
          )
          as Map;
  Map<String, dynamic> clone(Object value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));

  test(
    'booking 86 acknowledges committed delivery and preserves server state',
    () {
      final server = clone(fixture['server']);
      final pending = clone(fixture['pending']);
      expect(
        reconcileBookingHistory(
          server,
          pending,
          baseUpdatedAt: fixture['base_updated_at'],
        ),
        server,
      );
      expect(pending, fixture['pending']);
      for (final chassis in [null, 'other']) {
        expect(
          reconcileBookingHistory(
            {...server, 'chassis_id': chassis},
            pending,
            baseUpdatedAt: fixture['base_updated_at'],
          ),
          chassis == null ? {...server, 'chassis_id': null} : isNull,
        );
      }
    },
  );

  test(
    'rejects changes without matching delivery and original assignment evidence',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (p) => p['driver_id'] = 'other',
        (p) => p['client_id'] = 'other',
        (p) => p['chassis_id'] = 'other',
        (p) => p['billing_status'] = 'unknown',
        (p) => p['delivered_at'] = '2026-09-20T10:58:31.495Z',
        (p) => p['updated_at'] = '2026-09-20T18:58:31.495',
        (p) =>
            p['status_outputs']['ongoing__1789815511495000']['fields']['delivery_form_number'] =
                'other',
        (p) =>
            p['status_outputs']['ongoing__1789815511495000']['fields']['delivery_form_photo']['size'] =
                1,
        (p) =>
            p['status_outputs']['pending__1789545111839000']['fields']['chassis_id'] =
                'other',
        (p) => p['photo_cleanup_paths'] = ['stale'],
      ]) {
        final pending = clone(fixture['pending']);
        mutate(pending);
        expect(
          reconcileBookingHistory(
            clone(fixture['server']),
            pending,
            baseUpdatedAt: fixture['base_updated_at'],
          ),
          isNull,
        );
      }
      final server = clone(fixture['server']);
      server['billing_status'] = 'unbilled';
      final pending = clone(fixture['pending'])..['billing_status'] = 'billed';
      expect(
        reconcileBookingHistory(
          server,
          pending,
          baseUpdatedAt: fixture['base_updated_at'],
        ),
        isNull,
      );
    },
  );

  for (final invalid in [false, true]) {
    test('previously blocked delivery rechecks once: invalid=$invalid', () async {
      final server = clone(fixture['server']);
      final pending = clone(fixture['pending']);
      if (invalid) pending['chassis_id'] = 'other';
      final db = MergeAwareFirestore();
      await db.collection('bookings').doc('86').set(server);
      final chassis = {
        'id': '8',
        'current_booking_id': '200',
        'current_status': 'in_use',
      };
      await db.collection('chassis').doc('8').set(chassis);
      final backend = MemoryBackend();
      backend.data[storageKey] = [
        jsonEncode({
          'id': fixture['entry_id'],
          'kind': 'collectionDocumentUpsert',
          'target_id': '86',
          'collection_key': 'bookings',
          'payload': pending,
          'base_updated_at': fixture['base_updated_at'],
          'created_at': fixture['action_at'],
          'retry_count': 1,
          'is_blocked': true,
          for (final key in [
            'boxed_error_rechecked',
            'booking_conflict_rechecked',
            'booking_continuation_rechecked',
            'booking_history_rechecked',
            'conflict_recovery_attempted',
            'booking_metadata_rechecked',
            'booking_photo_rechecked',
            'booking_edit_archive_rechecked',
            'booking_delivery_history_rechecked',
            'booking_repeated_delivery_rechecked',
            'booking_start_archive_rechecked',
          ])
            key: true,
          'last_error':
              'Bad state: Sync conflict: booking changed remotely before applying this edit.',
        }),
      ];
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      addTearDown(queue.dispose);
      await queue.initialize();
      await queue.flushPendingMutations();
      final entries = await backend.readStringList(storageKey);
      expect(entries, hasLength(invalid ? 1 : 0));
      if (invalid) {
        final entry = jsonDecode(entries.single);
        expect(entry['is_blocked'], true);
        expect(entry['booking_committed_delivery_rechecked'], true);
        await queue.flushPendingMutations();
        expect(await backend.readStringList(storageKey), entries);
      }
      expect((await db.collection('bookings').doc('86').get()).data(), server);
      expect((await db.collection('chassis').doc('8').get()).data(), chassis);
    });
  }
}
