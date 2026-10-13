import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

class _Photos extends PhotoStorageService {
  Future<void> Function()? duringUpload;
  int uploads = 0;
  @override
  Future<Map<String, dynamic>> uploadUserPhoto({
    required Uint8List bytes,
    required String userId,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    uploads++;
    await duringUpload?.call();
    return {
      'storage_path': 'users/$userId/new.png',
      'download_url': 'https://example.test/new',
    };
  }

  @override
  Future<void> deleteByPath(String? path) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'partially conflicting profile edit retains the full local payload',
    () async {
      final db = MergeAwareFirestore();
      final disk = MemoryBackend();
      var online = false;
      final base = {
        'id': '7',
        'name': 'Original',
        'email': 'old@example.test',
        'updated_at': '2026-10-13T00:00:00Z',
      };
      final server = {
        ...base,
        'name': 'Office update',
        'updated_at': '2026-10-13T01:00:00Z',
      };
      final queued = {
        ...base,
        'name': 'Local update',
        'email': 'local@example.test',
        'updated_at': '2026-10-13T00:30:00Z',
      };
      await db.collection('users').doc('7').set(server);
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: disk,
        isOnline: () => online,
      );
      addTearDown(queue.dispose);
      await queue.queueCollectionDocumentUpsert(
        collectionKey: 'users',
        documentId: '7',
        document: queued,
        baseUpdatedAt: base['updated_at'],
        baseDocument: base,
      );
      online = true;
      await queue.flushPendingMutations();
      final entry = jsonDecode(
        disk.data['offline_mutation_queue_v1::signed_out']!.single,
      );
      expect(entry['payload'], queued);
      expect(entry['is_blocked'], true);
      expect(entry['last_error'], contains('Pending edit was preserved'));
      expect((await db.collection('users').doc('7').get()).data(), server);
    },
  );

  for (final scenario in ['missing user', 'newer photo', 'upload race']) {
    test('profile photo remains durable: $scenario', () async {
      final db = MergeAwareFirestore();
      final disk = MemoryBackend();
      final photos = _Photos();
      var online = false;
      const key = 'offline_media_sync_queue_v1::signed_out';
      const created = '2026-10-13T00:30:00Z';
      disk.data[key] = [
        jsonEncode({
          'id': 'photo1',
          'kind': 'userUpload',
          'user_id': '7',
          'field_key': 'profile_photo',
          'created_at': created,
          'bytes_base64': 'AQID',
          'file_name': 'photo.png',
          'mime_type': 'image/png',
          'size': 3,
          'original_value': 'https://example.test/original',
        }),
      ];
      final ref = db.collection('users').doc('7');
      if (scenario != 'missing user') {
        await ref.set({
          'id': '7',
          'photo': scenario == 'newer photo'
              ? 'https://example.test/newer'
              : 'https://example.test/original',
        });
      }
      if (scenario == 'upload race') {
        photos.duringUpload = () =>
            ref.update({'photo': 'https://example.test/newer'});
      }
      final queue = OfflineMediaSyncService(
        firestore: db,
        backend: disk,
        photoStorageService: photos,
        isOnline: () => online,
      );
      await queue.initialize();
      await Future<void>.delayed(Duration.zero);
      online = true;
      await queue.flushPendingOperations();
      final retained = jsonDecode(disk.data[key]!.single);
      expect(retained['bytes_base64'], 'AQID');
      expect(retained['created_at'], created);
      expect(retained['last_error'], contains('preserved'));
      if (scenario != 'missing user') {
        expect(
          (await ref.get()).data()!['photo'],
          'https://example.test/newer',
        );
      }
    });
  }
}
