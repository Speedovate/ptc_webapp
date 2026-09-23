import 'booking_photo_cleanup.dart';
import 'package:webapp/services/sync_error_log_service.dart';
import 'package:webapp/services/offline_error_diagnostics.dart';
import 'package:webapp/utils/copy_document_fields.dart';
import 'package:webapp/models/offline_queue_item.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/services/support_read_marker_writer.dart';
import 'package:webapp/services/firestore_transaction_errors.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:webapp/services/offline_reference_mapper.dart';
import 'package:webapp/services/booking_id_resolver.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/booking_chassis_lifecycle.dart';
import 'package:webapp/services/offline_sync_status_service.dart';
import 'package:webapp/utils/functions.dart';

class OfflineMutationQueueService {
  OfflineMutationQueueService({
    BookingStorageBackend? backend,
    FirebaseFirestore? firestore,
    bool Function()? isOnline,
    Future<void> Function(String userId, String scope, DateTime actionAt)?
    queueUserAssetCleanup,
  }) : _backend = backend ?? createBookingStorageBackend(),
       _providedFirestore = firestore,
       _isOnline = isOnline ?? currentNetworkStatus,
       _queueUserAssetCleanup =
           queueUserAssetCleanup ?? _defaultUserAssetCleanup;

  final Future<void> Function(String userId, String scope, DateTime actionAt)
  _queueUserAssetCleanup;

  static Future<void> _defaultUserAssetCleanup(
    String userId,
    String scope,
    DateTime actionAt,
  ) => OfflineCleanupQueueService.instance.queueDeleteFolder(
    'users/$userId',
    userScope: scope,
    actionAt: actionAt,
  );

  static final OfflineMutationQueueService instance =
      OfflineMutationQueueService();

  static const _storageKey = 'offline_mutation_queue_v1';
  static const _aliasStorageKeyPrefix = 'offline_mutation_queue_aliases_v1';
  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';
  static const _retryInterval = Duration(seconds: 20);
  static const _localStorageTimeout = Duration(seconds: 30);
  static const _remoteMutationTimeout = Duration(seconds: 30);

  final BookingStorageBackend _backend;
  final bool Function() _isOnline;
  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final AuthStorageBackend _authStorage = createAuthStorageBackend();

