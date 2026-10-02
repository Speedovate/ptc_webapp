import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_status_continuation.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'booking_photo_commit_safety_test.dart' show SlowPhotos;
import 'support/merge_aware_firestore.dart';

class _RecoverablePhotos extends SlowPhotos {
  bool fail = true;
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
    if (fail) throw StateError('Upload conversion failed');
    return super.uploadBookingPhoto(
      bytes: bytes,
      bookingId: bookingId,
      statusKey: statusKey,
      fieldKey: fieldKey,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final rows =
      jsonDecode(
            File('test/fixtures/helper19_oct2_history.json').readAsStringSync(),
          )
          as List;
  for (final row in rows.take(2)) {
    test(
      'helper historical start ${row['queue_snapshot']['target_id']} preserves delivered server and rejects unrelated edits',
      () async {
        final s = Map<String, dynamic>.from(row['server_document']);
        final q = row['queue_snapshot'];
        final p = Map<String, dynamic>.from(q['pending_payload']);
        final result = reconcileBookingHistory(
          s,
          p,
          baseUpdatedAt: q['base_updated_at'],
        );
        expect(result, isNotNull);
        for (final key in s.keys.where((k) => k != 'status_outputs')) {
          expect(result![key], s[key]);
        }
        for (final event in (s['status_outputs'] as Map).entries) {
          expect(result!['status_outputs'][event.key], event.value);
        }
        expect(
          reconcileBookingHistory(
            result!,
            p,
            baseUpdatedAt: q['base_updated_at'],
          ),
          result,
        );
        for (final field in [
          'driver_id',
          'helper_id',
          'client_id',
          'chassis_id',
          'submission_key',
        ]) {
          expect(
            reconcileBookingHistory(s, {
              ...p,
              field: 'unrelated',
            }, baseUpdatedAt: q['base_updated_at']),
            isNull,
          );
        }
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        await db.collection('bookings').doc(s['id']).set(s);
        const key = 'offline_mutation_queue_v1::signed_out';
        backend.data[key] = [
          jsonEncode({
            'id': q['queue_entry_id'],
            'kind': 'collectionDocumentUpsert',
            'collection_key': 'bookings',
            'target_id': s['id'],
            'payload': p,
            'base_updated_at': q['base_updated_at'],
            'created_at': q['action_at'],
            'is_blocked': true,
            'last_error':
                'Sync conflict: booking changed remotely before applying this edit.',
            'conflict_recovery_attempted': true,
            'booking_photo_rechecked': true,
            'booking_metadata_rechecked': true,
            'booking_history_rechecked': true,
            'booking_edit_archive_rechecked': true,
          }),
        ];
        final queue = OfflineMutationQueueService(
          backend: backend,
          firestore: db,
          isOnline: () => true,
        );
        await queue.initialize();
        await queue.flushPendingMutations();
        expect(await backend.readStringList(key), isEmpty);
        expect(
          (await db.collection('bookings').doc(s['id']).get()).data(),
          result,
        );
        if (s['id'] == '23') {
          final snap = rows.last['queue_snapshot'];
          final photo = Map<String, dynamic>.from(snap['photo_upload']);
          const photoKey = 'booking_pending_upload_queue_v1::signed_out';
          backend.data[photoKey] = [
            jsonEncode({
              ...photo,
              'id': snap['queue_entry_id'],
              'created_at': snap['action_at'],
              'bytes_base64': 'AQID',
            }),
          ];
          final photos = _RecoverablePhotos()..gate.complete();
          final service = BookingOfflineUploadQueueService(
            backend: backend,
            firestore: db,
            photoStorageService: photos,
            mutationQueue: queue,
            flushMutations: queue.flushPendingMutations,
          );
          await service.flushPendingUploads();
          final retained = await backend.readStringList(photoKey);
          expect(retained, hasLength(1));
          expect(jsonDecode(retained.single)['bytes_base64'], 'AQID');
          expect(
            (await db.collection('bookings').doc('23').get()).data(),
            result,
          );
          photos.fail = false;
          await service.flushPendingUploads();
          expect(await backend.readStringList(photoKey), isEmpty);
          expect(
            photos.started.isCompleted,
            isTrue,
            reason: 'Older committed photo must be archived, not discarded',
          );
          final actual = (await db.collection('bookings').doc('23').get())
              .data()!;
          for (final key in result.keys.where((k) => k != 'status_outputs')) {
            expect(actual[key], result[key]);
          }
          expect(
            actual['status_outputs']['photo__${snap['queue_entry_id']}']['submitted_at'],
            snap['action_at'],
          );
          for (final event in (result['status_outputs'] as Map).entries) {
            expect(actual['status_outputs'][event.key], event.value);
          }
        }
      },
    );
  }
}
