@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/booking_id_resolver.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import '../support/merge_aware_firestore.dart';

// Real browser local storage with a fake server. This does not simulate Firebase
// permissions, a full browser restart, or a physical network disconnection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final role in ['admin', 'client', 'driver', 'helper']) {
    final actions = role == 'driver' || role == 'helper'
        ? ['complete', 'finish', 'delivered']
        : ['book'];
    for (final action in actions) {
      test(
        '$role $action persists offline and replays once after reopening queue',
        () async {
          final scope =
              'browser_${role}_${action}_${DateTime.now().microsecondsSinceEpoch}';
          final storageKey = 'offline_mutation_queue_v1::$scope';
          final auth = createAuthStorageBackend();
          await auth.initialize();
          await auth.writeString('paltranco_current_user_id', scope);
          await auth.remove('paltranco_known_session_user_ids');
          final backend = createBookingStorageBackend();
          await backend.initialize();
          var online = false;
          addTearDown(() async {
            online = false;
            await backend.writeStringList(storageKey, []);
            await auth.remove('paltranco_current_user_id');
            await auth.remove('offline_mutation_queue_aliases_v1::$storageKey');
          });
          final db = MergeAwareFirestore();
          const created = '2026-09-01T01:00:00.000Z';
          const base = '2026-09-02T01:00:00.000Z';
          const actionAt = '2026-09-03T01:00:00.000Z';
          final existing = <String, dynamic>{
            'id': '1',
            'notes': 'Existing booking',
            'created_at': created,
            'updated_at': base,
          };
          await db.collection('bookings').doc('1').set(existing);
          final queue = OfflineMutationQueueService(
            firestore: db,
            backend: backend,
            isOnline: () => false,
          );
          final submissionKey = 'booking_$scope';
          final temporaryId = BookingIdResolver.temporaryId(submissionKey);
          final document = <String, dynamic>{
            'id': action == 'book' ? temporaryId : '1',
            if (action == 'book') 'submission_key': submissionKey,
            'created_at': action == 'book' ? actionAt : created,
            'updated_at': actionAt,
            'client_status': action,
            if (action == 'delivered') 'delivered_at': actionAt,
            'status_outputs': {
              'offline_action': {
                'submitted_at': actionAt,
                'submitted_by_role': role,
                'fields': {'notes': 'Offline $action'},
              },
            },
          };
          if (action == 'book') {
            await queue.queueOfflineBookingCreate(
              provisionalId: temporaryId,
              submissionKey: submissionKey,
              document: document,
            );
          } else {
            await queue.queueCollectionDocumentUpsert(
              collectionKey: 'bookings',
              documentId: '1',
              document: document,
              baseUpdatedAt: base,
            );
          }
          await queue.flushPendingMutations();
          expect(
            (await db.collection('bookings').doc('1').get()).data(),
            existing,
          );
          expect((await db.collection('bookings').get()).docs, hasLength(1));

          // Reopen using another real browser backend and queue instance.
          final reopenedBackend = createBookingStorageBackend();
          await reopenedBackend.initialize();
          final persisted = await reopenedBackend.readStringList(storageKey);
          expect(persisted, hasLength(1));
          expect(
            (jsonDecode(persisted.single)['payload'] as Map)['updated_at'],
            actionAt,
          );
          final reopened = OfflineMutationQueueService(
            firestore: db,
            backend: reopenedBackend,
            isOnline: () => online,
          );
          await reopened.initialize();
          online = true;
          await reopened.flushPendingMutations();
          final finalId = action == 'book' ? '2' : '1';
          final saved = (await db.collection('bookings').doc(finalId).get())
              .data()!;
          expect(saved['created_at'], document['created_at']);
          expect(saved['updated_at'], actionAt);
          expect(saved['status_outputs'], document['status_outputs']);
          if (action == 'delivered') {
            expect(saved['delivered_at'], actionAt);
          }
          expect(await reopenedBackend.readStringList(storageKey), isEmpty);
          await reopened.flushPendingMutations();
          expect(
            (await db.collection('bookings').get()).docs,
            hasLength(action == 'book' ? 2 : 1),
          );
          expect(
            (await db.collection('bookings').doc(finalId).get()).data(),
            saved,
          );
          if (action == 'book') {
            expect(
              (await db.collection('bookings').doc('1').get()).data(),
              existing,
            );
            expect(
              await BookingIdResolver(firestore: db).resolve(temporaryId, submissionKey: submissionKey),
              finalId,
            );
          }
        },
      );
    }
  }
}
