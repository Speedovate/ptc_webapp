import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class _Photos extends PhotoStorageService {
  final uploaded = <String>[];
  @override
  Future<Map<String, dynamic>> uploadBookingPhoto({
    required Uint8List bytes,
    required String bookingId,
    required String statusKey,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    uploaded.add(bookingId);
    return {
      'name': fileName,
      'size': size,
      'mime_type': mimeType,
      'storage_path':
          'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/test.jpg',
      'download_url': 'https://example.test/upload',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'paltranco_current_user_id': '8',
      'paltranco_known_session_user_ids': ['8'],
    }),
  );
  for (final startup in [false, true]) {
    test(
      'all 15 dispatcher photos drain after dependent delivery reconciliation; startup=$startup',
      () async {
        final rows =
            jsonDecode(
                  File(
                    'test/fixtures/dispatcher_oct2_fifteen_photos.json',
                  ).readAsStringSync(),
                )
                as List;
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        const photoKey = 'booking_pending_upload_queue_v1::8';
        const mutationKey = 'offline_mutation_queue_v1::8';
        final pending = <String>[];
        for (final row in rows) {
          final server = Map<String, dynamic>.from(row['server']);
          await db.collection('bookings').doc(server['id']).set(server);
          for (final a in row['pending']) {
            pending.add(
              jsonEncode({
                'id': a['queue_entry_id'],
                'kind': a['operation'],
                'collection_key': a['collection'],
                'target_id': a['target_id'],
                'payload': a['pending_payload'],
                'base_updated_at': a['base_updated_at'],
                'created_at': a['action_at'],
                'is_blocked': true,
                'booking_delivery_history_rechecked': true,
                'conflict_recovery_attempted': true,
                'last_error': a['last_error'],
              }),
            );
          }
        }
        backend.data[mutationKey] = pending;
        backend.data[photoKey] = rows
            .map(
              (row) => jsonEncode({
                ...row['photo'] as Map,
                // Logs intentionally exclude binary images. Simulated bytes/storage are
                // sufficient to exercise commit ordering; this is not a live upload test.
                'bytes_base64': 'AQID',
                'last_error': 'Photo still waiting',
              }),
            )
            .toList();
        final queue = OfflineMutationQueueService(
          backend: backend,
          firestore: db,
          isOnline: () => true,
        );
        final photos = _Photos();
        final uploader = BookingOfflineUploadQueueService(
          backend: backend,
          firestore: db,
          photoStorageService: photos,
          mutationQueue: queue,
          flushMutations: queue.flushPendingMutations,
        );
        if (startup) {
          await uploader.initialize();
          // Startup must recover persisted errors without pressing Retry/Sync.
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while ((await backend.readStringList(photoKey)).isNotEmpty &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        } else {
          await uploader.flushPendingUploads();
        }
        expect(await backend.readStringList(mutationKey), isEmpty);
        expect(await backend.readStringList(photoKey), isEmpty);
        expect(photos.uploaded, unorderedEquals(['165', '169', '170']));
        for (final row in rows) {
          final original = Map<String, dynamic>.from(row['server']);
          final actual =
              (await db.collection('bookings').doc(original['id']).get())
                  .data()!;
          expect(actual['delivered_at'], original['delivered_at']);
          expect(actual['created_at'], original['created_at']);
          if ((row['pending'] as List).isEmpty) {
            expect(
              actual,
              original,
              reason: 'Already uploaded photos must not rewrite server data',
            );
          } else {
            for (final event in (original['status_outputs'] as Map).entries) {
              expect(actual['status_outputs'][event.key], event.value);
            }
            final photo = row['photo'];
            final queued = row['pending'][0]['pending_payload'];
            final status = photo['status_key'];
            expect(
              actual['status_outputs'][status]['submitted_at'],
              queued['status_outputs'][status]['submitted_at'],
            );
            expect(
              actual['status_outputs'][status]['fields'][photo['field_key']]['pending_upload'],
              isNot(true),
            );
          }
        }
        await uploader.flushPendingUploads();
        expect(
          photos.uploaded,
          hasLength(3),
          reason: 'Repeated flush must not upload twice',
        );
      },
    );
  }
}
