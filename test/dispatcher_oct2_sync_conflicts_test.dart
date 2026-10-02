import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_status_continuation.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;
import 'booking_photo_commit_safety_test.dart' show SlowPhotos;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final fixtures =
      jsonDecode(
            File(
              'test/fixtures/dispatcher_oct2_sync_conflicts.json',
            ).readAsStringSync(),
          )
          as List;
  for (final f in fixtures) {
    final id = f['server']['id'];
    if (f['kind'] == 'photo') {
      for (final mismatch in [false, true]) {
        test(
          'uploaded photo $id acknowledges exact match only: mismatch=$mismatch',
          () async {
            final db = MergeAwareFirestore();
            final backend = MemoryBackend();
            final s = Map<String, dynamic>.from(
              jsonDecode(jsonEncode(f['server'])),
            );
            final p = Map<String, dynamic>.from(f['photo']);
            if (mismatch) {
              s['status_outputs'][p['status_key']]['fields'][p['field_key']]['name'] =
                  'different.jpg';
            }
            await db.collection('bookings').doc(id).set(s);
            const key = 'booking_pending_upload_queue_v1::signed_out';
            backend.data[key] = [
              jsonEncode({
                ...p,
                'id': f['id'],
                'created_at': f['action_at'],
                'bytes_base64': 'AQID',
                'last_error': 'marker superseded',
              }),
            ];
            final photos = SlowPhotos();
            final service = BookingOfflineUploadQueueService(
              backend: backend,
              firestore: db,
              photoStorageService: photos,
              flushMutations: () async {},
              mutationQueue: OfflineMutationQueueService(
                backend: backend,
                firestore: db,
                isOnline: () => false,
              ),
            );
            await service.flushPendingUploads();
            expect(backend.data[key]!.length, mismatch ? 1 : 0);
            expect(photos.started.isCompleted, false);
            expect((await db.collection('bookings').doc(id).get()).data(), s);
          },
        );
      }
    } else {
      test(
        'repeated delivery $id preserves both events and first delivery time',
        () async {
          final s = Map<String, dynamic>.from(f['server']);
          final p = Map<String, dynamic>.from(f['pending']);
          final result = reconcileBookingHistory(
            s,
            p,
            baseUpdatedAt: f['base'],
          );
          expect(result, isNotNull);
          expect(result!['delivered_at'], s['delivered_at']);
          expect(
            reconcileBookingHistory(result, p, baseUpdatedAt: f['base']),
            result,
            reason:
                'A replay after server commit must acknowledge the same history',
          );
          expect((result['status_outputs'] as Map).keys.toSet(), {
            ...(s['status_outputs'] as Map).keys,
            ...(p['status_outputs'] as Map).keys,
          });
          final db = MergeAwareFirestore();
          final backend = MemoryBackend();
          await db.collection('bookings').doc(id).set(s);
          backend.data[storageKey] = [
            jsonEncode({
              'id': f['id'],
              'kind': 'collectionDocumentUpsert',
              'collection_key': 'bookings',
              'target_id': id,
              'payload': p,
              'base_updated_at': f['base'],
              'created_at': f['action_at'],
              'is_blocked': true,
              'conflict_recovery_attempted': true,
              'booking_delivery_history_rechecked': true,
              'last_error':
                  'Sync conflict: booking changed remotely before applying this edit.',
            }),
          ];
          final queue = OfflineMutationQueueService(
            backend: backend,
            firestore: db,
            isOnline: () => true,
          );
          await queue.initialize();
          await queue.flushPendingMutations();
          expect(await backend.readStringList(storageKey), isEmpty);
          final actual = (await db.collection('bookings').doc(id).get())
              .data()!;
          expect(actual['delivered_at'], s['delivered_at']);
          expect(actual['status_outputs'], result['status_outputs']);
          final bad = Map<String, dynamic>.from(p)..['helper_id'] = '999';
          expect(
            reconcileBookingHistory(s, bad, baseUpdatedAt: f['base']),
            isNull,
          );
          final altered = Map<String, dynamic>.from(jsonDecode(jsonEncode(p)));
          final added = (altered['status_outputs'] as Map).keys.firstWhere(
            (k) => !(s['status_outputs'] as Map).containsKey(k),
          );
          altered['status_outputs'][added]['fields']['delivery_form_number'] =
              'UNRELATED';
          expect(
            reconcileBookingHistory(s, altered, baseUpdatedAt: f['base']),
            isNull,
          );
        },
      );
    }
  }
}
