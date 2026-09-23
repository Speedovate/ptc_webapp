import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'operations_store_test.dart'
    show BoxingFirestore, MemoryQueue, boxedError;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BoxingFirestore db;
  late MemoryQueue backend;
  late OfflineMutationQueueService queue;
  var online = false;
  const base = '2026-09-19T10:00:00Z';
  const action = '2026-09-19T10:51:26Z';
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.writeString('paltranco_current_user_id', 'manager');
    await auth.remove('paltranco_known_session_user_ids');
    db = BoxingFirestore();
    backend = MemoryQueue();
    online = false;
    queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => online,
    );
    await db.collection('bookings').doc('98').set({
      'id': '98',
      'submission_key': 'original',
      'updated_at': base,
      'client_status': 'pending',
    });
  });
  tearDown(() async {
    await createAuthStorageBackend().remove('paltranco_current_user_id');
  });
  Future<void> enqueue({
    String identity = 'original',
    String? chassis,
    String stage = 'assigned',
  }) async {
    await queue.queueCollectionDocumentUpsert(
      collectionKey: 'bookings',
      documentId: '98',
      baseUpdatedAt: base,
      document: {
        'id': '98',
        'submission_key': identity,
        'updated_at': action,
        'client_status': stage,
        'chassis_id': ?chassis,
      },
    );
    final key = backend.values.keys.singleWhere(
      (k) => k.startsWith('offline_mutation_queue_v1::'),
    );
    final entry =
        jsonDecode(backend.values[key]!.single) as Map<String, dynamic>;
    backend.values[key] = [
      jsonEncode({
        ...entry,
        'is_blocked': true,
        'last_error': boxedError.toLowerCase(),
      }),
    ];
  }

  test('foreground online save awaits server without queue progress', () async {
    online = true;
    await queue.initialize();
    final started = Completer<void>();
    final resume = Completer<void>();
    db.transactionStarted = started;
    db.resumeTransaction = resume;
    var done = false;
    final saving = queue
        .saveCollectionDocumentOnlineFirst(
          collectionKey: 'bookings',
          documentId: '98',
          baseUpdatedAt: base,
          document: {
            'id': '98',
            'submission_key': 'original',
            'updated_at': action,
            'client_status': 'delivered',
          },
        )
        .then((result) {
          done = true;
          return result;
        });
    await started.future;
    expect(done, isFalse);
    expect(await queue.readPendingItems('manager'), isEmpty);
    resume.complete();
    expect(await saving, isTrue);
    expect(
      (await db.collection('bookings').doc('98').get()).data()!['updated_at'],
      action,
    );
    expect(await queue.readPendingItems('manager'), isEmpty);
  });

  test(
    'online conflict stays a foreground error without queuing overwrite',
    () async {
      online = true;
      await expectLater(
        queue.saveCollectionDocumentOnlineFirst(
          collectionKey: 'bookings',
          documentId: '98',
          baseUpdatedAt: base,
          document: {
            'id': '98',
            'submission_key': 'wrong',
            'updated_at': action,
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(await queue.readPendingItems('manager'), isEmpty);
      expect(
        (await db.collection('bookings').doc('98').get())
            .data()!['submission_key'],
        'original',
      );
    },
  );

  test('offline online-first save preserves work in durable queue', () async {
    expect(
      await queue.saveCollectionDocumentOnlineFirst(
        collectionKey: 'bookings',
        documentId: '98',
        baseUpdatedAt: base,
        document: {
          'id': '98',
          'submission_key': 'original',
          'updated_at': action,
        },
      ),
      isFalse,
    );
    expect(await queue.readPendingItems('manager'), hasLength(1));
    expect(
      (await db.collection('bookings').doc('98').get()).data()!['updated_at'],
      base,
    );
  });

  test(
    'old boxed booking replays once and keeps original action timestamp',
    () async {
      await enqueue();
      online = true;
      await queue.flushPendingMutations();
      expect(await queue.readPendingItems('manager'), isEmpty);
      expect(
        (await db.collection('bookings').doc('98').get()).data()!['updated_at'],
        action,
      );
      final calls = db.transactionCalls;
      await queue.flushPendingMutations();
      expect(db.transactionCalls, calls);
    },
  );
  test(
    'identity conflict is unboxed and never overwrites the booking',
    () async {
      await enqueue(identity: 'different');
      online = true;
      await queue.flushPendingMutations();
      final item = (await queue.readPendingItems('manager')).single;
      expect(item.isBlocked, isTrue);
      expect(item.errorMessage, contains('booking identity changed'));
      expect(item.diagnostics, contains('offline_mutation_queue_service.dart'));
      expect(
        (await db.collection('bookings').doc('98').get())
            .data()!['submission_key'],
        'original',
      );
      final calls = db.transactionCalls;
      await queue.flushPendingMutations();
      expect(db.transactionCalls, calls);
    },
  );
  test('chassis conflict is unboxed and protects the other booking', () async {
    await db.collection('chassis').doc('3').set({
      'id': '3',
      'current_booking_id': 99,
    });
    await enqueue(chassis: '3', stage: 'ongoing');
    online = true;
    await queue.flushPendingMutations();
    final item = (await queue.readPendingItems('manager')).single;
    expect(item.errorMessage, contains('chassis is active on another booking'));
    expect(
      (await db.collection('chassis').doc('3').get())
          .data()!['current_booking_id'],
      99,
    );
    expect(
      (await db.collection('bookings').doc('98').get()).data()!['updated_at'],
      base,
    );
  });
  test('persistent boxed failure is not retried on every reconnect', () async {
    await enqueue();
    db.failBeforeCallback = true;
    online = true;
    await queue.flushPendingMutations();
    final calls = db.transactionCalls;
    await queue.flushPendingMutations();
    await queue.flushPendingMutations();
    expect(db.transactionCalls, calls);
    expect((await queue.readPendingItems('manager')).single.isBlocked, isTrue);
  });
}
