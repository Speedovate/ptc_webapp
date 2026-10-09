import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/support_message.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/requests/support.request.dart';
import 'package:webapp/services/offline_media_sync_service.dart';

class _DelayedQueueRead extends OfflineMediaSyncService {
  final started = Completer<void>();
  final release = Completer<List<Map<String, dynamic>>>();
  int reads = 0;

  @override
  Future<List<Map<String, dynamic>>> readQueuedSupportMessageDocuments({
    String? threadId,
  }) async {
    if (reads++ == 0) {
      started.complete();
      return release.future;
    }
    return [];
  }
}

class _EmptyQueue extends OfflineMediaSyncService {
  @override
  Future<List<Map<String, dynamic>>> readQueuedSupportMessageDocuments({
    String? threadId,
  }) async => [];
}

class _BlockedCache extends FirestoreCacheStore {
  _BlockedCache({this.blockRead = false, this.blockWrite = false});
  final bool blockRead;
  final bool blockWrite;
  final readStarted = Completer<void>();
  final writeStarted = Completer<void>();
  final releaseRead = Completer<void>();
  final releaseWrite = Completer<void>();
  List<Map<String, dynamic>> documents = [_message('earlier')];

  @override
  Future<List<Map<String, dynamic>>?> readDocumentMaps(String key) async {
    final snapshot = documents.map((doc) => {...doc}).toList();
    if (blockRead && !readStarted.isCompleted) {
      readStarted.complete();
      await releaseRead.future;
    }
    return snapshot;
  }

  @override
  Future<void> writeDocumentMaps(
    String key,
    List<Map<String, dynamic>> next,
  ) async {
    if (blockWrite && !writeStarted.isCompleted) {
      writeStarted.complete();
      await releaseWrite.future;
    }
    documents = next;
  }

  @override
  Future<String?> readVersion(String key) async => 'test';

  @override
  Future<void> writeVersion(String key, String version) async {}
}

Map<String, dynamic> _message(String id) => {
  'id': id,
  'thread_id': 'thread',
  'sender_user_id': '7',
  'text': id,
  'created_at': '2026-10-08T10:00:00Z',
};

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Message update did not arrive');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FirestoreCacheStore.instance.clearAll();
  });

  for (final hasCachedHistory in [false, true]) {
    test('slow cache hydration cannot erase server messages; '
        'cached history=$hasCachedHistory', () async {
      final db = FakeFirebaseFirestore();
      final queue = _DelayedQueueRead();
      final request = SupportRequest(
        firestore: db,
        offlineMediaSyncService: queue,
      );
      if (hasCachedHistory) {
        await FirestoreCacheStore.instance.writeDocumentMaps(
          'support_messages:thread',
          [_message('earlier')],
        );
      }
      await db
          .collection('support')
          .doc('thread')
          .collection('messages')
          .doc('yesterday')
          .set(_message('yesterday'));
      final emissions = <List<SupportMessage>>[];
      final subscription = request
          .watchMessages('thread')
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await queue.started.future;
      // The server can answer while the initial local queue read is delayed.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        emissions.last.map((message) => message.id),
        contains('yesterday'),
        reason:
            'Firestore messages must render before queue recovery completes',
      );
      queue.release.complete([]);
      await _waitUntil(
        () => emissions.any(
          (messages) => messages.any((message) => message.id == 'yesterday'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        emissions.last.map((message) => message.id),
        contains('yesterday'),
      );
      expect(
        request.peekLastVisibleMessages('thread')!.map((m) => m.id),
        contains('yesterday'),
      );
      final cached = await FirestoreCacheStore.instance.readDocumentMaps(
        'support_messages:thread',
      );
      expect(cached!.map((document) => document['id']), contains('yesterday'));
      final serverIndex = emissions.indexWhere(
        (messages) => messages.any((message) => message.id == 'yesterday'),
      );
      expect(
        emissions
            .skip(serverIndex)
            .every(
              (messages) =>
                  messages.any((message) => message.id == 'yesterday'),
            ),
        isTrue,
      );
    });
  }

  for (final blockRead in [true, false]) {
    test('Firestore renders while cache ${blockRead ? 'read' : 'write'} stalls '
        'and still respects confirmed deletions', () async {
      final db = FakeFirebaseFirestore();
      final cache = _BlockedCache(blockRead: blockRead, blockWrite: !blockRead);
      final request = SupportRequest(
        firestore: db,
        cacheStore: cache,
        offlineMediaSyncService: _EmptyQueue(),
      );
      final message = db
          .collection('support')
          .doc('thread')
          .collection('messages')
          .doc('yesterday');
      await message.set(_message('yesterday'));
      final emissions = <List<SupportMessage>>[];
      final subscription = request
          .watchMessages('thread')
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await (blockRead ? cache.readStarted.future : cache.writeStarted.future);
      await _waitUntil(
        () => emissions.any(
          (messages) => messages.any((message) => message.id == 'yesterday'),
        ),
      );
      // A second server update must render without waiting for storage either.
      await message.delete();
      await _waitUntil(() => emissions.last.isEmpty);
      (blockRead ? cache.releaseRead : cache.releaseWrite).complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions.last, isEmpty);
      expect(cache.documents, isEmpty);
    });
  }

  test(
    'cancelled watcher cannot publish delayed hydration into a reopened chat',
    () async {
      final db = FakeFirebaseFirestore();
      final queue = _DelayedQueueRead();
      final request = SupportRequest(
        firestore: db,
        offlineMediaSyncService: queue,
      );
      final first = request.watchMessages('thread').listen((_) {});
      await queue.started.future;
      await first.cancel();
      await db
          .collection('support')
          .doc('thread')
          .collection('messages')
          .doc('yesterday')
          .set(_message('yesterday'));
      final emissions = <List<SupportMessage>>[];
      final second = request.watchMessages('thread').listen(emissions.add);
      addTearDown(second.cancel);
      await _waitUntil(
        () => emissions.any(
          (messages) => messages.any((message) => message.id == 'yesterday'),
        ),
      );
      queue.release.complete([]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        request.peekLastVisibleMessages('thread')!.map((m) => m.id),
        contains('yesterday'),
      );
    },
  );
}
