import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/services/sync_diagnostic_outbox.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;

class _FakeFirebaseStorage implements FirebaseStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RejectingPhotoStorage extends PhotoStorageService {
  _RejectingPhotoStorage() : super(storage: _FakeFirebaseStorage());

  Future<void> Function()? onUpload;

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
    if (onUpload != null) {
      await onUpload!();
    }
    throw StateError('storage rejected this upload permanently');
  }

  @override
  Future<void> deleteByPath(String? storagePath) async {}
}

/// Every diagnostic row this device is currently holding.
///
/// The shared error-log singleton binds to the first mock store it sees, so
/// assertions about resolved rows need their own test file.
Future<List<Map<String, dynamic>>> _outboxRows() async {
  final preferences = await SharedPreferences.getInstance();
  final rows = <Map<String, dynamic>>[];
  for (final key in preferences.getKeys().where(
    (key) => key.startsWith('${SyncDiagnosticOutbox.prefix}_row_'),
  )) {
    for (final value in preferences.getStringList(key) ?? const <String>[]) {
      final row = jsonDecode(value);
      if (row is Map<String, dynamic>) rows.add(row);
    }
  }
  return rows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a later reclaim clears the failure that queued the photo', () async {
    // This is the production sequence: the upload failed on one day, and only
    // much later did the server tell us the photo would never be accepted. The
    // entry ends up settled, so the original failure must stop asking the admin
    // to act - otherwise a correctly reclaimed photo leaves a permanent
    // "needs attention" entry that nothing will ever clear.
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.writeString('paltranco_current_user_id', '13');
    const storageKey = 'booking_pending_upload_queue_v1::13';
    final db = FakeFirebaseFirestore();
    final backend = MemoryBackend();
    final uploads = _RejectingPhotoStorage();
    final service = BookingOfflineUploadQueueService(
      backend: backend,
      firestore: db,
      photoStorageService: uploads,
      flushMutations: () async {},
      mutationQueue: OfflineMutationQueueService(
        backend: MemoryBackend(),
        firestore: db,
        isOnline: () => false,
      ),
    );
    await service.initialize();
    await service.enqueueBookingPhoto(
      bookingId: '1',
      statusKey: 'book__1',
      fieldKey: 'waybill_photo',
      bytes: Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
      fileName: 'waybill.png',
    );
    final queued =
        jsonDecode((await backend.readStringList(storageKey)).single)
            as Map<String, dynamic>;
    await db.collection('bookings').doc('1').set({
      'id': '1',
      'status_outputs': {
        'book__1': {
          'status_key': 'book',
          'fields': {
            'waybill_photo': {'pending_upload_id': queued['id']},
          },
        },
      },
    });

    // First cycle: the upload is rejected while the marker is still in place, so
    // the entry is kept with a stored error and a failure is reported.
    uploads.onUpload = () async {};
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await service.flushPendingUploads();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await backend.readStringList(storageKey), hasLength(1));
    var failureRows = (await _outboxRows()).where(
      (row) =>
          row['kind'] == 'queue_failure' &&
          row['queue_entry_id'] == queued['id'],
    );
    expect(failureRows, isNotEmpty, reason: 'the rejection was reported');
    for (final row in failureRows) {
      expect(
        row['resolved_at'],
        isNull,
        reason: 'nothing has settled this entry yet',
      );
    }

    // Second cycle: the server drops the placeholder, so the queued photo can
    // never be applied and the entry is reclaimed.
    await db.collection('bookings').doc('1').set({
      'id': '1',
      'status_outputs': {
        'book__1': {'status_key': 'book', 'fields': <String, dynamic>{}},
      },
    });
    await service.flushPendingUploads();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await backend.readStringList(storageKey), isEmpty);

    failureRows = (await _outboxRows()).where(
      (row) =>
          row['kind'] == 'queue_failure' &&
          row['queue_entry_id'] == queued['id'],
    );
    expect(failureRows, isNotEmpty);
    for (final row in failureRows) {
      expect(
        row['resolved_at'],
        isNotNull,
        reason: 'a reclaimed photo must resolve its own failure report',
      );
    }
  });
}
