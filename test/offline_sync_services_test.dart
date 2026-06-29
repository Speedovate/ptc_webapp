import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/services/support_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BookingOfflineUploadQueueService', () {
    test('replays pending booking photo upload when field is still pending', () async {
      final firestore = FakeFirebaseFirestore();
      final backend = _MemoryBookingStorageBackend();
      final photoService = _FakeBookingPhotoStorageService();
      final service = BookingOfflineUploadQueueService(
        firestore: firestore,
        backend: backend,
        photoStorageService: photoService,
      );

      const pendingUploadId = 'booking_upload_test_1';
      await firestore.collection('bookings').doc('1').set({
        'id': '1',
        'status_outputs': {
          'book': {
            'fields': {
              'waybill_photo': {
                'name': 'waybill.png',
                'mime_type': 'image/png',
                'size': 3,
                'pending_upload': true,
                'pending_upload_id': pendingUploadId,
              },
            },
          },
        },
      });

      await backend.writeStringList('booking_pending_upload_queue_v1', <String>[
        jsonEncode({
          'id': pendingUploadId,
          'booking_id': '1',
          'status_key': 'book',
          'field_key': 'waybill_photo',
          'bytes_base64': base64Encode(Uint8List.fromList([1, 2, 3])),
          'file_name': 'waybill.png',
          'mime_type': 'image/png',
          'size': 3,
          'created_at': DateTime.utc(2026, 6, 29).toIso8601String(),
          'retry_count': 0,
          'last_error': null,
        }),
      ]);

      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final saved = (await firestore.collection('bookings').doc('1').get()).data()!;
      final value = (((saved['status_outputs'] as Map)['book'] as Map)['fields'] as Map)['waybill_photo'] as Map;

      expect(value['download_url'], 'https://example.com/booking-waybill.png');
      expect(value.containsKey('pending_upload'), isFalse);
      expect(photoService.uploadCalls, 1);
    });

    test('does not overwrite newer booking field if pending marker is gone', () async {
      final firestore = FakeFirebaseFirestore();
      final backend = _MemoryBookingStorageBackend();
      final photoService = _FakeBookingPhotoStorageService();
      final service = BookingOfflineUploadQueueService(
        firestore: firestore,
        backend: backend,
        photoStorageService: photoService,
      );

      const pendingUploadId = 'booking_upload_test_2';
      await firestore.collection('bookings').doc('1').set({
        'id': '1',
        'status_outputs': {
          'book': {
            'fields': {
              'waybill_photo': {
                'name': 'server-waybill.png',
                'download_url': 'https://server/newer.png',
              },
            },
          },
        },
      });

      await backend.writeStringList('booking_pending_upload_queue_v1', <String>[
        jsonEncode({
          'id': pendingUploadId,
          'booking_id': '1',
          'status_key': 'book',
          'field_key': 'waybill_photo',
          'bytes_base64': base64Encode(Uint8List.fromList([1, 2, 3])),
          'file_name': 'waybill.png',
          'mime_type': 'image/png',
          'size': 3,
          'created_at': DateTime.utc(2026, 6, 29).toIso8601String(),
          'retry_count': 0,
          'last_error': null,
        }),
      ]);

      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final saved = (await firestore.collection('bookings').doc('1').get()).data()!;
      final value = (((saved['status_outputs'] as Map)['book'] as Map)['fields'] as Map)['waybill_photo'] as Map;

      expect(value['download_url'], 'https://server/newer.png');
      expect(photoService.deletedPaths, contains('bookings/1/status_outputs/book/waybill_photo/fake.png'));
    });
  });

  group('OfflineMediaSyncService', () {
    test('replays queued user profile photo when server value is unchanged', () async {
      final firestore = FakeFirebaseFirestore();
      final backend = _MemoryBookingStorageBackend();
      final photoService = _FakeUserPhotoStorageService();
      final supportStorageService = _FakeSupportStorageService();
      final service = OfflineMediaSyncService(
        firestore: firestore,
        backend: backend,
        photoStorageService: photoService,
        supportStorageService: supportStorageService,
      );

      await firestore.collection('users').doc('7').set({
        'id': '7',
        'role': 'sub-client',
        'name': 'Adryc',
        'photo': 'https://server/old.png',
      });

      await backend.writeStringList('offline_media_sync_queue_v1', <String>[
        jsonEncode({
          'id': 'user_upload_test_1',
          'kind': 'userUpload',
          'created_at': DateTime.utc(2026, 6, 29).toIso8601String(),
          'retry_count': 0,
          'last_error': null,
          'user_id': '7',
          'field_key': 'profile_photo',
          'file_name': 'profile.png',
          'mime_type': 'image/png',
          'size': 3,
          'bytes_base64': base64Encode(Uint8List.fromList([1, 2, 3])),
          'original_value': 'https://server/old.png',
        }),
      ]);

      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final saved = (await firestore.collection('users').doc('7').get()).data()!;
      expect(saved['photo'], 'https://example.com/user-profile.png');
    });

    test('does not overwrite newer user photo if server changed first', () async {
      final firestore = FakeFirebaseFirestore();
      final backend = _MemoryBookingStorageBackend();
      final photoService = _FakeUserPhotoStorageService();
      final supportStorageService = _FakeSupportStorageService();
      final service = OfflineMediaSyncService(
        firestore: firestore,
        backend: backend,
        photoStorageService: photoService,
        supportStorageService: supportStorageService,
      );

      await firestore.collection('users').doc('7').set({
        'id': '7',
        'role': 'sub-client',
        'name': 'Adryc',
        'photo': 'https://server/old.png',
      });

      await firestore.collection('users').doc('7').update({
        'photo': 'https://server/newer.png',
      });

      await backend.writeStringList('offline_media_sync_queue_v1', <String>[
        jsonEncode({
          'id': 'user_upload_test_2',
          'kind': 'userUpload',
          'created_at': DateTime.utc(2026, 6, 29).toIso8601String(),
          'retry_count': 0,
          'last_error': null,
          'user_id': '7',
          'field_key': 'profile_photo',
          'file_name': 'profile.png',
          'mime_type': 'image/png',
          'size': 3,
          'bytes_base64': base64Encode(Uint8List.fromList([1, 2, 3])),
          'original_value': 'https://server/old.png',
        }),
      ]);

      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final saved = (await firestore.collection('users').doc('7').get()).data()!;
      expect(saved['photo'], 'https://server/newer.png');
    });

    test('replays queued support message and attachment', () async {
      final firestore = FakeFirebaseFirestore();
      final backend = _MemoryBookingStorageBackend();
      final photoService = _FakeUserPhotoStorageService();
      final supportStorageService = _FakeSupportStorageService();
      final service = OfflineMediaSyncService(
        firestore: firestore,
        backend: backend,
        photoStorageService: photoService,
        supportStorageService: supportStorageService,
      );

      await firestore.collection('support').doc('thread-1').set(
        const SupportThread(
          id: 'thread-1',
          requesterUserId: '7',
          requesterRole: 'sub-client',
          requesterName: 'Adryc Allen Catapang',
          requesterPhoto: null,
          topicKey: supportTopicGeneral,
          topicLabel: 'General',
          isActive: true,
        ).toMap(),
      );

      const sender = UserModel(
        id: '1',
        role: 'admin',
        name: 'Paltranco Transport Corporation',
      );

      await backend.writeStringList('offline_media_sync_queue_v1', <String>[
        jsonEncode({
          'id': 'support_message_test_1',
          'kind': 'supportMessage',
          'created_at': DateTime.utc(2026, 6, 29).toIso8601String(),
          'retry_count': 0,
          'last_error': null,
          'thread_id': 'thread-1',
          'sender_user_id': sender.id,
          'sender_role': sender.role,
          'sender_name': sender.name,
          'sender_photo': sender.photo,
          'text': 'Hello from queued support',
          'attachments': [
            {
              'bytes_base64': base64Encode(Uint8List.fromList([9, 8, 7])),
              'file_name': 'support.png',
              'mime_type': 'image/png',
              'size': 3,
            },
          ],
        }),
      ]);

      await service.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final messages = await firestore
          .collection('support')
          .doc('thread-1')
          .collection('messages')
          .get();
      expect(messages.docs, hasLength(1));

      final message = messages.docs.single.data();
      expect(message['text'], 'Hello from queued support');
      expect((message['attachments'] as List).length, 1);

      final thread = (await firestore.collection('support').doc('thread-1').get()).data()!;
      expect(thread['last_message_text'], 'Hello from queued support');
    });
  });
}

