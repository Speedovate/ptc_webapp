import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/support_message.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/services/firestore_public_document_fetcher.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/support_storage_service.dart';
import 'package:webapp/utils/functions.dart';

class SupportRequest {
  SupportRequest({
    FirebaseFirestore? firestore,
    SupportStorageService? storage,
    FirestorePublicDocumentFetcher? firestorePublicDocumentFetcher,
  }) : _providedFirestore = firestore,
       _storage = storage ?? SupportStorageService.instance,
       _firestorePublicDocumentFetcher =
           firestorePublicDocumentFetcher ??
           createFirestorePublicDocumentFetcher();

  static final SupportRequest instance = SupportRequest();
  static const _supportThreadsResourceKey = 'support_threads_all';
  static const Duration _startupTimeout = Duration(seconds: 6);
  static const Duration _queuedSupportReadTimeout = Duration(seconds: 1);
  static bool _hasResolvedAllThreads = false;
  static List<SupportThread> _hydratedAllThreadsSnapshot =
      const <SupportThread>[];

  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final SupportStorageService _storage;
  final FirestorePublicDocumentFetcher _firestorePublicDocumentFetcher;
  final OfflineMediaSyncService _offlineMediaSyncService =
      OfflineMediaSyncService.instance;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );
  final Map<String, Map<String, dynamic>> _volatileThreadDocumentsById =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, Map<String, dynamic>>>
  _volatileMessageDocumentsByThreadId =
      <String, Map<String, Map<String, dynamic>>>{};
  final Map<String, StreamController<List<SupportMessage>>>
  _messageWatchControllersByThreadId =
      <String, StreamController<List<SupportMessage>>>{};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _messageRemoteSubscriptionsByThreadId =
      <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  final Map<String, StreamSubscription<String>>
  _messageLocalSubscriptionsByThreadId = <String, StreamSubscription<String>>{};
  final Map<String, List<SupportMessage>> _lastVisibleMessagesByThreadId =
      <String, List<SupportMessage>>{};
  final Set<String> _messagePrefetchInFlightThreadIds = <String>{};
  final Set<String> _messageWarmThreadIds = <String>{};
  final StreamController<void> _threadCacheUpdates =
      StreamController<void>.broadcast();
  final StreamController<String> _threadReadMarkerUpdates =
      StreamController<String>.broadcast();
  final StreamController<String> _messageCacheUpdates =
      StreamController<String>.broadcast();

  CollectionReference<Map<String, dynamic>> get _supportCollection =>
      _firestore.collection('support');

  static bool get hasResolvedAllThreads => _hasResolvedAllThreads;
  static List<SupportThread> get hydratedAllThreadsSnapshot =>
      List<SupportThread>.unmodifiable(_hydratedAllThreadsSnapshot);

  static void _storeHydratedAllThreads(List<SupportThread> threads) {
    _hasResolvedAllThreads = true;
    _hydratedAllThreadsSnapshot = List<SupportThread>.from(threads);
  }

  CollectionReference<Map<String, dynamic>> _threadReadCollection(
    String userId,
  ) =>
      _firestore.collection('manage_support').doc(userId).collection('threads');

  Future<List<SupportThread>> prefetchAllThreads() async {
    final cachedDocuments = await _cache.readDocuments(
      _supportThreadsResourceKey,
    );
    if (cachedDocuments != null) {
      final cachedThreads = cachedDocuments.map(SupportThread.fromMap).toList()
        ..sort(_compareThreadsNewestFirst);
      _storeHydratedAllThreads(cachedThreads);
      unawaited(_warmThreadMessagesInBackground(cachedThreads));
      return cachedThreads;
    }
    List<Map<String, dynamic>> documents;
    try {
      final snapshot = await _supportCollection.get().timeout(
        _startupTimeout,
        onTimeout: () =>
            throw TimeoutException('support threads fetch timeout'),
      );
      documents = snapshot.docs.map(documentData).toList(growable: false);
    } catch (error) {
      documents = await _fetchCollectionDocumentsViaPublicRest('support');
      if (documents.isEmpty) {
        rethrow;
      }
    }
    await _cache.writeDocuments(
      resourceKey: _supportThreadsResourceKey,
      documents: documents,
    );
    final threads = documents.map(SupportThread.fromMap).toList();
    threads.sort(_compareThreadsNewestFirst);
    _storeHydratedAllThreads(threads);
    return threads;
  }

  Future<List<SupportThread>> prefetchThreadsForUser(String userId) async {
    final normalizedUserId = normalizeId(userId);
    if (normalizedUserId == null) {
      return const <SupportThread>[];
    }
    final cachedDocuments = await _cache.readDocuments(
      _supportThreadsResourceKey,
    );
    if (cachedDocuments != null) {
      final cachedThreads =
          cachedDocuments
              .map(SupportThread.fromMap)
              .where(
                (thread) =>
                    normalizeId(thread.requesterUserId) == normalizedUserId,
              )
              .toList()
            ..sort(_compareThreadsNewestFirst);
      final allCachedThreads =
          cachedDocuments.map(SupportThread.fromMap).toList()
            ..sort(_compareThreadsNewestFirst);
      _storeHydratedAllThreads(allCachedThreads);
      unawaited(_warmThreadMessagesInBackground(cachedThreads));
      return cachedThreads;
    }
    List<Map<String, dynamic>> documents;
    try {
      final snapshot = await _supportCollection
          .where('requester_user_id', isEqualTo: normalizedUserId)
          .get()
          .timeout(
            _startupTimeout,
            onTimeout: () =>
                throw TimeoutException('support user threads fetch timeout'),
          );
      documents = snapshot.docs.map(documentData).toList(growable: false);
    } catch (error) {
      final allDocuments = await _fetchCollectionDocumentsViaPublicRest(
        'support',
      );
      documents = allDocuments
          .where((document) {
            return normalizeId(document['requester_user_id']?.toString()) ==
                normalizedUserId;
          })
          .map((document) => Map<String, dynamic>.from(document))
          .toList(growable: false);
      if (documents.isEmpty) {
        rethrow;
      }
    }
    await _mergeThreadsIntoCache(documents);
    final threads = documents.map(SupportThread.fromMap).toList();
    threads.sort(_compareThreadsNewestFirst);
    final cachedAllThreads = _hydratedAllThreadsSnapshot;
    if (cachedAllThreads.isEmpty) {
      _storeHydratedAllThreads(threads);
    } else {
      final mergedById = <String, SupportThread>{};
      for (final thread in cachedAllThreads) {
        final threadId = normalizeId(thread.id);
        if (threadId == null) {
          continue;
        }
        mergedById[threadId] = thread;
      }
      for (final thread in threads) {
        final threadId = normalizeId(thread.id);
        if (threadId == null) {
          continue;
        }
        mergedById[threadId] = thread;
      }
      final mergedThreads = mergedById.values.toList()
        ..sort(_compareThreadsNewestFirst);
      _storeHydratedAllThreads(mergedThreads);
    }
    return threads;
  }

  Future<List<SupportMessage>> prefetchMessages(String threadId) async {
    final normalizedThreadId = normalizeId(threadId);
    if (normalizedThreadId == null) {
      return const <SupportMessage>[];
    }
    final cachedDocuments = await _cache.readDocuments(
      _messageResourceKey(normalizedThreadId),
    );
    if (cachedDocuments != null) {
      return _storeVisibleMessages(normalizedThreadId, cachedDocuments);
    }
    List<Map<String, dynamic>> documents;
    try {
      final snapshot = await _supportCollection
          .doc(normalizedThreadId)
          .collection('messages')
          .get()
          .timeout(
            _startupTimeout,
            onTimeout: () =>
                throw TimeoutException('support messages fetch timeout'),
          );
      documents = snapshot.docs.map(documentData).toList(growable: false);
    } catch (error) {
      documents = await _fetchCollectionDocumentsViaPublicRest(
        'support/$normalizedThreadId/messages',
      );
      if (documents.isEmpty) {
        rethrow;
      }
    }
    await _cache.writeDocuments(
      resourceKey: _messageResourceKey(normalizedThreadId),
      documents: documents,
    );
    return _storeVisibleMessages(normalizedThreadId, documents);
  }

  Future<void> prefetchMessagesForThreads(List<SupportThread> threads) async {
    final futures = <Future<void>>[];
    for (final thread in threads) {
      final threadId = normalizeId(thread.id);
      if (threadId == null) {
        continue;
      }
      futures.add(prefetchMessages(threadId).then((_) {}));
    }
    await Future.wait(futures);
  }

  Future<Map<String, String>> readThreadReadMarkers(String userId) async {
    final normalizedUserId = normalizeId(userId);
    if (normalizedUserId == null) {
      return const <String, String>{};
    }
    final localDocuments =
        await FirestoreCacheStore.instance.readDocumentMaps(
          _threadReadMarkersResourceKey(normalizedUserId),
        ) ??
        const <Map<String, dynamic>>[];
    final mergedDocuments = <String, Map<String, dynamic>>{};
    for (final document in localDocuments) {
      final threadId =
          normalizeId(document['thread_id']) ?? normalizeId(document['id']);
      if (threadId == null) {
        continue;
      }
      mergedDocuments[threadId] = Map<String, dynamic>.from(document);
    }
    if (currentNetworkStatus()) {
      try {
        final snapshot = await _threadReadCollection(normalizedUserId)
            .get()
            .timeout(
              _startupTimeout,
              onTimeout: () =>
                  throw TimeoutException('support thread reads fetch timeout'),
            );
        for (final document in snapshot.docs) {
          final data = documentData(document);
          final threadId =
              normalizeId(data['thread_id']) ?? normalizeId(data['id']);
          if (threadId == null) {
            continue;
          }
          final existing = mergedDocuments[threadId];
          if (existing == null ||
              _documentUpdatedAt(data).isAfter(_documentUpdatedAt(existing))) {
            mergedDocuments[threadId] = data;
          }
        }
        await FirestoreCacheStore.instance.writeDocumentMaps(
          _threadReadMarkersResourceKey(normalizedUserId),
          mergedDocuments.values.toList(growable: false),
        );
      } on FirebaseException {
        final remoteDocuments = await _readThreadReadMarkersViaPublicRest(
          normalizedUserId,
        );
        for (final data in remoteDocuments) {
          final threadId =
              normalizeId(data['thread_id']) ?? normalizeId(data['id']);
          if (threadId == null) {
            continue;
          }
          final existing = mergedDocuments[threadId];
          if (existing == null ||
              _documentUpdatedAt(data).isAfter(_documentUpdatedAt(existing))) {
            mergedDocuments[threadId] = data;
          }
        }
        await FirestoreCacheStore.instance.writeDocumentMaps(
          _threadReadMarkersResourceKey(normalizedUserId),
          mergedDocuments.values.toList(growable: false),
        );
      } on TimeoutException {
        final remoteDocuments = await _readThreadReadMarkersViaPublicRest(
          normalizedUserId,
        );
        for (final data in remoteDocuments) {
          final threadId =
              normalizeId(data['thread_id']) ?? normalizeId(data['id']);
          if (threadId == null) {
            continue;
          }
          final existing = mergedDocuments[threadId];
          if (existing == null ||
              _documentUpdatedAt(data).isAfter(_documentUpdatedAt(existing))) {
            mergedDocuments[threadId] = data;
          }
        }
        await FirestoreCacheStore.instance.writeDocumentMaps(
          _threadReadMarkersResourceKey(normalizedUserId),
          mergedDocuments.values.toList(growable: false),
        );
      } catch (_) {
        // Keep support UI responsive offline or under weak signal.
      }
    }
    final markers = <String, String>{};
    for (final document in mergedDocuments.values) {
      final threadId =
          normalizeId(document['thread_id']) ?? normalizeId(document['id']);
      final marker = document['marker']?.toString().trim() ?? '';
      if (threadId == null || marker.isEmpty) {
        continue;
      }
      markers[threadId] = marker;
    }
    return markers;
  }

  Future<void> markThreadRead({
    required String userId,
    required String threadId,
    required String marker,
  }) async {
    final normalizedUserId = normalizeId(userId);
    final normalizedThreadId = normalizeId(threadId);
    final normalizedMarker = marker.trim();
    if (normalizedUserId == null ||
        normalizedThreadId == null ||
        normalizedMarker.isEmpty) {
      return;
    }
    final resourceKey = _threadReadMarkersResourceKey(normalizedUserId);
    final existing =
        await FirestoreCacheStore.instance.readDocumentMaps(resourceKey) ??
        const <Map<String, dynamic>>[];
    final next = existing
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: true);
    final nextDocument = <String, dynamic>{
      'id': normalizedThreadId,
      'thread_id': normalizedThreadId,
      'marker': normalizedMarker,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final existingIndex = next.indexWhere(
      (item) => normalizeId(item['thread_id']) == normalizedThreadId,
    );
    if (existingIndex >= 0) {
      next[existingIndex] = nextDocument;
    } else {
      next.add(nextDocument);
    }
    await FirestoreCacheStore.instance.writeDocumentMaps(resourceKey, next);
    if (!_threadReadMarkerUpdates.isClosed) {
      _threadReadMarkerUpdates.add(normalizedUserId);
    }
    final remoteWrite = _threadReadCollection(
      normalizedUserId,
    ).doc(normalizedThreadId).set(nextDocument, SetOptions(merge: true));
    if (currentNetworkStatus()) {
      try {
        await remoteWrite.timeout(const Duration(seconds: 6));
      } on TimeoutException {
        unawaited(remoteWrite);
      } on FirebaseException {
        unawaited(remoteWrite);
      }
    } else {
      unawaited(remoteWrite);
    }
  }

  Stream<void> watchThreadReadMarkerUpdates(String userId) {
    final normalizedUserId = normalizeId(userId);
    if (normalizedUserId == null) {
      return const Stream<void>.empty();
    }
    return _threadReadMarkerUpdates.stream
        .where((updatedUserId) => updatedUserId == normalizedUserId)
        .map((_) {});
  }

  List<SupportMessage>? peekLastVisibleMessages(String threadId) {
    final normalizedThreadId = normalizeId(threadId);
    if (normalizedThreadId == null) {
      return null;
    }
    final messages = _lastVisibleMessagesByThreadId[normalizedThreadId];
    if (messages == null) {
      return null;
    }
    return List<SupportMessage>.from(messages);
  }

  Stream<List<SupportThread>> watchAllThreads() {
    return Stream<List<SupportThread>>.multi((controller) {
      Future<void> emitCachedThreads() async {
        final cached = await _readVisibleThreadDocuments();
        if (controller.isClosed) {
          return;
        }
        if (cached.isEmpty) {
          controller.add(const <SupportThread>[]);
          return;
        }
        final cachedThreads = cached.map(SupportThread.fromMap).toList()
          ..sort(_compareThreadsNewestFirst);
        _storeHydratedAllThreads(cachedThreads);
        controller.add(cachedThreads);
        unawaited(_warmThreadMessagesInBackground(cachedThreads));
      }

      unawaited(emitCachedThreads());

      final remoteSubscription = _supportCollection.snapshots().listen((
        snapshot,
      ) async {
        final documents = snapshot.docs.map(documentData).toList();
        // A server snapshot confirms an optimistic draft thread. It no longer
        // needs to be kept in the local overlay after this point.
        for (final document in documents) {
          final threadId = normalizeId(document['id']);
          if (threadId != null) {
            _volatileThreadDocumentsById.remove(threadId);
          }
        }
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
        _storeHydratedAllThreads(threads);
        unawaited(_warmThreadMessagesInBackground(threads));
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
        final cached = await _readVisibleThreadDocuments();
        if (controller.isClosed) {
          return;
        }
        if (cached.isEmpty) {
          controller.add(const <SupportThread>[]);
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
        final allCachedThreads = cached.map(SupportThread.fromMap).toList()
          ..sort(_compareThreadsNewestFirst);
        _storeHydratedAllThreads(allCachedThreads);
        controller.add(cachedThreads);
        unawaited(_warmThreadMessagesInBackground(cachedThreads));
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
            final cachedAllThreads = _hydratedAllThreadsSnapshot;
            if (cachedAllThreads.isEmpty) {
              _storeHydratedAllThreads(threads);
            } else {
              final mergedById = <String, SupportThread>{};
              for (final thread in cachedAllThreads) {
                final threadId = normalizeId(thread.id);
                if (threadId == null) {
                  continue;
                }
                mergedById[threadId] = thread;
              }
              for (final thread in threads) {
                final threadId = normalizeId(thread.id);
                if (threadId == null) {
                  continue;
                }
                mergedById[threadId] = thread;
              }
              final mergedAllThreads = mergedById.values.toList()
                ..sort(_compareThreadsNewestFirst);
              _storeHydratedAllThreads(mergedAllThreads);
            }
            unawaited(_warmThreadMessagesInBackground(threads));
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
    final existingController =
        _messageWatchControllersByThreadId[normalizedThreadId];
    if (existingController != null && !existingController.isClosed) {
      return existingController.stream;
    }

    late final StreamController<List<SupportMessage>> controller;
    controller = StreamController<List<SupportMessage>>.broadcast(
      onListen: () {
        final lastMessages = _lastVisibleMessagesByThreadId[normalizedThreadId];
        if (lastMessages != null && !controller.isClosed) {
          controller.add(List<SupportMessage>.from(lastMessages));
        }
      },
      onCancel: () async {
        if (controller.hasListener) {
          return;
        }
        // Keep the shared listener and its in-memory snapshot alive so
        // reopening a visited chat is cache-first and listener-driven.
      },
    );
    _messageWatchControllersByThreadId[normalizedThreadId] = controller;

    Future<void> emitCachedMessages() async {
      final cached = await _readVisibleMessageDocuments(normalizedThreadId);
      final queuedDocuments = await _readQueuedSupportMessageDocumentsSafe(
        normalizedThreadId,
      );
      final visibleDocuments = _mergeQueuedPendingMessageDocuments(
        existingDocuments: cached,
        queuedDocuments: queuedDocuments,
      );
      if (controller.isClosed) {
        return;
      }
      if (visibleDocuments.isEmpty && cached.isEmpty) {
        _lastVisibleMessagesByThreadId[normalizedThreadId] =
            const <SupportMessage>[];
        controller.add(const <SupportMessage>[]);
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
      _lastVisibleMessagesByThreadId[normalizedThreadId] =
          List<SupportMessage>.from(messages);
      controller.add(messages);
    }

    unawaited(emitCachedMessages());

    final remoteSubscription = _supportCollection
        .doc(normalizedThreadId)
        .collection('messages')
        .snapshots()
        .listen((snapshot) async {
          final documents = snapshot.docs.map(documentData).toList();
          final cachedDocuments = await _readVisibleMessageDocuments(
            normalizedThreadId,
          );
          final mergedDocuments = _mergeVisibleMessageDocuments(
            remoteDocuments: documents,
            cachedDocuments: cachedDocuments,
          );
          final queuedDocuments = await _readQueuedSupportMessageDocumentsSafe(
            normalizedThreadId,
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
          final messages = visibleDocuments.map(SupportMessage.fromMap).toList()
            ..sort(_compareMessagesOldestFirst);
          _lastVisibleMessagesByThreadId[normalizedThreadId] =
              List<SupportMessage>.from(messages);
          controller.add(messages);
        }, onError: controller.addError);
    _messageRemoteSubscriptionsByThreadId[normalizedThreadId] =
        remoteSubscription;

    final localSubscription = _messageCacheUpdates.stream.listen((threadId) {
      if (normalizeId(threadId) != normalizedThreadId) {
        return;
      }
      unawaited(emitCachedMessages());
    }, onError: controller.addError);
    _messageLocalSubscriptionsByThreadId[normalizedThreadId] =
        localSubscription;

    return controller.stream;
  }

  Future<void> _warmThreadMessagesInBackground(
    List<SupportThread> threads,
  ) async {
    if (!currentNetworkStatus()) {
      return;
    }
    final futures = <Future<void>>[];
    for (final thread in threads) {
      if (!thread.hasConversation) {
        continue;
      }
      final threadId = normalizeId(thread.id);
      if (threadId == null ||
          _messageWarmThreadIds.contains(threadId) ||
          _messagePrefetchInFlightThreadIds.contains(threadId)) {
        continue;
      }
      final hasVisibleMessages =
          (_lastVisibleMessagesByThreadId[threadId]?.isNotEmpty ?? false);
      if (hasVisibleMessages) {
        _messageWarmThreadIds.add(threadId);
        continue;
      }
      final persistedDocuments = await _cache.readDocuments(
        _messageResourceKey(threadId),
      );
      if (persistedDocuments != null) {
        _storeVisibleMessages(threadId, persistedDocuments);
        _messageWarmThreadIds.add(threadId);
        continue;
      }
      _messagePrefetchInFlightThreadIds.add(threadId);
      futures.add(
        prefetchMessages(threadId)
            .then((_) {
              _messageWarmThreadIds.add(threadId);
              _emitMessageCacheUpdate(threadId);
            })
            .catchError((_) {})
            .whenComplete(() {
              _messagePrefetchInFlightThreadIds.remove(threadId);
            }),
      );
    }
    if (futures.isEmpty) {
      return;
    }
    await Future.wait(futures);
  }

  List<SupportMessage> _storeVisibleMessages(
    String threadId,
    List<Map<String, dynamic>> documents,
  ) {
    final messages = documents.map(SupportMessage.fromMap).toList()
      ..sort(_compareMessagesOldestFirst);
    _lastVisibleMessagesByThreadId[threadId] = List<SupportMessage>.from(
      messages,
    );
    _messageWarmThreadIds.add(threadId);
    return messages;
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
    return _createLocalThread(
      requester: requester,
      topicKey: normalizedTopicKey,
      booking: booking,
      preferredThreadId: _supportCollection.doc().id,
    );
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
    return _createLocalAdminDirectThread(
      targetUser: targetUser,
      preferredThreadId: _supportCollection.doc().id,
    );
  }

  Future<SupportThread> createLocalAdminDirectThreadForSend({
    required UserModel targetUser,
  }) {
    return _createLocalAdminDirectThread(
      targetUser: targetUser,
      preferredThreadId: _supportCollection.doc().id,
    );
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
        .get()
        .timeout(
          _startupTimeout,
          onTimeout: () =>
              throw TimeoutException('support direct thread lookup timeout'),
        );
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
    String? pendingMessageId,
    String? pendingLocalOrderKey,
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
    final existingThread = await _findThreadById(normalizedThreadId);
    final message = SupportMessage(
      id: messageDoc.id,
      localOrderKey: pendingLocalOrderKey,
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
    await _replaceCachedMessageDocument(
      threadId: normalizedThreadId,
      pendingMessageId: pendingMessageId,
      document: messageMap,
    );
    _emitMessageCacheUpdate(normalizedThreadId);

    final lastPreview = trimmedText?.isNotEmpty == true
        ? trimmedText!
        : attachments.length == 1
        ? 'Sent an attachment'
        : 'Sent ${attachments.length} attachments';
    final threadPatch = {
      'requester_user_id':
          normalizeId(existingThread?.requesterUserId) ?? normalizedSenderId,
      'requester_role': existingThread?.requesterRole ?? sender.role,
      'requester_name': existingThread?.requesterName ?? sender.name,
      'requester_photo': existingThread?.requesterPhoto ?? sender.photo,
      'requester_parent_client_id': existingThread?.requesterParentClientId,
      'topic_key': existingThread?.topicKey ?? supportTopicGeneral,
      'topic_label':
          existingThread?.topicLabel ??
          supportTopicLabel(existingThread?.topicKey ?? supportTopicGeneral),
      'booking_id': normalizeId(existingThread?.bookingId),
      'booking_label': existingThread?.bookingLabel,
      'last_message_text': lastPreview,
      'last_message_at': now.toIso8601String(),
      'last_sender_user_id': normalizedSenderId,
      'last_sender_role': sender.role,
      'created_at':
          existingThread?.createdAt?.toIso8601String() ?? now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'is_active': true,
    };
    await threadDoc.set(threadPatch, SetOptions(merge: true));
    await _upsertThreadPatch(
      threadId: normalizedThreadId,
      patch: {
        'requester_user_id':
            normalizeId(existingThread?.requesterUserId) ?? normalizedSenderId,
        'requester_role': existingThread?.requesterRole ?? sender.role,
        'requester_name': existingThread?.requesterName ?? sender.name,
        'requester_photo': existingThread?.requesterPhoto ?? sender.photo,
        'requester_parent_client_id':
            existingThread?.requesterParentClientId ?? sender.parentClientId,
        'topic_key': existingThread?.topicKey ?? supportTopicGeneral,
        'topic_label':
            existingThread?.topicLabel ??
            supportTopicLabel(existingThread?.topicKey ?? supportTopicGeneral),
        'booking_id': normalizeId(existingThread?.bookingId),
        'booking_label': existingThread?.bookingLabel,
        'created_at':
            existingThread?.createdAt?.toIso8601String() ??
            now.toIso8601String(),
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
    final localQueuedMessage = await _cacheQueuedMessage(
      threadId: threadId,
      sender: sender,
      text: trimmedText,
      attachments: attachments,
    );

    if (!currentNetworkStatus()) {
      final thread = await _findThreadById(threadId);
      await _offlineMediaSyncService.queueSupportMessage(
        threadId: threadId,
        sender: sender,
        text: trimmedText,
        attachments: attachments,
        thread: thread,
        localOrderKey: localQueuedMessage?.localOrderKey,
        localCreatedAtIso: localQueuedMessage?.createdAt?.toIso8601String(),
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
        pendingMessageId: localQueuedMessage?.id,
        pendingLocalOrderKey: localQueuedMessage?.localOrderKey,
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
        thread: await _findThreadById(threadId),
        localOrderKey: localQueuedMessage?.localOrderKey,
        localCreatedAtIso: localQueuedMessage?.createdAt?.toIso8601String(),
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
    final existingThread = await _findThreadById(normalizedThreadId);
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
    _storeVolatileMessageDocument(normalizedThreadId, message.toMap());
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
        'requester_user_id':
            normalizeId(existingThread?.requesterUserId) ?? normalizedSenderId,
        'requester_role': existingThread?.requesterRole ?? sender.role,
        'requester_name': existingThread?.requesterName ?? sender.name,
        'requester_photo': existingThread?.requesterPhoto ?? sender.photo,
        'requester_parent_client_id':
            existingThread?.requesterParentClientId ?? sender.parentClientId,
        'topic_key': existingThread?.topicKey ?? supportTopicGeneral,
        'topic_label':
            existingThread?.topicLabel ??
            supportTopicLabel(existingThread?.topicKey ?? supportTopicGeneral),
        'booking_id': normalizeId(existingThread?.bookingId),
        'booking_label': existingThread?.bookingLabel,
        'last_message_text': lastPreview,
        'last_message_at': now.toIso8601String(),
        'last_sender_user_id': normalizedSenderId,
        'last_sender_role': sender.role,
        'created_at':
            existingThread?.createdAt?.toIso8601String() ??
            now.toIso8601String(),
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
    final existing = await _readVisibleThreadDocuments();
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
    final existing = await _readVisibleThreadDocuments();
    if (existing.isEmpty) {
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
    final existing = await _readVisibleThreadDocuments();
    if (existing.isEmpty) {
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
    String? preferredThreadId,
  }) async {
    final now = DateTime.now().toUtc();
    final thread = SupportThread(
      id: preferredThreadId?.trim().isNotEmpty == true
          ? preferredThreadId!.trim()
          : 'local_thread_${now.microsecondsSinceEpoch}',
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
    _storeVolatileThreadDocument(thread.toMap());
    unawaited(
      _cache.upsertDocument(
        resourceKey: _supportThreadsResourceKey,
        document: thread.toMap(),
      ),
    );
    _emitThreadCacheUpdate();
    return thread;
  }

  Future<SupportThread> _createLocalAdminDirectThread({
    required UserModel targetUser,
    String? preferredThreadId,
  }) async {
    final now = DateTime.now().toUtc();
    final thread = SupportThread(
      id: preferredThreadId?.trim().isNotEmpty == true
          ? preferredThreadId!.trim()
          : 'local_thread_${now.microsecondsSinceEpoch}',
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
    _storeVolatileThreadDocument(thread.toMap());
    unawaited(
      _cache.upsertDocument(
        resourceKey: _supportThreadsResourceKey,
        document: thread.toMap(),
      ),
    );
    _emitThreadCacheUpdate();
    return thread;
  }

  Future<List<Map<String, dynamic>>> _readVisibleThreadDocuments() async {
    final cached =
        await _cache.readDocuments(_supportThreadsResourceKey) ??
        const <Map<String, dynamic>>[];
    if (_volatileThreadDocumentsById.isEmpty) {
      return cached
          .map((document) => Map<String, dynamic>.from(document))
          .toList(growable: false);
    }
    final mergedById = <String, Map<String, dynamic>>{
      for (final document in cached)
        document['id']?.toString() ?? '': Map<String, dynamic>.from(document),
    };
    for (final entry in _volatileThreadDocumentsById.entries) {
      mergedById[entry.key] = Map<String, dynamic>.from(entry.value);
    }
    return mergedById.values.toList(growable: false);
  }

  void _storeVolatileThreadDocument(Map<String, dynamic> document) {
    final id = document['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      return;
    }
    _volatileThreadDocumentsById[id] = Map<String, dynamic>.from(document);
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

  String threadReadMarkerForThread(SupportThread thread) {
    final timestamp =
        thread.lastMessageAt?.toUtc().toIso8601String() ??
        thread.updatedAt?.toUtc().toIso8601String() ??
        '';
    final senderId = normalizeId(thread.lastSenderUserId) ?? '';
    final text = _supportMarkerToken(thread.lastMessageText);
    return '$timestamp|$senderId|$text';
  }

  String threadReadMarkerForMessage(SupportMessage message) {
    final timestamp =
        message.createdAt?.toUtc().toIso8601String() ??
        message.updatedAt?.toUtc().toIso8601String() ??
        '';
    final senderId = normalizeId(message.senderUserId) ?? '';
    final text = _supportMarkerToken(
      _supportThreadPreviewTokenForMessage(message),
    );
    return '$timestamp|$senderId|$text';
  }

  String _threadReadMarkersResourceKey(String userId) =>
      'manage_support:$userId';

  String _supportMarkerToken(String? value) {
    final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (normalized.isEmpty) {
      return '';
    }
    return normalized.length <= 120 ? normalized : normalized.substring(0, 120);
  }

  String _supportThreadPreviewTokenForMessage(SupportMessage message) {
    final trimmedText = message.text?.trim() ?? '';
    if (trimmedText.isNotEmpty) {
      return trimmedText;
    }
    final attachmentCount = message.attachments.length;
    if (attachmentCount <= 0) {
      return '';
    }
    if (attachmentCount == 1) {
      return 'Sent an attachment';
    }
    return 'Sent $attachmentCount attachments';
  }

  DateTime _documentUpdatedAt(Map<String, dynamic> document) {
    final value = document['updated_at'];
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Future<void> _replaceCachedMessageDocument({
    required String threadId,
    required String? pendingMessageId,
    required Map<String, dynamic> document,
  }) async {
    final resourceKey = _messageResourceKey(threadId);
    final existing = await _readVisibleMessageDocuments(threadId);
    final nextDocuments = <Map<String, dynamic>>[];
    for (final item in existing) {
      final itemId = item['id']?.toString().trim() ?? '';
      if (pendingMessageId != null && itemId == pendingMessageId) {
        continue;
      }
      if ((document['id']?.toString().trim() ?? '') == itemId) {
        continue;
      }
      nextDocuments.add(Map<String, dynamic>.from(item));
    }
    nextDocuments.add(Map<String, dynamic>.from(document));
    _replaceVolatileMessageDocuments(
      threadId: threadId,
      pendingMessageId: pendingMessageId,
      documents: nextDocuments,
    );
    await _cache.writeDocuments(
      resourceKey: resourceKey,
      documents: nextDocuments,
    );
  }

  Future<List<Map<String, dynamic>>> _readVisibleMessageDocuments(
    String threadId,
  ) async {
    final cached =
        await _cache.readDocuments(_messageResourceKey(threadId)) ??
        const <Map<String, dynamic>>[];
    final volatileDocumentsById = _volatileMessageDocumentsByThreadId[threadId];
    if (volatileDocumentsById == null || volatileDocumentsById.isEmpty) {
      return cached
          .map((document) => Map<String, dynamic>.from(document))
          .toList(growable: false);
    }
    final mergedById = <String, Map<String, dynamic>>{
      for (final document in cached)
        document['id']?.toString() ?? '': Map<String, dynamic>.from(document),
    };
    for (final entry in volatileDocumentsById.entries) {
      mergedById[entry.key] = Map<String, dynamic>.from(entry.value);
    }
    return mergedById.values.toList(growable: false);
  }

  void _storeVolatileMessageDocument(
    String threadId,
    Map<String, dynamic> document,
  ) {
    final documentId = document['id']?.toString().trim() ?? '';
    if (documentId.isEmpty) {
      return;
    }
    final documentsById = _volatileMessageDocumentsByThreadId.putIfAbsent(
      threadId,
      () => <String, Map<String, dynamic>>{},
    );
    documentsById[documentId] = Map<String, dynamic>.from(document);
  }

  void _replaceVolatileMessageDocuments({
    required String threadId,
    required String? pendingMessageId,
    required List<Map<String, dynamic>> documents,
  }) {
    final nextById = <String, Map<String, dynamic>>{};
    for (final document in documents) {
      final documentId = document['id']?.toString().trim() ?? '';
      if (documentId.isEmpty) {
        continue;
      }
      if (pendingMessageId != null && documentId == pendingMessageId) {
        continue;
      }
      nextById[documentId] = Map<String, dynamic>.from(document);
    }
    if (nextById.isEmpty) {
      _volatileMessageDocumentsByThreadId.remove(threadId);
      return;
    }
    _volatileMessageDocumentsByThreadId[threadId] = nextById;
  }

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
    final nextDocument = <String, dynamic>{
      ...?existingThread,
      'id': threadId,
      ...patch,
    };
    _storeVolatileThreadDocument(nextDocument);
    await _cache.upsertDocument(
      resourceKey: _supportThreadsResourceKey,
      document: nextDocument,
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
          (!id.startsWith('local_thread_') &&
              !_volatileThreadDocumentsById.containsKey(id))) {
        continue;
      }
      mergedById[id] = Map<String, dynamic>.from(cachedDocument);
    }
    for (final entry in _volatileThreadDocumentsById.entries) {
      mergedById.putIfAbsent(
        entry.key,
        () => Map<String, dynamic>.from(entry.value),
      );
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
      final matchingIndex = visibleMessages.indexWhere(
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
      if (matchingIndex >= 0) {
        // The persisted queue has the attachment bytes. Prefer it over the
        // lightweight local placeholder, but never replace a synced message.
        if (visibleMessages[matchingIndex].isPendingUpload) {
          merged[matchingIndex] = Map<String, dynamic>.from(queuedDocument);
          visibleMessages[matchingIndex] = queuedMessage;
        }
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

  Future<List<Map<String, dynamic>>> _readQueuedSupportMessageDocumentsSafe(
    String threadId,
  ) async {
    try {
      return await _offlineMediaSyncService
          .readQueuedSupportMessageDocuments(threadId: threadId)
          .timeout(_queuedSupportReadTimeout);
    } on TimeoutException {
      return const <Map<String, dynamic>>[];
    } catch (error) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCollectionDocumentsViaPublicRest(
    String collectionPath,
  ) async {
    return _firestorePublicDocumentFetcher
        .fetchCollectionDocuments(collectionPath)
        .timeout(
          _startupTimeout,
          onTimeout: () {
            throw TimeoutException('public rest $collectionPath fetch timeout');
          },
        );
  }

  Future<List<Map<String, dynamic>>> _readThreadReadMarkersViaPublicRest(
    String normalizedUserId,
  ) async {
    try {
      return await _fetchCollectionDocumentsViaPublicRest(
        'manage_support/$normalizedUserId/threads',
      );
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }
}
