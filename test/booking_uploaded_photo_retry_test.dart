import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final changed in ['none', 'path', 'size', 'amount', 'chassis']) {
    test('same-version uploaded photo retry: $changed', () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final photo = {
        'name': 'delivery.jpg',
        'size': 42,
        'mime_type': 'image/jpeg',
      };
      Map<String, dynamic> history(Object value, String amount) => {
        'ongoing__1': {
          'status_key': 'ongoing',
          'submitted_at': '2026-09-29T15:00:00',
          'fields': {'delivery_form_photo': value, 'amount': amount},
        },
      };
      final pending = {
        'id': '161',
        'submission_key': 'booking-original',
        'chassis_id': '3',
        'updated_at': '2026-09-29T15:36:34.129',
        'client_status': 'delivered',
        'status_outputs': history({
          ...photo,
          'pending_upload': true,
          'pending_upload_id': 'photo1',
          'download_url': 'data:image/jpeg;base64,AQID',
        }, '4000'),
      };
      final server = {
        ...pending,
        'status_outputs': history({
          ...photo,
          'storage_path':
              'bookings/${changed == 'path' ? '999' : '161'}/status_outputs/ongoing__1/delivery_form_photo/file.jpg',
          'download_url': 'https://example.test/photo',
          'height': 1080,
          if (changed == 'size') 'size': 99,
        }, changed == 'amount' ? '5000' : '4000'),
        'photo_cleanup_paths': [],
        'photo_cleanup_claims': [],
        'media_synced_at': '2026-09-29T07:38:58Z',
        if (changed == 'chassis') 'chassis_id': '4',
      };
      await db.collection('bookings').doc('161').set(server);
      backend.data[storageKey] = [
        jsonEncode({
          'id': 'retry-photo',
          'kind': 'collectionDocumentUpsert',
          'collection_key': 'bookings',
          'target_id': '161',
          'payload': pending,
          'base_updated_at': '2026-09-29T14:43:25.840',
          'created_at': '2026-09-29T07:36:34.129Z',
          'is_blocked': true,
          'booking_metadata_rechecked': true,
          'booking_history_rechecked': true,
          'conflict_recovery_attempted': true,
          'last_error':
              'Sync conflict: booking changed remotely before applying this edit.',
        }),
      ];
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );
      await queue.flushPendingMutations();
      expect((await db.collection('bookings').doc('161').get()).data(), server);
      expect(backend.data[storageKey], hasLength(changed == 'none' ? 0 : 1));
      if (changed != 'none') {
        final saved = List<String>.from(backend.data[storageKey]!);
        expect(jsonDecode(saved.single)['booking_photo_rechecked'], true);
        await queue.flushPendingMutations();
        expect(backend.data[storageKey], saved);
      }
    });
  }
}
