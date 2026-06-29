import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/support_message.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/support_storage_service.dart';
import 'package:webapp/utils/functions.dart';

class SupportRequest {
  SupportRequest({FirebaseFirestore? firestore, SupportStorageService? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? SupportStorageService.instance;

  static final SupportRequest instance = SupportRequest();

  final FirebaseFirestore _firestore;
  final SupportStorageService _storage;
  final OfflineMediaSyncService _offlineMediaSyncService =
      OfflineMediaSyncService.instance;

  CollectionReference<Map<String, dynamic>> get _supportCollection =>
      _firestore.collection('support');

  Stream<List<SupportThread>> watchAllThreads() {
    return _supportCollection.snapshots().map((snapshot) {
      final threads = snapshot.docs
          .map((doc) => SupportThread.fromMap(documentData(doc)))
          .toList();
      threads.sort(_compareThreadsNewestFirst);
      return threads;
    });
  }

  Stream<List<SupportThread>> watchThreadsForUser(String userId) {
    final normalizedUserId = normalizeId(userId);
    if (normalizedUserId == null) {
      return Stream.value(const []);
    }
    return _supportCollection
        .where('requester_user_id', isEqualTo: normalizedUserId)
        .snapshots()
        .map((snapshot) {
          final threads = snapshot.docs
              .map((doc) => SupportThread.fromMap(documentData(doc)))
              .toList();
          threads.sort(_compareThreadsNewestFirst);
          return threads;
        });
  }

  Stream<List<SupportMessage>> watchMessages(String threadId) {
    final normalizedThreadId = normalizeId(threadId);
    if (normalizedThreadId == null) {
      return Stream.value(const []);
    }
    return _supportCollection
        .doc(normalizedThreadId)
        .collection('messages')
        .orderBy('created_at')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => SupportMessage.fromMap(documentData(doc)))
              .toList();
        });
  }

  Future<SupportThread> ensureThread({
    required UserModel requester,
    required String topicKey,
    Booking? booking,
  }) async {
    final requesterId = normalizeId(requester.id);
    if (requesterId == null) {
      throw Exception('User ID is required.');
    }
    final normalizedTopicKey = (topicKey).trim().toLowerCase();
    final normalizedBookingId = normalizeId(booking?.id);

    final existingSnapshot = await _supportCollection
        .where('requester_user_id', isEqualTo: requesterId)
        .get();
    for (final doc in existingSnapshot.docs) {
      final thread = SupportThread.fromMap(documentData(doc));
      if ((thread.topicKey ?? '').trim().toLowerCase() != normalizedTopicKey) {
        continue;
      }
      if (normalizeId(thread.bookingId) != normalizedBookingId) {
        continue;
      }
      if (thread.isActive == false) {
        continue;
      }
      return thread;
    }

    final threadDoc = _supportCollection.doc();
    final now = DateTime.now().toUtc();
    final bookingLabel = normalizedBookingId == null
        ? null
        : _bookingLabel(booking ?? Booking(id: normalizedBookingId));
    final thread = SupportThread(
      id: threadDoc.id,
      requesterUserId: requesterId,
      requesterRole: requester.role,
      requesterName: requester.name,
      requesterPhoto: requester.photo,
      requesterParentClientId: requester.parentClientId,
      topicKey: normalizedTopicKey,
      topicLabel: supportTopicLabel(normalizedTopicKey),
      bookingId: normalizedBookingId,
      bookingLabel: bookingLabel,
      lastMessageText: null,
      lastMessageAt: now,
      lastSenderUserId: null,
      lastSenderRole: null,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
    await threadDoc.set(thread.toMap());
    return thread;
  }

  Future<SupportThread> ensureAdminDirectThread({
    required UserModel targetUser,
  }) async {
    final requesterId = normalizeId(targetUser.id);
    if (requesterId == null) {
      throw Exception('User ID is required.');
    }

    final existingSnapshot = await _supportCollection
        .where('requester_user_id', isEqualTo: requesterId)
        .get();
    final existingThreads = existingSnapshot.docs
        .map((doc) => SupportThread.fromMap(documentData(doc)))
        .where((thread) => thread.isActive != false)
        .toList()
      ..sort(_compareThreadsNewestFirst);

    final directThread = existingThreads.where((thread) {
      return normalizeId(thread.bookingId) == null &&
          (thread.topicKey ?? '').trim().toLowerCase() == supportTopicGeneral;
    }).firstOrNull;
    if (directThread != null) {
      return directThread;
    }

    final latestThread = existingThreads.firstOrNull;
    if (latestThread != null) {
      return latestThread;
    }

    final threadDoc = _supportCollection.doc();
    final now = DateTime.now().toUtc();
    final thread = SupportThread(
      id: threadDoc.id,
      requesterUserId: requesterId,
      requesterRole: targetUser.role,
      requesterName: targetUser.name,
      requesterPhoto: targetUser.photo,
      requesterParentClientId: targetUser.parentClientId,
      topicKey: supportTopicGeneral,
      topicLabel: supportTopicLabel(supportTopicGeneral),
      bookingId: null,
      bookingLabel: null,
      lastMessageText: null,
      lastMessageAt: now,
      lastSenderUserId: null,
      lastSenderRole: null,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
    await threadDoc.set(thread.toMap());
    return thread;
  }

  Future<SupportAttachment> uploadAttachment({
    required String threadId,
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    int? size,
  }) {
    final normalizedThreadId = normalizeId(threadId);
    if (normalizedThreadId == null) {
      throw Exception('Thread ID is required.');
    }
    return _storage.uploadAttachment(
      bytes: bytes,
      threadId: normalizedThreadId,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
    );
  }

  Future<void> sendMessage({
    required String threadId,
    required UserModel sender,
    String? text,
    List<SupportAttachment> attachments = const [],
  }) async {
    final normalizedThreadId = normalizeId(threadId);
    final normalizedSenderId = normalizeId(sender.id);
    if (normalizedThreadId == null || normalizedSenderId == null) {
      throw Exception('Support message could not be sent.');
    }
    final trimmedText = text?.trim();
    if ((trimmedText == null || trimmedText.isEmpty) && attachments.isEmpty) {
      return;
    }

    final threadDoc = _supportCollection.doc(normalizedThreadId);
    final messageDoc = threadDoc.collection('messages').doc();
    final now = DateTime.now().toUtc();
    final message = SupportMessage(
      id: messageDoc.id,
      threadId: normalizedThreadId,
      senderUserId: normalizedSenderId,
      senderRole: sender.role,
      senderName: sender.name,
      senderPhoto: sender.photo,
      text: trimmedText,
      attachments: attachments,
      createdAt: now,
      updatedAt: now,
    );
    await messageDoc.set(message.toMap());

    final lastPreview = trimmedText?.isNotEmpty == true
        ? trimmedText!
        : attachments.length == 1
        ? 'Sent an attachment'
        : 'Sent ${attachments.length} attachments';
    await threadDoc.set({
      'last_message_text': lastPreview,
      'last_message_at': now.toIso8601String(),
      'last_sender_user_id': normalizedSenderId,
      'last_sender_role': sender.role,
      'updated_at': now.toIso8601String(),
      'is_active': true,
    }, SetOptions(merge: true));
  }

  Future<bool> sendMessageWithAttachments({
    required String threadId,
    required UserModel sender,
    String? text,
    List<QueuedSupportAttachmentInput> attachments = const [],
  }) async {
    final trimmedText = text?.trim();
    if ((trimmedText == null || trimmedText.isEmpty) && attachments.isEmpty) {
      return false;
    }

    try {
      final uploadedAttachments = <SupportAttachment>[];
      for (final attachment in attachments) {
        uploadedAttachments.add(
          await uploadAttachment(
            threadId: threadId,
            bytes: attachment.bytes,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            size: attachment.size,
          ),
        );
      }
      await sendMessage(
        threadId: threadId,
        sender: sender,
        text: trimmedText,
        attachments: uploadedAttachments,
      );
      return false;
    } catch (error) {
      final normalizedError = normalizeUserErrorText(
        error.toString(),
        fallback: '',
      ).toLowerCase();
      if (!_isQueueableUploadError(normalizedError)) {
        rethrow;
      }
      await _offlineMediaSyncService.queueSupportMessage(
        threadId: threadId,
        sender: sender,
        text: trimmedText,
        attachments: attachments,
      );
      return true;
    }
  }

  bool _isQueueableUploadError(String normalizedError) {
    return normalizedError.contains('internet connection') ||
        normalizedError.contains('temporarily unavailable') ||
        normalizedError.contains('request took too long');
  }

  static int _compareThreadsNewestFirst(SupportThread left, SupportThread right) {
    final leftDate = left.updatedAt ?? left.lastMessageAt ?? left.createdAt;
    final rightDate = right.updatedAt ?? right.lastMessageAt ?? right.createdAt;
    if (leftDate == null && rightDate == null) {
      return 0;
    }
    if (leftDate == null) {
      return 1;
    }
    if (rightDate == null) {
      return -1;
    }
    return rightDate.compareTo(leftDate);
  }

  static String _bookingLabel(Booking booking) {
    final bookingId = booking.id?.trim();
    if (bookingId == null || bookingId.isEmpty) {
      return 'Booking';
    }
    return 'Booking $bookingId';
  }
}
