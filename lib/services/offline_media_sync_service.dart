import 'package:webapp/utils/copy_document_fields.dart';
import 'package:webapp/models/offline_queue_item.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:webapp/services/booking_id_resolver.dart';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:webapp/models/support_message.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/image_upload_processor.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_sync_status_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/services/support_storage_service.dart';
import 'package:webapp/utils/functions.dart';

class OfflineMediaSyncService {
  OfflineMediaSyncService({
    BookingStorageBackend? backend,
    FirebaseFirestore? firestore,
    PhotoStorageService? photoStorageService,
    SupportStorageService? supportStorageService,
    bool Function()? isOnline,
  }) : _backend = backend ?? createBookingStorageBackend(),
       _providedFirestore = firestore,
       _photoStorageService =
           photoStorageService ?? PhotoStorageService.instance,
       _supportStorageService =
           supportStorageService ?? SupportStorageService.instance,
       _isOnline = isOnline ?? currentNetworkStatus;

  static final OfflineMediaSyncService instance = OfflineMediaSyncService();

  static const _storageKey = 'offline_media_sync_queue_v1';
  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';
  static const _retryInterval = Duration(seconds: 20);
  static const Duration _queuedSupportReadTimeout = Duration(seconds: 1);

  final bool Function() _isOnline;
  final BookingStorageBackend _backend;
  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final PhotoStorageService _photoStorageService;
  final SupportStorageService _supportStorageService;
  final ImageUploadProcessor _imageUploadProcessor =
      ImageUploadProcessor.instance;
  final AuthStorageBackend _authStorage = createAuthStorageBackend();

  bool _isInitialized = false;
  bool _isFlushing = false;
  Future<void> _queueMutationChain = Future<void>.value();
  Timer? _retryTimer;
  StreamSubscription<bool>? _networkSubscription;
  final StreamController<OfflineQueueStatusSnapshot> _statusController =
      StreamController<OfflineQueueStatusSnapshot>.broadcast();
  OfflineQueueStatusSnapshot _currentStatus =
      const OfflineQueueStatusSnapshot.idle();

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _supportCollection =>
      _firestore.collection('support');

  Stream<OfflineQueueStatusSnapshot> get statusStream =>
      _statusController.stream;
  OfflineQueueStatusSnapshot get currentStatus => _currentStatus;

  /// Inspect only the requested account's persisted queue without starting sync.
  Future<List<OfflineQueueItem>> readPendingItems(String userId) async {
    if (userId.trim().isEmpty) {
      return const [];
    }
    await _backend.initialize();
    final entries = await _readEntriesForStorageKey(
      _storageKeyForUserId(userId),
    );
    return entries
        .map(
          (entry) => OfflineQueueItem(
            title: entry.kind.name == 'supportMessage'
                ? 'Send support message'
                : 'Upload profile or license photo',
            recordLabel: entry.kind.name == 'supportMessage'
                ? 'Support conversation'
                : 'User profile',
            createdAt: DateTime.tryParse(entry.createdAtIso),
            hasError: entry.lastError?.isNotEmpty == true,
            errorMessage: entry.lastError,
            nextRetryAt: entry.nextRetryAt,
          ),
        )
        .toList(growable: false);
  }

  bool _manualChatRetryRunning = false;

  String? _lastAutomaticChatRetryUser;
  DateTime? _lastAutomaticChatRetryAt;

  /// One bounded attempt on opening the queue; no listener or retry timer.
  Future<void> retryFailedSupportMessagesOnOpen(String userId) async {
    if (!_isOnline() || _isFlushing || _manualChatRetryRunning) {
      return;
    }
    final now = DateTime.now();
    if (_lastAutomaticChatRetryUser == userId &&
        _lastAutomaticChatRetryAt != null &&
        now.difference(_lastAutomaticChatRetryAt!) <
            const Duration(seconds: 30)) {
      return;
    }
    _lastAutomaticChatRetryUser = userId;
    _lastAutomaticChatRetryAt = now;
    await retryFailedSupportMessages(userId);
  }

  /// Preserve identity, payload and original dates.
  Future<void> retryFailedSupportMessages(String userId) async {
    if (_manualChatRetryRunning || _isFlushing) {
      throw StateError(
        'Sync is already running. Please wait for it to finish.',
      );
    }
    if (!_isOnline()) {
      throw StateError('Connect to the internet before retrying.');
    }
    _manualChatRetryRunning = true;
    try {
      await _authStorage.initialize();
      if (normalizeId(await _authStorage.readString(_currentUserIdKey)) !=
              normalizeId(userId) ||
          userId.trim().isEmpty) {
        throw StateError('Open queued actions from the active account.');
      }
      final storageKey = _storageKeyForUserId(userId);
      final hasFailedChat = await _serializeQueueMutation(() async {
        final entries = await _readEntriesForStorageKey(storageKey);
        if (!entries.any(
          (entry) =>
              entry.kind == _OfflineMediaQueueKind.supportMessage &&
              entry.lastError != null,
        )) {
          return false;
        }
        final updated = entries
            .map(
              (entry) =>
                  entry.kind == _OfflineMediaQueueKind.supportMessage &&
                      entry.lastError != null
                  ? entry.copyWith(
                      nextRetryAt: DateTime.fromMillisecondsSinceEpoch(
                        0,
                        isUtc: true,
                      ),
                    )
                  : entry,
            )
            .toList();
        await _writeEntriesForStorageKey(storageKey, updated);
        return true;
      });
      if (hasFailedChat) {
        await flushPendingOperations();
      }
    } finally {
      _manualChatRetryRunning = false;
    }
  }

