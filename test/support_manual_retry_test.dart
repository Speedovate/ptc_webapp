import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'support/merge_aware_firestore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'explicit chat retry preserves message identity/action time and does not retry another account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final auth = createAuthStorageBackend();
      await auth.initialize();
      await auth.writeString('paltranco_current_user_id', '7');
      await auth.writeStringList('paltranco_known_session_user_ids', ['7']);
      addTearDown(() async {
        await auth.remove('paltranco_current_user_id');
        await auth.remove('paltranco_known_session_user_ids');
      });
      final backend = MemoryBackend();
      final db = MergeAwareFirestore();
      final message = jsonEncode({
        'id': 'chat_1',
        'kind': 'supportMessage',
        'thread_id': 'thread_1',
        'sender_user_id': '7',
        'sender_role': 'driver',
        'sender_name': 'Driver',
        'local_order_key': 'original_action',
        'created_at': '2026-09-19T00:56:16.000Z',
        'last_error': r"NoSuchMethodError: other[$forEach]",
        'retry_count': 1,
        'next_retry_at': '2099-01-01T00:00:00Z',
        'text': 'Keep this message',
        'attachments': [],
      });
      await backend.writeStringList('offline_media_sync_queue_v1::7', [
        message,
      ]);
      await backend.writeStringList('offline_media_sync_queue_v1::8', [
        message,
      ]);
      await db.collection('support').doc('thread_1').set({'id': 'thread_1'});
      var online = false;
      final service = OfflineMediaSyncService(
        backend: backend,
        firestore: db,
        isOnline: () => online,
      );
      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await service.retryFailedSupportMessagesOnOpen('7');
      expect(await backend.readStringList('offline_media_sync_queue_v1::7'), [
        message,
      ]);
      online = true;
      await expectLater(
        service.retryFailedSupportMessages('8'),
        throwsStateError,
      );
      expect(await backend.readStringList('offline_media_sync_queue_v1::7'), [
        message,
      ]);
      await service.retryFailedSupportMessagesOnOpen('7');
      expect(
        await backend.readStringList('offline_media_sync_queue_v1::7'),
        isEmpty,
      );
      expect(await backend.readStringList('offline_media_sync_queue_v1::8'), [
        message,
      ]);
      final messages = await db
          .collection('support')
          .doc('thread_1')
          .collection('messages')
          .get();
      expect(messages.docs, hasLength(1));
      expect(messages.docs.single.id, 'chat_1');
      expect(messages.docs.single.data()['text'], 'Keep this message');
      expect(
        messages.docs.single.data()['created_at'],
        '2026-09-19T00:56:16.000Z',
      );
      await service.retryFailedSupportMessagesOnOpen('7');
      expect(
        (await db
                .collection('support')
                .doc('thread_1')
                .collection('messages')
                .get())
            .docs,
        hasLength(1),
      );
    },
  );
}
