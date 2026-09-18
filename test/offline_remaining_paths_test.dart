import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/booking.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/requests/support.request.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'booking_id_resolver_test.dart'
    show MemoryBackend, storageKey, key, temp, booking;
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
    await FirestoreCacheStore.instance.writeDocumentMaps('bookings', []);
    await FirestoreCacheStore.instance.writeDocumentMaps(
      'support_threads_all',
      [],
    );
  });

  test(
    'three committed photos clear after lost acknowledgement without restoring or reuploading',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      const mediaKey = 'offline_media_sync_queue_v1::signed_out';
      final entries = <String>[];
      for (var index = 1; index <= 3; index++) {
        entries.add(
          jsonEncode({
            'id': 'photo_$index',
            'kind': 'userUpload',
            'user_id': '7',
            'field_key': 'profile_photo',
            'bytes_base64': base64Encode([index]),
            'mime_type': 'image/png',
            'original_value': index == 1
                ? 'https://original'
                : 'data:image/png;base64,${base64Encode([index - 1])}',
            if (index > 1) 'previous_upload_id': 'photo_${index - 1}',
            'created_at': '2026-09-0${index}T00:00:00Z',
          }),
        );
      }
      await backend.writeStringList(mediaKey, entries);
      await db.collection('users').doc('7').set({
        'photo': 'https://third',
        'offline_photo_uploads': {
          'profile_photo': {'id': 'photo_3', 'url': 'https://third'},
        },
      });
      var online = false;
      final service = OfflineMediaSyncService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      await service.initialize();
      await Future<void>.delayed(Duration.zero);
      online = true;
      await service.flushPendingOperations();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await backend.readStringList(mediaKey), isEmpty);
      expect(
        (await db.collection('users').doc('7').get()).data()!['photo'],
        'https://third',
      );
    },
  );

  test(
    'photo receipt cannot acknowledge a chain from another user or field',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      const mediaKey = 'offline_media_sync_queue_v1::signed_out';
      await backend.writeStringList(mediaKey, [
        jsonEncode({
          'id': 'waiting',
          'kind': 'userUpload',
          'user_id': '7',
          'field_key': 'profile_photo',
          'bytes_base64': 'AQ==',
          'original_value': 'data:image/png;base64,AA==',
          'previous_upload_id': 'older',
          'created_at': '2026-09-01T00:00:00Z',
        }),
        jsonEncode({
          'id': 'other',
          'kind': 'userUpload',
          'user_id': '8',
          'field_key': 'license_photo',
          'bytes_base64': 'Ag==',
          'original_value': 'https://old',
          'previous_upload_id': 'waiting',
          'created_at': '2026-09-02T00:00:00Z',
        }),
      ]);
      await db.collection('users').doc('7').set({
        'photo': 'https://current',
        'offline_photo_uploads': {
          'profile_photo': {'id': 'other', 'url': 'https://current'},
        },
      });
      var online = false;
      final service = OfflineMediaSyncService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      await service.initialize();
      await Future<void>.delayed(Duration.zero);
      online = true;
      await service.flushPendingOperations();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final pending = (await backend.readStringList(
        mediaKey,
      )).map(jsonDecode).toList();
      expect(pending.any((item) => item['id'] == 'waiting'), true);
      expect(
        (await db.collection('users').doc('7').get()).data()!['photo'],
        'https://current',
      );
    },
  );

  test(
    'ordinary queued user edit preserves photo acknowledgement receipts',
    () async {
      var online = false;
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final receipt = {
        'profile_photo': {'id': 'photo_3', 'url': 'https://third'},
      };
      await db.collection('users').doc('7').set({
        'id': '7',
        'name': 'Old',
        'updated_at': '2026-09-01',
        'offline_photo_uploads': receipt,
      });
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      await queue.queueUserUpsert(
        userId: '7',
        baseUpdatedAt: '2026-09-01',
        document: {'id': '7', 'name': 'Edited', 'updated_at': '2026-09-02'},
      );
      online = true;
      await queue.flushPendingMutations();
      final saved = (await db.collection('users').doc('7').get()).data()!;
      expect(saved['name'], 'Edited');
      expect(saved['offline_photo_uploads'], receipt);
      expect(await backend.readStringList(storageKey), isEmpty);
    },
  );

  for (final bulk in [false, true]) {
    test(
      'billing request queues unresolved ID after reconnect, bulk=$bulk',
      () async {
        var online = false;
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        final queue = OfflineMutationQueueService(
          firestore: db,
          backend: backend,
          isOnline: () => online,
        );
        final document = {...booking(), 'billing_status': 'unbilled'};
        await queue.queueOfflineBookingCreate(
          provisionalId: temp,
          submissionKey: key,
          document: document,
        );
        await FirestoreCacheStore.instance.writeDocumentMaps('bookings', [
          document,
        ]);
        final request = BookingRequest(
          firestore: db,
          offlineMutationQueueService: queue,
          authRequest: _Auth(),
          vehicleRequest: _Vehicles(),
        );
        final before = DateTime.now().toUtc();
        if (bulk) {
          await request.updateBillingStatuses({temp: 'billed'});
        } else {
          final saved = await request.updateBillingStatus(temp, 'billed');
          expect(saved.id, temp);
          expect(saved.billingStatus, 'billed');
        }
        final entries = (await backend.readStringList(
          storageKey,
        )).map(jsonDecode).toList();
        final action = entries.singleWhere(
          (item) => item['kind'] == 'bookingBillingStatusUpdate',
        );
        expect(action['target_id'], temp);
        expect(DateTime.parse(action['created_at']).isBefore(before), false);
        online = true;
        await queue.flushPendingMutations();
        expect(await backend.readStringList(storageKey), isEmpty);
        final saved = (await db.collection('bookings').doc('1').get()).data()!;
        expect(saved['billing_status'], 'billed');
        expect(saved['updated_at'], action['created_at']);
      },
    );
  }

  test(
    'user deletion hands scoped asset cleanup off and removes only owned memberships',
    () async {
      var online = false;
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      final cleanupBackend = MemoryBackend();
      final cleanup = OfflineCleanupQueueService(
        backend: cleanupBackend,
        isOnline: () => false,
      );
      final auth = createAuthStorageBackend();
      await auth.initialize();
      await auth.writeString('paltranco_current_user_id', 'admin_A');
      final queue = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
        queueUserAssetCleanup: (userId, scope, time) =>
            cleanup.queueDeleteFolder(
              'users/$userId',
              userScope: scope,
              actionAt: time,
            ),
      );
      await db.collection('users').doc('7').set({'id': '7'});
      await db.collection('client_members').doc('owned').set({'user_id': '7'});
      await db.collection('client_members').doc('7').set({'user_id': '8'});
      await db.collection('client_members').doc('other').set({'user_id': '8'});
      await queue.queueUserDelete(userId: '7');
      final source = jsonDecode(
        (await backend.readStringList(
          'offline_mutation_queue_v1::admin_A',
        )).single,
      );
      await auth.writeStringList('paltranco_known_session_user_ids', [
        'admin_A',
      ]);
      await auth.writeString('paltranco_current_user_id', 'admin_B');
      online = true;
      await queue.flushPendingMutations();
      expect((await db.collection('users').doc('7').get()).exists, false);
      expect(
        (await db.collection('client_members').doc('owned').get()).exists,
        false,
      );
      expect(
        (await db.collection('client_members').doc('7').get()).exists,
        true,
      );
      expect(
        (await db.collection('client_members').doc('other').get()).exists,
        true,
      );
      final cleanupItems = await cleanupBackend.readStringList(
        'offline_cleanup_queue_v1::admin_A',
      );
      expect(cleanupItems, hasLength(1));
      expect(jsonDecode(cleanupItems.single)['target_path'], 'users/7');
      expect(
        jsonDecode(cleanupItems.single)['created_at'],
        source['created_at'],
      );
      expect(
        await cleanupBackend.readStringList(
          'offline_cleanup_queue_v1::admin_B',
        ),
        isEmpty,
      );
    },
  );

  test('cleanup handoff failure retains user deletion for retry', () async {
    var online = false;
    var fail = true;
    final db = MergeAwareFirestore();
    final backend = MemoryBackend();
    final queue = OfflineMutationQueueService(
      firestore: db,
      backend: backend,
      isOnline: () => online,
      queueUserAssetCleanup: (_, _, _) async {
        if (fail) {
          throw StateError('Storage temporarily unavailable. Try again.');
        }
      },
    );
    await db.collection('users').doc('7').set({'id': '7'});
    await queue.queueUserDelete(userId: '7');
    online = true;
    await queue.flushPendingMutations();
    expect(await backend.readStringList(storageKey), hasLength(1));
    fail = false;
    await queue.flushPendingMutations();
    expect(await backend.readStringList(storageKey), isEmpty);
  });

  test(
    'support with pending booking waits for verified booking ID after reconnect',
    () async {
      final db = MergeAwareFirestore();
      final backend = MemoryBackend();
      var online = false;
      final mutations = OfflineMutationQueueService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      await mutations.queueOfflineBookingCreate(
        provisionalId: temp,
        submissionKey: key,
        document: booking(),
      );
      final media = OfflineMediaSyncService(
        firestore: db,
        backend: backend,
        isOnline: () => online,
      );
      final request = SupportRequest(
        firestore: db,
        offlineMediaSyncService: media,
      );
      await FirestoreCacheStore.instance.writeDocumentMaps(
        'support_threads_all',
        [
          {
            'id': 'support_booking',
            'requester_user_id': '7',
            'booking_id': temp,
          },
        ],
      );
      expect(
        await request.sendMessageWithAttachments(
          threadId: 'support_booking',
          sender: const UserModel(id: '7', role: 'driver'),
          text: 'offline booking question',
        ),
        true,
      );
      expect(
        (await db.collection('support').doc('support_booking').get()).exists,
        false,
      );
      await Future<void>.delayed(Duration.zero);
      online = true;
      await mutations.flushPendingMutations();
      await media.flushPendingOperations();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        (await db.collection('support').doc('support_booking').get())
            .data()!['booking_id'],
        '1',
      );
      expect(
        (await db
                .collection('support')
                .doc('support_booking')
                .collection('messages')
                .get())
            .docs,
        hasLength(1),
      );
    },
  );

  for (final changed in [false, true]) {
    test(
      'support send remaps only matching requester, changed=$changed',
      () async {
        final db = MergeAwareFirestore();
        final backend = MemoryBackend();
        var online = false;
        final media = OfflineMediaSyncService(
          firestore: db,
          backend: backend,
          isOnline: () => online,
        );
        const sender = UserModel(id: 'offline_users_sender', role: 'client');
        final request = SupportRequest(
          firestore: db,
          offlineMediaSyncService: media,
        );
        final thread = {
          'id': 'support_pending',
          'requester_user_id': sender.id,
          'requester_role': 'client',
          'is_active': true,
        };
        await FirestoreCacheStore.instance.writeDocumentMaps(
          'support_threads_all',
          [thread],
        );
        expect(
          await request.sendMessageWithAttachments(
            threadId: 'support_pending',
            sender: sender,
            text: 'hello',
          ),
          true,
        );
        expect(
          (await db
                  .collection('support')
                  .doc('support_pending')
                  .collection('messages')
                  .get())
              .docs,
          isEmpty,
        );
        await db.collection('support').doc('support_pending').set({
          ...thread,
          if (changed) 'requester_user_id': '10',
        });
        final auth = createAuthStorageBackend();
        await auth.initialize();
        await auth.writeString(
          'offline_mutation_queue_aliases_v1::$storageKey',
          jsonEncode({sender.id!: '9'}),
        );
        online = true;
        await media.flushPendingOperations();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (changed) {
          expect(
            (await db.collection('support').doc('support_pending').get())
                .data()!['requester_user_id'],
            '10',
          );
          expect(
            (await db
                    .collection('support')
                    .doc('support_pending')
                    .collection('messages')
                    .get())
                .docs,
            isEmpty,
          );
          expect(
            await backend.readStringList(
              'offline_media_sync_queue_v1::signed_out',
            ),
            hasLength(1),
          );
          return;
        }
        expect(
          (await db.collection('support').doc('support_pending').get())
              .data()!['requester_user_id'],
          '9',
        );
        final messages =
            (await db
                    .collection('support')
                    .doc('support_pending')
                    .collection('messages')
                    .get())
                .docs;
        expect(messages, hasLength(1));
        expect(messages.single.data()['sender_user_id'], '9');
        expect(
          await backend.readStringList(
            'offline_media_sync_queue_v1::signed_out',
          ),
          isEmpty,
        );
      },
    );
  }
}

class _Auth extends Fake implements AuthRequest {
  @override
  Future<List<UserModel>> getUsers() async => [];
}

class _Vehicles extends Fake implements VehicleRequest {
  @override
  Future<List<VehicleCatalogItem>> getTypes() async => [];
  @override
  Future<List<VehicleMake>> getMakes() async => [];
  @override
  Future<List<VehicleCatalogItem>> getSizes() async => [];
}