  Future<Map<String, OfflineQueueStatusSnapshot>> readScopedStatuses({
    Iterable<String> userIds = const [],
    bool includeSignedOut = true,
  }) async {
    // Inspection must not publish status and recursively trigger aggregate scans.
    if (!_isInitialized) {
      await initialize();
    }
    final normalizedUserIds = userIds
        .map(normalizeId)
        .whereType<String>()
        .toSet()
        .toList();
    final statuses = <String, OfflineQueueStatusSnapshot>{};
    if (includeSignedOut) {
      statuses['signed_out'] = await _readStatusForStorageKey(
        _storageKeyForUserId(null),
      );
    }
    for (final userId in normalizedUserIds) {
      statuses[userId] = await _readStatusForStorageKey(
        _storageKeyForUserId(userId),
      );
    }
    return statuses;
  }

  Future<List<Map<String, dynamic>>> readQueuedSupportMessageDocuments({
    String? threadId,
  }) async {
    await initialize();
    try {
      await _queueMutationChain
          .catchError((_) {})
          .timeout(_queuedSupportReadTimeout);
    } on TimeoutException {
      // Ignore queue read delays so support UI can continue rendering.
    }
    final normalizedThreadId = normalizeId(threadId);
    final entries = await _readEntries();
    final documents = entries
        .where((entry) => entry.kind == _OfflineMediaQueueKind.supportMessage)
        .where((entry) {
          if (normalizedThreadId == null) {
            return true;
          }
          return normalizeId(entry.threadId) == normalizedThreadId;
        })
        .map(_queuedSupportEntryToDocument)
        .toList(growable: false);
    return documents;
  }

  Future<void> initialize() async {
    await _authStorage.initialize();
    if (_isInitialized) {
      await _refreshStatusFromStorage();
      return;
    }
    await _backend.initialize();
    await _refreshStatusFromStorage();
    _retryTimer ??= Timer.periodic(_retryInterval, (_) {
      if (!isAppVisible()) return;
      unawaited(flushPendingOperations());
    });
    _networkSubscription ??= networkStatusEvents().listen((isOnline) {
      if (isOnline && isAppVisible()) {
        unawaited(flushPendingOperations());
      }
    });
    _isInitialized = true;
    unawaited(flushPendingOperations());
  }

  Future<QueuedUserMediaResult> queueUserPhotoUpload({
    required String userId,
    required String fieldKey,
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    int? size,
    required String? originalValue,
  }) async {
    final actionAt = DateTime.now().toUtc();
    await initialize();
    return _serializeQueueMutation(() async {
      final processed = await _imageUploadProcessor.prepare(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );
      final entries = await _readEntries();
      final previous = _photoPredecessor(
        entries,
        userId,
        fieldKey,
        originalValue,
      );
      final entry = _OfflineMediaQueueEntry.userUpload(
        id: _nextEntryId('user_upload'),
        createdAtIso: actionAt.toIso8601String(),
        userId: userId,
        fieldKey: fieldKey,
        fileName: processed.fileName,
        mimeType: processed.mimeType,
        size: processed.size,
        bytesBase64: base64Encode(processed.bytes),
        originalValue: originalValue,
        previousUploadId: previous?.id,
      );
      entries.add(entry);
      await _writeEntries(entries);
      _setStatus(
        _currentStatus.copyWith(pendingCount: entries.length, isSyncing: false),
      );
      unawaited(flushPendingOperations());

      return QueuedUserMediaResult(
        previewUrl: _dataUrlForBytes(
          bytes: processed.bytes,
          mimeType: processed.mimeType,
        ),
        queuedAt: actionAt,
      );
    });
  }

  Future<void> queueSupportMessage({
    required String threadId,
    required UserModel sender,
    String? text,
    required List<QueuedSupportAttachmentInput> attachments,
    SupportThread? thread,
    String? localOrderKey,
    String? localCreatedAtIso,
  }) async {
    await initialize();
    await _serializeQueueMutation(() async {
      final queuedAt =
          DateTime.tryParse(localCreatedAtIso ?? '')?.toUtc() ??
          DateTime.now().toUtc();
      final entry = _OfflineMediaQueueEntry.supportMessage(
        id: localOrderKey?.isNotEmpty == true
            ? 'support_message_${base64UrlEncode(utf8.encode('$threadId:${sender.id}:$localOrderKey'))}'
            : _nextEntryId('support_message'),
        createdAtIso: queuedAt.toIso8601String(),
        localOrderKey: localOrderKey,
        threadId: threadId,
        senderUserId: normalizeId(sender.id),
        senderRole: sender.role,
        senderName: sender.name,
        senderPhoto: sender.photo,
        text: text?.trim(),
        threadDocument: thread?.toMap(),
        attachments: attachments
            .map(
              (attachment) => _QueuedAttachmentPayload(
                bytesBase64: base64Encode(attachment.bytes),
                fileName: attachment.fileName,
                mimeType: attachment.mimeType,
                size: attachment.size ?? attachment.bytes.length,
              ),
            )
            .toList(),
      );
      final entries = await _readEntries();
      if (!entries.any((pending) => pending.id == entry.id)) {
        entries.add(entry);
      }
      await _writeEntries(entries);
      _setStatus(
        _currentStatus.copyWith(pendingCount: entries.length, isSyncing: false),
      );
    });
    unawaited(flushPendingOperations());
  }

