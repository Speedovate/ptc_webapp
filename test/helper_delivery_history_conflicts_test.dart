import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/booking_status_continuation.dart';
import 'support/merge_aware_firestore.dart';
import 'booking_photo_commit_safety_test.dart' show SlowPhotos;
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final fixtures =
      jsonDecode(
            File(
              'test/fixtures/helper_delivery_history_conflicts.json',
            ).readAsStringSync(),
          )
          as List;
  for (final fixture in fixtures) {
    for (final scenario in ['available', 'occupied', 'conflicting crew']) {
      test('persisted delivery ${fixture['pending']['id']}: $scenario', () async {
        final pending = Map<String, dynamic>.from(fixture['pending']);
        final server = Map<String, dynamic>.from(fixture['server']);
        if (scenario == 'conflicting crew') server['helper_id'] = '999';
        final db = MergeAwareFirestore();
        await db.collection('bookings').doc(pending['id']).set(server);
        final chassis = <String, dynamic>{
          'id': pending['chassis_id'],
          'current_status': scenario == 'occupied' ? 'loaded' : 'ready',
          'current_booking_id': scenario == 'occupied' ? '999' : null,
          'location': 'Garage',
        };
        await db.collection('chassis').doc(pending['chassis_id']).set(chassis);
        if (scenario == 'occupied') {
          await db.collection('bookings').doc('999').set({
            'id': '999',
            'client_status': 'ongoing',
            'chassis_id': pending['chassis_id'],
          });
        }
        final backend = MemoryBackend();
        await backend.writeStringList(storageKey, [
          jsonEncode({
            'id': 'delivery-${pending['id']}',
            'kind': 'collectionDocumentUpsert',
            'collection_key': 'bookings',
            'target_id': pending['id'],
            'payload': pending,
            'base_updated_at': fixture['base'],
            'created_at': pending['delivered_at'],
            'retry_count': 1,
            'is_blocked': true,
            'conflict_recovery_attempted': true,
            'booking_edit_archive_rechecked': true,
            'booking_photo_rechecked': true,
            'booking_metadata_rechecked': true,
            'booking_history_rechecked': true,
            'last_error':
                'Sync conflict: booking changed remotely before applying this edit.',
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
        if (scenario == 'conflicting crew') {
          expect(saved, hasLength(1));
          final entry = jsonDecode(saved.single);
          expect(entry['is_blocked'], true);
          expect(entry['booking_delivery_history_rechecked'], true);
          await queue.flushPendingMutations();
          expect(await backend.readStringList(storageKey), saved);
          expect(
            (await db.collection('bookings').doc(pending['id']).get()).data(),
            server,
          );
        } else {
          expect(saved, isEmpty);
          final actual =
              (await db.collection('bookings').doc(pending['id']).get())
                  .data()!;
          expect(actual['client_status'], 'delivered');
          expect(actual['delivered_at'], pending['delivered_at']);
          expect(
            actual['updated_at'],
            pending['id'] == '63'
                ? pending['updated_at']
                : server['updated_at'],
          );
          for (final entry in (server['status_outputs'] as Map).entries) {
            expect(actual['status_outputs'][entry.key], entry.value);
          }
          if (pending['id'] == '63') {
            expect(actual['chassis_id'], isNull);
            expect(
              (await db.collection('chassis').doc('6').get()).data(),
              chassis,
            );
            if (scenario == 'available') {
              // The fake retains dynamic-key maps from transaction merges;
              // real Firestore serializes them before the next SDK read.
              await db.collection('bookings').doc('63').set(
                Map<String, dynamic>.from(jsonDecode(jsonEncode(actual))),
              );
              const photoKey = 'booking_pending_upload_queue_v1::signed_out';
              const eventKey = 'ongoing__1790906099857000';
              final marker =
                  pending['status_outputs'][eventKey]['fields']['delivery_form_photo'];
              await backend.writeStringList(photoKey, [
                jsonEncode({
                  'id': marker['pending_upload_id'],
                  'booking_id': '63',
                  'status_key': eventKey,
                  'field_key': 'delivery_form_photo',
                  'file_name': marker['name'],
                  'mime_type': marker['mime_type'],
                  'bytes_base64': 'AQID',
                  'size': marker['size'],
                  'created_at': '2026-10-02T01:55:00.060Z',
                  'waiting_for_commit': true,
                  'wait_count': 106,
                  'wait_reason': 'booking_mutation_pending',
                }),
              ]);
              final photos = SlowPhotos()..gate.complete();
              final uploads = BookingOfflineUploadQueueService(
                backend: backend,
                firestore: db,
                mutationQueue: queue,
                photoStorageService: photos,
                flushMutations: () async {},
              );
              await uploads.flushPendingUploads();
              expect(await backend.readStringList(photoKey), isEmpty);
              final uploaded = (await db.collection('bookings').doc('63').get())
                  .data()!;
              expect(
                uploaded['status_outputs'][eventKey]['fields']['delivery_form_photo']['storage_path'],
                'new-path',
              );
              expect(uploaded['delivered_at'], pending['delivered_at']);
              expect(uploaded['updated_at'], pending['updated_at']);
            }
          }
          if (scenario == 'occupied') {
            expect(
              (await db.collection('chassis').doc(pending['chassis_id']).get())
                  .data(),
              chassis,
            );
          }
        }
      });
    }
    Map<String, dynamic> copy(String key) =>
        Map<String, dynamic>.from(jsonDecode(jsonEncode(fixture[key])) as Map);
    test(
      'booking ${fixture['pending']['id']} preserves delivery and later amount edit',
      () {
        final server = copy('server');
        final pending = copy('pending');
        final original = jsonEncode([server, pending]);
        final merged = reconcileBookingHistory(
          server,
          pending,
          baseUpdatedAt: fixture['base'],
        );
        expect(merged, isNotNull);
        expect(merged!['client_status'], 'delivered');
        expect(merged['delivered_at'], pending['delivered_at']);
        expect(
          merged['updated_at'],
          pending['id'] == '63' ? pending['updated_at'] : server['updated_at'],
        );
        final history = merged['status_outputs'] as Map;
        for (final entry in (server['status_outputs'] as Map).entries) {
          expect(history[entry.key], entry.value);
        }
        for (final entry in (pending['status_outputs'] as Map).entries) {
          expect(history[entry.key], entry.value);
        }
        expect(jsonEncode([server, pending]), original);
      },
    );
    for (final issue in [
      'crew',
      'time',
      'history',
      'reassignment',
      'regression',
    ]) {
      test('booking ${fixture['pending']['id']} rejects $issue conflict', () {
        final server = copy('server');
        final pending = copy('pending');
        switch (issue) {
          case 'crew':
            pending['helper_id'] = '999';
          case 'time':
            pending['delivered_at'] = '2026-10-01T00:00:00Z';
          case 'history':
            (pending['status_outputs'] as Map).remove(
              (server['status_outputs'] as Map).keys.first,
            );
          case 'reassignment':
            server['chassis_id'] = '999';
          case 'regression':
            server['client_status'] = 'return';
        }
        expect(
          reconcileBookingHistory(
            server,
            pending,
            baseUpdatedAt: fixture['base'],
          ),
          isNull,
        );
      });
    }
  }
}
