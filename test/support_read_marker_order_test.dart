import 'dart:async';
import 'operations_store_test.dart' show BoxingFirestore;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/support_read_marker_writer.dart';
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
  });
  test(
    'timed-out foreground and replay share one transaction until acknowledgement',
    () async {
      final db = BoxingFirestore();
      final gate = Completer<void>();
      db.resumeTransaction = gate;
      final ref = db
          .collection('manage_support')
          .doc('1')
          .collection('threads')
          .doc('chat');
      final document = {
        'id': 'chat',
        'thread_id': 'chat',
        'marker': 'message',
        'updated_at': '2026-09-24T07:31:31.393Z',
      };
      final foreground = writeSupportReadMarker(db, ref, document);
      await expectLater(
        foreground.timeout(Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      final replay = writeSupportReadMarker(db, ref, {...document});
      expect(identical(foreground, replay), true);
      expect(db.transactionCalls, 1);
      gate.complete();
      await replay;
      expect((await ref.get()).data()!['updated_at'], document['updated_at']);
      await writeSupportReadMarker(db, ref, document);
      expect(
        db.transactionCalls,
        2,
      ); // Completed writes leave no in-flight entry.
    },
  );
  test('failed transaction is released for a later retry', () async {
    final db = BoxingFirestore()..failBeforeCallback = true;
    final ref = db
        .collection('manage_support')
        .doc('1')
        .collection('threads')
        .doc('chat');
    final document = {
      'marker': 'message',
      'updated_at': '2026-09-24T07:31:31.393Z',
    };
    await expectLater(
      writeSupportReadMarker(db, ref, document),
      throwsStateError,
    );
    db.failBeforeCallback = false;
    await writeSupportReadMarker(db, ref, document);
    expect(db.transactionCalls, 2);
    expect((await ref.get()).data()!['marker'], 'message');
  });
  test(
    'a delayed read of an older message cannot replace newer message progress',
    () async {
      final db = MergeAwareFirestore();
      final ref = db
          .collection('manage_support')
          .doc('7')
          .collection('threads')
          .doc('chat');
      const newer = '2026-10-29T09:02:00.000Z|2|Hello';
      await ref.set({'marker': newer, 'updated_at': '2026-10-29T10:00:00Z'});
      await writeSupportReadMarker(db, ref, {
        'marker': '2026-10-29T09:01:00.000Z|2|Hello',
        'updated_at': '2026-10-29T11:00:00Z',
      });
      expect((await ref.get()).data()!['marker'], newer);
    },
  );
  for (final incoming in [
    '2026-09-01',
    '2026-09-02',
    '2026-09-03',
    'invalid',
  ]) {
    test('read marker transaction preserves ordering for $incoming', () async {
      final db = MergeAwareFirestore();
      final ref = db
          .collection('manage_support')
          .doc('7')
          .collection('threads')
          .doc('t');
      await ref.set({
        'marker': 'newer',
        'updated_at': '2026-09-02',
        'other': 'preserved',
      });
      await writeSupportReadMarker(db, ref, {
        'marker': 'incoming',
        'updated_at': incoming,
      });
      final saved = (await ref.get()).data()!;
      expect(saved['marker'], incoming == '2026-09-03' ? 'incoming' : 'newer');
      expect(saved['other'], 'preserved');
    });
  }
  test('older enqueue cannot replace a newer pending read action', () async {
    var online = false;
    final db = MergeAwareFirestore();
    final backend = MemoryBackend();
    final queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => online,
    );
    for (final date in ['2026-09-03', '2026-09-01']) {
      await queue.queueSupportThreadReadMarker(
        userId: '7',
        threadId: 't',
        document: {'marker': date, 'updated_at': date},
      );
    }
    online = true;
    await queue.flushPendingMutations();
    final saved = await db
        .collection('manage_support')
        .doc('7')
        .collection('threads')
        .doc('t')
        .get();
    expect(saved.data()!['marker'], '2026-09-03');
    expect(await backend.readStringList(storageKey), isEmpty);
  });

  test(
    'delayed offline replay acknowledges stale read action without overwriting newer marker',
    () async {
      var online = false;
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      await queue.queueSupportThreadReadMarker(
        userId: '7',
        threadId: 't',
        document: {'marker': 'old', 'updated_at': '2026-09-01'},
      );
      final ref = db
          .collection('manage_support')
          .doc('7')
          .collection('threads')
          .doc('t');
      await ref.set({'marker': 'newer', 'updated_at': '2026-09-02'});
      online = true;
      await queue.flushPendingMutations();
      expect((await ref.get()).data()!['marker'], 'newer');
      expect(await backend.readStringList(storageKey), isEmpty);
    },
  );
}