  Future<void> flushPendingOperations() async {
    await initialize();
    if (_isFlushing) {
      return;
    }
    _isFlushing = true;
    var shouldFlushAgainImmediately = false;
    try {
      await _queueMutationChain;
      if (!_isOnline()) {
        final entries = await _readEntries();
        _setStatus(
          _currentStatus.copyWith(
            pendingCount: entries.length,
            isSyncing: false,
            processedInBatch: 0,
            totalInBatch: 0,
          ),
        );
        return;
      }
      final currentStorageKey = await _resolvedStorageKey();
      final storageKeys = await _allKnownStorageKeys();
      for (final storageKey in storageKeys) {
        final flushed = await _flushPendingOperationsForStorageKey(
          storageKey,
          updateStatus: storageKey == currentStorageKey,
        );
        shouldFlushAgainImmediately =
            shouldFlushAgainImmediately || flushed.shouldFlushAgainImmediately;
      }
      await _refreshStatusFromStorage();
    } finally {
      _isFlushing = false;
      if (_currentStatus.isSyncing) {
        _setStatus(
          _currentStatus.copyWith(
            isSyncing: false,
            processedInBatch: 0,
            totalInBatch: 0,
          ),
        );
      }
      if (shouldFlushAgainImmediately) {
        unawaited(flushPendingOperations());
      }
    }
  }

  _OfflineMediaQueueEntry? _photoPredecessor(
    List<_OfflineMediaQueueEntry> entries,
    String? userId,
    String? fieldKey,
    String? originalValue,
  ) {
    if (originalValue?.startsWith('data:') != true) {
      return null;
    }
    for (final candidate in entries.reversed) {
      if (candidate.kind == _OfflineMediaQueueKind.userUpload &&
          candidate.userId == userId &&
          candidate.fieldKey == fieldKey &&
          candidate.bytesBase64 != null &&
          _dataUrlForBytes(
                bytes: base64Decode(candidate.bytesBase64!),
                mimeType: candidate.mimeType,
              ) ==
              originalValue) {
        return candidate;
      }
    }
    return null;
  }

  bool _canApplyUserPhoto(
    _OfflineMediaQueueEntry entry,
    Map<String, dynamic> data,
  ) {
    final currentValue = entry.fieldKey == 'license_photo'
        ? data['license']?.toString()
        : data['photo']?.toString();
    final receipts = data['offline_photo_uploads'];
    final receipt = receipts is Map ? receipts[entry.fieldKey] : null;
    final followsPrevious =
        entry.previousUploadId != null &&
        receipt is Map &&
        receipt['id'] == entry.previousUploadId &&
        receipt['url'] == currentValue;
    if (receipt is Map && receipt['id'] == entry.id) {
      return false; // Acknowledged retry must not restore an older photo.
    }
    if (!followsPrevious &&
        (currentValue ?? '') != (entry.originalValue ?? '')) {
      if (entry.previousUploadId != null) {
        throw StateError(
          'Previous photo is temporarily unavailable. Try again after sync.',
        );
      }
      return false;
    }

    return true;
  }

  bool _photoWasAcknowledged(
    _OfflineMediaQueueEntry entry,
    Map<String, dynamic> user,
    Map<String, _OfflineMediaQueueEntry> pending,
  ) {
    final receipts = user['offline_photo_uploads'];
    final receipt = receipts is Map ? receipts[entry.fieldKey] : null;
    if (receipt is! Map) {
      return false;
    }
    String? id = receipt['id']?.toString();
    final visited = <String>{};
    while (id != null && visited.add(id)) {
      if (id == entry.id) {
        return true;
      }
      final successor = pending[id];
      if (successor == null ||
          successor.userId != entry.userId ||
          successor.fieldKey != entry.fieldKey) {
        return false;
      }
      id = successor.previousUploadId;
    }
    return false;
  }

