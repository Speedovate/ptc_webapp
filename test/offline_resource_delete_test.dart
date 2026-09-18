import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend, storageKey;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.remove('paltranco_current_user_id');
    await auth.remove('paltranco_known_session_user_ids');
    await auth.remove('offline_mutation_queue_aliases_v1::$storageKey');
  });
  for (final resource in [
    'users',
    'vehicle_makes',
    'vehicle_types',
    'vehicle_sizes',
    'status_forms',
    'status_fields',
    'statuses',
  ]) {
    test(
      '$resource provisional delete waits for its create and preserves occupied ID',
      () async {
        var online = false;
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        final queue = OfflineMutationQueueService(
          queueUserAssetCleanup: (_, _, _) async {},
          firestore: db,
          backend: backend,
          isOnline: () => online,
        );
        final id = 'offline_${resource}_delete_test';
        await db.collection(resource).doc('1').set({
          'id': '1',
          'name': 'Occupied',
        });
        await _create(queue, resource, id);
        if (resource == 'users') {
          await queue.queueUserDelete(userId: id);
        } else {
          await queue.queueCollectionDocumentDelete(
            collectionKey: resource,
            documentId: id,
          );
        }
        expect(await backend.readStringList(storageKey), hasLength(2));
        // Reopen before reconnect: the create identity must remain persisted.
        final reopened = OfflineMutationQueueService(
          queueUserAssetCleanup: (_, _, _) async {},
          firestore: db,
          backend: backend,
          isOnline: () => online,
        );
        online = true;
        await reopened.flushPendingMutations();
        expect(await backend.readStringList(storageKey), isEmpty);
        final docs = (await db.collection(resource).get()).docs;
        expect(docs, hasLength(1));
        expect(docs.single.data(), {'id': '1', 'name': 'Occupied'});
        await reopened.flushPendingMutations();
        expect((await db.collection(resource).get()).docs, hasLength(1));
      },
    );
  }

  for (final resource in ['vehicle_makes', 'vehicle_types', 'vehicle_sizes']) {
    test(
      '$resource request queues temporary delete even while connection is online',
      () async {
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        final queue = OfflineMutationQueueService(
          queueUserAssetCleanup: (_, _, _) async {},
          firestore: db,
          backend: backend,
          isOnline: () => false,
        );
        final request = VehicleRequest(
          firestore: db,
          offlineMutationQueueService: queue,
          offlineQueueInitializer: () async {},
        );
        final id = 'offline_${resource}_request_delete';
        await _create(queue, resource, id);
        switch (resource) {
          case 'vehicle_makes':
            await request.deleteMake(id);
          case 'vehicle_types':
            await request.deleteType(id);
          case 'vehicle_sizes':
            await request.deleteSize(id);
        }
        final pending = (await backend.readStringList(
          storageKey,
        )).map(jsonDecode).toList();
        expect(pending, hasLength(2));
        expect(pending.last['kind'], 'collectionDocumentDelete');
        expect(pending.last['target_id'], id);
      },
    );
  }

  test(
    'unresolved negative delete never deletes a server document with that raw ID',
    () async {
      var online = false;
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      await db.collection('users').doc('-9').set({'name': 'Legacy record'});
      final queue = OfflineMutationQueueService(
        queueUserAssetCleanup: (_, _, _) async {},
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      await queue.queueUserDelete(userId: '-9');
      online = true;
      await queue.flushPendingMutations();
      expect((await db.collection('users').doc('-9').get()).exists, true);
      expect(await backend.readStringList(storageKey), hasLength(1));
    },
  );

  test(
    'user delete during create commit survives flush merge and resolves on next pass',
    () async {
      var online = false;
      final db = _PausedCreate();
      final backend = MemoryBackend();
      final queue = OfflineMutationQueueService(
        queueUserAssetCleanup: (_, _, _) async {},
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      const id = 'offline_users_inflight_delete';
      await _create(queue, 'users', id);
      online = true;
      final syncing = queue.flushPendingMutations();
      await db.started.future;
      online = false;
      await queue.queueUserDelete(userId: id);
      db.release.complete();
      await syncing;
      online = true;
      await queue.flushPendingMutations();
      expect(await backend.readStringList(storageKey), isEmpty);
      expect((await db.collection('users').get()).docs, isEmpty);
    },
  );
}

Future<void> _create(
  OfflineMutationQueueService queue,
  String resource,
  String id,
) => queue.queueOfflineCollectionDocumentCreate(
  collectionKey: resource,
  provisionalId: id,
  submissionKey: 'create_$id',
  document: {
    'id': id,
    'name': 'Pending',
    'created_at': '2026-09-01T00:00:00Z',
    'updated_at': '2026-09-01T00:00:00Z',
  },
);

class _PausedCreate extends MergeAwareFirestore {
  final started = Completer<void>();
  final release = Completer<void>();
  int calls = 0;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) => super.runTransaction(
    (transaction) async {
      final result = await handler(transaction);
      if (++calls == 2) {
        started.complete();
        await release.future;
      }
      return result;
    },
    timeout: timeout,
    maxAttempts: maxAttempts,
  );
}
