import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/orphan_photo_recovery_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class _Disk extends MemoryBackend {
  String? failPrefix;
  @override
  Future<void> writeStringList(String key, List<String> rows) async {
    if (failPrefix != null && key.startsWith(failPrefix!)) {
      throw StateError('Injected storage failure');
    }
    await super.writeStringList(key, rows);
  }
}

class _Photos extends PhotoStorageService {
  int uploads = 0;
  Future<void> Function()? duringUpload;
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
    uploads++;
    await duringUpload?.call();
    return {
      'name': fileName,
      'size': size,
      'mime_type': mimeType,
      'download_url': 'https://example.test/photo',
      'storage_path':
          'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/photo.jpg',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final reports =
      jsonDecode(
            File(
              'test/fixtures/oct15_six_photo_reports.json',
            ).readAsStringSync(),
          )
          as List;
  for (final report in reports.take(3)) {
    for (final scenario in [
      'success',
      'changed server',
      'changed source',
      'wrong client',
      'wrong owner',
      'archive failure',
      'completion failure',
      'original found',
      'destination queued',
    ]) {
      test(
        'reviewed photo ${report['photo_upload']['file_name']}: $scenario',
        () async {
          final db = MergeAwareFirestore();
          final disk = _Disk();
          final photos = _Photos();
          var activeOwner = '8';
          var destinationPending = false;
          final p = report['photo_upload'];
          final id = report['queue_entry_id'] as String;
          final row = <String, dynamic>{
            'id': id,
            'booking_id': p['booking_id'],
            'status_key': p['status_key'],
            'field_key': p['field_key'],
            'file_name': p['file_name'],
            'mime_type': p['mime_type'],
            'size': p['size'],
            'bytes_base64': base64Encode(Uint8List(p['size'])),
            'created_at': report['action_at'],
            'retry_count': 17,
            'wait_count': 108,
            'waiting_for_commit': true,
            'wait_reason': 'temporary_booking_id',
            'last_error':
                'Failed to get document because the client is offline.',
            'error_diagnostics':
                'Failed at (UTC): 2026-10-14T00:09:29.609Z\nOriginal diagnostic evidence',
          };
          final sourceRaw = jsonEncode(row);
          const owner = '8', targetId = '600';
          final scope = OrphanPhotoRecoveryService.queueKey(owner);
          disk.data[scope] = [sourceRaw];
          final server = <String, dynamic>{
            'id': targetId,
            'submission_key': 'booking_8_9_1_1792024716308000',
            'client_id': scenario == 'wrong client' ? '10' : '9',
            'client_status': 'delivered',
            'driver_id': '17',
            'helper_id': '19',
            'billing_status': 'billed',
            'updated_at': '2026-10-16T10:00:00',
            'status_outputs': {
              'delivery': {
                'fields': {
                  'delivery_form_photo': {
                    'download_url': 'https://existing.test/photo',
                    'storage_path': 'existing-photo',
                  },
                },
              },
            },
          };
          await db.collection('bookings').doc(targetId).set(server);
          final service = OrphanPhotoRecoveryService(
            backend: disk,
            firestore: db,
            photos: photos,
            requireOwner: (owner) async {
              if (activeOwner != owner) throw StateError('Wrong owner');
            },
            hasPending: (id, owner) async =>
                id == targetId && destinationPending,
            withQueueLock: (action) => action(),
            onResolved: (_, _) async {},
          );
          if (scenario == 'wrong owner') activeOwner = '9';
          if (scenario == 'wrong owner' || scenario == 'wrong client') {
            await expectLater(
              service.review(owner: owner, entryId: id, bookingId: targetId),
              throwsStateError,
            );
            expect(disk.data[scope], [sourceRaw]);
            expect(photos.uploads, 0);
            return;
          }
          final review = await service.review(
            owner: owner,
            entryId: id,
            bookingId: targetId,
          );
          if (scenario == 'changed source') {
            disk.data[scope] = [
              jsonEncode({...row, 'file_name': 'different.jpg'}),
            ];
          }
          if (scenario == 'changed server') {
            photos.duringUpload = () => db
                .collection('bookings')
                .doc(targetId)
                .update({'billing_status': 'updated remotely'});
          }
          if (scenario == 'archive failure') {
            disk.failPrefix = 'booking_photo_recovery_archive_v1';
          }
          if (scenario == 'completion failure') disk.failPrefix = scope;
          if (scenario == 'destination queued') destinationPending = true;
          if (scenario == 'original found') {
            await db.collection('bookings').doc('601').set({
              'id': '601',
              'submission_key': (p['booking_id'] as String).substring(
                'offline_'.length,
              ),
            });
          }
          if (scenario == 'success') {
            await service.apply(review);
          } else {
            await expectLater(service.apply(review), throwsStateError);
            expect(disk.data[scope]?.length, 1);
            expect(
              jsonDecode(disk.data[scope]!.single)['bytes_base64'],
              row['bytes_base64'],
            );
            if (scenario != 'completion failure') {
              final saved =
                  (await db.collection('bookings').doc(targetId).get()).data()!;
              expect(saved['status_outputs'], server['status_outputs']);
              expect(
                (await db.collection('booking_photo_recoveries').get()).docs,
                isEmpty,
              );
              return;
            }
            // A committed receipt survives a failed local completion. Re-review
            // acknowledges it without a duplicate Storage upload or history row.
            disk.failPrefix = null;
            await db.collection('bookings').doc('602').set({
              ...server,
              'id': '602',
            });
            await expectLater(
              service.review(owner: owner, entryId: id, bookingId: '602'),
              throwsStateError,
            );
            await service.apply(
              await service.review(
                owner: owner,
                entryId: id,
                bookingId: targetId,
              ),
            );
          }
          expect(disk.data[scope], isEmpty);
          expect(photos.uploads, 1);
          final archive = jsonDecode(
            disk.data[OrphanPhotoRecoveryService.archiveKey(owner, id)]!.single,
          );
          expect(archive['original_entry'], row);
          expect(archive['state'], 'committed');
          final saved = (await db.collection('bookings').doc(targetId).get())
              .data()!;
          for (final key in server.keys.where(
            (key) => key != 'status_outputs',
          )) {
            expect(saved[key], server[key]);
          }
          expect(
            saved['status_outputs']['delivery'],
            server['status_outputs']['delivery'],
          );
          final recovered = saved['status_outputs']['photo__$id'];
          expect(recovered['original_booking_id'], p['booking_id']);
          expect(recovered['submitted_at'], report['action_at']);
          final receipt =
              (await db
                      .collection('booking_photo_recoveries')
                      .doc(OrphanPhotoRecoveryService.receiptId(owner, id))
                      .get())
                  .data()!;
          expect(receipt['original_action_at'], report['action_at']);
          expect(archive['recovered_at'], receipt['recovered_at']);
          expect(receipt['original_failed_at'], '2026-10-14T00:09:29.609Z');
          expect(
            receipt['original_diagnostics'],
            contains('2026-10-14T00:09:29.609Z'),
          );
          expect(jsonEncode(receipt), isNot(contains('bytes_base64')));
        },
      );
    }
  }
}