class _MemoryBookingStorageBackend implements BookingStorageBackend {
  final Map<String, List<String>> _store = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<List<String>> readStringList(String key) async {
    return List<String>.from(_store[key] ?? const []);
  }

  @override
  Future<void> writeStringList(String key, List<String> values) async {
    _store[key] = List<String>.from(values);
  }
}

class _FakeFirebaseStorage implements FirebaseStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBookingPhotoStorageService extends PhotoStorageService {
  _FakeBookingPhotoStorageService() : super(storage: _FakeFirebaseStorage());

  int uploadCalls = 0;
  final List<String> deletedPaths = <String>[];

  @override
  Future<Map<String, dynamic>> uploadBookingPhoto({
    required Uint8List bytes,
    required String bookingId,
    required String statusKey,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    uploadCalls += 1;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return {
      'name': fileName,
      'download_url': 'https://example.com/booking-$fileName',
      'storage_path': 'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/fake.png',
      'mime_type': mimeType ?? 'image/png',
      'size': size ?? bytes.length,
    };
  }

  @override
  Future<void> deleteByPath(String? storagePath) async {
    if (storagePath != null) {
      deletedPaths.add(storagePath);
    }
  }
}

class _FakeUserPhotoStorageService extends PhotoStorageService {
  _FakeUserPhotoStorageService() : super(storage: _FakeFirebaseStorage());

  @override
  Future<Map<String, dynamic>> uploadUserPhoto({
    required Uint8List bytes,
    required String userId,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    final suffix = fieldKey == 'license_photo' ? 'license' : 'user';
    return {
      'name': fileName,
      'download_url': 'https://example.com/$suffix-$fileName',
      'storage_path': 'users/$userId/$fieldKey/fake.png',
      'mime_type': mimeType ?? 'image/png',
      'size': size ?? bytes.length,
    };
  }

  @override
  Future<void> deleteByPath(String? storagePath) async {}
}

class _FakeSupportStorageService extends SupportStorageService {
  _FakeSupportStorageService() : super(storage: _FakeFirebaseStorage());

  @override
  Future<SupportAttachment> uploadAttachment({
    required Uint8List bytes,
    required String threadId,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    return SupportAttachment(
      name: fileName,
      downloadUrl: 'https://example.com/support-$fileName',
      storagePath: 'support/$threadId/attachments/$fileName',
      mimeType: mimeType ?? 'image/png',
      size: size ?? bytes.length,
    );
  }
}
