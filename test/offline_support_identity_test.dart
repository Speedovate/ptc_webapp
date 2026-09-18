import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/requests/support.request.dart';
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
  for (final createUser in [true, false]) {
    test(
      'support marker resolves actual user reference, createUser=$createUser',
      () async {
        var online = false;
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        final queue = OfflineMutationQueueService(
          backend: backend,
          firestore: db,
          isOnline: () => online,
        );
        const userId = 'offline_users_support';
        const actionAt = '2026-09-01T01:00:00.000Z';
        await db.collection('users').doc('1').set({
          'id': '1',
          'name': 'Occupied',
        });
        if (createUser) {
          await queue.queueOfflineCollectionDocumentCreate(
            collectionKey: 'users',
            provisionalId: userId,
            submissionKey: 'test_user',
            document: {
              'name': 'New user',
              'created_at': actionAt,
              'updated_at': actionAt,
            },
          );
        }
        await queue.queueSupportThreadReadMarker(
          userId: userId,
          threadId: 'thread_1',
          document: {
            'id': 'thread_1',
            'thread_id': 'thread_1',
            'marker': 'message_5',
            'updated_at': actionAt,
          },
        );
        final reopened = OfflineMutationQueueService(
          backend: backend,
          firestore: db,
          isOnline: () => online,
        );
        online = true;
        await reopened.flushPendingMutations();
        final marker = db
            .collection('support_read_markers')
            .doc('2')
            .collection('threads')
            .doc('thread_1');
        if (createUser) {
          expect((await marker.get()).data()?['updated_at'], actionAt);
          expect((await marker.get()).data()?['marker'], 'message_5');
          expect(await backend.readStringList(storageKey), isEmpty);
          await reopened.flushPendingMutations();
          expect((await marker.get()).data()?['updated_at'], actionAt);
        } else {
          expect((await marker.get()).exists, false);
          expect(await backend.readStringList(storageKey), hasLength(1));
        }
        expect(
          (await db
                  .collection('support_read_markers')
                  .doc(userId)
                  .collection('threads')
                  .get())
              .docs,
          isEmpty,
        );
        expect(
          (await db
                  .collection('support_read_markers')
                  .doc('1')
                  .collection('threads')
                  .get())
              .docs,
          isEmpty,
        );
      },
    );
  }
  test(
    'online read-marker request queues temporary user, preserving thread identity',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final queue = OfflineMutationQueueService(
        backend: backend,
        firestore: db,
        isOnline: () => false,
      );
      final request = SupportRequest(
        firestore: db,
        offlineMutationQueueService: queue,
      );
      final before = DateTime.now().toUtc();
      await request.markThreadRead(
        userId: 'offline_users_request',
        threadId: 'thread_request',
        marker: 'message_7',
      );
      final entries = await backend.readStringList(storageKey);
      expect(entries, hasLength(1));
      final payload = jsonDecode(entries.single)['payload'];
      expect(payload['user_id'], 'offline_users_request');
      expect(payload['thread_id'], 'thread_request');
      expect(payload['document']['marker'], 'message_7');
      expect(
        DateTime.parse(payload['document']['updated_at']).isBefore(before),
        false,
      );
      expect(
        (await db
                .collection('support_read_markers')
                .doc('offline_users_request')
                .collection('threads')
                .get())
            .docs,
        isEmpty,
      );
    },
  );
}
