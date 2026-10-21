import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/orphan_photo_recovery_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'booking254_pending_preview_recovery_test.dart' show Photos;
import 'support/merge_aware_firestore.dart';

class _Db extends MergeAwareFirestore {
  final release = Completer<void>();
  bool pause = true;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final ref = super.collection(path);
    return path == 'manage_id' ? _Collection(ref, this) : ref;
  }
}

// Intentional SDK test doubles to hold a reservation read at the reported stage.
// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.ref, this.db);
  final CollectionReference<Map<String, dynamic>> ref;
  final _Db db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      _Doc(ref.doc(id), db);
}

// ignore: subtype_of_sealed_class
class _Doc extends Fake implements DocumentReference<Map<String, dynamic>> {
  _Doc(this.ref, this.db);
  final DocumentReference<Map<String, dynamic>> ref;
  final _Db db;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    if (db.pause) await db.release.future;
    return ref.get(options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reported reservation read timeout retains original bytes, dates and error, then retries',
    () async {
      SharedPreferences.setMockInitialValues({});
      final auth = createAuthStorageBackend();
      await auth.writeString('paltranco_current_user_id', '8');
      await auth.writeStringList('paltranco_known_session_user_ids', ['8']);
      final disk = MemoryBackend();
      final db = _Db();
      final mutations = OfflineMutationQueueService(
        backend: disk,
        firestore: db,
        isOnline: () => false,
      );
      addTearDown(mutations.dispose);
      final photos = Photos();
      final queue = BookingOfflineUploadQueueService(
        backend: disk,
        firestore: db,
        mutationQueue: mutations,
        photoStorageService: photos,
        flushMutations: () async {},
        cachedBookingReader: (_) async => null,
      );
      await queue.initialize();
      await Future<void>.delayed(Duration.zero);
      const id = 'booking_upload_1791929179742000_bb9462bf';
      const bookingId = 'offline_booking_8_9_1_1791929171081000';
      const scope = 'booking_pending_upload_queue_v1::8';
      const actionAt = '2026-10-13T22:06:16.112Z';
      const event = 'book__1791929171081000';
      final original = <String, dynamic>{
        'id': id,
        'booking_id': bookingId,
        'status_key': event,
        'field_key': 'waybill_photo',
        'file_name': '1000142021.jpg',
        'mime_type': 'image/jpeg',
        'size': 238479,
        'bytes_base64': base64Encode(Uint8List(238479)),
        'created_at': actionAt,
        'wait_reason': 'temporary_booking_id',
        'wait_count': 126,
        'retry_count': 14,
        'last_error': 'Failed to get document because the client is offline.',
        'error_diagnostics':
            'Failed at (UTC): 2026-10-21T05:27:38.186Z\nOriginal evidence',
      };
      disk.data[scope] = [jsonEncode(original)];
      // Use the real production 30s gate budget to reproduce the reported stall.
      await queue.flushPendingUploads().timeout(const Duration(seconds: 45));
      final retained = jsonDecode(disk.data[scope]!.single);
      expect(retained['last_error'], contains('identity check timed out'));
      expect(retained['error_diagnostics'], contains('TimeoutException'));
      expect(
        retained['error_diagnostics'],
        contains('"gate_reason":"request_timeout"'),
      );
      expect(retained['bytes_base64'], original['bytes_base64']);
      expect(retained['created_at'], actionAt);
      expect(photos.uploads, 0);
      expect(
        jsonDecode(
          disk
              .data[OrphanPhotoRecoveryService.originalEvidenceKey('8', id)]!
              .single,
        ),
        original,
      );
      final booking = <String, dynamic>{
        'id': '700',
        'submission_key': 'booking_8_9_1_1791929171081000',
        'created_at': actionAt,
        'updated_at': '2026-10-21T07:30:00Z',
        'client_status': 'assigned',
        'status_outputs': {
          event: {
            'status_key': 'book',
            'submitted_at': actionAt,
            'fields': {
              'waybill_photo': {
                'name': '1000142021.jpg',
                'mime_type': 'image/jpeg',
                'size': 238479,
                'pending_upload': true,
                'pending_upload_id': id,
              },
            },
          },
        },
      };
      await db.collection('bookings').doc('700').set(booking);
      db.pause = false;
      db.release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(
        disk.data[scope],
        hasLength(1),
        reason: 'A late lookup alone cannot acknowledge an upload',
      );
      await queue.flushPendingUploads();
      expect(disk.data[scope], isEmpty);
      expect(photos.uploads, 1);
      final saved = (await db.collection('bookings').doc('700').get()).data()!;
      expect(saved['client_status'], booking['client_status']);
      expect(saved['updated_at'], booking['updated_at']);
      expect(saved['status_outputs'][event]['submitted_at'], actionAt);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
