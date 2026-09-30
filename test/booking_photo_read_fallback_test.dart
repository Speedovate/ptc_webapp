import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class Photos extends PhotoStorageService {
  int uploads = 0;
  final deleted = <String?>[];
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
    return {'storage_path': 'uploaded', 'download_url': 'https://test/photo'};
  }

  @override
  Future<void> deleteByPath(String? path) async {
    deleted.add(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scenario in [
    'matching',
    'replaced',
    'missing cache',
    'permission',
  ]) {
    test('photo read fallback: $scenario', () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final photos = Photos();
      const key = 'booking_pending_upload_queue_v1::signed_out';
      const at = '2026-09-30T05:18:53.809Z';
      backend.data[key] = [
        jsonEncode({
          'id': 'upload1',
          'booking_id': '173',
          'status_key': 'book__1',
          'field_key': 'waybill_photo',
          'bytes_base64': 'AQID',
          'file_name': 'photo.jpg',
          'size': 3,
          'mime_type': 'image/jpeg',
          'created_at': at,
          'waiting_for_commit': false,
        }),
      ];
      final cached = <String, dynamic>{
        'id': '173',
        'updated_at': '2026-09-30T13:19:52.416',
        'client_status': 'assigned',
        'status_outputs': {
          'book__1': {
            'fields': {
              'waybill_photo': {
                'pending_upload': true,
                'pending_upload_id': 'upload1',
                'name': 'photo.jpg',
                'size': 3,
                'mime_type': 'image/jpeg',
              },
            },
          },
        },
      };
      final server = <String, dynamic>{
        ...cached,
        if (scenario == 'replaced')
          'status_outputs': {
            'book__1': {
              'fields': {
                'waybill_photo': {'download_url': 'https://test/replacement'},
              },
            },
          },
      };
      await db.collection('bookings').doc('173').set(server);
      var cacheReads = 0;
      final queue = BookingOfflineUploadQueueService(
        backend: backend,
        firestore: db,
        photoStorageService: photos,
        flushMutations: () async {},
        mutationQueue: OfflineMutationQueueService(
          backend: MemoryBackend(),
          firestore: db,
          isOnline: () => false,
        ),
        bookingReader: (_) async {
          if (scenario == 'permission') {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
              message: 'denied',
            );
          }
          throw TimeoutException('read stalled');
        },
        cachedBookingReader: (_) async {
          cacheReads++;
          return scenario == 'missing cache' ? null : cached;
        },
      );
      await queue.flushPendingUploads();
      await queue.flushPendingUploads();
      final saved = (await db.collection('bookings').doc('173').get()).data()!;
      expect(saved['updated_at'], cached['updated_at']);
      expect(saved['client_status'], 'assigned');
      if (scenario == 'matching' || scenario == 'replaced') {
        expect(photos.uploads, 1);
        expect(backend.data[key], isEmpty);
        if (scenario == 'replaced') {
          expect(saved, server);
          expect(photos.deleted, ['uploaded']);
        } else {
          expect(
            saved['status_outputs']['book__1']['fields']['waybill_photo']['download_url'],
            'https://test/photo',
          );
        }
      } else {
        for (var i = 0; i < 3; i++) {
          await queue.flushPendingUploads();
        }
        final retained = jsonDecode(backend.data[key]!.single);
        expect(retained['bytes_base64'], 'AQID');
        expect(retained['created_at'], at);
        expect(photos.uploads, 0);
        expect(retained['error_diagnostics'], contains('marker_read_failure'));
        if (scenario == 'permission') {
          expect(cacheReads, 0);
          expect(retained['wait_reason'], 'marker_read_failed');
          expect(retained['error_diagnostics'], contains('permission-denied'));
        }
      }
    });
  }
}
