import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

const _scope = 'offline_cleanup_queue_v1::8';
const _path =
    'bookings/273/status_outputs/book__1792365563312000/waybill_photo/1792365573912.jpg';
const _id = 'bookingPhoto_1792365612042000_b27fa473';
const _action = '2026-10-18T23:20:10.206Z';

class _Db extends MergeAwareFirestore {
  Completer<void>? readGate, claimGate, finalizeGate;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(super.collection(path), this);
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> action, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    await claimGate?.future;
    return super.runTransaction(
      action,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

// Intentional SDK test double to delay server responses at operation boundaries.
// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.delegate, this.db);
  final CollectionReference<Map<String, dynamic>> delegate;
  final _Db db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      _Doc(delegate.doc(id), db);
}

// ignore: subtype_of_sealed_class
class _Doc extends Fake implements DocumentReference<Map<String, dynamic>> {
  _Doc(this.delegate, this.db);
  final DocumentReference<Map<String, dynamic>> delegate;
  final _Db db;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    await db.readGate?.future;
    return delegate.get(options);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      delegate.set(data, options);
  @override
  Future<void> update(Map<Object, Object?> data) async {
    await delegate.update(data);
    if (data.containsKey('photo_cleanup_paths')) await db.finalizeGate?.future;
  }
}

class _Storage extends Fake implements FirebaseStorage {
  bool exists = true;
  int deletes = 0;
  Completer<void>? deleteGate, metadataGate;
  FirebaseException? metadataError;
  @override
  Reference ref([String? path]) => _Ref(this);
}

class _Ref extends Fake implements Reference {
  _Ref(this.storage);
  @override
  final _Storage storage;
  @override
  Future<void> delete() async {
    storage.deletes++;
    storage.exists = false;
    await storage.deleteGate?.future;
  }

  @override
  Future<FullMetadata> getMetadata() async {
    await storage.metadataGate?.future;
    if (storage.metadataError != null) throw storage.metadataError!;
    if (!storage.exists) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
      );
    }
    return FullMetadata({
      'creationTimeMillis': DateTime.parse(
        '2026-10-18T23:19:33.912Z',
      ).millisecondsSinceEpoch,
    });
  }
}

