import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/requests/support.request.dart';

class _ReadCache extends FirestoreCacheStore {
  final Map<String, List<Map<String, dynamic>>> values = {};
  @override
  Future<List<Map<String, dynamic>>?> readDocumentMaps(String key) async {
    final snapshot = values[key]?.map((value) => {...value}).toList();
    await Future<void>.delayed(Duration.zero);
    return snapshot;
  }

  @override
  Future<void> writeDocumentMaps(
    String key,
    List<Map<String, dynamic>> documents,
  ) async {
    await Future<void>.delayed(Duration.zero);
    values[key] = documents.map((value) => {...value}).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'concurrent reads of two conversations preserve both local markers',
    () async {
      final db = FakeFirebaseFirestore();
      final cache = _ReadCache();
      final request = SupportRequest(firestore: db, cacheStore: cache);
      const marker = '2026-10-29T09:02:00.000Z|2|Hello';
      await Future.wait([
        request.markThreadRead(userId: '1', threadId: 'a', marker: marker),
        request.markThreadRead(userId: '1', threadId: 'b', marker: marker),
      ]);
      final saved = cache.values['manage_support:1']!;
      expect(saved.map((document) => document['thread_id']).toSet(), {
        'a',
        'b',
      });
      expect(await request.readThreadReadMarkers('1'), {
        'a': marker,
        'b': marker,
      });
    },
  );
  test(
    'stale remote read state cannot erase newer locally read message',
    () async {
      final db = FakeFirebaseFirestore();
      final cache = _ReadCache();
      const latest = '2026-10-29T09:02:00.000Z|2|New message';
      cache.values['manage_support:1'] = [
        {
          'id': 'chat',
          'thread_id': 'chat',
          'marker': latest,
          'updated_at': '2026-10-29T10:00:00Z',
        },
      ];
      await db
          .collection('support_read_markers')
          .doc('1')
          .collection('threads')
          .doc('chat')
          .set({
            'id': 'chat',
            'thread_id': 'chat',
            'marker': '2026-10-29T09:01:00.000Z|2|Old message',
            'updated_at': '2026-10-29T11:00:00Z',
          });
      final request = SupportRequest(firestore: db, cacheStore: cache);
      expect(await request.readThreadReadMarkers('1'), {'chat': latest});
      expect(cache.values['manage_support:1']!.single['marker'], latest);
    },
  );
}