  bool _isInitialized = false;
  Future<void>? _flushFuture;
  Timer? _retryTimer;
  StreamSubscription<bool>? _networkSubscription;
  final StreamController<OfflineQueueStatusSnapshot> _statusController =
      StreamController<OfflineQueueStatusSnapshot>.broadcast();
  OfflineQueueStatusSnapshot _currentStatus =
      const OfflineQueueStatusSnapshot.idle();

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
            title: OfflineQueueItem.action(entry.kind.name),
            recordLabel:
                entry.kind == _OfflineMutationKind.supportThreadReadMarkerUpsert
                ? 'Support conversation'
                : OfflineQueueItem.record(
                    entry.collectionKey ??
                        (entry.kind.name.startsWith('user')
                            ? 'users'
                            : entry.kind.name.startsWith('chassis')
                            ? 'chassis'
                            : 'bookings'),
                    entry.targetId,
                  ),
            conflictId: entry.isBlocked ? entry.id : null,
            collectionKey: entry.collectionKey,
            isBlocked: entry.isBlocked,
            createdAt: DateTime.tryParse(entry.createdAtIso),
            hasError: entry.lastError?.isNotEmpty == true,
            errorMessage: entry.lastError,
            diagnostics: entry.diagnostics,
          ),
        )
        .toList(growable: false);
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

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _bookingsCollection =>
      _firestore.collection('bookings');
  DocumentReference<Map<String, dynamic>> get _bookingsCounterRef =>
      _firestore.collection('manage_count').doc('bookings_counter');
  CollectionReference<Map<String, dynamic>> get _idManagementCollection =>
      _firestore.collection('manage_id');

  DocumentReference<Map<String, dynamic>> _resourceCounterRef(
    String collectionKey,
  ) => _firestore
      .collection('manage_count')
      .doc('resource_counters')
      .collection('items')
      .doc(collectionKey);

  /// Reserves a numeric document ID atomically for resources whose documents
  /// intentionally use sequential IDs. A retry with the same submission key
  /// always returns the original reservation.
  Future<String> reserveNumericDocumentId({
    required String collectionKey,
    required String submissionKey,
  }) async {
    final collection = _collectionForKey(collectionKey);
    if (collection == null) {
      throw ArgumentError.value(collectionKey, 'collectionKey');
    }
    final normalizedKey = submissionKey.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(submissionKey, 'submissionKey');
    }
    final counterRef = _resourceCounterRef(collectionKey);
    final bootstrapNextId = await _bootstrapNextIdIfCounterMissing(
      counterRef: counterRef,
      collection: collection,
    );
    final reservation = await _firestore.runTransaction<String>((
      transaction,
    ) async {
      final idempotencyRef = _idManagementCollection.doc(
        _idempotencyDocumentId(collectionKey, normalizedKey),
      );
      final idempotencySnapshot = await transaction.get(idempotencyRef);
      final reserved = int.tryParse(
        idempotencySnapshot.data()?['document_id']?.toString() ?? '',
      );
      if (reserved != null && reserved > 0) {
        return '$reserved';
      }
      final counterSnapshot = await transaction.get(counterRef);
      var nextId =
          int.tryParse(counterSnapshot.data()?['next_id']?.toString() ?? '') ??
          bootstrapNextId ??
          1;
      while ((await transaction.get(collection.doc('$nextId'))).exists) {
        nextId++;
      }
      final now = DateTime.now().toUtc().toIso8601String();
      transaction.set(counterRef, {
        'next_id': nextId + 1,
        'updated_at': now,
      }, SetOptions(merge: true));
      transaction.set(idempotencyRef, {
        'kind': 'idempotency',
        'resource_key': collectionKey,
        'submission_key': normalizedKey,
        'document_id': '$nextId',
        'created_at': now,
      });
      return '$nextId';
    });
    return reservation;
  }

  Future<int?> _bootstrapNextIdIfCounterMissing({
    required DocumentReference<Map<String, dynamic>> counterRef,
    required CollectionReference<Map<String, dynamic>> collection,
  }) async {
    final counterSnapshot = await counterRef.get().timeout(
      _remoteMutationTimeout,
      onTimeout: () => throw TimeoutException('resource counter read timeout'),
    );
    final existingNextId = int.tryParse(
      counterSnapshot.data()?['next_id']?.toString() ?? '',
    );
    if (counterSnapshot.exists &&
        existingNextId != null &&
        existingNextId > 0) {
      return null;
    }
    final documents = await collection.get().timeout(
      _remoteMutationTimeout,
      onTimeout: () => throw TimeoutException('resource ID bootstrap timeout'),
    );
    final highestId = documents.docs
        .map(
          (document) =>
              int.tryParse(documentData(document)['id']?.toString() ?? ''),
        )
        .whereType<int>()
        .fold<int>(0, (highest, id) => id > highest ? id : highest);
    return highestId + 1;
  }

  String _idempotencyDocumentId(String collectionKey, String submissionKey) =>
      '${collectionKey}_${base64UrlEncode(utf8.encode(submissionKey))}';

  Future<List<OfflineMutationConflictRecord>> getBlockedConflicts() async {
    await initialize();
    final entries = await _readEntries();
    return entries
        .where((entry) => entry.isBlocked)
        .map(_conflictRecordFromEntry)
        .toList(growable: false);
  }

  Future<CatalogConflictReview> reviewCatalogConflict(String id) async {
    await initialize();
    if (!_isOnline()) {
      throw StateError('Go online to compare with the current server record.');
    }
    final storageKey = await _resolvedStorageKey();
    final entry = (await _readEntriesForStorageKey(storageKey))
        .where(
          (e) =>
              e.id == id &&
              e.isBlocked &&
              e.collectionKey == 'operations_catalog' &&
              e.kind == _OfflineMutationKind.collectionDocumentUpsert,
        )
        .firstOrNull;
    if (entry == null) {
      throw StateError(
        'This queued change is no longer available. Refresh the queue.',
      );
    }
    final ref = _firestore.collection('operations_catalog');
    final snapshot = await ref
        .doc(entry.targetId)
        .get(const GetOptions(source: Source.server))
        .timeout(_remoteMutationTimeout);
    final server = snapshot.data();
    if (server == null || server['updated_at'] == null) {
      throw StateError(
        'The server record is missing its version. Keep this action for review.',
      );
    }
    final versions = await Future.wait(
      (server['matrix_version_ids'] as List? ?? []).map(
        (id) =>
            ref.doc('matrix_$id').get(const GetOptions(source: Source.server)),
      ),
    ).timeout(_remoteMutationTimeout);
    if (versions.any((v) => !v.exists)) {
      throw StateError(
        'A server matrix version is unavailable. Try comparison again.',
      );
    }
    if (await _resolvedStorageKey() != storageKey) {
      throw StateError('The active account changed. Reopen the queue.');
    }
    final pendingVersions = <String, Map>{
      for (final v
          in (server['matrix_versions'] as List? ?? []).whereType<Map>())
        v['id'].toString(): v,
      for (final v
          in (entry.payload['matrix_versions'] as List? ?? []).whereType<Map>())
        v['id'].toString(): v,
    };
    final retainedIds = <String>{
      ...(server['matrix_version_ids'] as List? ?? []).map((v) => v.toString()),
      ...(entry.payload['matrix_version_ids'] as List? ?? []).map(
        (v) => v.toString(),
      ),
      ...pendingVersions.keys,
    }.toList();
    final proposed = {
      ...entry.payload,
      'matrix_version_ids': retainedIds,
      'matrix_versions': pendingVersions.values.toList(),
    };
    return CatalogConflictReview(
      id: id,
      storageKey: storageKey,
      pending: entry.payload,
      proposed: proposed,
      server: server,
      serverVersions: versions.map((v) => v.data()!).toList(),
    );
  }

  Future<void> applyReviewedCatalogConflict(
    CatalogConflictReview review,
  ) async {
    await initialize();
    await _serializeQueueMutation(() async {
      if (await _resolvedStorageKey() != review.storageKey) {
        throw StateError('The active account changed. Reopen the queue.');
      }
      final entries = await _readEntries();
      final index = entries.indexWhere((e) => e.id == review.id && e.isBlocked);
      if (index < 0 || !_sameDocument(entries[index].payload, review.pending)) {
        throw StateError(
          'The queued change was updated. Compare again before applying.',
        );
      }
      final snapshot = await _firestore
          .collection('operations_catalog')
          .doc(entries[index].targetId)
          .get(const GetOptions(source: Source.server))
          .timeout(_remoteMutationTimeout);
      if (!_sameDocument(snapshot.data(), review.server)) {
        throw StateError(
          'The server changed since this comparison. Compare again before applying.',
        );
      }
      entries[index] = entries[index].copyWith(
        payload: review.proposed,
        baseUpdatedAt: review.server['updated_at'].toString(),
        isBlocked: false,
        clearLastError: true,
      );
      await _writeEntries(entries);
      _setStatus(_snapshotForEntries(entries));
    });
    await flushPendingMutations();
  }

  Future<void> retryBlockedConflict(
    String conflictId, {
    bool clearBaseVersion = false,
  }) async {
    await initialize();
    return _serializeQueueMutation(() async {
      final entries = await _readEntries();
      var changed = false;
      final nextEntries = entries.map((entry) {
        if (entry.id != conflictId || !entry.isBlocked) {
          return entry;
        }
        changed = true;
        BookingIdResolver(firestore: _firestore).invalidate(entry.targetId);
        return entry.copyWith(
          isBlocked: false,
          clearBaseUpdatedAt: clearBaseVersion,
          clearLastError: true,
        );
      }).toList();
      if (!changed) {
        return;
      }
      await _writeEntries(nextEntries);
      _setStatus(_snapshotForEntries(nextEntries));
      unawaited(flushPendingMutations());
    });
  }

  Future<void> dismissBlockedConflict(String conflictId) async {
    await initialize();
    return _serializeQueueMutation(() async {
      final entries = await _readEntries();
      final nextEntries = entries
          .where((entry) => entry.id != conflictId)
          .toList(growable: false);
      if (nextEntries.length == entries.length) {
        return;
      }
      await _writeEntries(nextEntries);
      _setStatus(_snapshotForEntries(nextEntries));
    });
  }

  Future<void> initialize() async {
    await _authStorage.initialize();
    if (_isInitialized) {
      return;
    }
    await _backend.initialize();
    await _refreshStatusFromStorage();
    _retryTimer ??= Timer.periodic(_retryInterval, (_) {
      if (!isAppVisible()) return;
      unawaited(flushPendingMutations());
    });
    _networkSubscription ??= networkStatusEvents().listen((isOnline) {
      if (isOnline && isAppVisible()) {
        _traceChassis('network online event received; requesting sync flush');
        unawaited(flushPendingMutations());
      }
    });
    _isInitialized = true;
    unawaited(flushPendingMutations());
  }

  Future<void> _queueMutationTail = Future<void>.value();

  final Object _storageScopeKey = Object();

  /// Retain the initiating account through network awaits and offline fallback.
  Future<T> withAccountScope<T>(Future<T> Function() action) async {
    await _authStorage.initialize();
    final scope = await _resolvedStorageKey();
    return runZoned(action, zoneValues: {_storageScopeKey: scope});
  }

  Future<T> _serializeQueueMutation<T>(Future<T> Function() action) {
    // Capture the originating account before waiting for another local write.
    final scope = _resolvedStorageKey();
    final next = _queueMutationTail.then((_) async {
      final storageKey = await scope;
      return runZoned(action, zoneValues: {_storageScopeKey: storageKey});
    });
    _queueMutationTail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> queueUserUpsert({
    required String userId,
    required Map<String, dynamic> document,
    String? baseUpdatedAt,
  }) async {
    return queueCollectionDocumentUpsert(
      collectionKey: 'users',
      documentId: userId,
      document: document,
      baseUpdatedAt: baseUpdatedAt,
    );
  }

  Future<void> queueUserDelete({required String userId}) async {
    await initialize();
    return _serializeQueueMutation(() async {
      final entries = await _readEntries();
      // Keep the provisional create until its exact final identity is known.
      // It may already be in flight; dropping it can orphan the delete.
      entries.removeWhere(
        (entry) =>
            ((entry.collectionKey == 'users' &&
                    entry.kind ==
                        _OfflineMutationKind.collectionDocumentUpsert) ||
                entry.kind == _OfflineMutationKind.userUpsert ||
                entry.kind == _OfflineMutationKind.userDelete) &&
            entry.targetId == userId,
      );
      entries.add(
        _OfflineMutationEntry(
          id: _nextEntryId('user_delete'),
          kind: _OfflineMutationKind.userDelete,
          targetId: userId,
          payload: const <String, dynamic>{},
          createdAtIso: DateTime.now().toUtc().toIso8601String(),
          retryCount: 0,
        ),
      );
      await _writeEntries(entries);
      _setStatus(_snapshotForEntries(entries));
      unawaited(flushPendingMutations());
    });
  }

  Future<bool> hasPendingUserMutation(String userId) async {
    await initialize();
    final normalizedUserId = normalizeId(userId);
    if (normalizedUserId == null) {
      return false;
    }
    final entries = await _readEntries();
    return entries.any(
      (entry) =>
          !entry.isBlocked &&
          ((entry.collectionKey == 'users' &&
                  (entry.kind ==
                          _OfflineMutationKind.collectionDocumentUpsert ||
                      entry.kind ==
                          _OfflineMutationKind.collectionDocumentCreate)) ||
              entry.kind == _OfflineMutationKind.userUpsert ||
              entry.kind == _OfflineMutationKind.userDelete) &&
          entry.targetId == normalizedUserId,
    );
  }

  Future<bool> hasPendingChassisCreate(String documentId) async {
    await initialize();
    final entries = await _readEntries();
    return entries.any(
      (entry) =>
          entry.kind == _OfflineMutationKind.chassisAssignment &&
          entry.targetId == documentId &&
          entry.payload['provisional_create'] == true,
    );
  }

  /// A queued delivery photo may only be uploaded after its booking mutation
  /// has reached Firestore, otherwise its follow-up photo patch has no
  /// placeholder field to update.
  Future<bool> hasPendingBookingMutation(String bookingId) async {
    await initialize();
    final normalizedBookingId = normalizeId(bookingId);
    if (normalizedBookingId == null) {
      return false;
    }
    final entries = await _readEntries();
    return entries.any(
      (entry) =>
          !entry.isBlocked &&
          entry.targetId == normalizedBookingId &&
          (entry.kind == _OfflineMutationKind.bookingCreate ||
              (entry.kind == _OfflineMutationKind.collectionDocumentUpsert &&
                  entry.collectionKey == 'bookings')),
    );
  }

  Future<void> queueBookingBillingStatusUpdate({
    required String bookingId,
    required String billingStatus,
    String? baseUpdatedAt,
    DateTime? actionAt,
  }) async {
    await initialize();
    return _serializeQueueMutation(() async {
      final entries = await _readEntries();
      final previous = entries
          .where(
            (entry) =>
                entry.kind == _OfflineMutationKind.bookingBillingStatusUpdate &&
                entry.targetId == bookingId,
          )
          .firstOrNull;
      entries.removeWhere(
        (entry) =>
            entry.kind == _OfflineMutationKind.bookingBillingStatusUpdate &&
            entry.targetId == bookingId,
      );
      entries.add(
        _OfflineMutationEntry(
          id: _nextEntryId('booking_billing_status'),
          kind: _OfflineMutationKind.bookingBillingStatusUpdate,
          targetId: bookingId,
          payload: {'billing_status': billingStatus},
          baseUpdatedAt: previous != null
              ? previous.baseUpdatedAt
              : baseUpdatedAt,
          createdAtIso: (actionAt ?? DateTime.now()).toUtc().toIso8601String(),
          retryCount: 0,
        ),
      );
      await _writeEntries(entries);
      _setStatus(_snapshotForEntries(entries));
      unawaited(flushPendingMutations());
    });
  }

  Future<void> queueBookingBillingStatusUpdates(
    Map<String, String> statusesByBookingId, {
    Map<String, String?> baseUpdatedAtByBookingId = const {},
    DateTime? actionAt,
  }) async {
    await initialize();
    if (statusesByBookingId.isEmpty) {
      return;
    }
    return _serializeQueueMutation(() async {
      final entries = await _readEntries();
      final targets = statusesByBookingId.keys
          .map(normalizeId)
          .whereType<String>()
          .toSet();
      final previous = {
        for (final entry in entries)
          if (entry.kind == _OfflineMutationKind.bookingBillingStatusUpdate)
            entry.targetId: entry,
      };
      entries.removeWhere(
        (entry) =>
            entry.kind == _OfflineMutationKind.bookingBillingStatusUpdate &&
            targets.contains(entry.targetId),
      );
      final now = (actionAt ?? DateTime.now()).toUtc();
      for (final entry in statusesByBookingId.entries) {
        final normalizedId = normalizeId(entry.key);
        if (normalizedId == null) {
          continue;
        }
        entries.add(
          _OfflineMutationEntry(
            id: _nextEntryId('booking_billing_status'),
            kind: _OfflineMutationKind.bookingBillingStatusUpdate,
            targetId: normalizedId,
            payload: {'billing_status': entry.value},
            baseUpdatedAt: previous.containsKey(normalizedId)
                ? previous[normalizedId]!.baseUpdatedAt
                : baseUpdatedAtByBookingId[normalizedId],
            createdAtIso: now.toIso8601String(),
            retryCount: 0,
          ),
        );
      }
      await _writeEntries(entries);
      _setStatus(_snapshotForEntries(entries));
      unawaited(flushPendingMutations());
    });
  }

  Future<void> queueSupportThreadReadMarker({
    required String userId,
    required String threadId,
    required Map<String, dynamic> document,
  }) async {
    await initialize();
    final targetId = '$userId:$threadId';
    return _serializeQueueMutation(() async {
      final entries = await _readEntries();
      final incomingAt = DateTime.tryParse(
        document['updated_at']?.toString() ?? '',
      );
      for (final previous in entries) {
        if (previous.kind !=
                _OfflineMutationKind.supportThreadReadMarkerUpsert ||
            previous.targetId != targetId) {
          continue;
        }
        final previousDocument = previous.payload['document'];
        final previousAt = previousDocument is Map
            ? DateTime.tryParse(
                previousDocument['updated_at']?.toString() ?? '',
              )
            : null;
        if (previousAt != null &&
            (incomingAt == null || !incomingAt.isAfter(previousAt))) {
          return;
        }
      }
      entries.removeWhere(
        (entry) =>
            entry.kind == _OfflineMutationKind.supportThreadReadMarkerUpsert &&
            entry.targetId == targetId,
      );
      entries.add(
        _OfflineMutationEntry(
          id: _nextEntryId('support_read_marker'),
          kind: _OfflineMutationKind.supportThreadReadMarkerUpsert,
          targetId: targetId,
          payload: {
            'user_id': userId,
            'thread_id': threadId,
            'document': document,
          },
          createdAtIso: DateTime.now().toUtc().toIso8601String(),
          retryCount: 0,
        ),
      );
      await _writeEntries(entries);
      _setStatus(_snapshotForEntries(entries));
      unawaited(flushPendingMutations());
    });
  }

  /// Returns false only when the write needs the durable offline queue.
  /// Foreground writes use the same version/identity checks without emitting
  /// queue progress or completing before the server acknowledges the write.
  Future<bool> tryWriteCollectionDocumentOnline({
    required String collectionKey,
    required String documentId,
    required Map<String, dynamic> document,
    String? baseUpdatedAt,
  }) async {
    if (!_isOnline() ||
        documentId.startsWith('offline_') ||
        documentId.startsWith('-') ||
        OfflineReferenceMapper.hasTemporaryReferences(document)) {
      return false;
    }
    await initialize();
    final entries = await _readEntries();
    if (entries.any(
      (entry) =>
          entry.targetId == documentId && entry.collectionKey == collectionKey,
    )) {
      return false;
    }
    if (collectionKey != 'bookings' &&
        _collectionForKey(collectionKey) == null) {
      throw StateError('Unsupported collection: $collectionKey');
    }
    final entry = _OfflineMutationEntry(
      id: _nextEntryId('foreground'),
      kind: _OfflineMutationKind.collectionDocumentUpsert,
      targetId: documentId,
      collectionKey: collectionKey,
      payload: document,
      baseUpdatedAt: baseUpdatedAt,
      createdAtIso: DateTime.now().toUtc().toIso8601String(),
      retryCount: 0,
    );
    try {
      if (collectionKey == 'bookings') {
        await _applyQueuedBookingUpsert(entry);
      } else {
        await _applyVersionedUpsert(_collectionForKey(collectionKey)!, entry);
      }
    } catch (error, stack) {
      unawaited(
        SyncErrorLogService.instance.report(
          error,
          stack,
          source: 'offline_mutation_queue_service.dart',
          operation: 'foreground upsert',
          target: '$collectionKey/$documentId',
          owner: (await _resolvedStorageKey()).substring(
            '$_storageKey::'.length,
          ),
          details: {
            'base_updated_at': baseUpdatedAt,
            'payload_keys': document.keys.toList(),
          },
        ),
      );
      if (!_isOnline() ||
          error is TimeoutException ||
          (error is FirebaseException &&
              const {
                'unavailable',
                'deadline-exceeded',
                'network-request-failed',
              }.contains(error.code))) {
        return false;
      }
      rethrow;
    }
    unawaited(_publishCollectionVersion(collectionKey));
    if (collectionKey == 'bookings') {
      unawaited(_publishCollectionVersion('chassis'));
    }
    return true;
  }

  Future<bool> saveCollectionDocumentOnlineFirst({
    required String collectionKey,
    required String documentId,
    required Map<String, dynamic> document,
    String? baseUpdatedAt,
  }) => withAccountScope(() async {
    if (await tryWriteCollectionDocumentOnline(
      collectionKey: collectionKey,
      documentId: documentId,
      document: document,
      baseUpdatedAt: baseUpdatedAt,
    )) {
      return true;
    }
    await queueCollectionDocumentUpsert(
      collectionKey: collectionKey,
      documentId: documentId,
      document: document,
      baseUpdatedAt: baseUpdatedAt,
    );
    return false;
  });

  Future<void> queueCollectionDocumentUpsert({
    required String collectionKey,
    required String documentId,
    required Map<String, dynamic> document,
    String? baseUpdatedAt,
  }) async {
    await initialize();
    return _serializeQueueMutation(() async {
      final entries = await _readEntries();
      final queuedBookingCreateIndex = collectionKey == 'bookings'
          ? entries.indexWhere(
              (entry) =>
                  entry.kind == _OfflineMutationKind.bookingCreate &&
                  entry.targetId == documentId,
            )
          : -1;
      final queuedCollectionCreateIndex = entries.indexWhere(
        (entry) =>
            entry.kind == _OfflineMutationKind.collectionDocumentCreate &&
            entry.collectionKey == collectionKey &&
            entry.targetId == documentId,
      );
      if (queuedBookingCreateIndex >= 0) {
        final queuedCreate = entries[queuedBookingCreateIndex];
        entries[queuedBookingCreateIndex] = _OfflineMutationEntry(
          id: queuedCreate.id,
          kind: queuedCreate.kind,
          targetId: queuedCreate.targetId,
          collectionKey: queuedCreate.collectionKey,
          payload: Map<String, dynamic>.from(document)
            ..['id'] = queuedCreate.targetId
            ..['submission_key'] = queuedCreate.payload['submission_key'],
          createdAtIso: queuedCreate.createdAtIso,
          retryCount: queuedCreate.retryCount,
          isBlocked: queuedCreate.isBlocked,
          lastError: queuedCreate.lastError,
        );
        await _writeEntries(entries);
        _setStatus(_snapshotForEntries(entries));
        unawaited(flushPendingMutations());
        return;
      }
      if (queuedCollectionCreateIndex >= 0) {
        final queuedCreate = entries[queuedCollectionCreateIndex];
        entries[queuedCollectionCreateIndex] = queuedCreate.copyWith(
          payload: Map<String, dynamic>.from(document)
            ..['id'] = queuedCreate.targetId
            ..['submission_key'] = queuedCreate.payload['submission_key'],
        );
        await _writeEntries(entries);
        _setStatus(_snapshotForEntries(entries));
        unawaited(flushPendingMutations());
        return;
      }
      final previous = entries
          .where(
            (entry) =>
                (entry.kind == _OfflineMutationKind.collectionDocumentUpsert ||
                    (collectionKey == 'users' &&
                        entry.kind == _OfflineMutationKind.userUpsert)) &&
                (entry.collectionKey == collectionKey ||
                    (collectionKey == 'users' &&
                        entry.kind == _OfflineMutationKind.userUpsert)) &&
                entry.targetId == documentId,
          )
          .firstOrNull;
      entries.removeWhere(
        (entry) =>
            (entry.kind == _OfflineMutationKind.collectionDocumentUpsert ||
                (collectionKey == 'users' &&
                    entry.kind == _OfflineMutationKind.userUpsert)) &&
            (entry.collectionKey == collectionKey ||
                (collectionKey == 'users' &&
                    entry.kind == _OfflineMutationKind.userUpsert)) &&
            entry.targetId == documentId,
      );
      entries.add(
        _OfflineMutationEntry(
          id: _nextEntryId('vehicle_upsert'),
          kind: _OfflineMutationKind.collectionDocumentUpsert,
          targetId: documentId,
          collectionKey: collectionKey,
          payload: document,
          catalogPredecessorVersions:
              collectionKey == 'operations_catalog' &&
                  previous != null &&
                  baseUpdatedAt != null &&
                  baseUpdatedAt == previous.payload['updated_at']
              ? [...previous.catalogPredecessorVersions, baseUpdatedAt]
              : const [],
          baseUpdatedAt: previous != null
              ? previous.baseUpdatedAt
              : baseUpdatedAt,
          createdAtIso: DateTime.now().toUtc().toIso8601String(),
          retryCount: 0,
        ),
      );
      await _writeEntries(entries);
      _setStatus(_snapshotForEntries(entries));
      unawaited(flushPendingMutations());
    });
  }

  /// Stores one offline create attempt. Its final numeric ID is reserved only
  /// when Firestore is reachable again.
  Future<void> queueOfflineCollectionDocumentCreate({
    required String collectionKey,
    required String provisionalId,
    required String submissionKey,
    required Map<String, dynamic> document,
  }) async {
    await initialize();
    return _serializeQueueMutation(() async {
      final entries = await _readEntries();
      entries.removeWhere(
        (entry) =>
            entry.kind == _OfflineMutationKind.collectionDocumentCreate &&
            entry.collectionKey == collectionKey &&
            entry.targetId == provisionalId,
      );
      entries.add(
        _OfflineMutationEntry(
          id: _nextEntryId('collection_create'),
          kind: _OfflineMutationKind.collectionDocumentCreate,
          targetId: provisionalId,
          collectionKey: collectionKey,
          payload: Map<String, dynamic>.from(document)
            ..['id'] = provisionalId
            ..['submission_key'] =
                'offline_resource:$collectionKey:$provisionalId',
          createdAtIso: DateTime.now().toUtc().toIso8601String(),
          retryCount: 0,
        ),
      );
      await _writeEntries(entries);
      _setStatus(_snapshotForEntries(entries));
      unawaited(flushPendingMutations());
    });
  }

  String createOfflineProvisionalId(String collectionKey) {
    final normalizedKey = collectionKey.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomSuffix = Random().nextInt(0x100000000).toRadixString(16);
    return 'offline_${normalizedKey}_${timestamp}_$randomSuffix';
  }

  /// Queues a new booking without reserving a numeric ID while offline.
  /// The reconnect transaction assigns the next free ID atomically.
  Future<void> queueOfflineBookingCreate({
    required String provisionalId,
    required String submissionKey,
    required Map<String, dynamic> document,
  }) async {
    _log('booking create queue start id=$provisionalId');
    await _localStorageOperation('booking create initialize', initialize);
    return _serializeQueueMutation(() async {
      final entries = await _localStorageOperation(
        'booking create read',
        _readEntries,
      );
      entries.removeWhere(
        (entry) =>
            entry.kind == _OfflineMutationKind.bookingCreate &&
            entry.payload['submission_key']?.toString() == submissionKey,
      );
      entries.add(
        _OfflineMutationEntry(
          id: _nextEntryId('booking_create'),
          kind: _OfflineMutationKind.bookingCreate,
          targetId: provisionalId,
          collectionKey: 'bookings',
          payload: Map<String, dynamic>.from(document)
            ..['id'] = provisionalId
            ..['submission_key'] = submissionKey,
          createdAtIso: DateTime.now().toUtc().toIso8601String(),
          retryCount: 0,
        ),
      );
      await _localStorageOperation(
        'booking create write entries=${entries.length}',
        () => _writeEntries(entries),
      );
      _setStatus(_snapshotForEntries(entries));
      _log('booking create queue persisted id=$provisionalId');
      unawaited(flushPendingMutations());
    });
  }

  /// Queues a chassis save with its booking assignment as one reconnect
  /// transaction. This preserves the relationship even when created offline.
  Future<void> queueChassisAssignment({
    required String documentId,
    required String submissionKey,
    required Map<String, dynamic> chassisDocument,
    required String? previousBookingId,
    required String? nextBookingId,
    required bool isProvisionalCreate,
    String? baseUpdatedAt,
  }) async {
    _traceChassis('queue initialize start documentId=$documentId');
    await initialize();
    _traceChassis('queue initialize done documentId=$documentId');
    _traceChassis(
      'queue start documentId=$documentId bookingId=${nextBookingId ?? '-'}',
    );
    return _serializeQueueMutation(() async {
      final entries = await _readEntries();
      final previous = entries
          .where(
            (entry) =>
                entry.kind == _OfflineMutationKind.chassisAssignment &&
                entry.targetId == documentId,
          )
          .firstOrNull;
      entries.removeWhere(
        (entry) =>
            entry.kind == _OfflineMutationKind.chassisAssignment &&
            entry.targetId == documentId,
      );
      entries.add(
        _OfflineMutationEntry(
          id: _nextEntryId('chassis_assignment'),
          kind: _OfflineMutationKind.chassisAssignment,
          targetId: documentId,
          collectionKey: 'chassis',
          baseUpdatedAt: previous != null
              ? previous.baseUpdatedAt
              : baseUpdatedAt,
          payload: <String, dynamic>{
            'chassis': Map<String, dynamic>.from(chassisDocument),
            'submission_key': submissionKey,
            'previous_booking_id': previous != null
                ? previous.payload['previous_booking_id']
                : previousBookingId,
            'next_booking_id': nextBookingId,
            'booking_link_ids': <String>{
              ...?((previous?.payload['booking_link_ids'] as List?)?.map(
                (id) => '$id',
              )),
              if (previous?.payload['next_booking_id'] case final String id
                  when id.isNotEmpty)
                id,
              if (nextBookingId != null && nextBookingId.isNotEmpty)
                nextBookingId,
            }.toList(),
            'provisional_create':
                previous?.payload['provisional_create'] == true ||
                isProvisionalCreate,
          },
          createdAtIso: DateTime.now().toUtc().toIso8601String(),
          retryCount: 0,
        ),
      );
      await _writeEntries(entries);
      _setStatus(_snapshotForEntries(entries));
      _traceChassis(
        'queue persisted documentId=$documentId pending=${_snapshotForEntries(entries).pendingCount}',
      );
      unawaited(flushPendingMutations());
    });
  }

  Future<void> queueChassisDelete({
    required String documentId,
    required String? bookingId,
  }) async {
    await initialize();
    return _serializeQueueMutation(() async {
      final entries = await _readEntries();
      final requiresCreateResolution = entries.any(
        (entry) =>
            entry.kind == _OfflineMutationKind.chassisAssignment &&
            entry.targetId == documentId &&
            entry.payload['provisional_create'] == true,
      );
      entries.removeWhere(
        (entry) =>
            ((entry.kind == _OfflineMutationKind.chassisAssignment &&
                    entry.payload['provisional_create'] != true) ||
                entry.kind == _OfflineMutationKind.chassisDelete) &&
            entry.targetId == documentId,
      );
      entries.add(
        _OfflineMutationEntry(
          id: _nextEntryId('chassis_delete'),
          kind: _OfflineMutationKind.chassisDelete,
          targetId: documentId,
          collectionKey: 'chassis',
          payload: <String, dynamic>{
            'booking_id': bookingId,
            'requires_create_resolution': requiresCreateResolution,
          },
          createdAtIso: DateTime.now().toUtc().toIso8601String(),
          retryCount: 0,
        ),
      );
      await _writeEntries(entries);
      _setStatus(_snapshotForEntries(entries));
      unawaited(flushPendingMutations());
    });
  }

  Future<void> queueCollectionDocumentDelete({
    required String collectionKey,
    required String documentId,
  }) async {
    await initialize();
    return _serializeQueueMutation(() async {
      final entries = await _readEntries();
      final queuedBookingCreate =
          collectionKey == 'bookings' &&
          entries.any(
            (entry) =>
                entry.kind == _OfflineMutationKind.bookingCreate &&
                entry.targetId == documentId,
          );
      if (queuedBookingCreate) {
        entries.removeWhere(
          (entry) =>
              entry.kind == _OfflineMutationKind.bookingCreate &&
              entry.targetId == documentId,
        );
        await _writeEntries(entries);
        _setStatus(_snapshotForEntries(entries));
        return;
      }
      entries.removeWhere(
        (entry) =>
            (entry.kind == _OfflineMutationKind.collectionDocumentUpsert ||
                entry.kind == _OfflineMutationKind.collectionDocumentDelete) &&
            entry.collectionKey == collectionKey &&
            entry.targetId == documentId,
      );
      entries.add(
        _OfflineMutationEntry(
          id: _nextEntryId('vehicle_delete'),
          kind: _OfflineMutationKind.collectionDocumentDelete,
          targetId: documentId,
          collectionKey: collectionKey,
          payload: const <String, dynamic>{},
          createdAtIso: DateTime.now().toUtc().toIso8601String(),
          retryCount: 0,
        ),
      );
      await _writeEntries(entries);
      _setStatus(_snapshotForEntries(entries));
      unawaited(flushPendingMutations());
    });
  }

  Future<List<Map<String, dynamic>>> readQueuedCollectionDocuments({
    required String collectionKey,
  }) async {
    await initialize();
    final normalizedCollectionKey = collectionKey.trim();
    final entries = await _readEntries();
    return entries
        .where((entry) => !entry.isBlocked)
        .where(
          (entry) =>
              (entry.kind == _OfflineMutationKind.collectionDocumentUpsert ||
                  entry.kind == _OfflineMutationKind.collectionDocumentCreate ||
                  entry.kind == _OfflineMutationKind.bookingCreate ||
                  entry.kind == _OfflineMutationKind.chassisAssignment) &&
              entry.collectionKey == normalizedCollectionKey,
        )
        .map((entry) {
          final source = entry.kind == _OfflineMutationKind.chassisAssignment
              ? entry.payload['chassis']
              : entry.payload;
          final document = source is Map
              ? Map<String, dynamic>.from(source)
              : <String, dynamic>{};
          document['local_sync_status'] =
              document['local_sync_status']?.toString().trim().isNotEmpty ==
                  true
              ? document['local_sync_status']
              : 'queued';
          document['queued_entry_id'] = entry.id;
          document['queued_created_at'] = entry.createdAtIso;
          return document;
        })
        .toList(growable: false);
  }

  Future<Set<String>> readQueuedCollectionDocumentDeleteIds({
    required String collectionKey,
  }) async {
    await initialize();
    final normalizedCollectionKey = collectionKey.trim();
    final entries = await _readEntries();
    return entries
        .where((entry) => !entry.isBlocked)
        .where(
          (entry) =>
              entry.collectionKey == normalizedCollectionKey &&
              (entry.kind == _OfflineMutationKind.collectionDocumentDelete ||
                  entry.kind == _OfflineMutationKind.chassisDelete),
        )
        .map((entry) => entry.targetId)
        .toSet();
  }

  Future<void> queueRoleAccessUpsert({
    required String roleKey,
    required Map<String, dynamic> document,
    String? baseUpdatedAt,
  }) {
    return queueCollectionDocumentUpsert(
      collectionKey: 'role_access',
      documentId: roleKey,
      document: document,
      baseUpdatedAt: baseUpdatedAt,
    );
  }

  Future<void> flushPendingMutations() async {
    await initialize();
    final activeFlush = _flushFuture;
    if (activeFlush != null) {
      return activeFlush;
    }
    if (!_isOnline()) {
      return;
    }

    final flush = _flushPendingMutationsInternal();
    _flushFuture = flush;
    try {
      await flush;
    } finally {
      if (identical(_flushFuture, flush)) {
        _flushFuture = null;
      }
    }
  }

  Future<void> _flushPendingMutationsInternal() async {
    _markPendingAsSyncing();
    try {
      final currentStorageKey = await _resolvedStorageKey();
      final storageKeys = await _allKnownStorageKeys();
      for (final storageKey in storageKeys) {
        await _flushPendingMutationsForStorageKey(
          storageKey,
          updateStatus: storageKey == currentStorageKey,
        );
      }
      await _refreshStatusFromStorage();
    } finally {
      if (_currentStatus.isSyncing) {
        _setStatus(
          _currentStatus.copyWith(
            isSyncing: false,
            processedInBatch: 0,
            totalInBatch: 0,
          ),
        );
      }
    }
  }

  Future<_OfflineMutationEntry> _resolveBookingReferences(
    _OfflineMutationEntry entry,
  ) async {
    final resolver = BookingIdResolver(firestore: _firestore);
    var targetId = entry.targetId;
    final payload = Map<String, dynamic>.from(entry.payload);
    final isBookingTarget =
        entry.collectionKey == 'bookings' ||
        entry.kind == _OfflineMutationKind.bookingBillingStatusUpdate;
    if (isBookingTarget &&
        entry.kind != _OfflineMutationKind.bookingCreate &&
        BookingIdResolver.isTemporary(targetId)) {
      if (entry.kind == _OfflineMutationKind.collectionDocumentDelete) {
        throw StateError(
          'Sync conflict: deleting a temporary copy cannot delete its confirmed booking. Review the canonical record.',
        );
      }
      final resolved = await resolver.resolve(
        targetId,
        submissionKey: payload['submission_key']?.toString(),
      );
      if (resolved == null) {
        throw StateError(
          'Booking identity is temporarily unavailable. Try again after its create syncs.',
        );
      }
      if (entry.kind == _OfflineMutationKind.collectionDocumentUpsert &&
          (entry.baseUpdatedAt == null ||
              entry.baseUpdatedAt!.isEmpty ||
              payload['submission_key']?.toString().trim().isNotEmpty !=
                  true)) {
        throw StateError(
          'Sync conflict: pending booking edit has no verified submission key or original version. Review before applying.',
        );
      }
      targetId = resolved;
      if (entry.collectionKey == 'bookings') payload['id'] = resolved;
    }
    Future<Object?> resolveReference(Object? value) async {
      final id = value?.toString();
      if (id == null || !BookingIdResolver.isTemporary(id)) return value;
      final resolved = await resolver.resolve(id);
      if (resolved == null) {
        throw StateError(
          'Booking reference is temporarily unavailable. Try again after sync.',
        );
      }
      return resolved;
    }

    for (final key in [
      'booking_id',
      'current_booking_id',
      'next_booking_id',
      'previous_booking_id',
    ]) {
      if (payload.containsKey(key)) {
        payload[key] = await resolveReference(payload[key]);
      }
    }
    if (payload['booking_link_ids'] is List) {
      payload['booking_link_ids'] = await Future.wait(
        (payload['booking_link_ids'] as List).map(resolveReference),
      );
    }
    if (payload['chassis'] is Map) {
      final chassis = Map<String, dynamic>.from(payload['chassis'] as Map);
      if (chassis.containsKey('current_booking_id')) {
        chassis['current_booking_id'] = await resolveReference(
          chassis['current_booking_id'],
        );
      }
      payload['chassis'] = chassis;
    }
    return entry.copyWith(targetId: targetId, payload: payload);
  }

  Future<String?> _applyEntry(_OfflineMutationEntry entry, String scope) async {
    switch (entry.kind) {
      case _OfflineMutationKind.userUpsert:
        await _applyVersionedUpsert(_usersCollection, entry);
        await _publishCollectionVersion('users');
        return null;
      case _OfflineMutationKind.userDelete:
        await _applyUserDelete(entry, scope);
        await _publishCollectionVersion('users');
        return null;
      case _OfflineMutationKind.bookingBillingStatusUpdate:
        final nextStatus = entry.payload['billing_status']?.toString();
        if (nextStatus == null || nextStatus.trim().isEmpty) {
          return null;
        }
        await _applyVersionedUpsert(
          _bookingsCollection,
          entry,
          patch: {
            'billing_status': nextStatus.trim(),
            'updated_at': entry.createdAtIso,
          },
        );
        await _publishCollectionVersion('bookings');
        return null;
      case _OfflineMutationKind.supportThreadReadMarkerUpsert:
        final userId = normalizeId(entry.payload['user_id']?.toString());
        final threadId = normalizeId(entry.payload['thread_id']?.toString());
        final document = entry.payload['document'];
        if (userId == null || threadId == null || document is! Map) {
          return null;
        }
        await writeSupportReadMarker(
          _firestore,
          _firestore
              .collection('support_read_markers')
              .doc(userId)
              .collection('threads')
              .doc(threadId),
          Map<String, dynamic>.from(document),
        );
        return null;
      case _OfflineMutationKind.bookingCreate:
        final finalId = await _applyOfflineBookingCreate(entry);
        BookingIdResolver(firestore: _firestore).invalidate(entry.targetId);
        await _publishCollectionVersion('bookings');
        if (normalizeId(entry.payload['chassis_id']?.toString()) != null) {
          await _publishCollectionVersion('chassis');
        }
        return finalId;
      case _OfflineMutationKind.chassisAssignment:
        return _applyChassisAssignment(entry);
      case _OfflineMutationKind.chassisDelete:
        await _applyChassisDelete(entry);
        return null;
      case _OfflineMutationKind.collectionDocumentCreate:
        final resolvedId = await _applyOfflineCollectionDocumentCreate(entry);
        await _publishCollectionVersion(entry.collectionKey);
        return resolvedId;
      case _OfflineMutationKind.collectionDocumentUpsert:
        if (entry.collectionKey == 'bookings') {
          await _applyQueuedBookingUpsert(entry);
          await _publishCollectionVersion('bookings');
          await _publishCollectionVersion('chassis');
          return null;
        }
        final collection = _collectionForKey(entry.collectionKey);
        if (collection == null) {
          return null;
        }
        await _applyVersionedUpsert(collection, entry);
        await _publishCollectionVersion(entry.collectionKey);
        return null;
      case _OfflineMutationKind.collectionDocumentDelete:
        final collection = _collectionForKey(entry.collectionKey);
        if (collection == null) {
          return null;
        }
        await collection.doc(entry.targetId).delete();
        await _publishCollectionVersion(entry.collectionKey);
        return null;
    }
  }

  Future<void> _applyUserDelete(
    _OfflineMutationEntry entry,
    String scope,
  ) async {
    final userId = entry.targetId;
    final members = _firestore.collection('client_members');
    final matches = await members.where('user_id', isEqualTo: userId).get();
    final refs = <String, DocumentReference<Map<String, dynamic>>>{
      for (final doc in matches.docs) doc.id: doc.reference,
      userId: members.doc(userId),
    }.values.toList();
    // Bound transaction size, and recheck membership ownership inside each one.
    for (var offset = 0; offset < refs.length; offset += 100) {
      final chunk = refs.skip(offset).take(100).toList();
      await _firestore.runTransaction((tx) async {
        final snapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final ref in chunk) {
          snapshots.add(await tx.get(ref));
        }
        for (final doc in snapshots) {
          final owner = doc.data()?['user_id']?.toString();
          if (doc.exists &&
              (owner == userId || (doc.id == userId && owner == null))) {
            tx.delete(doc.reference);
          }
        }
      });
    }
    await _usersCollection.doc(userId).delete();
    // Keep the mutation pending if durable cleanup handoff fails. Retrying the
    // document deletions is safe; do not acknowledge before this handoff.
    await _queueUserAssetCleanup(
      userId,
      scope,
      DateTime.tryParse(entry.createdAtIso) ?? DateTime.now().toUtc(),
    );
    await _publishCollectionVersion('client_members');
  }

  Future<void> _applyVersionedUpsert(
    CollectionReference<Map<String, dynamic>> collection,
    _OfflineMutationEntry entry, {
    Map<String, dynamic>? patch,
  }) async {
    final document = patch ?? entry.payload;
    await runTransactionWithOriginalErrors(_firestore, (tx) async {
      final ref = collection.doc(entry.targetId);
      final existing = await tx.get(ref);
      final base = _parseSyncTimestamp(entry.baseUpdatedAt);
      final remote = _parseSyncTimestamp(
        existing.data()?['updated_at']?.toString(),
      );
      final next = _parseSyncTimestamp(document['updated_at']?.toString());
      // KPI day IDs are deterministic. Concurrent first-time entries must
      // not overwrite another manager's confirmed record.
      if (const {
            'pm_kpi_records',
            'pm_fuel_entries',
            'operations_catalog',
          }.contains(collection.path) &&
          existing.exists &&
          base == null &&
          remote != next) {
        throw StateError(
          'Sync conflict: ${collection.path}/${entry.targetId} already exists. '
          'This queued change has no original server version. Review before replacing.',
        );
      }
      if (!existing.exists && (base != null || patch != null)) {
        throw StateError(
          'Sync conflict: record was deleted. Pending edit was preserved.',
        );
      }
      if (base != null &&
          remote != null &&
          (collection.path == 'operations_catalog'
              ? remote != base
              : remote.isAfter(base)) &&
          remote != next) {
        throw StateError(
          'Sync conflict: ${collection.path}/${entry.targetId} changed remotely. '
          'Original version: ${entry.baseUpdatedAt}; server version: ${existing.data()?['updated_at']}. '
          'Pending edit was preserved.',
        );
      }
      final catalogVersions = <Map<String, dynamic>>[];
      if (collection.path == 'operations_catalog' &&
          document['matrix_versions'] is List) {
        for (final raw in document['matrix_versions'] as List) {
          if (raw is! Map) {
            throw StateError('Invalid trip matrix snapshot.');
          }
          final version = Map<String, dynamic>.from(raw);
          final id = version['id']?.toString() ?? '';
          if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
            throw StateError('Invalid trip matrix version ID.');
          }
          final snapshot = await tx.get(collection.doc('matrix_$id'));
          if (snapshot.exists && !_sameDocument(snapshot.data(), version)) {
            throw StateError(
              'Sync conflict: trip matrix version $id already exists with different contents.',
            );
          }
          catalogVersions.add(version);
        }
      }
      for (final version in catalogVersions) {
        tx.set(collection.doc('matrix_${version['id']}'), version);
      }
      if (patch != null) {
        tx.update(ref, patch);
      } else {
        final receipts = existing.data()?['offline_photo_uploads'];
        tx.set(ref, {
          for (final e in document.entries)
            if (collection.path != 'operations_catalog' ||
                e.key != 'matrix_versions')
              e.key: e.value,
          if (collection.path == 'users' && receipts is Map)
            'offline_photo_uploads': receipts,
        });
      }
    }).timeout(_remoteMutationTimeout);
  }

  Future<void> _publishCollectionVersion(String? collectionKey) async {
    final normalizedKey = collectionKey?.trim();
    if (normalizedKey == null || normalizedKey.isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _firestore
          .collection('manage_cache')
          .doc(normalizedKey)
          .set({'version': now, 'updated_at': now}, SetOptions(merge: true))
          .timeout(_remoteMutationTimeout);
    } catch (error, stack) {
      unawaited(
        SyncErrorLogService.instance.report(
          error,
          stack,
          source: 'offline_mutation_queue_service.dart',
          operation: 'publish cache version',
          target: 'manage_cache/$normalizedKey',
          kind: 'cache_notification_failure',
          details: {'business_write_committed': true},
        ),
      );
      // The primary mutation has already succeeded. A later refresh still
      // reconciles clients if the optional cross-device signal cannot publish.
    }
  }

  Future<void> _applyQueuedBookingUpsert(_OfflineMutationEntry entry) async {
    // The transaction below validates the server version and identity atomically.
    // A separate unbounded get() can stall after reconnect before the transaction
    // timeout even starts; it adds no conflict protection to this write.
    final document = Map<String, dynamic>.from(entry.payload)
      ..['id'] = entry.targetId
      ..remove('local_sync_status');
    await runTransactionWithOriginalErrors(_firestore, (transaction) async {
      final bookingRef = _bookingsCollection.doc(entry.targetId);
      final existingBooking = await transaction.get(bookingRef);
      final expectedKey = document['submission_key'];
      if (expectedKey != null &&
          entry.baseUpdatedAt != null &&
          !existingBooking.exists) {
        throw StateError(
          'Sync conflict: the booking was removed before applying the pending edit.',
        );
      }
      if (expectedKey != null &&
          existingBooking.exists &&
          existingBooking.data()?['submission_key'] != expectedKey) {
        throw StateError(
          'Sync conflict: booking identity changed before applying the edit.',
        );
      }
      final remoteVersion = _parseSyncTimestamp(
        existingBooking.data()?['updated_at']?.toString(),
      );
      final baseVersion = _parseSyncTimestamp(entry.baseUpdatedAt);
      final nextVersion = _parseSyncTimestamp(
        document['updated_at']?.toString(),
      );
      if (remoteVersion != null &&
          baseVersion != null &&
          remoteVersion.isAfter(baseVersion) &&
          remoteVersion != nextVersion) {
        final serverContents =
            Map<String, dynamic>.from(existingBooking.data()!)
              ..remove('updated_at')
              ..remove('local_sync_status');
        final pendingContents = Map<String, dynamic>.from(document)
          ..remove('updated_at');
        if (_sameDocument(serverContents, pendingContents)) {
          // Already reflected on the server. Do not replay chassis transitions
          // or replace the server's timestamp with the old action timestamp.
          return;
        }
        throw OfflineSyncConflict(
          'Sync conflict: booking changed remotely before applying this edit.',
          {
            'base_updated_at': entry.baseUpdatedAt,
            'server_updated_at': existingBooking
                .data()?['updated_at']
                ?.toString(),
            'pending_updated_at': document['updated_at']?.toString(),
            'server_document': existingBooking.data(),
            'server_status': existingBooking.data()?['client_status'],
            'pending_status': document['client_status'],
            'differing_fields': [
              for (final key in {
                ...?existingBooking.data()?.keys,
                ...document.keys,
              })
                if (!_sameDocument(existingBooking.data()?[key], document[key]))
                  key,
            ],
          },
        );
      }
      final previousChassisId = normalizeId(
        existingBooking.data()?['chassis_id']?.toString(),
      );
      final nextChassisId = normalizeId(document['chassis_id']?.toString());
      final lifecycle = chassisLifecycleInstruction(
        previousBookingStatus: existingBooking
            .data()?['client_status']
            ?.toString(),
        nextBookingStatus: document['client_status']?.toString(),
        bookingDocument: document,
      );

      DocumentSnapshot<Map<String, dynamic>>? nextChassis;
      DocumentSnapshot<Map<String, dynamic>>? previousChassis;
      if (previousChassisId != null && previousChassisId != nextChassisId) {
        previousChassis = await transaction.get(
          _firestore.collection('chassis').doc(previousChassisId),
        );
      }
      if (nextChassisId != null) {
        nextChassis = await transaction.get(
          _firestore.collection('chassis').doc(nextChassisId),
        );
        if (!nextChassis.exists && lifecycle?.keepBookingLink != false) {
          throw StateError('The selected chassis no longer exists.');
        }
        final ownerId = normalizeId(
          nextChassis.data()?['current_booking_id']?.toString(),
        );
        final ownerBooking = ownerId != null && ownerId != entry.targetId
            ? (await transaction.get(_bookingsCollection.doc(ownerId))).data()
            : null;
        if (!shouldProjectBookingOntoChassis(
          bookingId: entry.targetId,
          booking: document,
          chassis: nextChassis.data() ?? {},
          ownerBooking: ownerBooking,
        )) {
          nextChassis = null;
        }
      }

      final now = document['updated_at']?.toString() ?? entry.createdAtIso;
      if (previousChassisId != null &&
          previousChassisId != nextChassisId &&
          normalizeId(
                previousChassis?.data()?['current_booking_id']?.toString(),
              ) ==
              entry.targetId) {
        transaction
            .set(_firestore.collection('chassis').doc(previousChassisId), {
              'current_booking_id': FieldValue.delete(),
              'current_driver_id': FieldValue.delete(),
              'current_status': 'ready',
              'updated_at': now,
            }, SetOptions(merge: true));
      }
      if (nextChassis != null) {
        transaction.set(
          nextChassis.reference,
          lifecycle == null
              ? _defaultChassisAssignmentPatch(
                  bookingId: entry.targetId,
                  bookingDocument: document,
                  now: now,
                )
              : _lifecycleChassisPatch(
                  instruction: lifecycle,
                  bookingId: entry.targetId,
                  bookingDocument: document,
                  now: now,
                ),
          SetOptions(merge: true),
        );
      }
      BookingPhotoCleanup.prepare(document, existingBooking.data());
      transaction.set(bookingRef, document);
    }).timeout(
      _remoteMutationTimeout,
      onTimeout: () => throw TimeoutException(
        'queued bookings write timeout for ${entry.targetId}',
      ),
    );
    BookingPhotoCleanup.schedule(entry.targetId, document);
  }

  Future<String> _applyOfflineBookingCreate(
    _OfflineMutationEntry entry, {
    Map<String, dynamic>? linkedChassis,
    String? linkedChassisSubmissionKey,
  }) async {
    final submissionKey = entry.payload['submission_key']?.toString().trim();
    if (submissionKey == null || submissionKey.isEmpty) {
      throw StateError(
        'Sync conflict: queued booking is missing its submission key.',
      );
    }

    final bootstrapNextId = await _bootstrapNextIdIfCounterMissing(
      counterRef: _bookingsCounterRef,
      collection: _bookingsCollection,
    );
    return await runTransactionWithOriginalErrors<String>(_firestore, (
      transaction,
    ) async {
      final repair = await transaction.get(
        _firestore.collection('booking_id_repairs').doc(entry.targetId),
      );
      if (repair.data()?['resolution'] == 'keep_both_new_id') {
        throw StateError(
          'Sync conflict: this offline booking was preserved under a new ID. Refresh and review this pending create.',
        );
      }
      final idempotencyRef = _idManagementCollection.doc(
        _idempotencyDocumentId('bookings', submissionKey),
      );
      final idempotencySnapshot = await transaction.get(idempotencyRef);
      final existingId = int.tryParse(
        idempotencySnapshot.data()?['document_id']?.toString() ?? '',
      );

      if (BookingIdResolver.temporaryId(submissionKey) != entry.targetId) {
        throw StateError(
          'Sync conflict: offline booking identity is inconsistent.',
        );
      }
      if (idempotencySnapshot.exists &&
          (idempotencySnapshot.data()?['resource_key'] != 'bookings' ||
              idempotencySnapshot.data()?['submission_key'] != submissionKey ||
              existingId == null ||
              existingId <= 0)) {
        throw StateError(
          'Sync conflict: booking reservation identity is inconsistent.',
        );
      }
      final counterSnapshot = await transaction.get(_bookingsCounterRef);
      var nextId =
          int.tryParse(counterSnapshot.data()?['next_id']?.toString() ?? '') ??
          bootstrapNextId ??
          1;
      if (existingId != null && existingId > 0) {
        nextId = existingId;
      } else {
        // Older deployments may not have a counter yet. Avoid overwriting an
        // existing numeric booking while establishing the counter.
        while ((await transaction.get(
          _bookingsCollection.doc('$nextId'),
        )).exists) {
          nextId++;
        }
      }

      final finalId = '$nextId';
      final existingBooking = await transaction.get(
        _bookingsCollection.doc(finalId),
      );
      DocumentReference<Map<String, dynamic>>? linkedReservation;
      Map<String, dynamic>? linkedIdentity;
      if (linkedChassis != null) {
        linkedReservation = _idManagementCollection.doc(
          _idempotencyDocumentId('chassis', linkedChassisSubmissionKey!),
        );
        linkedIdentity = (await transaction.get(linkedReservation)).data();
        if (linkedIdentity?['resource_key'] != 'chassis' ||
            linkedIdentity?['submission_key'] != linkedChassisSubmissionKey ||
            linkedIdentity?['document_id']?.toString() !=
                linkedChassis['id']?.toString()) {
          throw StateError(
            'Sync conflict: linked chassis reservation identity changed.',
          );
        }
      }

      if (existingBooking.exists) {
        if (existingBooking.data()?['submission_key'] != submissionKey) {
          throw StateError(
            'Sync conflict: reserved booking belongs to another submission.',
          );
        }
        // A retried create must never replay old assignments or statuses
        // over a booking that has already progressed on another device.
        final source = idempotencySnapshot.data()?['source_document'];
        final retryMatches =
            BookingIdResolver.reconcileCopies([
              {...entry.payload, 'id': entry.targetId},
              {
                ...(source is Map
                    ? Map<String, dynamic>.from(source)
                    : existingBooking.data()!),
                'id': finalId,
              },
            ]).length ==
            1;
        if (!retryMatches) {
          throw StateError(
            'Sync conflict: booking was edited while its create was syncing. Review the pending edit.',
          );
        }
        if (linkedChassis != null &&
            (linkedIdentity?['linked_booking_submission_key'] !=
                    submissionKey ||
                !_sameDocument(
                  linkedIdentity?['linked_source_document'],
                  linkedChassis,
                ))) {
          throw StateError(
            'Sync conflict: linked chassis create changed while syncing.',
          );
        }
        return finalId;
      }
      if (linkedIdentity?['committed_document'] != null) {
        throw StateError(
          'Sync conflict: linked create was already committed; booking was removed.',
        );
      }
      final linkedDriverId = linkedChassis?['current_driver_id']?.toString();
      if (linkedDriverId != null &&
          !(await transaction.get(
            _usersCollection.doc(linkedDriverId),
          )).exists) {
        throw StateError(
          'Driver record is temporarily unavailable. Try again after its create syncs.',
        );
      }
      final finalDocument = Map<String, dynamic>.from(entry.payload)
        ..['id'] = finalId
        ..remove('local_sync_status');
      final chassisId = normalizeId(finalDocument['chassis_id']?.toString());
      DocumentSnapshot<Map<String, dynamic>>? chassisSnapshot;
      if (chassisId != null) {
        chassisSnapshot = await transaction.get(
          _firestore.collection('chassis').doc(chassisId),
        );
        if (!chassisSnapshot.exists && linkedChassis == null) {
          throw StateError('The selected chassis no longer exists.');
        }
        if (linkedChassis != null && chassisSnapshot.exists) {
          throw StateError('Sync conflict: linked chassis ID is occupied.');
        }
        if (linkedChassis == null) {
          final ownerId = normalizeId(
            chassisSnapshot.data()?['current_booking_id']?.toString(),
          );
          final ownerBooking = ownerId != null && ownerId != finalId
              ? (await transaction.get(_bookingsCollection.doc(ownerId))).data()
              : null;
          if (!shouldProjectBookingOntoChassis(
            bookingId: finalId,
            booking: finalDocument,
            chassis: chassisSnapshot.data() ?? {},
            ownerBooking: ownerBooking,
          )) {
            chassisSnapshot = null;
          }
        }
      }
      final now = finalDocument['updated_at']?.toString() ?? entry.createdAtIso;
      if (linkedChassis != null) {
        final chassisDocument = Map<String, dynamic>.from(linkedChassis)
          ..['current_booking_id'] = nextId;
        if (isChassisReservation(finalDocument['client_status']?.toString())) {
          chassisDocument.remove('current_booking_id');
          chassisDocument.remove('current_driver_id');
          chassisDocument['current_status'] = 'ready';
        }
        transaction.set(chassisSnapshot!.reference, chassisDocument);
        transaction.set(linkedReservation!, {
          'committed_document': chassisDocument,
          'linked_source_document': linkedChassis,
          'linked_booking_submission_key': submissionKey,
          'linked_booking_id': finalId,
        }, SetOptions(merge: true));
      } else if (chassisSnapshot != null) {
        final lifecycle = chassisLifecycleInstruction(
          previousBookingStatus: null,
          nextBookingStatus: finalDocument['client_status']?.toString(),
          bookingDocument: finalDocument,
        );
        transaction.set(
          chassisSnapshot.reference,
          lifecycle == null
              ? _defaultChassisAssignmentPatch(
                  bookingId: finalId,
                  bookingDocument: finalDocument,
                  now: now,
                )
              : _lifecycleChassisPatch(
                  instruction: lifecycle,
                  bookingId: finalId,
                  bookingDocument: finalDocument,
                  now: now,
                ),
          SetOptions(merge: true),
        );
      }
      transaction.set(_bookingsCollection.doc(finalId), finalDocument);
      transaction.set(_bookingsCounterRef, {
        'next_id': max(
          int.tryParse(counterSnapshot.data()?['next_id']?.toString() ?? '') ??
              1,
          nextId + 1,
        ),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
      transaction.set(idempotencyRef, {
        'kind': 'idempotency',
        'resource_key': 'bookings',
        'document_id': finalId,
        'submission_key': submissionKey,
        'provisional_id': entry.targetId,
        'source_updated_at': entry.payload['updated_at'],
        'source_document': Map<String, dynamic>.from(entry.payload)
          ..remove('local_sync_status'),
        'created_at':
            idempotencySnapshot.data()?['created_at'] ??
            DateTime.now().toUtc().toIso8601String(),
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
      return finalId;
    }).timeout(
      _remoteMutationTimeout,
      onTimeout: () =>
          throw TimeoutException('queued booking create transaction timeout'),
    );
  }

  bool _sameDocument(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every(
            (key) => b.containsKey(key) && _sameDocument(a[key], b[key]),
          );
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(
            a.length,
            (i) => i,
          ).every((i) => _sameDocument(a[i], b[i]));
    }
    return a == b;
  }

  Future<String> _applyOfflineCollectionDocumentCreate(
    _OfflineMutationEntry entry,
  ) async {
    final collectionKey = entry.collectionKey;
    final submissionKey = entry.payload['submission_key']?.toString().trim();
    final collection = collectionKey == null
        ? null
        : _collectionForKey(collectionKey);
    if (collectionKey == null ||
        collection == null ||
        submissionKey == null ||
        submissionKey.isEmpty) {
      throw Exception('Queued resource create is missing reservation data.');
    }
    final finalId = await reserveNumericDocumentId(
      collectionKey: collectionKey,
      submissionKey: submissionKey,
    );
    final document = Map<String, dynamic>.from(entry.payload)
      ..['id'] = finalId
      ..remove('submission_key')
      ..remove('local_sync_status');
    final reservation = _idManagementCollection.doc(
      _idempotencyDocumentId(collectionKey, submissionKey),
    );
    await _firestore.runTransaction<void>((tx) async {
      final existing = await tx.get(collection.doc(finalId));
      final identity = await tx.get(reservation);
      final committed = identity.data()?['committed_document'];
      if (existing.exists) {
        if (committed != null && _sameDocument(committed, document)) {
          return; // Already committed; never restore a stale snapshot over edits.
        }
        throw StateError(
          'Sync conflict: reserved ID is occupied. Existing data was preserved.',
        );
      }
      if (committed != null) {
        throw StateError(
          'Sync conflict: previously created record was deleted. Review before recreating.',
        );
      }
      tx.set(collection.doc(finalId), document);
      tx.set(reservation, {
        'committed_document': document,
      }, SetOptions(merge: true));
    });
    return finalId;
  }

  Future<String> _applyChassisAssignment(_OfflineMutationEntry entry) async {
    final payload = entry.payload;
    final rawChassis = payload['chassis'];
    final submissionKey = payload['submission_key']?.toString().trim();
    if (rawChassis is! Map || submissionKey == null || submissionKey.isEmpty) {
      throw Exception('Queued chassis assignment is missing required data.');
    }
    final isProvisionalCreate = payload['provisional_create'] == true;
    final provisionalId = int.tryParse(entry.targetId);
    final resolvedId =
        isProvisionalCreate || provisionalId == null || provisionalId <= 0
        ? await reserveNumericDocumentId(
            collectionKey: 'chassis',
            submissionKey: submissionKey,
          )
        : entry.targetId;
    _traceChassis(
      'sync transaction start provisionalId=${entry.targetId} resolvedId=$resolvedId',
    );
    final previousBookingId = payload['previous_booking_id']?.toString().trim();
    final nextBookingId = payload['next_booking_id']?.toString().trim();
    final now = DateTime.now().toUtc().toIso8601String();
    final chassisDocument = Map<String, dynamic>.from(rawChassis)
      ..['id'] = resolvedId
      ..remove('submission_key')
      ..remove('local_sync_status');
    for (final key in ['current_booking_id', 'current_driver_id']) {
      final value = chassisDocument[key]?.toString();
      if (value != null) chassisDocument[key] = int.tryParse(value) ?? value;
    }
    final reservationRef = _idManagementCollection.doc(
      _idempotencyDocumentId('chassis', submissionKey),
    );
    final originalChassisDocument = Map<String, dynamic>.from(chassisDocument);
    await _firestore.runTransaction<void>((transaction) async {
      final chassisDocument = Map<String, dynamic>.from(
        originalChassisDocument,
      );
      final chassisRef = _firestore.collection('chassis').doc(resolvedId);
      final currentChassis = await transaction.get(chassisRef);
      final remoteVersion = _parseSyncTimestamp(
        currentChassis.data()?['updated_at']?.toString(),
      );
      final baseVersion = _parseSyncTimestamp(entry.baseUpdatedAt);
      final actionVersion = _parseSyncTimestamp(
        chassisDocument['updated_at']?.toString(),
      );
      if (!currentChassis.exists &&
          baseVersion != null &&
          !isProvisionalCreate &&
          (provisionalId ?? 0) > 0) {
        throw StateError(
          'Sync conflict: chassis was deleted on another device.',
        );
      }
      if (!isProvisionalCreate &&
          (provisionalId ?? 0) > 0 &&
          baseVersion != null &&
          remoteVersion != null &&
          remoteVersion.isAfter(baseVersion) &&
          remoteVersion != actionVersion) {
        throw StateError(
          'Sync conflict: chassis changed on another device. Pending assignment was preserved.',
        );
      }
      if (isProvisionalCreate || (provisionalId ?? 0) <= 0) {
        final existing = currentChassis;
        final reservation = await transaction.get(reservationRef);
        final committed = reservation.data()?['committed_document'];
        if (existing.exists) {
          if (committed != null && _sameDocument(committed, chassisDocument)) {
            return;
          }
          throw StateError(
            'Sync conflict: chassis ID is occupied. Existing data was preserved.',
          );
        }
        if (committed != null) {
          throw StateError(
            'Sync conflict: previously created chassis was deleted. Review before recreating.',
          );
        }
      }
      final currentBooking = currentChassis
          .data()?['current_booking_id']
          ?.toString();
      if ((nextBookingId == null || nextBookingId.isEmpty) &&
          currentBooking != null &&
          currentBooking != previousBookingId) {
        throw StateError(
          'Sync conflict: chassis now belongs to another booking.',
        );
      }
      final driverId = normalizeId(
        chassisDocument['current_driver_id']?.toString(),
      );
      if (driverId != null &&
          !(await transaction.get(_usersCollection.doc(driverId))).exists) {
        throw StateError(
          'Driver record is temporarily unavailable. Try again after its create syncs.',
        );
      }
      final additionalLinks = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final rawId in payload['booking_link_ids'] as List? ?? const []) {
        final linkId = rawId.toString();
        if (linkId == nextBookingId) continue;
        final linked = await transaction.get(_bookingsCollection.doc(linkId));
        final assigned = linked.data()?['chassis_id']?.toString();
        if (!linked.exists || (assigned != null && assigned != resolvedId)) {
          throw StateError(
            'Sync conflict: an earlier booking reservation changed before syncing.',
          );
        }
        additionalLinks.add(linked);
      }
      if (nextBookingId != null && nextBookingId.isNotEmpty) {
        final targetSnapshot = await transaction.get(
          _bookingsCollection.doc(nextBookingId),
        );
        if (!targetSnapshot.exists) {
          throw StateError('The selected booking no longer exists.');
        }
        final ownerId = currentChassis
            .data()?['current_booking_id']
            ?.toString();
        final ownerBooking = ownerId != null && ownerId != nextBookingId
            ? (await transaction.get(_bookingsCollection.doc(ownerId))).data()
            : null;
        if (!shouldProjectBookingOntoChassis(
          bookingId: nextBookingId,
          booking: targetSnapshot.data()!,
          chassis: currentChassis.data() ?? {},
          ownerBooking: ownerBooking,
        )) {
          preserveChassisPhysicalAssignment(
            chassisDocument,
            currentChassis.data() ?? {},
          );
        }
        final priorChassisId = int.tryParse(
          targetSnapshot.data()?['chassis_id']?.toString() ?? '',
        );
        if (priorChassisId != null && priorChassisId.toString() != resolvedId) {
          throw StateError(
            'Sync conflict: selected booking now has another chassis.',
          );
        }
      }
      if (nextBookingId != null && nextBookingId.isNotEmpty) {
        transaction.set(_bookingsCollection.doc(nextBookingId), {
          'chassis_id': resolvedId,
          'updated_at': rawChassis['updated_at'] ?? entry.createdAtIso,
        }, SetOptions(merge: true));
      }
      for (final linked in additionalLinks) {
        if (linked.data()?['chassis_id']?.toString() == resolvedId) continue;
        transaction.set(linked.reference, {
          'chassis_id': resolvedId,
          'updated_at': rawChassis['updated_at'] ?? entry.createdAtIso,
        }, SetOptions(merge: true));
      }
      transaction.set(
        _firestore.collection('chassis').doc(resolvedId),
        chassisDocument,
      );
      if (isProvisionalCreate || (provisionalId ?? 0) <= 0) {
        transaction.set(reservationRef, {
          'committed_document': chassisDocument,
        }, SetOptions(merge: true));
      }
      transaction.set(_firestore.collection('manage_cache').doc('chassis'), {
        'version': now,
        'updated_at': now,
      }, SetOptions(merge: true));
      if (previousBookingId != nextBookingId ||
          (nextBookingId?.isNotEmpty ?? false)) {
        transaction.set(_firestore.collection('manage_cache').doc('bookings'), {
          'version': now,
          'updated_at': now,
        }, SetOptions(merge: true));
      }
    });
    _traceChassis('sync transaction committed resolvedId=$resolvedId');
    return resolvedId;
  }

  Future<void> _applyChassisDelete(_OfflineMutationEntry entry) async {
    final bookingId = entry.payload['booking_id']?.toString().trim();
    final now = DateTime.now().toUtc().toIso8601String();
    await _firestore.runTransaction<void>((transaction) async {
      final booking = bookingId == null || bookingId.isEmpty
          ? null
          : await transaction.get(_bookingsCollection.doc(bookingId));
      if (booking?.data()?['chassis_id']?.toString() == entry.targetId) {
        transaction.set(_bookingsCollection.doc(bookingId), {
          'chassis_id': FieldValue.delete(),
          'updated_at': entry.createdAtIso,
        }, SetOptions(merge: true));
      }
      transaction.delete(_firestore.collection('chassis').doc(entry.targetId));
      transaction.set(_firestore.collection('manage_cache').doc('chassis'), {
        'version': now,
        'updated_at': now,
      }, SetOptions(merge: true));
      if (bookingId != null && bookingId.isNotEmpty) {
        transaction.set(_firestore.collection('manage_cache').doc('bookings'), {
          'version': now,
          'updated_at': now,
        }, SetOptions(merge: true));
      }
    });
  }

  CollectionReference<Map<String, dynamic>>? _collectionForKey(
    String? collectionKey,
  ) {
    return switch (collectionKey) {
      'users' => _usersCollection,
      'bookings' => _bookingsCollection,
      'role_access' => _firestore.collection('role_access'),
      'vehicle_makes' => _firestore.collection('vehicle_makes'),
      'pm_kpi_records' => _firestore.collection('pm_kpi_records'),
      'pm_fuel_entries' => _firestore.collection('pm_fuel_entries'),
      'operations_catalog' => _firestore.collection('operations_catalog'),
      'vehicle_types' => _firestore.collection('vehicle_types'),
      'vehicle_sizes' => _firestore.collection('vehicle_sizes'),
      'chassis' => _firestore.collection('chassis'),
      'status_forms' => _firestore.collection('status_forms'),
      'status_fields' => _firestore.collection('status_fields'),
      'statuses' => _firestore.collection('statuses'),
      _ => null,
    };
  }

  Map<String, dynamic> _defaultChassisAssignmentPatch({
    required String bookingId,
    required Map<String, dynamic> bookingDocument,
    required String now,
  }) {
    final driverId = normalizeId(bookingDocument['driver_id']?.toString());
    return {
      'current_booking_id': int.tryParse(bookingId) ?? bookingId,
      'current_driver_id': driverId == null
          ? FieldValue.delete()
          : (int.tryParse(driverId) ?? driverId),
      'updated_at': now,
    };
  }

  Map<String, dynamic> _lifecycleChassisPatch({
    required ChassisLifecycleInstruction instruction,
    required String bookingId,
    required Map<String, dynamic> bookingDocument,
    required String now,
  }) {
    final patch = <String, dynamic>{
      'current_status': instruction.status,
      'updated_at': now,
      'current_booking_id': instruction.keepBookingLink
          ? (int.tryParse(bookingId) ?? bookingId)
          : FieldValue.delete(),
    };
    final driverId = switch (instruction.driverLink) {
      ChassisDriverLink.deliveryDriver => normalizeId(
        bookingDocument['driver_id']?.toString(),
      ),
      ChassisDriverLink.returnDriver => chassisReturnDriverId(bookingDocument),
      ChassisDriverLink.clear || ChassisDriverLink.preserve => null,
    };
    if (instruction.driverLink == ChassisDriverLink.clear) {
      patch['current_driver_id'] = FieldValue.delete();
    } else if (instruction.driverLink != ChassisDriverLink.preserve) {
      patch['current_driver_id'] = driverId == null
          ? FieldValue.delete()
          : (int.tryParse(driverId) ?? driverId);
    }
    final location = instruction.location?.trim();
    if (location?.isNotEmpty == true) {
      patch['location'] = location;
    }
    return patch;
  }

  Future<List<_OfflineMutationEntry>> _readEntries() async {
    final rawEntries = await _backend.readStringList(
      await _resolvedStorageKey(),
    );
    return rawEntries
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .map(_OfflineMutationEntry.fromMap)
        .toList();
  }

  Future<List<_OfflineMutationEntry>> _readEntriesForStorageKey(
    String storageKey,
  ) async {
    final rawEntries = await _backend.readStringList(storageKey);
    return rawEntries
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .map(_OfflineMutationEntry.fromMap)
        .toList();
  }

  Future<void> _writeEntries(List<_OfflineMutationEntry> entries) async {
    await _backend.writeStringList(
      await _resolvedStorageKey(),
      entries.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }

  Future<void> _writeEntriesForStorageKey(
    String storageKey,
    List<_OfflineMutationEntry> entries,
  ) async {
    await _backend.writeStringList(
      storageKey,
      entries.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }

  Future<T> _localStorageOperation<T>(
    String label,
    Future<T> Function() operation,
  ) async {
    _log('$label start');
    try {
      final result = await operation().timeout(_localStorageTimeout);
      _log('$label done');
      return result;
    } on TimeoutException {
      _log('$label timeout after ${_localStorageTimeout.inSeconds}s');
      rethrow;
    } catch (error) {
      _log('$label error=$error');
      rethrow;
    }
  }

  void _log(String message) {
    // Temporary diagnostics removed.
  }

  void _traceChassis(String message) {}

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

  Future<OfflineQueueStatusSnapshot> _readStatusForStorageKey(
    String storageKey,
  ) async {
    final entries = await _readEntriesForStorageKey(storageKey);
    return const OfflineQueueStatusSnapshot.idle().copyWith(
      pendingCount: entries.where((entry) => !entry.isBlocked).length,
      failedCount: entries.where((entry) => entry.isBlocked).length,
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
    final currentStorageKey = await _resolvedStorageKey();
    keys.add(currentStorageKey);
    return keys.toList(growable: false);
  }

  Map<String, _OfflineMutationEntry> _linkedChassisCreates(
    List<_OfflineMutationEntry> entries,
  ) {
    final pairs = <String, _OfflineMutationEntry>{};
    for (final booking in entries.where(
      (item) => item.kind == _OfflineMutationKind.bookingCreate,
    )) {
      final candidates = entries
          .where(
            (chassis) =>
                chassis.kind == _OfflineMutationKind.chassisAssignment &&
                chassis.payload['provisional_create'] == true &&
                chassis.targetId == booking.payload['chassis_id']?.toString() &&
                chassis.payload['next_booking_id']?.toString() ==
                    booking.targetId &&
                (chassis.payload['previous_booking_id'] == null ||
                    chassis.payload['previous_booking_id'] ==
                        booking.targetId) &&
                (chassis.payload['chassis'] as Map?)?['current_booking_id']
                        ?.toString() ==
                    booking.targetId,
          )
          .toList();
      if (candidates.length == 1) pairs[booking.id] = candidates.single;
    }
    return pairs;
  }

  Future<(String, String)> _applyLinkedCreate(
    _OfflineMutationEntry booking,
    _OfflineMutationEntry chassis,
    Map<String, String> aliases,
  ) async {
    final key = chassis.payload['submission_key']?.toString();
    if (key == null || key.isEmpty) {
      throw StateError('Sync conflict: chassis submission key is missing.');
    }
    final raw = Map<String, dynamic>.from(chassis.payload['chassis'] as Map)
      ..remove('current_booking_id');
    final document =
        OfflineReferenceMapper.mapDocument(raw, aliases, mapId: false)
          ..remove('submission_key')
          ..remove('local_sync_status');
    final chassisId = await reserveNumericDocumentId(
      collectionKey: 'chassis',
      submissionKey: key,
    );
    document['id'] = chassisId;
    final driverId = document['current_driver_id']?.toString();
    if (driverId != null) {
      document['current_driver_id'] = int.tryParse(driverId) ?? driverId;
    }
    final resolvedBooking = _resolveEntryAliases(booking, {
      ...aliases,
      chassis.targetId: chassisId,
    });
    final bookingId = await _applyOfflineBookingCreate(
      resolvedBooking,
      linkedChassis: document,
      linkedChassisSubmissionKey: key,
    );
    BookingIdResolver(firestore: _firestore).invalidate(booking.targetId);
    await _publishCollectionVersion('bookings');
    await _publishCollectionVersion('chassis');
    return (bookingId, chassisId);
  }

  Future<void> _flushPendingMutationsForStorageKey(
    String storageKey, {
    required bool updateStatus,
  }) async {
    final entries = await _serializeQueueMutation(() async {
      final saved = await _readEntriesForStorageKey(storageKey);
      var changed = false;
      final recovered = saved.map((entry) {
        final boxed =
            !entry.boxedErrorRechecked &&
            isBoxedTransactionError(entry.lastError ?? '') &&
            (entry.kind == _OfflineMutationKind.bookingCreate ||
                (entry.kind == _OfflineMutationKind.collectionDocumentUpsert &&
                    const {
                      'operations_catalog',
                      'bookings',
                    }.contains(entry.collectionKey)));
        final bookingConflict =
            !entry.bookingConflictRechecked &&
            entry.kind == _OfflineMutationKind.collectionDocumentUpsert &&
            entry.collectionKey == 'bookings' &&
            ((entry.lastError ?? '').contains(
                  'booking changed remotely before applying this edit',
                ) ||
                (entry.lastError ?? '').contains(
                  'Sync conflict detected. This record changed remotely',
                ));
        if (entry.isBlocked && (boxed || bookingConflict)) {
          changed = true;
          return entry.copyWith(
            isBlocked: false,
            boxedErrorRechecked: boxed || entry.boxedErrorRechecked,
            bookingConflictRechecked:
                bookingConflict || entry.bookingConflictRechecked,
            clearLastError: true,
          );
        }
        return entry;
      }).toList();
      if (changed) {
        // Persist the one-time marker before touching the server. Keep the
        // original base version: this is diagnosis, never forced overwrite.
        await _writeEntriesForStorageKey(storageKey, recovered);
      }
      return recovered;
    });
    final activeEntries = entries.where((entry) => !entry.isBlocked).toList();
    final aliases = await _readResolvedIdAliases(storageKey);
    final linkedCreates = _linkedChassisCreates(activeEntries);
    final companions = linkedCreates.values.map((entry) => entry.id).toSet();
    final committedChassisCreates = <String, _OfflineMutationEntry>{};
    if (updateStatus) {
      _setStatus(
        _currentStatus.copyWith(
          pendingCount: activeEntries.length,
          failedCount: entries.length - activeEntries.length,
          isSyncing: activeEntries.isNotEmpty,
          processedInBatch: 0,
          totalInBatch: activeEntries.length,
          clearLastSyncAt: activeEntries.isNotEmpty,
        ),
      );
    }
    if (activeEntries.isEmpty) {
      return;
    }

    final confirmedSuccesses = <String>{};
    final remaining = <_OfflineMutationEntry>[];
    var processed = 0;

    for (final sourceEntry in activeEntries) {
      if (companions.contains(sourceEntry.id)) {
        processed++;
        continue;
      }
      final companion = linkedCreates[sourceEntry.id];
      var entry = sourceEntry;
      try {
        if (companion != null) {
          final (bookingId, chassisId) = await _applyLinkedCreate(
            sourceEntry,
            companion,
            aliases,
          );
          aliases[sourceEntry.targetId] = bookingId;
          aliases[companion.targetId] = chassisId;
          committedChassisCreates[companion.targetId] = companion;
          await _writeResolvedIdAliases(storageKey, aliases);
          confirmedSuccesses.addAll({
            if (sourceEntry.retryCount > 0 || sourceEntry.lastError != null)
              sourceEntry.id,
            if (companion.retryCount > 0 || companion.lastError != null)
              companion.id,
          });
          continue;
        }
        entry = await _resolveBookingReferences(sourceEntry);
        entry = _resolveEntryAliases(entry, aliases);
        final resolvedId = await _applyEntry(
          entry,
          storageKey.substring('$_storageKey::'.length),
        );
        if (sourceEntry.kind == _OfflineMutationKind.chassisAssignment &&
            sourceEntry.payload['provisional_create'] == true &&
            resolvedId != null) {
          committedChassisCreates[sourceEntry.targetId] = sourceEntry;
        }
        if ((sourceEntry.kind ==
                    _OfflineMutationKind.collectionDocumentCreate ||
                sourceEntry.kind == _OfflineMutationKind.bookingCreate ||
                sourceEntry.kind == _OfflineMutationKind.chassisAssignment) &&
            resolvedId != null &&
            sourceEntry.targetId != resolvedId) {
          aliases[sourceEntry.targetId] = resolvedId;
          await _writeResolvedIdAliases(storageKey, aliases);
        }
        if (entry.kind == _OfflineMutationKind.chassisAssignment) {
          _traceChassis('sync applied documentId=${entry.targetId}');
        }
        confirmedSuccesses.addAll({
          if (entry.retryCount > 0 || entry.lastError != null) entry.id,
        });
      } catch (error, stackTrace) {
        if (entry.kind == _OfflineMutationKind.chassisAssignment) {
          _traceChassis(
            'sync failed documentId=${entry.targetId} error=$error',
          );
        }
        final normalizedError = normalizeUserErrorText(
          error.toString(),
          fallback: 'Something went wrong. Please try again.',
        );
        final diagnostics = await offlineErrorDiagnostics(
          error: error,
          stack: stackTrace,
          source: 'offline_mutation_queue_service.dart',
          operation: entry.kind.name,
          entryId: entry.id,
          target: '${entry.collectionKey ?? entry.kind.name}/${entry.targetId}',
          attempt: entry.retryCount + 1,
          owner: storageKey.substring('$_storageKey::'.length),
          actionAt: entry.createdAtIso,
          context: {
            'queue_snapshot': SyncErrorLogService.pendingMutationSnapshot(
              entry.toMap(),
            ),
            'base_updated_at': entry.baseUpdatedAt,
            'payload_keys': entry.payload.keys.take(100).toList(),
            'blocked_before_attempt': entry.isBlocked,
          },
        );
        if (companion != null) {
          remaining.add(
            companion.copyWith(
              isBlocked:
                  _isConflictError(normalizedError) ||
                  (!_isRetryable(normalizedError) &&
                      error is! TimeoutException),
              retryCount: companion.retryCount + 1,
              lastError: normalizedError,
              diagnostics: diagnostics,
            ),
          );
        }
        if (_isConflictError(normalizedError)) {
          remaining.add(
            entry.copyWith(
              isBlocked: true,
              lastError: normalizedError,
              diagnostics: diagnostics,
            ),
          );
        } else if (_isRetryable(normalizedError) || error is TimeoutException) {
          remaining.add(
            entry.copyWith(
              retryCount: entry.retryCount + 1,
              lastError: normalizedError,
              diagnostics: diagnostics,
            ),
          );
        } else {
          // Preserve failed work for review instead of silently losing edits.
          remaining.add(
            entry.copyWith(
              isBlocked: true,
              lastError: normalizedError,
              diagnostics: diagnostics,
            ),
          );
        }
      } finally {
        processed++;
        if (updateStatus) {
          _setStatus(
            _currentStatus.copyWith(
              pendingCount:
                  remaining.where((entry) => !entry.isBlocked).length +
                  (activeEntries.length - processed),
              failedCount:
                  remaining.where((entry) => entry.isBlocked).length +
                  (entries.length - activeEntries.length),
              isSyncing: true,
              processedInBatch: processed,
              totalInBatch: activeEntries.length,
            ),
          );
        }
      }
    }

    await _serializeQueueMutation(() async {
      final originals = {for (final item in entries) item.id: item};
      final outcomes = {for (final item in remaining) item.id: item};
      final latest = await _readEntriesForStorageKey(storageKey);
      final merged = <_OfflineMutationEntry>[];
      for (final item in latest) {
        final original = originals[item.id];
        if (item.collectionKey == 'operations_catalog' &&
            item.kind == _OfflineMutationKind.collectionDocumentUpsert &&
            original == null) {
          final predecessor = entries
              .where(
                (candidate) =>
                    candidate.collectionKey == item.collectionKey &&
                    candidate.targetId == item.targetId &&
                    candidate.kind == item.kind &&
                    !candidate.isBlocked &&
                    !outcomes.containsKey(candidate.id) &&
                    item.catalogPredecessorVersions.contains(
                      candidate.payload['updated_at']?.toString(),
                    ),
              )
              .firstOrNull;
          if (predecessor != null) {
            // Only advance through a successfully committed, proven local
            // predecessor. The next transaction still checks the server version.
            merged.add(
              item.copyWith(
                baseUpdatedAt: predecessor.payload['updated_at']?.toString(),
              ),
            );
            continue;
          }
        }
        final committedChassis = committedChassisCreates[item.targetId];
        if (item.kind == _OfflineMutationKind.chassisAssignment &&
            committedChassis != null &&
            (item.id != committedChassis.id ||
                !_sameDocument(item.payload, committedChassis.payload))) {
          final originalDocument = committedChassis.payload['chassis'] as Map;
          merged.add(
            item.copyWith(
              targetId: aliases[item.targetId],
              baseUpdatedAt: originalDocument['updated_at']?.toString(),
              payload: Map<String, dynamic>.from(item.payload)
                ..['provisional_create'] = false
                ..['previous_booking_id'] =
                    originalDocument['current_booking_id'],
            ),
          );
          continue;
        }

        if (original == null ||
            jsonEncode(item.toMap()) != jsonEncode(original.toMap())) {
          if ((item.kind == _OfflineMutationKind.bookingCreate ||
                  item.kind == _OfflineMutationKind.collectionDocumentCreate) &&
              original != null &&
              aliases.containsKey(item.targetId)) {
            merged.add(
              _OfflineMutationEntry(
                id: item.id,
                kind: _OfflineMutationKind.collectionDocumentUpsert,
                targetId: aliases[item.targetId]!,
                collectionKey: item.collectionKey,
                baseUpdatedAt: original.payload['updated_at']?.toString(),
                payload: Map<String, dynamic>.from(item.payload)
                  ..['id'] = aliases[item.targetId],
                createdAtIso: item.createdAtIso,
                retryCount: item.retryCount,
              ),
            );
          } else {
            merged.add(item);
          }
        } else if (original.isBlocked) {
          merged.add(original);
        } else if (outcomes.containsKey(item.id)) {
          merged.add(outcomes[item.id]!);
        }
      }
      remaining
        ..clear()
        ..addAll(merged);
      await _writeEntriesForStorageKey(storageKey, remaining);
    });
    unawaited(
      SyncErrorLogService.instance.resolveQueueEntries(
        storageKey,
        confirmedSuccesses,
      ),
    );

    if (updateStatus) {
      _setStatus(
        _currentStatus.copyWith(
          pendingCount: remaining.where((entry) => !entry.isBlocked).length,
          failedCount: remaining.where((entry) => entry.isBlocked).length,
          isSyncing: false,
          processedInBatch: remaining.isEmpty ? activeEntries.length : 0,
          totalInBatch: remaining.isEmpty ? activeEntries.length : 0,
          lastSyncAt: remaining.length < entries.length ? DateTime.now() : null,
        ),
      );
    }
  }

  String _aliasStorageKey(String storageKey) =>
      '$_aliasStorageKeyPrefix::$storageKey';

  Future<Map<String, String>> _readResolvedIdAliases(String storageKey) async {
    final raw = await _authStorage.readString(_aliasStorageKey(storageKey));
    if (raw == null || raw.isEmpty) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, String>{};
      }
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeResolvedIdAliases(
    String storageKey,
    Map<String, String> aliases,
  ) {
    return _authStorage.writeString(
      _aliasStorageKey(storageKey),
      jsonEncode(aliases),
    );
  }

  /// Resolves only aliases committed by this user's resource-create queue.
  /// This lookup creates no timer, subscription or automatic retry.
  Future<Map<String, dynamic>> resolveResourceReferences(
    Map<String, dynamic> document, {
    required String scope,
  }) async {
    if (!OfflineReferenceMapper.hasTemporaryReferences(document)) {
      return copyDocumentFields(document);
    }
    await _authStorage.initialize();
    final aliases = await _readResolvedIdAliases('$_storageKey::$scope');
    return OfflineReferenceMapper.mapDocument(document, aliases);
  }

  _OfflineMutationEntry _resolveEntryAliases(
    _OfflineMutationEntry entry,
    Map<String, String> aliases,
  ) {
    final bookingAliases = Map<String, String>.fromEntries(
      aliases.entries.where(
        (alias) => alias.key.startsWith('offline_booking_'),
      ),
    );
    final otherAliases = Map<String, String>.from(aliases)
      ..removeWhere((key, _) => bookingAliases.containsKey(key));
    final isCreate =
        entry.kind == _OfflineMutationKind.collectionDocumentCreate ||
        entry.kind == _OfflineMutationKind.bookingCreate;
    final payload = OfflineReferenceMapper.mapDocument(
      entry.payload,
      aliases,
      mapId: !isCreate,
    );
    // Only identity fields can be remapped; never notes, waybills, user IDs,
    // status answers, or other strings that happen to contain the same value.
    for (final key in [
      'booking_id',
      'current_booking_id',
      'next_booking_id',
      'previous_booking_id',
    ]) {
      final value = payload[key]?.toString();
      if (bookingAliases.containsKey(value)) {
        payload[key] = bookingAliases[value];
      }
    }
    if (entry.collectionKey == 'bookings' &&
        entry.kind != _OfflineMutationKind.bookingCreate) {
      payload['id'] = bookingAliases[entry.targetId] ?? entry.targetId;
    }
    final chassis = payload['chassis'];
    if (chassis is Map &&
        bookingAliases.containsKey(chassis['current_booking_id']?.toString())) {
      payload['chassis'] = Map<String, dynamic>.from(chassis)
        ..['current_booking_id'] =
            bookingAliases[chassis['current_booking_id'].toString()];
    }
    final resolvedTarget = aliases[entry.targetId] ?? entry.targetId;
    if (entry.kind == _OfflineMutationKind.chassisDelete &&
        ((int.tryParse(resolvedTarget) ?? 0) < 0 ||
            (entry.payload['requires_create_resolution'] == true &&
                !aliases.containsKey(entry.targetId)))) {
      throw StateError(
        'Chassis identity is temporarily unavailable. Try again after its create syncs.',
      );
    }
    // Read-marker targets are local composite keys (user:thread), not remote
    // document IDs. Their actual user reference was resolved in the payload.
    if (!isCreate &&
        entry.kind != _OfflineMutationKind.supportThreadReadMarkerUpsert &&
        entry.kind != _OfflineMutationKind.chassisAssignment &&
        OfflineReferenceMapper.hasTemporaryReferences({'id': resolvedTarget})) {
      throw StateError(
        'Record identity is temporarily unavailable. Try again after its create syncs.',
      );
    }
    return entry.copyWith(
      // A queued create must retain its own provisional target until it is
      // reconciled, but its foreign-key values may refer to an earlier create.
      targetId:
          entry.kind == _OfflineMutationKind.collectionDocumentCreate ||
              entry.kind == _OfflineMutationKind.bookingCreate
          ? entry.targetId
          : (entry.collectionKey == 'bookings' ||
                entry.kind == _OfflineMutationKind.bookingBillingStatusUpdate)
          ? aliases[entry.targetId] ?? entry.targetId
          : otherAliases[entry.targetId] ?? entry.targetId,
      payload: payload,
    );
  }

  Future<void> _refreshStatusFromStorage() async {
    final entries = await _readEntries();
    _setStatus(_snapshotForEntries(entries));
  }

  DateTime? _parseSyncTimestamp(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return DateTime.tryParse(normalized)?.toUtc();
  }

  OfflineQueueStatusSnapshot _snapshotForEntries(
    List<_OfflineMutationEntry> entries,
  ) {
    return _currentStatus.copyWith(
      pendingCount: entries.where((entry) => !entry.isBlocked).length,
      failedCount: entries.where((entry) => entry.isBlocked).length,
    );
  }

  void _markPendingAsSyncing() {
    final pendingCount = _currentStatus.pendingCount;
    if (pendingCount <= 0 || _currentStatus.isSyncing) {
      return;
    }
    _setStatus(
      _currentStatus.copyWith(
        isSyncing: true,
        processedInBatch: 0,
        totalInBatch: pendingCount,
        clearLastSyncAt: true,
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

  bool _isConflictError(String message) {
    return message.trim().toLowerCase().contains('sync conflict');
  }

  String _nextEntryId(String prefix) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomSuffix = Random().nextInt(0x100000000).toRadixString(16);
    return '${prefix}_${timestamp}_$randomSuffix';
  }
}

enum _OfflineMutationKind {
  userUpsert,
  userDelete,
  bookingBillingStatusUpdate,
  supportThreadReadMarkerUpsert,
  bookingCreate,
  chassisAssignment,
  chassisDelete,
  collectionDocumentCreate,
  collectionDocumentUpsert,
  collectionDocumentDelete,
}

class _OfflineMutationEntry {
  const _OfflineMutationEntry({
    required this.id,
    required this.kind,
    required this.targetId,
    this.collectionKey,
    this.baseUpdatedAt,
    required this.payload,
    required this.createdAtIso,
    required this.retryCount,
    this.isBlocked = false,
    this.boxedErrorRechecked = false,
    this.bookingConflictRechecked = false,
    this.catalogPredecessorVersions = const [],
    this.lastError,
    this.diagnostics,
  });

  final String id;
  final _OfflineMutationKind kind;
  final String targetId;
  final String? collectionKey;
  final String? baseUpdatedAt;
  final Map<String, dynamic> payload;
  final String createdAtIso;
  final int retryCount;
  final bool isBlocked;
  final bool boxedErrorRechecked;
  final bool bookingConflictRechecked;
  final List<String> catalogPredecessorVersions;
  final String? lastError;
  final String? diagnostics;

  _OfflineMutationEntry copyWith({
    String? targetId,
    Map<String, dynamic>? payload,
    int? retryCount,
    bool? isBlocked,
    bool? boxedErrorRechecked,
    bool? bookingConflictRechecked,
    String? baseUpdatedAt,
    bool clearBaseUpdatedAt = false,
    String? lastError,
    String? diagnostics,
    bool clearLastError = false,
  }) {
    return _OfflineMutationEntry(
      id: id,
      kind: kind,
      targetId: targetId ?? this.targetId,
      collectionKey: collectionKey,
      baseUpdatedAt: clearBaseUpdatedAt
          ? null
          : (baseUpdatedAt ?? this.baseUpdatedAt),
      payload: Map<String, dynamic>.from(payload ?? this.payload),
      createdAtIso: createdAtIso,
      retryCount: retryCount ?? this.retryCount,
      isBlocked: isBlocked ?? this.isBlocked,
      boxedErrorRechecked: boxedErrorRechecked ?? this.boxedErrorRechecked,
      bookingConflictRechecked:
          bookingConflictRechecked ?? this.bookingConflictRechecked,
      catalogPredecessorVersions: catalogPredecessorVersions,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      diagnostics: clearLastError ? null : (diagnostics ?? this.diagnostics),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'kind': kind.name,
      'target_id': targetId,
      'collection_key': collectionKey,
      'base_updated_at': baseUpdatedAt,
      'payload': payload,
      'created_at': createdAtIso,
      'retry_count': retryCount,
      'is_blocked': isBlocked,
      'boxed_error_rechecked': boxedErrorRechecked,
      'booking_conflict_rechecked': bookingConflictRechecked,
      if (catalogPredecessorVersions.isNotEmpty)
        'catalog_predecessor_versions': catalogPredecessorVersions,
      'last_error': lastError,
      if (diagnostics != null) 'error_diagnostics': diagnostics,
    };
  }

  factory _OfflineMutationEntry.fromMap(Map<String, dynamic> map) {
    final kindName = map['kind']?.toString() ?? '';
    return _OfflineMutationEntry(
      id: map['id']?.toString() ?? '',
      kind: _OfflineMutationKind.values.firstWhere(
        (value) => value.name == kindName,
        orElse: () => _OfflineMutationKind.userUpsert,
      ),
      targetId: map['target_id']?.toString() ?? '',
      collectionKey: map['collection_key']?.toString(),
      baseUpdatedAt: map['base_updated_at']?.toString(),
      payload: map['payload'] is Map
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : const <String, dynamic>{},
      createdAtIso: map['created_at']?.toString() ?? '',
      retryCount: map['retry_count'] is num
          ? (map['retry_count'] as num).toInt()
          : int.tryParse(map['retry_count']?.toString() ?? '') ?? 0,
      isBlocked: map['is_blocked'] as bool? ?? false,
      boxedErrorRechecked: map['boxed_error_rechecked'] == true,
      bookingConflictRechecked: map['booking_conflict_rechecked'] == true,
      catalogPredecessorVersions:
          (map['catalog_predecessor_versions'] as List? ?? [])
              .whereType<String>()
              .toList(),
      lastError: map['last_error']?.toString(),
      diagnostics: map['error_diagnostics']?.toString(),
    );
  }
}

class CatalogConflictReview {
  const CatalogConflictReview({
    required this.id,
    required this.storageKey,
    required this.pending,
    required this.proposed,
    required this.server,
    required this.serverVersions,
  });
  final String id, storageKey;
  final Map<String, dynamic> pending, proposed, server;
  final List<Map<String, dynamic>> serverVersions;
}

class OfflineMutationConflictRecord {
  const OfflineMutationConflictRecord({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.collectionKey,
    required this.createdAt,
    required this.retryCount,
    required this.lastError,
  });

  final String id;
  final String kind;
  final String targetId;
  final String? collectionKey;
  final DateTime? createdAt;
  final int retryCount;
  final String? lastError;
}

OfflineMutationConflictRecord _conflictRecordFromEntry(
  _OfflineMutationEntry entry,
) {
  return OfflineMutationConflictRecord(
    id: entry.id,
    kind: entry.kind.name,
    targetId: entry.targetId,
    collectionKey: entry.collectionKey,
    createdAt: DateTime.tryParse(entry.createdAtIso),
    retryCount: entry.retryCount,
    lastError: entry.lastError,
  );
}
