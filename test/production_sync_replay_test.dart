import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;

/// Full-fidelity replay of every `sync_error_logs` entry reported from
/// production on 2026-09-25.
///
/// The queued payload, the server booking, the owning booking and the chassis
/// document are copied verbatim from the reports (photo byte payloads keep the
/// logs' `[INLINE MEDIA OMITTED]` placeholder, since only their shape matters).
/// Each case asserts both halves of the contract: the stale action is retired
/// when the evidence proves it, and nothing on the server is overwritten when
/// the evidence does not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cases =
      (jsonDecode(
                File(
                  'test/fixtures/production_sync_recovery.json',
                ).readAsStringSync(),
              )
              as List)
          .cast<Map<String, dynamic>>();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = createAuthStorageBackend();
    await auth.initialize();
    await auth.writeString('paltranco_current_user_id', 'manager');
  });
  tearDown(() async {
    final auth = createAuthStorageBackend();
    await auth.remove('paltranco_current_user_id');
    await auth.remove('paltranco_known_session_user_ids');
  });

  const queueKey = 'offline_mutation_queue_v1::manager';

  Map<String, dynamic> entryJson(Map<String, dynamic> c) => {
    'id': c['entry_id'],
    'kind': 'collectionDocumentUpsert',
    'target_id': c['target_id'],
    'collection_key': c['collection'],
    'base_updated_at': c['base_updated_at'],
    'payload': c['pending_payload'],
    'created_at': c['action_at'],
    'retry_count': 3,
    'is_blocked': true,
    'last_error': c['error'],
  };

  for (final c in cases.where((c) => c['kind'] != 'cleanup_timeout')) {
    test('${c['name']} -> ${c['expect']}', () async {
      final db = FakeFirebaseFirestore();
      if (c['collection'] == 'bookings') {
        await db
            .collection('bookings')
            .doc('${c['target_id']}')
            .set(Map<String, dynamic>.from(c['server_booking'] as Map));
        final owner = c['owner_booking'] as Map?;
        if (owner != null) {
          await db
              .collection('bookings')
              .doc('${owner['id']}')
              .set(Map<String, dynamic>.from(owner));
        }
        final chassis = c['chassis'] as Map?;
        if (chassis != null) {
          await db
              .collection('chassis')
              .doc('${chassis['id']}')
              .set(Map<String, dynamic>.from(chassis));
        }
      } else {
        await db
            .collection('users')
            .doc('${c['target_id']}')
            .set(Map<String, dynamic>.from(c['server_document'] as Map));
      }
      final before = jsonDecode(db.dump().toString());
      final backend = MemoryBackend();
      await backend.writeStringList(queueKey, [jsonEncode(entryJson(c))]);
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => true,
      );

      await queue.flushPendingMutations();

      final remaining = await backend.readStringList(queueKey);
      if (c['expect'] == 'retired') {
        expect(
          remaining,
          isEmpty,
          reason: 'the stale action should be retired, not left blocked',
        );
      } else {
        expect(remaining, hasLength(1));
        final retained = jsonDecode(remaining.single) as Map<String, dynamic>;
        expect(retained['is_blocked'], isTrue);
        expect('${retained['last_error']}', isNotEmpty);
        final item = (await queue.readPendingItems('manager')).single;
        expect(item.isBlocked, isTrue);
        expect(item.conflictId, c['entry_id']);
      }

      // A chassis conflict resolves in two independent halves: the trip's own
      // status is recorded, and the vehicle is left with the booking that
      // physically holds it. Neither half may damage the other.
      if (c['expect_booking_status'] != null) {
        final saved =
            (await db.collection('bookings').doc('${c['target_id']}').get())
                .data()!;
        expect(
          saved['client_status'],
          c['expect_booking_status'],
          reason: 'the trip really happened; its status must be recorded',
        );
        final outputs = Map<String, dynamic>.from(
          saved['status_outputs'] as Map? ?? const {},
        );
        for (final key in c['expect_booking_has_event'] as List? ?? const []) {
          expect(
            outputs.containsKey(key),
            isTrue,
            reason: 'the queued status event $key must survive the replay',
          );
          // The delivery form photo is still marked pending on the server. That
          // marker is what the photo-upload queue matches against, so it is the
          // only thing that lets the captured bytes finish uploading; dropping
          // the action used to strand them with nowhere to attach.
          final event = Map<String, dynamic>.from(outputs[key] as Map);
          final fields = Map<String, dynamic>.from(
            event['fields'] as Map? ?? const {},
          );
          for (final field in fields.entries) {
            final photo = field.value;
            if (photo is! Map || photo['pending_upload'] != true) continue;
            expect(
              '${photo['pending_upload_id'] ?? ''}',
              isNotEmpty,
              reason:
                  'a pending photo needs its upload id so the captured bytes '
                  'can still be attached to $key',
            );
            expect(
              '${photo['download_url'] ?? ''}',
              startsWith('data:'),
              reason:
                  'the placeholder must stay a local preview until the '
                  'upload completes',
            );
          }
        }
        expect(saved['driver_status'], c['expect_booking_status']);
        expect(saved['helper_status'], c['expect_booking_status']);
        if (c['expect_booking_status'] == 'delivered') {
          expect(
            saved['delivered_at'],
            isNotNull,
            reason: 'a delivery confirmation must not be dropped',
          );
        }
        // Applying the trip also arms the photo-replacement cleanup. The queued
        // payload is a superset of the server copy here, so nothing the server
        // still references may end up queued for deletion.
        expect(
          (saved['photo_cleanup_paths'] as List?) ?? const [],
          isEmpty,
          reason: 'no photo the server still references may be deleted',
        );
        expect((saved['photo_cleanup_claims'] as List?) ?? const [], isEmpty);
      }

      // Nothing the recovery did not prove may change on the server.
      final after = jsonDecode(db.dump().toString());
      final protectedTargets = <String>[
        // A chassis conflict writes the trip it is about, so only the *other*
        // bookings are held to a byte-identical comparison.
        if (c['collection'] == 'bookings' && c['expect_booking_status'] == null)
          c['target_id'] as String,
        if (c['owner_booking'] != null) '${(c['owner_booking'] as Map)['id']}',
      ];
      for (final id in protectedTargets.toSet()) {
        final beforeDoc =
            ((before['bookings'] as Map?)?[id] ?? before['users']?[id]) as Map?;
        final afterDoc =
            ((after['bookings'] as Map?)?[id] ?? after['users']?[id]) as Map?;
        expect(
          jsonEncode(afterDoc),
          jsonEncode(beforeDoc),
          reason: 'bookings/$id must be left exactly as the server had it',
        );
      }
      final beforeChassis = before['chassis'] as Map?;
      expect(
        jsonEncode(after['chassis']),
        jsonEncode(beforeChassis),
        reason: 'no chassis document may move during a replay',
      );
      if (c['assert_owner'] != null) {
        final owner = c['assert_owner'] as Map;
        final chassisId = '${owner['chassis_id']}';
        final chassis = (await db.collection('chassis').doc(chassisId).get())
            .data()!;
        expect(
          '${chassis['current_booking_id']}',
          '${owner['booking_id']}',
          reason: 'the active chassis owner must survive the replay',
        );
        expect(chassis['current_status'], 'loaded');
        final ownerDoc =
            (await db
                    .collection('bookings')
                    .doc('${owner['booking_id']}')
                    .get())
                .data()!;
        expect('${ownerDoc['chassis_id']}', chassisId);
        final stale =
            (await db.collection('bookings').doc('${c['target_id']}').get())
                .data()!;
        // A live claim on a vehicle the server proves is on another trip is
        // corrected. A completed trip keeps the record of which vehicle ran it,
        // and anything unproven is left exactly as the server had it.
        expect(
          '${stale['chassis_id'] ?? ''}',
          c['expect_chassis_link'] == 'cleared' ? isNot(chassisId) : chassisId,
          reason: c['expect_chassis_link'] == 'cleared'
              ? 'evidence proved the chassis moved to a newer trip, so the '
                    'live claim must be corrected'
              : "the server's own link stands: it is either history or "
                    'unproven, and this code does not invent either way',
        );
      }
      for (final field in (c['assert_preserved_fields'] as List? ?? const [])) {
        final saved =
            (await db.collection('users').doc('${c['target_id']}').get())
                .data()!;
        expect(saved[field], isNotNull);
      }
    });
  }

  for (final c in cases.where((c) => c['kind'] == 'cleanup_timeout')) {
    test('${c['name']} -> ${c['expect']}', () async {
      final cleanup = c['cleanup'] as Map;
      final path = '${cleanup['path']}';
      final db = FakeFirebaseFirestore();
      await db
          .collection('bookings')
          .doc('${c['target_id']}')
          .set(Map<String, dynamic>.from(cleanup['booking'] as Map));
      final storage = _Storage(
        present: cleanup['object_exists'] as bool,
        createdAt: DateTime.tryParse('${cleanup['object_created_at']}'),
      );
      final backend = MemoryBackend();
      const key = 'offline_cleanup_queue_v1::signed_out';
      await backend.writeStringList(key, [
        jsonEncode({
          'id': c['entry_id'],
          'kind': 'bookingPhoto',
          'target_path': jsonEncode({
            'booking_id': c['target_id'],
            'path': path,
          }),
          'created_at': c['action_at'],
          'retry_count': 1,
          'last_error': c['error'],
        }),
      ]);
      final queue = OfflineCleanupQueueService(
        backend: backend,
        storage: storage,
        firestore: db,
        isOnline: () => true,
      );

      await queue.flushPendingCleanups();

      final booking =
          (await db.collection('bookings').doc('${c['target_id']}').get())
              .data()!;
      if (c['expect'] == 'cleanup_retired') {
        expect(await backend.readStringList(key), isEmpty);
        expect(booking['photo_cleanup_paths'], isEmpty);
        expect(booking['photo_cleanup_claims'], isEmpty);
        expect(
          storage.deleted,
          cleanup['object_exists'] as bool ? [path] : isEmpty,
          reason: cleanup['object_exists'] as bool
              // The object predates the cleanup, so it is the very photo the
              // entry was queued to remove and the deletion can be finished.
              ? 'the superseded object is the one this cleanup was created for'
              : 'a missing object is never re-deleted',
        );
        return;
      }

      // The path was written again after the cleanup was queued, so the bytes
      // are not the ones the entry was created to remove. A plain retry must
      // not delete them; the user has to confirm.
      final retained =
          jsonDecode((await backend.readStringList(key)).single)
              as Map<String, dynamic>;
      expect('${retained['last_error']}', contains('cleanup is still claimed'));
      expect(storage.deleted, isEmpty);
      expect(booking['photo_cleanup_claims'], [path]);

      final item = (await queue.readPendingItems('signed_out')).single;
      expect(item.isBlocked, isTrue);
      expect(
        item.conflictId,
        '${OfflineCleanupQueueService.claimedCleanupPrefix}${c['entry_id']}',
      );

      await queue.resolveClaimedCleanup(
        '${OfflineCleanupQueueService.claimedCleanupPrefix}${c['entry_id']}',
        keepLocal: true,
        storageKey: key,
      );
      await queue.flushPendingCleanups();
      expect(storage.deleted, [path]);
      expect(await backend.readStringList(key), isEmpty);
      final settled =
          (await db.collection('bookings').doc('${c['target_id']}').get())
              .data()!;
      expect(settled['photo_cleanup_paths'], isEmpty);
      expect(settled['photo_cleanup_claims'], isEmpty);
    });
  }
}

class _Storage extends Fake implements FirebaseStorage {
  _Storage({required this.present, this.createdAt});

  final bool present;

  /// When the object at the path was written, mirroring Storage's metadata.
  final DateTime? createdAt;
  final deleted = <String>[];

  @override
  Reference ref([String? path]) => _Reference(this, path!);
}

class _Reference extends Fake implements Reference {
  _Reference(this.owner, this.path);

  final _Storage owner;
  final String path;

  @override
  Future<FullMetadata> getMetadata() async {
    if (!owner.present) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
        message: 'not found',
      );
    }
    return FullMetadata({
      'name': path,
      'bucket': 'test',
      'generation': '1',
      'metageneration': '1',
      'contentType': 'image/jpeg',
      'creationTimeMillis':
          (owner.createdAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
      'updatedTimeMillis':
          (owner.createdAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
      'size': '1',
      'md5Hash': 'x',
      'etag': 'x',
      'crc32c': 'x',
      'downloadTokens': 'x',
    });
  }

  @override
  Future<void> delete() async => owner.deleted.add(path);
}
