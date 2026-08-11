import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/support_message.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/support_storage_service.dart';
import 'package:webapp/utils/functions.dart';

class SupportRequest {
  SupportRequest({FirebaseFirestore? firestore, SupportStorageService? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? SupportStorageService.instance;

  static final SupportRequest instance = SupportRequest();
  static const _supportThreadsResourceKey = 'support_threads_all';

  final FirebaseFirestore _firestore;
  final SupportStorageService _storage;
  final OfflineMediaSyncService _offlineMediaSyncService =
      OfflineMediaSyncService.instance;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );
  final StreamController<void> _threadCacheUpdates =
      StreamController<void>.broadcast();
  final StreamController<String> _messageCacheUpdates =
      StreamController<String>.broadcast();

  CollectionReference<Map<String, dynamic>> get _supportCollection =>
      _firestore.collection('support');

  Future<List<SupportThread>> prefetchAllThreads() async {
    final snapshot = await _supportCollection.get();
    final documents = snapshot.docs.map(documentData).toList();
    await _cache.writeDocuments(
      resourceKey: _supportThreadsResourceKey,
      documents: documents,
    );
    final threads = documents.map(SupportThread.fromMap).toList();
    threads.sort(_compareThreadsNewestFirst);
    return threads;
  }

  Future<List<SupportThread>> prefetchThreadsForUser(String userId) async {
    final normalizedUserId = normalizeId(userId);
    if (normalizedUserId == null) {
      return const <SupportThread>[];
    }
    final snapshot = await _supportCollection
        .where('requester_user_id', isEqualTo: normalizedUserId)
        .get();
    final documents = snapshot.docs.map(documentData).toList();
    await _mergeThreadsIntoCache(documents);
    final threads = documents.map(SupportThread.fromMap).toList();
    threads.sort(_compareThreadsNewestFirst);
    return threads;
  }

  Future<List<SupportMessage>> prefetchMessages(String threadId) async {
    final normalizedThreadId = normalizeId(threadId);
    if (normalizedThreadId == null) {
      return const <SupportMessage>[];
    }
    final snapshot = await _supportCollection
        .doc(normalizedThreadId)
        .collection('messages')
        .orderBy('created_at')
        .get();
    final documents = snapshot.docs.map(documentData).toList();
    await _cache.writeDocuments(
      resourceKey: _messageResourceKey(normalizedThreadId),
      documents: documents,
    );
    final messages = documents.map(SupportMessage.fromMap).toList()
      ..sort(_compareMessagesOldestFirst);
    return messages;
  }

  Future<void> prefetchMessagesForThreads(List<SupportThread> threads) async {
    for (final thread in threads) {
      final threadId = normalizeId(thread.id);
      if (threadId == null) {
        continue;
      }
      await prefetchMessages(threadId);
    }
  }

  Stream<List<SupportThread>> watchAllThreads() {
    return Stream<List<SupportThread>>.multi((controller) {
      Future<void> emitCachedThreads() async {
        final cached = await _cache.readDocuments(_supportThreadsResourceKey);
        if (controller.isClosed || cached == null) {
          return;
        }
        final cachedThreads = cached.map(SupportThread.fromMap).toList()
          ..sort(_compareThreadsNewestFirst);
        controller.add(cachedThreads);
      }

      unawaited(emitCachedThreads());

      final remoteSubscription = _supportCollection.snapshots().listen((
        snapshot,
      ) async {
        final documents = snapshot.docs.map(documentData).toList();
        final cachedDocuments =
            await _cache.readDocuments(_supportThreadsResourceKey) ??
            const <Map<String, dynamic>>[];
        final mergedDocuments = _mergeVisibleThreadDocuments(
          remoteDocuments: documents,
          cachedDocuments: cachedDocuments,
        );
        await _cache.writeDocuments(
          resourceKey: _supportThreadsResourceKey,
          documents: mergedDocuments,
        );
        if (controller.isClosed) {
          return;
        }
        final threads = mergedDocuments.map(SupportThread.fromMap).toList()
          ..sort(_compareThreadsNewestFirst);
        controller.add(threads);
      }, onError: controller.addError);

      final localSubscription = _threadCacheUpdates.stream.listen((_) {
        unawaited(emitCachedThreads());
      }, onError: controller.addError);

      controller.onCancel = () async {
        await remoteSubscription.cancel();
        await localSubscription.cancel();
      };
    });
  }

  Stream<List<SupportThread>> watchThreadsForUser(String userId) {
    final normalizedUserId = normalizeId(userId);
    if (normalizedUserId == null) {
      return Stream<List<SupportThread>>.value(const <SupportThread>[]);
    }
    return Stream<List<SupportThread>>.multi((controller) {
      Future<void> emitCachedThreads() async {
        final cached = await _cache.readDocuments(_supportThreadsResourceKey);
        if (controller.isClosed || cached == null) {
          return;
        }
        final cachedThreads =
            cached
                .map(SupportThread.fromMap)
                .where(
                  (thread) =>
                      normalizeId(thread.requesterUserId) == normalizedUserId,
                )
                .toList()
              ..sort(_compareThreadsNewestFirst);
        controller.add(cachedThreads);
      }

      unawaited(emitCachedThreads());

      final remoteSubscription = _supportCollection
          .where('requester_user_id', isEqualTo: normalizedUserId)
          .snapshots()
          .listen((snapshot) async {
            final documents = snapshot.docs.map(documentData).toList();
            final cachedDocuments =
                await _cache.readDocuments(_supportThreadsResourceKey) ??
                const <Map<String, dynamic>>[];
            final mergedDocuments = _mergeVisibleThreadDocuments(
              remoteDocuments: documents,
              cachedDocuments: cachedDocuments,
            );
            await _mergeThreadsIntoCache(mergedDocuments);
            if (controller.isClosed) {
              return;
            }
            final threads = mergedDocuments.map(SupportThread.fromMap).toList();
            threads.sort(_compareThreadsNewestFirst);
            controller.add(threads);
          }, onError: controller.addError);

      final localSubscription = _threadCacheUpdates.stream.listen((_) {
        unawaited(emitCachedThreads());
      }, onError: controller.addError);

      controller.onCancel = () async {
        await remoteSubscription.cancel();
        await localSubscription.cancel();
      };
    });
  }

  Stream<List<SupportMessage>> watchMessages(String threadId) {
    final normalizedThreadId = normalizeId(threadId);
    if (normalizedThreadId == null) {
      return Stream<List<SupportMessage>>.value(const <SupportMessage>[]);
    }
    return Stream<List<SupportMessage>>.multi((controller) {
      Future<void> emitCachedMessages() async {
        final cached =
            await _cache.readDocuments(
              _messageResourceKey(normalizedThreadId),
            ) ??
            const <Map<String, dynamic>>[];
        final queuedDocuments = await _offlineMediaSyncService
            .readQueuedSupportMessageDocuments(threadId: normalizedThreadId);
        final visibleDocuments = _mergeQueuedPendingMessageDocuments(
          existingDocuments: cached,
          queuedDocuments: queuedDocuments,
        );
        if (controller.isClosed || visibleDocuments.isEmpty && cached.isEmpty) {
          return;
        }
        if (!_sameMessageDocumentSet(cached, visibleDocuments)) {
          await _cache.writeDocuments(
            resourceKey: _messageResourceKey(normalizedThreadId),
            documents: visibleDocuments,
          );
        }
        final messages = visibleDocuments.map(SupportMessage.fromMap).toList()
          ..sort(_compareMessagesOldestFirst);
        controller.add(messages);
      }

      unawaited(emitCachedMessages());

      final remoteSubscription = _supportCollection
          .doc(normalizedThreadId)
          .collection('messages')
          .orderBy('created_at')
          .snapshots()
          .listen((snapshot) async {
            final documents = snapshot.docs.map(documentData).toList();
            final cachedDocuments =
                await _cache.readDocuments(
                  _messageResourceKey(normalizedThreadId),
                ) ??
                const <Map<String, dynamic>>[];
            final mergedDocuments = _mergeVisibleMessageDocuments(
              remoteDocuments: documents,
              cachedDocuments: cachedDocuments,
            );
            final queuedDocuments = await _offlineMediaSyncService
                .readQueuedSupportMessageDocuments(
                  threadId: normalizedThreadId,
                );
            final visibleDocuments = _mergeQueuedPendingMessageDocuments(
              existingDocuments: mergedDocuments,
              queuedDocuments: queuedDocuments,
            );
            await _cache.writeDocuments(
              resourceKey: _messageResourceKey(normalizedThreadId),
              documents: visibleDocuments,
            );
            if (controller.isClosed) {
              return;
            }
            final messages =
                visibleDocuments.map(SupportMessage.fromMap).toList()
                  ..sort(_compareMessagesOldestFirst);
            controller.add(messages);
          }, onError: controller.addError);

      final localSubscription = _messageCacheUpdates.stream.listen((threadId) {
        if (normalizeId(threadId) != normalizedThreadId) {
          return;
        }
        unawaited(emitCachedMessages());
      }, onError: controller.addError);

      controller.onCancel = () async {
        await remoteSubscription.cancel();
        await localSubscription.cancel();
      };
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
    final cachedThread = await _findCachedThread(
      requesterUserId: requesterId,
      topicKey: normalizedTopicKey,
      bookingId: normalizedBookingId,
    );
    if (cachedThread != null && cachedThread.isActive != false) {
      return cachedThread;
    }

    if (!currentNetworkStatus()) {
      return _createLocalThread(
        requester: requester,
        topicKey: normalizedTopicKey,
        booking: booking,
      );
    }

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
    await _cache.upsertDocument(
      resourceKey: _supportThreadsResourceKey,
      document: thread.toMap(),
    );
    _emitThreadCacheUpdate();
    return thread;
  }

  Future<SupportThread> ensureAdminDirectThread({
    required UserModel targetUser,
  }) async {
    final existingThread = await findAdminDirectThread(targetUser: targetUser);
    if (existingThread != null) {
      return existingThread;
    }

    final requesterId = normalizeId(targetUser.id);
    if (requesterId == null) {
      throw Exception('User ID is required.');
    }

    if (!currentNetworkStatus()) {
      return _createLocalAdminDirectThread(targetUser: targetUser);
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
      lastMessageAt: null,
      lastSenderUserId: null,
      lastSenderRole: null,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
    await threadDoc.set(thread.toMap());
    await _cache.upsertDocument(
      resourceKey: _supportThreadsResourceKey,
      document: thread.toMap(),
    );
    _emitThreadCacheUpdate();
    return thread;
  }

  Future<SupportThread?> findAdminDirectThread({
    required UserModel targetUser,
  }) async {
    final requesterId = normalizeId(targetUser.id);
    if (requesterId == null) {
      throw Exception('User ID is required.');
    }
    final cachedThread = await _findCachedDirectThread(requesterId);
    if (cachedThread != null) {
      return cachedThread;
    }

    if (!currentNetworkStatus()) {
      return null;
    }

    final existingSnapshot = await _supportCollection
        .where('requester_user_id', isEqualTo: requesterId)
        .get();
    final existingThreads =
        existingSnapshot.docs
            .map((doc) => SupportThread.fromMap(documentData(doc)))
            .where(
              (thread) => thread.isActive != false && thread.hasConversation,
            )
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
    return null;
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
    final messageMap = message.toMap();
    await messageDoc.set(message.toMap());
    await _cache.upsertDocument(
      resourceKey: _messageResourceKey(normalizedThreadId),
      document: messageMap,
    );
    _emitMessageCacheUpdate(normalizedThreadId);

    final lastPreview = trimmedText?.isNotEmpty == true
        ? trimmedText!
        : attachments.length == 1
        ? 'Sent an attachment'
        : 'Sent ${attachments.length} attachments';
    final threadPatch = {
      'last_message_text': lastPreview,
      'last_message_at': now.toIso8601String(),
      'last_sender_user_id': normalizedSenderId,
      'last_sender_role': sender.role,
      'updated_at': now.toIso8601String(),
      'is_active': true,
    };
    await threadDoc.set(threadPatch, SetOptions(merge: true));
    await _upsertThreadPatch(
      threadId: normalizedThreadId,
      patch: {
        'requester_user_id': normalizedSenderId,
        'requester_role': sender.role,
        'requester_name': sender.name,
        'requester_photo': sender.photo,
        'requester_parent_client_id': sender.parentClientId,
        'last_message_text': lastPreview,
        'last_message_at': now.toIso8601String(),
        'last_sender_user_id': normalizedSenderId,
        'last_sender_role': sender.role,
        'updated_at': now.toIso8601String(),
        'is_active': true,
      },
    );
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

    if (!currentNetworkStatus()) {
      final thread = await _findThreadById(threadId);
      final queuedMessage = await _cacheQueuedMessage(
        threadId: threadId,
        sender: sender,
        text: trimmedText,
        attachments: attachments,
      );
      await _offlineMediaSyncService.queueSupportMessage(
        threadId: threadId,
        sender: sender,
        text: trimmedText,
        attachments: attachments,
        thread: thread,
        localOrderKey: queuedMessage?.localOrderKey,
        localCreatedAtIso: queuedMessage?.createdAt?.toIso8601String(),
      );
      return true;
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
      final queuedMessage = await _cacheQueuedMessage(
        threadId: threadId,
        sender: sender,
        text: trimmedText,
        attachments: attachments,
      );
      await _offlineMediaSyncService.queueSupportMessage(
        threadId: threadId,
        sender: sender,
        text: trimmedText,
        attachments: attachments,
        thread: await _findThreadById(threadId),
        localOrderKey: queuedMessage?.localOrderKey,
        localCreatedAtIso: queuedMessage?.createdAt?.toIso8601String(),
      );
      return true;
    }
  }

  bool _isQueueableUploadError(String normalizedError) {
    return normalizedError.contains('internet connection') ||
        normalizedError.contains('temporarily unavailable') ||
        normalizedError.contains('request took too long') ||
        normalizedError.contains('failed to fetch') ||
        normalizedError.contains('network error') ||
        normalizedError.contains('network-request-failed') ||
        normalizedError.contains('progressevent');
  }

  static int _compareThreadsNewestFirst(
    SupportThread left,
    SupportThread right,
  ) {
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

  Future<SupportMessage?> _cacheQueuedMessage({
    required String threadId,
    required UserModel sender,
    required String? text,
    required List<QueuedSupportAttachmentInput> attachments,
  }) async {
    final normalizedThreadId = normalizeId(threadId);
    final normalizedSenderId = normalizeId(sender.id);
    if (normalizedThreadId == null || normalizedSenderId == null) {
      return null;
    }
    final now = DateTime.now().toUtc();
    final messageId = 'local_${now.microsecondsSinceEpoch}';
    final localOrderKey = '$messageId|${now.toIso8601String()}';
    final message = SupportMessage(
      id: messageId,
      localOrderKey: localOrderKey,
      threadId: normalizedThreadId,
      senderUserId: normalizedSenderId,
      senderRole: sender.role,
      senderName: sender.name,
      senderPhoto: sender.photo,
      text: text,
      attachments: attachments
          .map(
            (attachment) => SupportAttachment(
              name: attachment.fileName,
              mimeType: attachment.mimeType,
              size: attachment.size ?? attachment.bytes.length,
            ),
          )
          .toList(),
      createdAt: now,
      updatedAt: now,
    );
    await _cache.upsertDocument(
      resourceKey: _messageResourceKey(normalizedThreadId),
      document: message.toMap(),
    );
    _emitMessageCacheUpdate(normalizedThreadId);
    final lastPreview = text?.isNotEmpty == true
        ? text!
        : attachments.length == 1
        ? 'Queued an attachment'
        : 'Queued ${attachments.length} attachments';
    await _upsertThreadPatch(
      threadId: normalizedThreadId,
      patch: {
        'requester_user_id': normalizedSenderId,
        'requester_role': sender.role,
        'requester_name': sender.name,
        'requester_photo': sender.photo,
        'requester_parent_client_id': sender.parentClientId,
        'topic_key': supportTopicGeneral,
        'topic_label': supportTopicLabel(supportTopicGeneral),
        'last_message_text': lastPreview,
        'last_message_at': now.toIso8601String(),
        'last_sender_user_id': normalizedSenderId,
        'last_sender_role': sender.role,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'is_active': true,
      },
    );
    return message;
  }

  Future<SupportThread?> _findThreadById(String threadId) async {
    final normalizedThreadId = normalizeId(threadId);
    if (normalizedThreadId == null) {
      return null;
    }
    final existing = await _cache.readDocuments(_supportThreadsResourceKey);
    if (existing == null) {
      return null;
    }
    for (final document in existing) {
      if (normalizeId(document['id']?.toString()) == normalizedThreadId) {
        return SupportThread.fromMap(document);
      }
    }
    return null;
  }

  Future<SupportThread?> _findCachedThread({
    required String requesterUserId,
    required String topicKey,
    required String? bookingId,
  }) async {
    final existing = await _cache.readDocuments(_supportThreadsResourceKey);
    if (existing == null) {
      return null;
    }
    final threads = existing.map(SupportThread.fromMap).where((thread) {
      return normalizeId(thread.requesterUserId) == requesterUserId &&
          (thread.topicKey ?? '').trim().toLowerCase() == topicKey &&
          normalizeId(thread.bookingId) == bookingId &&
          thread.isActive != false;
    }).toList()..sort(_compareThreadsNewestFirst);
    return threads.firstOrNull;
  }

  Future<SupportThread?> _findCachedDirectThread(String requesterId) async {
    final existing = await _cache.readDocuments(_supportThreadsResourceKey);
    if (existing == null) {
      return null;
    }
    final threads = existing.map(SupportThread.fromMap).where((thread) {
      return normalizeId(thread.requesterUserId) == requesterId &&
          normalizeId(thread.bookingId) == null &&
          (thread.topicKey ?? '').trim().toLowerCase() == supportTopicGeneral &&
          thread.isActive != false;
    }).toList()..sort(_compareThreadsNewestFirst);
    return threads.firstOrNull;
  }

  Future<SupportThread> _createLocalThread({
    required UserModel requester,
    required String topicKey,
    Booking? booking,
  }) async {
    final now = DateTime.now().toUtc();
    final thread = SupportThread(
      id: 'local_thread_${now.microsecondsSinceEpoch}',
      requesterUserId: normalizeId(requester.id),
      requesterRole: requester.role,
      requesterName: requester.name,
      requesterPhoto: requester.photo,
      requesterParentClientId: requester.parentClientId,
      topicKey: topicKey,
      topicLabel: supportTopicLabel(topicKey),
      bookingId: normalizeId(booking?.id),
      bookingLabel: booking == null ? null : _bookingLabel(booking),
      lastMessageText: null,
      lastMessageAt: null,
      lastSenderUserId: null,
      lastSenderRole: null,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
    await _cache.upsertDocument(
      resourceKey: _supportThreadsResourceKey,
      document: thread.toMap(),
    );
    _emitThreadCacheUpdate();
    return thread;
  }

  Future<SupportThread> _createLocalAdminDirectThread({
    required UserModel targetUser,
  }) async {
    final now = DateTime.now().toUtc();
    final thread = SupportThread(
      id: 'local_thread_${now.microsecondsSinceEpoch}',
      requesterUserId: normalizeId(targetUser.id),
      requesterRole: targetUser.role,
      requesterName: targetUser.name,
      requesterPhoto: targetUser.photo,
      requesterParentClientId: targetUser.parentClientId,
      topicKey: supportTopicGeneral,
      topicLabel: supportTopicLabel(supportTopicGeneral),
      bookingId: null,
      bookingLabel: null,
      lastMessageText: null,
      lastMessageAt: null,
      lastSenderUserId: null,
      lastSenderRole: null,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
    await _cache.upsertDocument(
      resourceKey: _supportThreadsResourceKey,
      document: thread.toMap(),
    );
    _emitThreadCacheUpdate();
    return thread;
  }

  Future<void> _mergeThreadsIntoCache(
    List<Map<String, dynamic>> documents,
  ) async {
    final existing = await _cache.readDocuments(_supportThreadsResourceKey);
    if (existing == null || existing.isEmpty) {
      await _cache.writeDocuments(
        resourceKey: _supportThreadsResourceKey,
        documents: documents,
      );
      return;
    }
    final mergedById = {
      for (final document in existing)
        document['id']?.toString() ?? '': Map<String, dynamic>.from(document),
    };
    for (final document in documents) {
      final id = document['id']?.toString() ?? '';
      if (id.isEmpty) {
        continue;
      }
      mergedById[id] = Map<String, dynamic>.from(document);
    }
    await _cache.writeDocuments(
      resourceKey: _supportThreadsResourceKey,
      documents: mergedById.values.toList(),
    );
  }

  String _messageResourceKey(String threadId) => 'support_messages:$threadId';

  Future<void> _upsertThreadPatch({
    required String threadId,
    required Map<String, dynamic> patch,
  }) async {
    final existing = await _cache.readDocuments(_supportThreadsResourceKey);
    Map<String, dynamic>? existingThread;
    if (existing != null) {
      for (final document in existing) {
        if ((document['id']?.toString().trim() ?? '') == threadId) {
          existingThread = Map<String, dynamic>.from(document);
          break;
        }
      }
    }
    await _cache.upsertDocument(
      resourceKey: _supportThreadsResourceKey,
      document: {...?existingThread, 'id': threadId, ...patch},
    );
    _emitThreadCacheUpdate();
  }

  void _emitThreadCacheUpdate() {
    if (!_threadCacheUpdates.isClosed) {
      _threadCacheUpdates.add(null);
    }
  }

  void _emitMessageCacheUpdate(String threadId) {
    if (!_messageCacheUpdates.isClosed) {
      _messageCacheUpdates.add(threadId);
    }
  }

  static int _compareMessagesOldestFirst(
    SupportMessage left,
    SupportMessage right,
  ) {
    final leftDate = _supportMessageSortDate(left);
    final rightDate = _supportMessageSortDate(right);
    if (leftDate == null && rightDate == null) {
      return (left.id ?? '').compareTo(right.id ?? '');
    }
    if (leftDate == null) {
      return -1;
    }
    if (rightDate == null) {
      return 1;
    }
    final byDate = leftDate.compareTo(rightDate);
    if (byDate != 0) {
      return byDate;
    }
    final leftOrderKey = _supportMessageStableOrderKey(left);
    final rightOrderKey = _supportMessageStableOrderKey(right);
    final byOrderKey = leftOrderKey.compareTo(rightOrderKey);
    if (byOrderKey != 0) {
      return byOrderKey;
    }
    return (left.id ?? '').compareTo(right.id ?? '');
  }

  List<Map<String, dynamic>> _mergeVisibleThreadDocuments({
    required List<Map<String, dynamic>> remoteDocuments,
    required List<Map<String, dynamic>> cachedDocuments,
  }) {
    final mergedById = <String, Map<String, dynamic>>{
      for (final document in remoteDocuments)
        document['id']?.toString() ?? '': Map<String, dynamic>.from(document),
    };
    for (final cachedDocument in cachedDocuments) {
      final id = cachedDocument['id']?.toString() ?? '';
      if (id.isEmpty ||
          mergedById.containsKey(id) ||
          !id.startsWith('local_thread_')) {
        continue;
      }
      mergedById[id] = Map<String, dynamic>.from(cachedDocument);
    }
    return mergedById.values.toList();
  }

  List<Map<String, dynamic>> _mergeVisibleMessageDocuments({
    required List<Map<String, dynamic>> remoteDocuments,
    required List<Map<String, dynamic>> cachedDocuments,
  }) {
    final pendingCachedDocuments = cachedDocuments
        .where((document) => SupportMessage.fromMap(document).isPendingUpload)
        .map((document) => Map<String, dynamic>.from(document))
        .toList(growable: false);
    final matchedPendingIds = <String>{};
    final merged = <Map<String, dynamic>>[];
    for (final remoteDocument in remoteDocuments) {
      final mergedRemoteDocument = Map<String, dynamic>.from(remoteDocument);
      final remoteMessage = SupportMessage.fromMap(mergedRemoteDocument);
      final matchingPendingDocument = _findMatchingPendingMessageDocument(
        pendingDocuments: pendingCachedDocuments,
        matchedPendingIds: matchedPendingIds,
        remoteMessage: remoteMessage,
      );
      if (matchingPendingDocument != null) {
        final pendingMessage = SupportMessage.fromMap(matchingPendingDocument);
        final preservedCreatedAt =
            pendingMessage.createdAt ?? pendingMessage.updatedAt;
        final preservedUpdatedAt =
            pendingMessage.updatedAt ?? pendingMessage.createdAt;
        if (preservedCreatedAt != null) {
          mergedRemoteDocument['created_at'] = preservedCreatedAt
              .toIso8601String();
        }
        if (preservedUpdatedAt != null) {
          mergedRemoteDocument['updated_at'] = preservedUpdatedAt
              .toIso8601String();
        }
        mergedRemoteDocument['local_order_key'] =
            pendingMessage.localOrderKey?.trim().isNotEmpty == true
            ? pendingMessage.localOrderKey!.trim()
            : _supportMessageStableOrderKey(pendingMessage);
      }
      merged.add(mergedRemoteDocument);
    }
    final remoteMessages = merged.map(SupportMessage.fromMap).toList();
    for (final cachedDocument in cachedDocuments) {
      final cachedMessage = SupportMessage.fromMap(cachedDocument);
      if (!cachedMessage.isPendingUpload) {
        continue;
      }
      if (matchedPendingIds.contains(cachedMessage.id)) {
        continue;
      }
      final alreadySynced = remoteMessages.any(
        (remoteMessage) => _matchesPendingSupportMessage(
          pendingMessage: cachedMessage,
          remoteMessage: remoteMessage,
        ),
      );
      if (alreadySynced) {
        continue;
      }
      merged.add(Map<String, dynamic>.from(cachedDocument));
    }
    return merged;
  }

  Map<String, dynamic>? _findMatchingPendingMessageDocument({
    required List<Map<String, dynamic>> pendingDocuments,
    required Set<String> matchedPendingIds,
    required SupportMessage remoteMessage,
  }) {
    for (final pendingDocument in pendingDocuments) {
      final pendingMessage = SupportMessage.fromMap(pendingDocument);
      final pendingId = pendingMessage.id;
      if (pendingId == null || matchedPendingIds.contains(pendingId)) {
        continue;
      }
      if (_matchesPendingSupportMessage(
        pendingMessage: pendingMessage,
        remoteMessage: remoteMessage,
      )) {
        matchedPendingIds.add(pendingId);
        return pendingDocument;
      }
    }
    return null;
  }

  bool _matchesPendingSupportMessage({
    required SupportMessage pendingMessage,
    required SupportMessage remoteMessage,
  }) {
    if (remoteMessage.isPendingUpload) {
      return false;
    }
    if (normalizeId(pendingMessage.senderUserId) !=
        normalizeId(remoteMessage.senderUserId)) {
      return false;
    }
    if ((pendingMessage.text ?? '').trim() !=
        (remoteMessage.text ?? '').trim()) {
      return false;
    }
    if (!_supportAttachmentsRoughlyMatch(
      pendingMessage.attachments,
      remoteMessage.attachments,
    )) {
      return false;
    }
    final pendingCreatedAt =
        pendingMessage.createdAt ?? pendingMessage.updatedAt;
    final remoteCreatedAt = remoteMessage.createdAt ?? remoteMessage.updatedAt;
    if (pendingCreatedAt == null || remoteCreatedAt == null) {
      return true;
    }
    final difference = remoteCreatedAt.difference(pendingCreatedAt).inMinutes;
    return difference >= 0 && difference <= 15;
  }

  bool _supportAttachmentsRoughlyMatch(
    List<SupportAttachment> pendingAttachments,
    List<SupportAttachment> remoteAttachments,
  ) {
    if (pendingAttachments.length != remoteAttachments.length) {
      return false;
    }
    for (var index = 0; index < pendingAttachments.length; index++) {
      final pendingAttachment = pendingAttachments[index];
      final remoteAttachment = remoteAttachments[index];
      if ((pendingAttachment.name ?? '').trim() !=
          (remoteAttachment.name ?? '').trim()) {
        return false;
      }
      if ((pendingAttachment.mimeType ?? '').trim() !=
          (remoteAttachment.mimeType ?? '').trim()) {
        return false;
      }
    }
    return true;
  }

  static DateTime? _supportMessageSortDate(SupportMessage message) {
    return message.createdAt ?? message.updatedAt;
  }

  static String _supportMessageStableOrderKey(SupportMessage message) {
    final explicitOrderKey = message.localOrderKey?.trim();
    if (explicitOrderKey != null && explicitOrderKey.isNotEmpty) {
      return explicitOrderKey;
    }
    final createdAt = message.createdAt?.toIso8601String();
    if (createdAt != null && createdAt.isNotEmpty) {
      return '$createdAt|${message.id ?? ''}';
    }
    final updatedAt = message.updatedAt?.toIso8601String();
    if (updatedAt != null && updatedAt.isNotEmpty) {
      return '$updatedAt|${message.id ?? ''}';
    }
    return message.id ?? '';
  }

  List<Map<String, dynamic>> _mergeQueuedPendingMessageDocuments({
    required List<Map<String, dynamic>> existingDocuments,
    required List<Map<String, dynamic>> queuedDocuments,
  }) {
    final merged = existingDocuments
        .map((document) => Map<String, dynamic>.from(document))
        .toList(growable: true);
    final visibleMessages = merged.map(SupportMessage.fromMap).toList();
    for (final queuedDocument in queuedDocuments) {
      final queuedMessage = SupportMessage.fromMap(queuedDocument);
      final alreadyVisible = visibleMessages.any(
        (message) =>
            _matchesPendingSupportMessage(
              pendingMessage: queuedMessage,
              remoteMessage: message,
            ) ||
            _matchesPendingSupportMessage(
              pendingMessage: message,
              remoteMessage: queuedMessage,
            ),
      );
      if (alreadyVisible) {
        continue;
      }
      merged.add(Map<String, dynamic>.from(queuedDocument));
      visibleMessages.add(queuedMessage);
    }
    return merged;
  }

  bool _sameMessageDocumentSet(
    List<Map<String, dynamic>> left,
    List<Map<String, dynamic>> right,
  ) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    final leftSignatures = left
        .map((document) => _supportMessageSignatureForMap(document))
        .toList(growable: false);
    final rightSignatures = right
        .map((document) => _supportMessageSignatureForMap(document))
        .toList(growable: false);
    for (var index = 0; index < leftSignatures.length; index++) {
      if (leftSignatures[index] != rightSignatures[index]) {
        return false;
      }
    }
    return true;
  }

  String _supportMessageSignatureForMap(Map<String, dynamic> document) {
    final message = SupportMessage.fromMap(document);
    return [
      message.id?.trim() ?? '',
      message.threadId?.trim() ?? '',
      message.senderUserId?.trim() ?? '',
      message.createdAt?.toIso8601String() ?? '',
      message.updatedAt?.toIso8601String() ?? '',
      message.localOrderKey?.trim() ?? '',
      message.text?.trim() ?? '',
      '${message.attachments.length}',
    ].join('|');
  }
}
