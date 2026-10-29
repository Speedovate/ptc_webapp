import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/requests/support.request.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/support_read_state.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;

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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final collection in ['manage_support', 'support_read_markers']) {
    test('read in another session updates the badge via $collection', () async {
      final db = FakeFirebaseFirestore();
      final request = SupportRequest(firestore: db, cacheStore: _ReadCache());
      const latest = '2026-10-29T09:02:00.000Z|2|Hello';
      final thread = SupportThread(
        id: 'chat',
        requesterUserId: '2',
        lastSenderUserId: '2',
        lastMessageText: 'Hello',
        lastMessageAt: DateTime.utc(2026, 10, 29, 9, 2),
      );
      int badge(Map<String, String> markers) => unreadSupportThreadCount(
        threads: [thread],
        viewer: const UserModel(id: '1', role: 'admin'),
        markers: markers,
        canBrowseAllThreads: true,
        markersResolved: true,
      );
      expect(badge({}), 1);
      final update = request
          .watchThreadReadMarkerUpdates('1')
          .asyncMap(
            (_) => request.readThreadReadMarkers('1', refreshRemote: false),
          )
          .firstWhere((markers) => markers['chat'] == latest)
          .timeout(const Duration(seconds: 3));
      await db
          .collection(collection)
          .doc('1')
          .collection('threads')
          .doc('chat')
          .set({
            'id': 'chat',
            'thread_id': 'chat',
            'marker': latest,
            'updated_at': '2026-10-29T09:03:00Z',
          });
      final markers = await update;
      expect(markers, {'chat': latest});
      expect(badge(markers), 0);
    });
  }
  test('local read updates do not require a Firebase connection', () async {
    final cache = _ReadCache();
    const marker = '2026-10-29T09:02:00.000Z|2|Hello';
    cache.values['manage_support:1'] = [
      {'id': 'chat', 'marker': marker},
    ];
    // Firebase is intentionally not initialized in this test.
    final request = SupportRequest(cacheStore: cache);
    expect(await request.readThreadReadMarkers('1', refreshRemote: false), {
      'chat': marker,
    });
  });

  test('queued read survives a new session with no local cache', () async {
    var online = false;
    final db = FakeFirebaseFirestore();
    final queue = OfflineMutationQueueService(
      firestore: db,
      backend: MemoryBackend(),
      isOnline: () => online,
    );
    const marker = '2026-10-29T09:02:00.000Z|2|Hello';
    await queue.queueSupportThreadReadMarker(
      userId: '1',
      threadId: 'chat',
      document: {
        'id': 'chat',
        'thread_id': 'chat',
        'marker': marker,
        'updated_at': '2026-10-29T09:03:00Z',
      },
    );
    online = true;
    await queue.flushPendingMutations();
    final reopened = SupportRequest(firestore: db, cacheStore: _ReadCache());
    expect(await reopened.readThreadReadMarkers('1'), {'chat': marker});
  });

  test('legacy queued reads remain visible after login', () async {
    final db = FakeFirebaseFirestore();
    const marker = '2026-10-29T09:02:00.000Z|2|Hello';
    await db
        .collection('support_read_markers')
        .doc('1')
        .collection('threads')
        .doc('chat')
        .set({
          'id': 'chat',
          'thread_id': 'chat',
          'marker': marker,
          'updated_at': '2026-10-29T09:03:00Z',
        });
    await db
        .collection('manage_support')
        .doc('1')
        .collection('threads')
        .doc('chat')
        .set({
          'id': 'chat',
          'thread_id': 'chat',
          'marker': '2026-10-29T09:01:00.000Z|2|Old',
          'updated_at': '2026-10-29T10:00:00Z',
        });
    final reopened = SupportRequest(firestore: db, cacheStore: _ReadCache());
    expect(await reopened.readThreadReadMarkers('1'), {'chat': marker});
  });
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
          .collection('manage_support')
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
