import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/orphan_photo_recovery_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class _Disk extends MemoryBackend {
  String? failPrefix;
  @override
  Future<void> writeStringList(String key, List<String> values) async {
    if (failPrefix != null && key.startsWith(failPrefix!)) {
      throw StateError('Injected storage failure');
    }
    await super.writeStringList(key, values);
  }
}

class _Db extends MergeAwareFirestore {
  bool failCommit = false;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> action, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    if (failCommit) throw StateError('Injected server commit failure');
    return super.runTransaction(
      action,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

class _Photos extends PhotoStorageService {
  int bundles = 0, attachments = 0;
  bool fail = false, badHash = false;
  Future<void> Function()? duringBundle;
  Map<String, dynamic>? uploadedBundle;
  @override
  Future<Map<String, dynamic>> uploadBookingRecoveryBundle({
    required String owner,
    required String entryId,
    required Map<String, dynamic> bundle,
  }) async {
    if (fail) throw StateError('Injected upload failure');
    bundles++;
    uploadedBundle = jsonDecode(jsonEncode(bundle));
    await duringBundle?.call();
    final hash = sha256.convert(utf8.encode(jsonEncode(bundle))).toString();
    return {
      'sha256': badHash ? 'corrupt' : hash,
      'storage_path': 'booking_photo_recoveries/$owner/$entryId/$hash.json',
      'download_url': 'https://example.test/recovery',
    };
  }

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
    attachments++;
    return {
      'name': fileName,
      'size': size,
      'mime_type': mimeType,
      'storage_path':
          'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/recovered.jpg',
      'download_url': 'https://example.test/photo',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.writeString('paltranco_current_user_id', '8');
    await auth.writeStringList('paltranco_known_session_user_ids', ['8']);
  });
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
      'upload failure',
      'archive failure',
      'commit failure',
      'completion failure',
      'bad upload evidence',
      'booking appears during upload',
    ]) {
      test(
        'automatic orphan ${report['photo_upload']['file_name']}: $scenario',
        () async {
          final p = report['photo_upload'];
          final id = report['queue_entry_id'] as String;
          final db = _Db();
          final disk = _Disk();
          final photos = _Photos();
          final row = <String, dynamic>{
            'id': id,
            'booking_id': p['booking_id'],
            'status_key': p['status_key'],
            'field_key': p['field_key'],
            'file_name': p['file_name'],
            'size': p['size'],
            'mime_type': p['mime_type'],
            'bytes_base64': base64Encode(Uint8List(p['size'])),
            'created_at': report['action_at'],
            'wait_reason': 'temporary_booking_id',
            'wait_count': 66,
            'retry_count': 2,
            'last_error':
                'Failed to get document because the client is offline.',
            'error_diagnostics':
                'Failed at (UTC): 2026-10-14T00:09:29.609Z\nOriginal evidence',
          };
          final mutations = OfflineMutationQueueService(
            firestore: db,
            backend: disk,
            isOnline: () => false,
          );
          addTearDown(mutations.dispose);
          final queue = BookingOfflineUploadQueueService(
            firestore: db,
            backend: disk,
            photoStorageService: photos,
            mutationQueue: mutations,
            flushMutations: () async {},
            cachedBookingReader: (_) async => null,
          );
          await queue.initialize();
          await Future<void>.delayed(Duration.zero);
          final scope = OrphanPhotoRecoveryService.queueKey('8');
          disk.data[scope] = [jsonEncode(row)];
          if (scenario == 'upload failure') photos.fail = true;
          if (scenario == 'archive failure') {
            disk.failPrefix = 'booking_photo_recovery_archive_v1';
          }
          if (scenario == 'commit failure') db.failCommit = true;
          if (scenario == 'completion failure') disk.failPrefix = scope;
          if (scenario == 'bad upload evidence') photos.badHash = true;
          if (scenario == 'booking appears during upload') {
            photos.duringBundle = () =>
                db.collection('bookings').doc('700').set({
                  'id': '700',
                  'submission_key': (p['booking_id'] as String).substring(
                    'offline_'.length,
                  ),
                });
          }
          if (scenario == 'completion failure') {
            await expectLater(queue.flushPendingUploads(), throwsStateError);
          } else {
            await queue.flushPendingUploads();
          }
          if (scenario != 'success') {
            expect(disk.data[scope]?.length, 1);
            expect(
              jsonDecode(disk.data[scope]!.single)['bytes_base64'],
              row['bytes_base64'],
            );
            if (scenario != 'completion failure') {
              expect(
                (await db.collection('booking_photo_recoveries').get()).docs,
                isEmpty,
              );
              return;
            }
            disk.failPrefix = null;
            BookingIdResolver(firestore: db).invalidate(p['booking_id']);
            await queue.flushPendingUploads();
          }
          expect(disk.data[scope], isEmpty);
          expect(photos.bundles, 1);
          expect(photos.attachments, 0);
          expect((await db.collection('bookings').get()).docs, isEmpty);
          final receipt =
              (await db
                      .collection('booking_photo_recoveries')
                      .doc(OrphanPhotoRecoveryService.receiptId('8', id))
                      .get())
                  .data()!;
          expect(receipt['state'], 'preserved_unassigned');
          expect(receipt['booking_id'], isNull);
          expect(receipt['original_action_at'], report['action_at']);
          expect(photos.uploadedBundle!['original_entry'], row);
          final archive = jsonDecode(
            disk.data[OrphanPhotoRecoveryService.archiveKey('8', id)]!.single,
          );
          expect(archive['original_entry'], row);
          expect(
            disk.data[OrphanPhotoRecoveryService.unassignedIndexKey('8')],
            [id],
          );
          // A late booking with the exact original marker is completed on the
          // existing flush path, with no user selection and no status rollback.
          final server = <String, dynamic>{
            'id': '700',
            'submission_key': (p['booking_id'] as String).substring(
              'offline_'.length,
            ),
            'client_id': '9',
            'client_status': 'assigned',
            'driver_id': '13',
            'billing_status': 'unbilled',
            'updated_at': '2026-10-16T10:00:00',
            'status_outputs': <String, dynamic>{
              p['status_key']: {
                'status_key': 'book',
                'submitted_by': '8',
                'fields': {
                  p['field_key']: {
                    'pending_upload': true,
                    'pending_upload_id': id,
                    'name': p['file_name'],
                    'size': p['size'],
                    'mime_type': p['mime_type'],
                  },
                },
              },
            },
          };
          await db
              .collection('bookings')
              .doc('700')
              .set(jsonDecode(jsonEncode(server)));
          BookingIdResolver(firestore: db).invalidate(p['booking_id']);
          await queue.flushPendingUploads();
          expect(photos.attachments, 1);
          expect(photos.bundles, 1);
          expect(
            disk.data[OrphanPhotoRecoveryService.unassignedIndexKey('8')],
            isEmpty,
          );
          final associated = (await db.collection('bookings').doc('700').get())
              .data()!;
          expect(associated['client_status'], 'assigned');
          expect(associated['driver_id'], '13');
          expect(associated['updated_at'], server['updated_at']);
          expect(
            (await db
                    .collection('booking_photo_recoveries')
                    .doc(OrphanPhotoRecoveryService.receiptId('8', id))
                    .get())
                .data()!['state'],
            'associated',
          );
          expect(
            jsonDecode(
              disk.data[OrphanPhotoRecoveryService.archiveKey('8', id)]!.single,
            )['original_entry'],
            row,
          );
          await queue.flushPendingUploads();
          expect(photos.attachments, 1);
        },
      );
    }
  }
}
