// Test doubles intercept only the optional Firestore cache notification.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'operations_store_test.dart' show BoxingFirestore, MemoryQueue;

class HoldSignalDb extends FakeFirebaseFirestore {
  final reached = Completer<void>();
  final release = Completer<void>();
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      path == 'manage_cache' ? SignalCollection(this) : super.collection(path);
}

class SignalCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  SignalCollection(this.db);
  final HoldSignalDb db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => SignalDoc(db);
}

class SignalDoc extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  SignalDoc(this.db);
  final HoldSignalDb db;
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    if (!db.reached.isCompleted) db.reached.complete();
    await db.release.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'online failure after switching accounts stays with originating account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final auth = createAuthStorageBackend();
      await auth.initialize();
      await auth.writeString('paltranco_current_user_id', 'account-A');
      final db = BoxingFirestore();
      final backend = MemoryQueue();
      var online = true;
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      await queue.initialize();
      final started = Completer<void>(), resume = Completer<void>();
      db.transactionStarted = started;
      db.resumeTransaction = resume;
      db.failBeforeCallback = true;
      final saving = queue.saveCollectionDocumentOnlineFirst(
        collectionKey: 'pm_kpi_records',
        documentId: 'pm4_day',
        document: {
          'id': 'pm4_day',
          'updated_by': 'account-A',
          'updated_at': '2026-09-23T01:00:00Z',
        },
      );
      await started.future;
      await auth.writeString('paltranco_current_user_id', 'account-B');
      online = false;
      resume.complete();
      expect(await saving, isFalse);
      final a = await queue.readPendingItems('account-A');
      final b = await queue.readPendingItems('account-B');
      expect(a, hasLength(1));
      expect(b, isEmpty);
    },
  );
  test(
    'committed foreground save completes while cache notification is pending',
    () async {
      SharedPreferences.setMockInitialValues({});
      final auth = createAuthStorageBackend();
      await auth.initialize();
      await auth.writeString('paltranco_current_user_id', 'account-A');
      final db = HoldSignalDb();
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: MemoryQueue(),
        isOnline: () => true,
      );
      await queue.initialize();
      var returned = false;
      final saving = queue
          .saveCollectionDocumentOnlineFirst(
            collectionKey: 'pm_kpi_records',
            documentId: 'pm4_day',
            document: {'id': 'pm4_day', 'updated_at': '2026-09-23T01:00:00Z'},
          )
          .then((v) {
            returned = true;
            return v;
          });
      await db.reached.future;
      expect(
        (await db.collection('pm_kpi_records').doc('pm4_day').get()).exists,
        isTrue,
      );
      expect(await saving.timeout(const Duration(seconds: 1)), isTrue);
      expect(returned, isTrue);
      db.release.complete();
      expect(await saving, isTrue);
    },
  );
}