  Future<bool> _flushUserUpload(
    _OfflineMediaQueueEntry entry,
    String scope,
    Map<String, _OfflineMediaQueueEntry> pending,
  ) async {
    final bytesBase64 = entry.bytesBase64;
    final references = await OfflineMutationQueueService(
      firestore: _firestore,
    ).resolveResourceReferences({'user_id': entry.userId}, scope: scope);
    final userId = references['user_id']?.toString();
    final fieldKey = entry.fieldKey;
    if (bytesBase64 == null || userId == null || fieldKey == null) {
      return true;
    }

    final currentUser = await _usersCollection.doc(userId).get();
    if (!currentUser.exists ||
        _photoWasAcknowledged(entry, documentData(currentUser), pending) ||
        !_canApplyUserPhoto(entry, documentData(currentUser))) {
      return true;
    }
    final uploaded = await _photoStorageService.uploadUserPhoto(
      bytes: base64Decode(bytesBase64),
      userId: userId,
      fieldKey: fieldKey,
      fileName: entry.fileName ?? 'photo',
      mimeType: entry.mimeType,
      size: entry.size,
    );
    final applied = await _firestore.runTransaction<bool>((transaction) async {
      final userRef = _usersCollection.doc(userId);
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) {
        return false;
      }
      final data = documentData(snapshot);
      if (_photoWasAcknowledged(entry, data, pending) ||
          !_canApplyUserPhoto(entry, data)) {
        return false;
      }

      final patch = <String, dynamic>{
        'offline_photo_uploads.$fieldKey': {
          'id': entry.id,
          'url': uploaded['download_url']?.toString(),
        },
        'photo_updated_at': entry.createdAtIso,
        'media_synced_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (fieldKey == 'license_photo') {
        patch['license'] = uploaded['download_url']?.toString();
      } else {
        patch['photo'] = uploaded['download_url']?.toString();
      }
      transaction.update(userRef, patch);
      return true;
    });