Future<void> _makeDue(MemoryBackend disk) async {
  final row = jsonDecode(disk.data[_scope]!.single);
  row['next_retry_at'] = '2000-01-01T00:00:00Z';
  await disk.writeStringList(_scope, [jsonEncode(row)]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.writeString('paltranco_current_user_id', '8');
    await auth.writeStringList('paltranco_known_session_user_ids', ['8']);
  });
  for (final phase in [
    'booking_preflight',
    'claim_booking_photo',
    'read_storage_metadata',
    'delete_superseded_photo',
    'finalize_booking_cleanup',
  ]) {
    test(
      'booking273 $phase timeout retains action, diagnoses stage, and recovers',
      () async {
        final db = _Db();
        final storage = _Storage();
        final disk = MemoryBackend();
        final booking = <String, dynamic>{
          'id': '273',
          'client_status': 'assigned',
          'driver_id': '17',
          'updated_at': '2026-10-19T07:20:10.206',
          'photo_cleanup_paths': [_path],
          'photo_cleanup_claims': phase == 'read_storage_metadata'
              ? [_path]
              : <String>[],
          'status_outputs': {
            'book__1792365563312000': {
              'submitted_at': '2026-10-19T07:19:23.312',
              'fields': {
                'waybill_photo': {
                  'storage_path': 'bookings/273/new.jpg',
                  'name': 'new.jpg',
                },
              },
            },
          },
        };
        await db.collection('bookings').doc('273').set(booking);
        disk.data[_scope] = [
          jsonEncode({
            'id': _id,
            'kind': 'bookingPhoto',
            'target_path': jsonEncode({'booking_id': '273', 'path': _path}),
            'created_at': _action,
            'retry_count': 0,
            'last_error':
                'TimeoutException after 0:00:10.000000: Future not completed',
          }),
        ];
        var online = false;
        final queue = OfflineCleanupQueueService(
          backend: disk,
          firestore: db,
          storage: storage,
          isOnline: () => online,
          bookingRequestTimeout: const Duration(milliseconds: 30),
        );
        await queue.initialize();
        final gate = Completer<void>();
        switch (phase) {
          case 'booking_preflight':
            db.readGate = gate;
          case 'claim_booking_photo':
            db.claimGate = gate;
          case 'read_storage_metadata':
            storage.metadataGate = gate;
          case 'delete_superseded_photo':
            storage.deleteGate = gate;
          case 'finalize_booking_cleanup':
            db.finalizeGate = gate;
        }
        online = true;
        await queue.flushPendingCleanups();
        final retained = jsonDecode(disk.data[_scope]!.single);
        expect(retained['id'], _id);
        expect(retained['created_at'], _action);
        expect(
          retained['target_path'],
          jsonEncode({'booking_id': '273', 'path': _path}),
        );
        expect(
          retained['error_diagnostics'],
          contains('"cleanup_phase":"$phase"'),
        );
        expect(
          retained['error_diagnostics'],
          contains('"request_timeout_ms":30'),
        );
        expect(retained['next_retry_at'], isNotNull);
        expect(queue.currentStatus.failedCount, 1);

        // Deliver the late SDK response. It must not start another deletion or
        // claim after this attempt was already recorded as failed.
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 5));
        db.readGate = db.claimGate = db.finalizeGate = null;
        storage.deleteGate = storage.metadataGate = null;
        if (phase == 'booking_preflight' ||
            phase == 'claim_booking_photo' ||
            phase == 'read_storage_metadata') {
          expect(storage.deletes, 0);
        }
        if (phase == 'claim_booking_photo') {
          expect(
            (await db.collection('bookings').doc('273').get())
                .data()!['photo_cleanup_claims'],
            isEmpty,
          );
        }
        expect(disk.data[_scope], hasLength(1));
        await _makeDue(disk);
        await queue.flushPendingCleanups();
        expect(disk.data[_scope], isEmpty);
        expect(storage.deletes, 1);
        final saved = (await db.collection('bookings').doc('273').get())
            .data()!;
        expect(saved['photo_cleanup_paths'], isEmpty);
        expect(saved['photo_cleanup_claims'], isEmpty);
        for (final field in [
          'status_outputs',
          'client_status',
          'driver_id',
          'updated_at',
        ]) {
          expect(saved[field], booking[field]);
        }
        await queue.flushPendingCleanups();
        expect(storage.deletes, 1);
      },
    );
  }

  for (final scenario in [
    'slow read',
    'still referenced',
    'permission error',
    'operation timeout',
  ]) {
    test(
      'booking273 preserves evidence and current photo: $scenario',
      () async {
        final db = _Db();
        final disk = MemoryBackend();
        final storage = _Storage();
        final booking = <String, dynamic>{
          'id': '273',
          'client_status': 'assigned',
          'updated_at': '2026-10-19T07:20:10.206',
          'photo_cleanup_paths': [_path],
          'photo_cleanup_claims': scenario == 'permission error'
              ? [_path]
              : <String>[],
          'status_outputs': {
            'book__1792365563312000': {
              'submitted_at': '2026-10-19T07:19:23.312',
              'fields': {
                'waybill_photo': {
                  'storage_path': scenario == 'still referenced'
                      ? _path
                      : 'bookings/273/new.jpg',
                },
              },
            },
          },
        };
        await db.collection('bookings').doc('273').set(booking);
        disk.data[_scope] = [
          jsonEncode({
            'id': _id,
            'kind': 'bookingPhoto',
            'created_at': _action,
            'target_path': jsonEncode({'booking_id': '273', 'path': _path}),
            'retry_count': 0,
            'last_error': 'TimeoutException after 0:00:10.000000',
          }),
        ];
        var online = false;
        final queue = OfflineCleanupQueueService(
          backend: disk,
          firestore: db,
          storage: storage,
          isOnline: () => online,
          bookingRequestTimeout: const Duration(seconds: 2),
          operationTimeout: scenario == 'operation timeout'
              ? const Duration(milliseconds: 30)
              : const Duration(seconds: 5),
        );
        await queue.initialize();
        Completer<void>? gate;
        if (scenario == 'slow read' || scenario == 'operation timeout') {
          gate = Completer<void>();
          db.readGate = gate;
          if (scenario == 'slow read') {
            Timer(const Duration(milliseconds: 50), gate.complete);
          }
        }
        if (scenario == 'permission error') {
          storage.metadataError = FirebaseException(
            plugin: 'firebase_storage',
            code: 'unauthorized',
          );
        }
        online = true;
        await queue.flushPendingCleanups();
        if (scenario == 'permission error' || scenario == 'operation timeout') {
          final retained = jsonDecode(disk.data[_scope]!.single);
          expect(retained['id'], _id);
          expect(retained['created_at'], _action);
          expect(storage.deletes, 0);
          if (scenario == 'permission error') {
            expect(
              retained['error_diagnostics'],
              contains('Firebase code: unauthorized'),
            );
            expect(
              retained['error_diagnostics'],
              contains('Firebase plugin: firebase_storage'),
            );
            expect(
              retained['error_diagnostics'],
              contains('"cleanup_phase":"read_storage_metadata"'),
            );
            storage.metadataError = null;
          } else {
            expect(
              retained['error_diagnostics'],
              contains('"cleanup_operation_timeout_ms":30'),
            );
            gate!.complete();
            await Future<void>.delayed(const Duration(milliseconds: 5));
            expect(storage.deletes, 0);
            db.readGate = null;
          }
          await _makeDue(disk);
          await queue.flushPendingCleanups();
        }
        expect(disk.data[_scope], isEmpty);
        expect(storage.deletes, scenario == 'still referenced' ? 0 : 1);
        final saved = (await db.collection('bookings').doc('273').get())
            .data()!;
        for (final field in ['status_outputs', 'client_status', 'updated_at']) {
          expect(saved[field], booking[field]);
        }
        if (scenario == 'still referenced') {
          expect(storage.exists, true);
          expect(saved, booking);
        }
      },
    );
  }

  test(
    'booking273 flush timeout prevents late claim and allows next flush',
    () async {
      final db = _Db();
      final disk = MemoryBackend();
      final storage = _Storage();
      await db.collection('bookings').doc('273').set({
        'photo_cleanup_paths': [_path],
        'photo_cleanup_claims': <String>[],
      });
      final raw = jsonEncode({
        'id': _id,
        'kind': 'bookingPhoto',
        'created_at': _action,
        'target_path': jsonEncode({'booking_id': '273', 'path': _path}),
        'retry_count': 0,
      });
      disk.data[_scope] = [raw];
      var online = false;
      final queue = OfflineCleanupQueueService(
        backend: disk,
        firestore: db,
        storage: storage,
        isOnline: () => online,
        flushTimeout: const Duration(milliseconds: 30),
      );
      await queue.initialize();
      final gate = Completer<void>();
      db.claimGate = gate;
      online = true;
      await queue.flushPendingCleanups();
      expect(disk.data[_scope], [raw]);
      db.claimGate = null;
      await queue.flushPendingCleanups();
      expect(disk.data[_scope], isEmpty);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(storage.deletes, 1);
      expect(disk.data[_scope], isEmpty);
      expect(
        (await db.collection('bookings').doc('273').get())
            .data()!['photo_cleanup_claims'],
        isEmpty,
      );
    },
  );
}
