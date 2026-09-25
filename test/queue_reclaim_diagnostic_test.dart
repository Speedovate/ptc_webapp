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

/// The shared error-log singleton binds to the first mock store it sees, so this
/// assertion lives in its own file.
Future<bool> _waitsForReclaimedLog() async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith('${SyncDiagnosticOutbox.prefix}_row_'),
    )) {
      for (final value in preferences.getStringList(key) ?? const <String>[]) {
        final row = jsonDecode(value);
        if (row is Map && row['kind'] == 'queue_reclaimed') {
          return true;
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a discarded queued photo leaves a diagnostic record', () async {
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
      statusKey: 'delivered',
      fieldKey: 'proof',
      bytes: Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
      fileName: 'proof.png',
    );
    final queued =
        jsonDecode((await backend.readStringList(storageKey)).single)
            as Map<String, dynamic>;
    // The server owns this placeholder when the upload starts.
    await db.collection('bookings').doc('1').set({
      'id': '1',
      'status_outputs': {
        'delivered': {
          'status_key': 'delivered',
          'fields': {
            'proof': {'pending_upload_id': queued['id']},
          },
        },
      },
    });
    // The placeholder disappears during the upload, so the queued bytes can no
    // longer be applied to this booking.
    uploads.onUpload = () async {
      await db.collection('bookings').doc('1').set({
        'id': '1',
        'status_outputs': {
          'delivered': {
            'status_key': 'delivered',
            'fields': <String, dynamic>{},
          },
        },
      });
    };

    // Let the enqueue-triggered flush finish, then run a deterministic cycle.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await service.flushPendingUploads();

    expect(await backend.readStringList(storageKey), isEmpty);
    expect(
      await _waitsForReclaimedLog(),
      isTrue,
      reason: 'discarding queued bytes must leave a diagnostic record',
    );
  });
}