    if (!applied) {
      await _photoStorageService.deleteByPath(
        uploaded['storage_path']?.toString(),
      );
    }
    return true;
  }

  Future<void> _flushSupportMessage(
    _OfflineMediaQueueEntry entry,
    String scope,
  ) async {
    final threadId = entry.threadId;
    final references = await OfflineMutationQueueService(firestore: _firestore)
        .resolveResourceReferences({
          'sender_user_id': entry.senderUserId,
        }, scope: scope);
    final senderUserId = references['sender_user_id']?.toString();
    if (threadId == null || senderUserId == null) {
      return;
    }
    final threadDoc = _supportCollection.doc(threadId);
    final threadDocument = entry.threadDocument == null
        ? null
        : copyDocumentFields(entry.threadDocument!);
    if (threadDocument != null) {
      final originalId = threadDocument['booking_id']?.toString();
      if (BookingIdResolver.isTemporary(originalId)) {
        final finalId = await BookingIdResolver(
          firestore: _firestore,
        ).resolve(originalId!);
        if (finalId == null) {
          throw StateError(
            'Booking identity is temporarily unavailable. Try again after sync.',
          );
        }
        threadDocument['booking_id'] = finalId;
      }
      final originalReferences = copyDocumentFields(threadDocument);
      final linkedDocument = await OfflineMutationQueueService(
        firestore: _firestore,
      ).resolveResourceReferences(threadDocument, scope: scope);
      for (final key in linkedDocument.keys) {
        threadDocument[key] = linkedDocument[key];
      }
      await _firestore.runTransaction((transaction) async {
        final existing = await transaction.get(threadDoc);
        final existingId = existing.data()?['booking_id']?.toString();
        final finalId = threadDocument['booking_id']?.toString();
        if (existingId != null &&
            existingId != originalId &&
            existingId != finalId) {
          throw StateError(
            'Sync conflict: support thread is linked to another booking.',
          );
        }
        if (!existing.exists) {
          transaction.set(threadDoc, threadDocument);
        } else {
          final patch = <String, dynamic>{};
          if (BookingIdResolver.isTemporary(originalId)) {
            patch['booking_id'] = finalId;
          }
          for (final field in [
            'requester_user_id',
            'requester_parent_client_id',
          ]) {
            final original = originalReferences[field];
            final resolved = threadDocument[field];
            if (original != resolved && existing.data()?[field] == original) {
              patch[field] = resolved;
            } else if (original != resolved &&
                existing.data()?[field] != resolved) {
              throw StateError(
                'Sync conflict: support requester identity changed.',
              );
            }
          }
          if (patch.isNotEmpty) {
            transaction.update(threadDoc, patch);
          }
        }
      });
    }

    if ((await threadDoc.collection('messages').doc(entry.id).get()).exists) {
      return;
    }
    final uploadedAttachments = <SupportAttachment>[];
    for (final attachment in entry.attachments) {
      uploadedAttachments.add(
        await _supportStorageService.uploadAttachment(
          bytes: base64Decode(attachment.bytesBase64),
          threadId: threadId,
          fileName: attachment.fileName,
          mimeType: attachment.mimeType,
          size: attachment.size,
        ),
      );
    }

    final messageDoc = threadDoc.collection('messages').doc(entry.id);
    final now =
        DateTime.tryParse(entry.createdAtIso)?.toUtc() ??
        DateTime.now().toUtc();
    final message = SupportMessage(
      id: messageDoc.id,
      localOrderKey: entry.localOrderKey,
      threadId: threadId,
      senderUserId: senderUserId,
      senderRole: entry.senderRole,
      senderName: entry.senderName,
      senderPhoto: entry.senderPhoto,
      text: entry.text,
      attachments: uploadedAttachments,
      createdAt: now,
      updatedAt: now,
    );

    final lastPreview = entry.text?.trim().isNotEmpty == true
        ? entry.text!.trim()
        : uploadedAttachments.length == 1
        ? 'Sent an attachment'
        : 'Sent ${uploadedAttachments.length} attachments';

    await _firestore.runTransaction<void>((tx) async {
      final existingMessage = await tx.get(messageDoc);
      final currentThread = await tx.get(threadDoc);
      if (existingMessage.exists) {
        return;
      }
      tx.set(messageDoc, message.toMap());
      final latestAt = DateTime.tryParse(
        currentThread.data()?['last_message_at']?.toString() ?? '',
      );
      if (latestAt == null || !latestAt.isAfter(now)) {
        tx.set(threadDoc, {
          'last_message_text': lastPreview,
          'last_message_at': now.toIso8601String(),
          'last_sender_user_id': senderUserId,
          'last_sender_role': entry.senderRole,
          'updated_at': now.toIso8601String(),
          'is_active': true,
        }, SetOptions(merge: true));
      }
    });
  }

  Future<List<_OfflineMediaQueueEntry>> _readEntries() async {
    final rawEntries = await _backend.readStringList(
      await _resolvedStorageKey(),
    );
    return rawEntries
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .map(_OfflineMediaQueueEntry.fromMap)
        .toList();
  }

  Future<void> _writeEntries(List<_OfflineMediaQueueEntry> entries) async {
    await _backend.writeStringList(
      await _resolvedStorageKey(),
      entries.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }

  Future<String> _resolvedStorageKey() async {
    final captured = Zone.current[_storageScopeKey];
    if (captured is String) return captured;
    final normalizedUserId = normalizeId(
      await _authStorage.readString(_currentUserIdKey),
    );
    return _storageKeyForUserId(normalizedUserId);
  }

  String _storageKeyForUserId(String? userId) {
    final normalizedUserId = normalizeId(userId);
    if (normalizedUserId == null) {
      return '$_storageKey::signed_out';
    }
    return '$_storageKey::$normalizedUserId';
  }

  Future<List<_OfflineMediaQueueEntry>> _readEntriesForStorageKey(
    String storageKey,
  ) async {
    final rawEntries = await _backend.readStringList(storageKey);
    return rawEntries
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .map(_OfflineMediaQueueEntry.fromMap)
        .toList();
  }

  Future<OfflineQueueStatusSnapshot> _readStatusForStorageKey(
    String storageKey,
  ) async {
    final entries = await _readEntriesForStorageKey(storageKey);
    return const OfflineQueueStatusSnapshot.idle().copyWith(
      pendingCount: entries.length,
      failedCount: entries.where((entry) => entry.lastError != null).length,
    );
  }

  Future<void> _writeEntriesForStorageKey(
    String storageKey,
    List<_OfflineMediaQueueEntry> entries,
  ) async {
    await _backend.writeStringList(
      storageKey,
      entries.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }

  Future<List<String>> _allKnownStorageKeys() async {
    final knownUsers = await _authStorage.readStringList(
      _knownSessionUserIdsKey,
    );
    final keys = <String>{_storageKeyForUserId(null)};
    for (final userId in knownUsers) {
      keys.add(_storageKeyForUserId(userId));
    }
    keys.add(await _resolvedStorageKey());
    return keys.toList(growable: false);
  }

  Future<_ScopedMediaFlushResult> _flushPendingOperationsForStorageKey(
    String storageKey, {
    required bool updateStatus,
  }) async {
    // Persist exact predecessor links for legacy pending photos before removing
    // any successfully synced predecessor from the queue.
    final entries = await _serializeQueueMutation(() async {
      final stored = await _readEntriesForStorageKey(storageKey);
      final linked = <_OfflineMediaQueueEntry>[];
      var changed = false;
      for (final entry in stored) {
        final previous =
            entry.kind == _OfflineMediaQueueKind.userUpload &&
                entry.previousUploadId == null
            ? _photoPredecessor(
                linked,
                entry.userId,
                entry.fieldKey,
                entry.originalValue,
              )
            : null;
        linked.add(
          previous == null
              ? entry
              : entry.copyWith(previousUploadId: previous.id),
        );
        changed = changed || previous != null;
      }
      if (changed) {
        await _writeEntriesForStorageKey(storageKey, linked);
      }
      return linked;
    });
    final now = DateTime.now().toUtc();
    final hasDueWork = entries.any(
      (entry) => entry.nextRetryAt?.isAfter(now) != true,
    );
    if (!hasDueWork) {
      if (updateStatus) {
        _setStatus(
          _currentStatus.copyWith(
            pendingCount: entries.length,
            failedCount: entries
                .where((entry) => entry.lastError != null)
                .length,
            isSyncing: false,
          ),
        );
      }
      // Preserve the stored payload verbatim until work is actually due.
      return const _ScopedMediaFlushResult(shouldFlushAgainImmediately: false);
    }
    final entriesById = {for (final entry in entries) entry.id: entry};
    final originalEntryIds = entriesById.keys.toSet();
    if (updateStatus) {
      _setStatus(
        _currentStatus.copyWith(
          pendingCount: entries.length,
          isSyncing: entries.isNotEmpty,
          processedInBatch: 0,
          totalInBatch: entries.length,
          clearLastSyncAt: entries.isNotEmpty,
        ),
      );
    }
    if (entries.isEmpty) {
      return const _ScopedMediaFlushResult(shouldFlushAgainImmediately: false);
    }

    final remaining = <_OfflineMediaQueueEntry>[];
    var processed = 0;

    for (final entry in entries) {
      try {
        if (entry.nextRetryAt?.isAfter(DateTime.now().toUtc()) == true) {
          remaining.add(entry);
          continue;
        }
        if (entry.kind == _OfflineMediaQueueKind.userUpload) {
          final applied = await _flushUserUpload(
            entry,
            storageKey.substring('$_storageKey::'.length),
            entriesById,
          );
          if (!applied) {
            continue;
          }
        } else if (entry.kind == _OfflineMediaQueueKind.supportMessage) {
          await _flushSupportMessage(
            entry,
            storageKey.substring('$_storageKey::'.length),
          );
        }
      } catch (error, stackTrace) {
        if (kDebugMode && entry.kind == _OfflineMediaQueueKind.supportMessage) {
          debugPrint('[Support sync] ${entry.id}: $error');
          debugPrintStack(
            label: '[Support sync] replay failure',
            stackTrace: stackTrace,
          );
        }
        final normalizedError = normalizeUserErrorText(
          error.toString(),
          fallback: 'Something went wrong. Please try again.',
        );
        // Keep the only persisted copy, even for permission/storage failures.
        // The existing scheduler checks this deadline; no extra timer is added.
        final delaySeconds = _isRetryable(normalizedError)
            ? min(1200, 20 * pow(2, min(entry.retryCount, 6)).toInt())
            : 1200;
        remaining.add(
          entry.copyWith(
            retryCount: entry.retryCount + 1,
            lastError: normalizedError,
            nextRetryAt: DateTime.now().toUtc().add(
              Duration(seconds: delaySeconds),
            ),
          ),
        );
      } finally {
        processed++;
        if (updateStatus) {
          _setStatus(
            _currentStatus.copyWith(
              pendingCount: remaining.length + (entries.length - processed),
              isSyncing: true,
              processedInBatch: processed,
              totalInBatch: entries.length,
            ),
          );
        }
      }
    }

    await _serializeQueueMutation(() async {
      final latestStoredEntries = await _readEntriesForStorageKey(storageKey);
      final newlyQueuedEntries = latestStoredEntries.where((entry) {
        return !originalEntryIds.contains(entry.id);
      });
      await _writeEntriesForStorageKey(storageKey, [
        ...remaining,
        ...newlyQueuedEntries,
      ]);
    });
    final latestEntries = await _readEntriesForStorageKey(storageKey);
    final shouldFlushAgainImmediately =
        _isOnline() &&
        latestEntries.isNotEmpty &&
        latestEntries.length < entries.length;
    if (updateStatus) {
      _setStatus(
        _currentStatus.copyWith(
          pendingCount: latestEntries.length,
          isSyncing: false,
          processedInBatch: remaining.isEmpty ? entries.length : 0,
          totalInBatch: remaining.isEmpty ? entries.length : 0,
          lastSyncAt: remaining.length < entries.length ? DateTime.now() : null,
        ),
      );
    }
    return _ScopedMediaFlushResult(
      shouldFlushAgainImmediately: shouldFlushAgainImmediately,
    );
  }

  Future<void> _refreshStatusFromStorage() async {
    final entries = await _readEntries();
    _setStatus(
      _currentStatus.copyWith(
        pendingCount: entries.length,
        failedCount: entries.where((entry) => entry.lastError != null).length,
      ),
    );
  }

  void _setStatus(OfflineQueueStatusSnapshot nextStatus) {
    _currentStatus = nextStatus;
    if (!_statusController.isClosed) {
      _statusController.add(nextStatus);
    }
  }

  bool _isRetryable(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized.contains('internet connection') ||
        normalized.contains('temporarily unavailable') ||
        normalized.contains('request took too long') ||
        normalized.contains('try again');
  }

  String _nextEntryId(String prefix) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomSuffix = Random().nextInt(0x100000000).toRadixString(16);
    return '${prefix}_${timestamp}_$randomSuffix';
  }

  final Object _storageScopeKey = Object();

  Future<T> _serializeQueueMutation<T>(Future<T> Function() action) {
    // Capture the originating account before waiting for another local write.
    final scope = _resolvedStorageKey();
    final next = _queueMutationChain.then((_) async {
      final storageKey = await scope;
      return runZoned(action, zoneValues: {_storageScopeKey: storageKey});
    });
    _queueMutationChain = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  String _dataUrlForBytes({required Uint8List bytes, String? mimeType}) {
    final resolvedMimeType = (mimeType?.trim().isNotEmpty == true)
        ? mimeType!.trim()
        : 'image/jpeg';
    return 'data:$resolvedMimeType;base64,${base64Encode(bytes)}';
  }

  Map<String, dynamic> _queuedSupportEntryToDocument(
    _OfflineMediaQueueEntry entry,
  ) {
    return SupportMessage(
      // Reuse the optimistic local message ID so a restart cannot create a
      // duplicate bubble beside the queued message.
      id: _pendingSupportMessageId(entry),
      localOrderKey: entry.localOrderKey,
      threadId: entry.threadId,
      senderUserId: entry.senderUserId,
      senderRole: entry.senderRole,
      senderName: entry.senderName,
      senderPhoto: entry.senderPhoto,
      text: entry.text,
      attachments: entry.attachments
          .map(
            (attachment) => SupportAttachment(
              name: attachment.fileName,
              // The bytes are already persisted in the offline queue. Expose
              // them as a local data URL so queued image chats remain visible
              // after a browser restart and while offline.
              downloadUrl: _dataUrlForBytes(
                bytes: base64Decode(attachment.bytesBase64),
                mimeType: attachment.mimeType,
              ),
              mimeType: attachment.mimeType,
              size: attachment.size,
            ),
          )
          .toList(growable: false),
      createdAt: DateTime.tryParse(entry.createdAtIso)?.toUtc(),
      updatedAt: DateTime.tryParse(entry.createdAtIso)?.toUtc(),
    ).toMap();
  }

  String _pendingSupportMessageId(_OfflineMediaQueueEntry entry) {
    final localOrderKey = entry.localOrderKey?.trim() ?? '';
    final separatorIndex = localOrderKey.indexOf('|');
    final candidate = separatorIndex >= 0
        ? localOrderKey.substring(0, separatorIndex).trim()
        : localOrderKey;
    if (candidate.startsWith('local_') || candidate.startsWith('queued_')) {
      return candidate;
    }
    return 'queued_${entry.id}';
  }
}

class QueuedSupportAttachmentInput {
  const QueuedSupportAttachmentInput({
    required this.bytes,
    required this.fileName,
    this.mimeType,
    this.size,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mimeType;
  final int? size;
}

class _ScopedMediaFlushResult {
  const _ScopedMediaFlushResult({required this.shouldFlushAgainImmediately});

  final bool shouldFlushAgainImmediately;
}

class QueuedUserMediaResult {
  const QueuedUserMediaResult({
    required this.previewUrl,
    required this.queuedAt,
  });

  final String previewUrl;
  final DateTime queuedAt;
}

enum _OfflineMediaQueueKind { userUpload, supportMessage }

class _OfflineMediaQueueEntry {
  const _OfflineMediaQueueEntry({
    required this.id,
    required this.kind,
    required this.createdAtIso,
    required this.retryCount,
    this.localOrderKey,
    this.lastError,
    this.nextRetryAt,
    this.userId,
    this.fieldKey,
    this.fileName,
    this.mimeType,
    this.size,
    this.bytesBase64,
    this.originalValue,
    this.previousUploadId,
    this.threadId,
    this.senderUserId,
    this.senderRole,
    this.senderName,
    this.senderPhoto,
    this.text,
    this.threadDocument,
    this.attachments = const [],
  });

  factory _OfflineMediaQueueEntry.userUpload({
    required String id,
    required String createdAtIso,
    required String userId,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
    required String bytesBase64,
    required String? originalValue,
    String? previousUploadId,
  }) {
    return _OfflineMediaQueueEntry(
      id: id,
      kind: _OfflineMediaQueueKind.userUpload,
      createdAtIso: createdAtIso,
      retryCount: 0,
      userId: userId,
      fieldKey: fieldKey,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
      bytesBase64: bytesBase64,
      originalValue: originalValue,
      previousUploadId: previousUploadId,
    );
  }

  factory _OfflineMediaQueueEntry.supportMessage({
    required String id,
    required String createdAtIso,
    String? localOrderKey,
    required String threadId,
    required String? senderUserId,
    required String? senderRole,
    required String? senderName,
    required String? senderPhoto,
    required String? text,
    required Map<String, dynamic>? threadDocument,
    required List<_QueuedAttachmentPayload> attachments,
  }) {
    return _OfflineMediaQueueEntry(
      id: id,
      kind: _OfflineMediaQueueKind.supportMessage,
      createdAtIso: createdAtIso,
      retryCount: 0,
      localOrderKey: localOrderKey,
      threadId: threadId,
      senderUserId: senderUserId,
      senderRole: senderRole,
      senderName: senderName,
      senderPhoto: senderPhoto,
      text: text,
      threadDocument: threadDocument == null
          ? null
          : Map<String, dynamic>.from(threadDocument),
      attachments: attachments,
    );
  }

  final String id;
  final _OfflineMediaQueueKind kind;
  final String createdAtIso;
  final int retryCount;
  final String? localOrderKey;
  final String? lastError;
  final DateTime? nextRetryAt;
  final String? userId;
  final String? fieldKey;
  final String? fileName;
  final String? mimeType;
  final int? size;
  final String? bytesBase64;
  final String? originalValue;
  final String? previousUploadId;
  final String? threadId;
  final String? senderUserId;
  final String? senderRole;
  final String? senderName;
  final String? senderPhoto;
  final String? text;
  final Map<String, dynamic>? threadDocument;
  final List<_QueuedAttachmentPayload> attachments;

  _OfflineMediaQueueEntry copyWith({
    int? retryCount,
    String? lastError,
    DateTime? nextRetryAt,
    String? previousUploadId,
  }) {
    return _OfflineMediaQueueEntry(
      id: id,
      kind: kind,
      createdAtIso: createdAtIso,
      retryCount: retryCount ?? this.retryCount,
      localOrderKey: localOrderKey,
      lastError: lastError ?? this.lastError,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      userId: userId,
      fieldKey: fieldKey,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
      bytesBase64: bytesBase64,
      originalValue: originalValue,
      previousUploadId: previousUploadId ?? this.previousUploadId,
      threadId: threadId,
      senderUserId: senderUserId,
      senderRole: senderRole,
      senderName: senderName,
      senderPhoto: senderPhoto,
      text: text,
      threadDocument: threadDocument == null
          ? null
          : Map<String, dynamic>.from(threadDocument!),
      attachments: attachments,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'kind': kind.name,
      'created_at': createdAtIso,
      'retry_count': retryCount,
      'local_order_key': localOrderKey,
      'last_error': lastError,
      'next_retry_at': nextRetryAt?.toIso8601String(),
      'user_id': userId,
      'field_key': fieldKey,
      'file_name': fileName,
      'mime_type': mimeType,
      'size': size,
      'bytes_base64': bytesBase64,
      'original_value': originalValue,
      'previous_upload_id': previousUploadId,
      'thread_id': threadId,
      'sender_user_id': senderUserId,
      'sender_role': senderRole,
      'sender_name': senderName,
      'sender_photo': senderPhoto,
      'text': text,
      'thread_document': threadDocument,
      'attachments': attachments.map((item) => item.toMap()).toList(),
    };
  }

  factory _OfflineMediaQueueEntry.fromMap(Map<String, dynamic> map) {
    final kindName = map['kind']?.toString() ?? '';
    return _OfflineMediaQueueEntry(
      id: map['id']?.toString() ?? '',
      kind: kindName == _OfflineMediaQueueKind.supportMessage.name
          ? _OfflineMediaQueueKind.supportMessage
          : _OfflineMediaQueueKind.userUpload,
      createdAtIso: map['created_at']?.toString() ?? '',
      retryCount: map['retry_count'] is num
          ? (map['retry_count'] as num).toInt()
          : int.tryParse(map['retry_count']?.toString() ?? '') ?? 0,
      localOrderKey: map['local_order_key']?.toString(),
      lastError: map['last_error']?.toString(),
      nextRetryAt: DateTime.tryParse(map['next_retry_at']?.toString() ?? ''),
      userId: map['user_id']?.toString(),
      fieldKey: map['field_key']?.toString(),
      fileName: map['file_name']?.toString(),
      mimeType: map['mime_type']?.toString(),
      size: map['size'] is num
          ? (map['size'] as num).toInt()
          : int.tryParse(map['size']?.toString() ?? ''),
      bytesBase64: map['bytes_base64']?.toString(),
      originalValue: map['original_value']?.toString(),
      previousUploadId: map['previous_upload_id']?.toString(),
      threadId: map['thread_id']?.toString(),
      senderUserId: map['sender_user_id']?.toString(),
      senderRole: map['sender_role']?.toString(),
      senderName: map['sender_name']?.toString(),
      senderPhoto: map['sender_photo']?.toString(),
      text: map['text']?.toString(),
      threadDocument: map['thread_document'] is Map
          ? Map<String, dynamic>.from(map['thread_document'] as Map)
          : null,
      attachments: (map['attachments'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _QueuedAttachmentPayload.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }
}

class _QueuedAttachmentPayload {
  const _QueuedAttachmentPayload({
    required this.bytesBase64,
    required this.fileName,
    this.mimeType,
    this.size,
  });

  final String bytesBase64;
  final String fileName;
  final String? mimeType;
  final int? size;

  Map<String, dynamic> toMap() {
    return {
      'bytes_base64': bytesBase64,
      'file_name': fileName,
      'mime_type': mimeType,
      'size': size,
    };
  }

  factory _QueuedAttachmentPayload.fromMap(Map<String, dynamic> map) {
    return _QueuedAttachmentPayload(
      bytesBase64: map['bytes_base64']?.toString() ?? '',
      fileName: map['file_name']?.toString() ?? 'attachment',
      mimeType: map['mime_type']?.toString(),
      size: map['size'] is num
          ? (map['size'] as num).toInt()
          : int.tryParse(map['size']?.toString() ?? ''),
    );
  }
}
