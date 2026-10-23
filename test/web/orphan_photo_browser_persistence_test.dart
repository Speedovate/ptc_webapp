@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/orphan_photo_recovery_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import '../support/merge_aware_firestore.dart';

// Real localStorage/IndexedDB with a fake server and uploader. This verifies
// browser persistence, not production rules or a physical device restart.
class _Photos extends PhotoStorageService {
  bool fail = true;
  int uploads = 0;
  @override
  Future<Map<String, dynamic>> uploadBookingRecoveryBundle({
    required String owner,
    required String entryId,
    required Map<String, dynamic> bundle,
  }) async {
    if (fail) throw StateError('Injected connection failure');
    uploads++;
    final hash = sha256.convert(utf8.encode(jsonEncode(bundle))).toString();
    return {
      'sha256': hash,
      'storage_path': 'booking_photo_recoveries/$owner/$entryId/$hash.json',
      'download_url': 'https://example.test/recovery',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final photo in [
    ('1000142073.jpg', 200100),
    ('1000142021.jpg', 238479),
    ('1000142075.jpg', 72531),
  ]) {
    test(
      '${photo.$1}: failed upload retries, then verified archive retires action across reopening',
      () async {
        const owner = '8';
        final stamp = '${DateTime.now().microsecondsSinceEpoch}';
        final id = 'browser_photo_$stamp';
        final row = <String, dynamic>{
          'id': id,
          'booking_id': 'offline_booking_8_9_1_$stamp',
          'status_key': 'book__$stamp',
          'field_key': 'waybill_photo',
          'file_name': photo.$1,
          'size': photo.$2,
          'mime_type': 'image/jpeg',
          'bytes_base64': base64Encode(
            Uint8List.fromList(List.generate(photo.$2, (index) => index % 251)),
          ),
          'created_at': '2026-10-14T06:04:10.527Z',
          'wait_reason': 'temporary_booking_id',
          'wait_count': 66,
          'retry_count': 2,
          'last_error': 'Failed to get document because the client is offline.',
          'error_diagnostics':
              'Failed at (UTC): 2026-10-14T06:05:00.000Z\nOriginal evidence',
        };
        final db = MergeAwareFirestore();
        final photos = _Photos();
        final backend = createBookingStorageBackend();
        await backend.initialize();
        final key = OrphanPhotoRecoveryService.queueKey(owner);
        final indexKey = OrphanPhotoRecoveryService.unassignedIndexKey(owner);
        addTearDown(() async {
          for (final key in [
            key,
            indexKey,
            OrphanPhotoRecoveryService.archiveKey(owner, id),
            OrphanPhotoRecoveryService.originalEvidenceKey(owner, id),
          ]) {
            await backend.writeStringList(key, []);
          }
        });
        OrphanPhotoRecoveryService recovery(BookingStorageBackend disk) =>
            OrphanPhotoRecoveryService(
              backend: disk,
              firestore: db,
              photos: photos,
              requireOwner: (value) async => expect(value, owner),
              hasPending: (_, _) async => false,
              withQueueLock: (action) => action(),
              onResolved: (_, _) async =>
                  fail('Backup must not resolve a booking'),
            );
        await backend.writeStringList(indexKey, []);
        await backend.writeStringList(key, [jsonEncode(row)]);
        await expectLater(
          recovery(backend).archiveUnassigned(owner: owner, entryId: id),
          throwsStateError,
        );
        final reopened = createBookingStorageBackend();
        await reopened.initialize();
        expect(jsonDecode((await reopened.readStringList(key)).single), row);
        photos.fail = false;
        await recovery(reopened).archiveUnassigned(owner: owner, entryId: id);
        expect(await reopened.readStringList(key), isEmpty);
        expect((await db.collection('bookings').get()).docs, isEmpty);
        final receipt =
            (await db
                    .collection('booking_photo_recoveries')
                    .doc(OrphanPhotoRecoveryService.receiptId(owner, id))
                    .get())
                .data()!;
        expect(receipt['state'], 'preserved_unassigned');
        expect(receipt['booking_id'], isNull);
        expect(receipt['original_action_at'], row['created_at']);

        // Reopening must not recreate a retired action; its exact bytes and
        // timestamps remain in the recovery archive instead.
        final migrated = createBookingStorageBackend();
        await migrated.initialize();
        await recovery(migrated).restoreUnassignedPending(owner);
        await recovery(migrated).restoreUnassignedPending(owner);
        expect(await migrated.readStringList(key), isEmpty);
        final archive = jsonDecode(
          (await migrated.readStringList(
            OrphanPhotoRecoveryService.archiveKey(owner, id),
          )).single,
        );
        expect(archive['original_entry'], row);
        expect(archive['state'], 'retired_unassigned');
        expect(photos.uploads, 1);
      },
    );
  }
}
