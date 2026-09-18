import 'dart:async';
import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;

const queueKey = 'offline_cleanup_queue_v1::signed_out';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.remove('paltranco_current_user_id');
    await auth.remove('paltranco_known_session_user_ids');
  });

  test('concurrent path and folder enqueues retain every cleanup', () async {
    final backend = MemoryBackend();
    final queue = OfflineCleanupQueueService(
      backend: backend,
      storage: _Storage(),
      isOnline: () => false,
    );
    await Future.wait([
      queue.queueDeleteByPath('photos/one.png'),
      queue.queueDeleteByPath('photos/two.png'),
      queue.queueDeleteFolder('photos/old'),
    ]);
    final saved = (await backend.readStringList(
      queueKey,
    )).map(jsonDecode).toList();
    expect(saved, hasLength(3));
    expect(
      saved.map((entry) => entry['target_path']),
      unorderedEquals(['photos/one.png', 'photos/two.png', 'photos/old']),
    );
  });

  for (final samePath in [false, true]) {
    test(
      'enqueue during cleanup sync survives merge, samePath=$samePath',
      () async {
        var online = false;
        final started = Completer<void>();
        final release = Completer<void>();
        final backend = MemoryBackend();
        final storage = _Storage()
          ..onDelete = (path) async {
            started.complete();
            await release.future;
          };
        final queue = OfflineCleanupQueueService(
          backend: backend,
          storage: storage,
          isOnline: () => online,
        );
        await queue.queueDeleteByPath('photos/one.png');
        final original = (await backend.readStringList(queueKey)).single;
        online = true;
        final syncing = queue.flushPendingCleanups();
        await started.future;
        online = false;
        await queue.queueDeleteByPath(
          samePath ? 'photos/one.png' : 'photos/two.png',
        );
        release.complete();
        await syncing;
        final pending = await backend.readStringList(queueKey);
        expect(pending, hasLength(1));
        expect(
          jsonDecode(pending.single)['id'],
          isNot(jsonDecode(original)['id']),
        );
        expect(
          jsonDecode(pending.single)['target_path'],
          samePath ? 'photos/one.png' : 'photos/two.png',
        );
        storage.onDelete = (_) async {};
        online = true;
        await queue.flushPendingCleanups();
        expect(await backend.readStringList(queueKey), isEmpty);
        expect(storage.deleted, hasLength(2));
      },
    );
  }

  test(
    'account switch while local write waits keeps both actions in originating queue',
    () async {
      final auth = createAuthStorageBackend();
      await auth.initialize();
      await auth.writeString('paltranco_current_user_id', 'cleanup_A');
      addTearDown(() => auth.remove('paltranco_current_user_id'));
      final backend = _PausedBackend();
      final queue = OfflineCleanupQueueService(
        backend: backend,
        storage: _Storage(),
        isOnline: () => false,
      );
      final first = queue.queueDeleteByPath('photos/one.png');
      await backend.started.future;
      final second = queue.queueDeleteFolder('photos/old');
      await Future<void>.delayed(Duration.zero);
      await auth.writeString('paltranco_current_user_id', 'cleanup_B');
      backend.release.complete();
      await Future.wait([first, second]);
      expect(
        await backend.readStringList('offline_cleanup_queue_v1::cleanup_A'),
        hasLength(2),
      );
      expect(
        await backend.readStringList('offline_cleanup_queue_v1::cleanup_B'),
        isEmpty,
      );
    },
  );

  test(
    'failed cleanup retains its action time and retry deadline across reopening',
    () async {
      var online = false;
      final backend = _CountingBackend();
      final storage = _Storage()
        ..onDelete = (_) async {
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'unauthorized',
            message: 'Not authorized',
          );
        };
      final queue = OfflineCleanupQueueService(
        backend: backend,
        storage: storage,
        isOnline: () => online,
      );
      await queue.queueDeleteByPath('photos/one.png');
      final original = jsonDecode(
        (await backend.readStringList(queueKey)).single,
      );
      online = true;
      await queue.flushPendingCleanups();
      final entry = jsonDecode((await backend.readStringList(queueKey)).single);
      expect(entry['created_at'], original['created_at']);
      expect(entry['retry_count'], 1);
      expect(entry['last_error'], isNotEmpty);
      expect(entry['next_retry_at'], isNotNull);
      expect(queue.currentStatus.failedCount, 1);
      final writes = backend.writes;
      final reopened = OfflineCleanupQueueService(
        backend: backend,
        storage: storage,
        isOnline: () => online,
      );
      for (var i = 0; i < 3; i++) {
        await reopened.flushPendingCleanups();
      }
      expect(storage.deleted, hasLength(1));
      expect(
        backend.writes,
        writes,
        reason: 'Backoff must not rewrite cleanup entries',
      );
      expect(await backend.readStringList(queueKey), hasLength(1));
    },
  );

  test(
    'already missing object is acknowledged without retaining failed work',
    () async {
      var online = false;
      final backend = MemoryBackend();
      final storage = _Storage()
        ..onDelete = (_) async {
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'object-not-found',
          );
        };
      final queue = OfflineCleanupQueueService(
        backend: backend,
        storage: storage,
        isOnline: () => online,
      );
      await queue.queueDeleteByPath('photos/missing.png');
      online = true;
      await queue.flushPendingCleanups();
      expect(await backend.readStringList(queueKey), isEmpty);
    },
  );
}

class _Storage extends Fake implements FirebaseStorage {
  final deleted = <String>[];
  Future<void> Function(String) onDelete = (_) async {};
  @override
  Reference ref([String? path]) => _Reference(this, path!);
}

class _Reference extends Fake implements Reference {
  _Reference(this.storage, this.path);
  @override
  final _Storage storage;
  final String path;
  @override
  Future<void> delete() async {
    storage.deleted.add(path);
    await storage.onDelete(path);
  }
}

class _PausedBackend extends MemoryBackend {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> writeStringList(String key, List<String> values) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.writeStringList(key, values);
  }
}

class _CountingBackend extends MemoryBackend {
  int writes = 0;

  @override
  Future<void> writeStringList(String key, List<String> values) async {
    writes++;
    await super.writeStringList(key, values);
  }
}
