import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_sync_status_service.dart';
import 'package:webapp/utils/functions.dart';

class OfflineMutationQueueService {
  OfflineMutationQueueService({
    BookingStorageBackend? backend,
    FirebaseFirestore? firestore,
  }) : _backend = backend ?? createBookingStorageBackend(),
       _providedFirestore = firestore;

  static final OfflineMutationQueueService instance =
      OfflineMutationQueueService();

  static const _storageKey = 'offline_mutation_queue_v1';
  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';
  static const _retryInterval = Duration(seconds: 20);
  static const _localStorageTimeout = Duration(seconds: 30);
  static const _remoteMutationTimeout = Duration(seconds: 30);

  final BookingStorageBackend _backend;
  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final AuthStorageBackend _authStorage = createAuthStorageBackend();

  bool _isInitialized = false;
  bool _isFlushing = false;
  Timer? _retryTimer;
  StreamSubscription<bool>? _networkSubscription;
  final StreamController<OfflineQueueStatusSnapshot> _statusController =
      StreamController<OfflineQueueStatusSnapshot>.broadcast();
  OfflineQueueStatusSnapshot _currentStatus =
      const OfflineQueueStatusSnapshot.idle();

  Stream<OfflineQueueStatusSnapshot> get statusStream =>
      _statusController.stream;
  OfflineQueueStatusSnapshot get currentStatus => _currentStatus;

  Future<Map<String, OfflineQueueStatusSnapshot>> readScopedStatuses({
    Iterable<String> userIds = const [],
    bool includeSignedOut = true,
  }) async {
    await initialize();
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

  Future<void> retryBlockedConflict(
    String conflictId, {
    bool clearBaseVersion = true,
  }) async {
    await initialize();
    final entries = await _readEntries();
    var changed = false;
    final nextEntries = entries.map((entry) {
      if (entry.id != conflictId || !entry.isBlocked) {
        return entry;
      }
      changed = true;
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
  }

  Future<void> dismissBlockedConflict(String conflictId) async {
    await initialize();
    final entries = await _readEntries();
    final nextEntries = entries
        .where((entry) => entry.id != conflictId)
        .toList(growable: false);
    if (nextEntries.length == entries.length) {
      return;
    }
    await _writeEntries(nextEntries);
    _setStatus(_snapshotForEntries(nextEntries));
  }

  Future<void> initialize() async {
    await _authStorage.initialize();
    if (_isInitialized) {
      return;
    }
    await _backend.initialize();
    await _refreshStatusFromStorage();
    _retryTimer ??= Timer.periodic(_retryInterval, (_) {
      unawaited(flushPendingMutations());
    });
    _networkSubscription ??= networkStatusEvents().listen((isOnline) {
      if (isOnline) {
        unawaited(flushPendingMutations());
      }
    });
    _isInitialized = true;
    unawaited(flushPendingMutations());
  }

  Future<void> queueUserUpsert({
    required String userId,
    required Map<String, dynamic> document,
    String? baseUpdatedAt,
  }) async {
    await initialize();
    final entries = await _readEntries();
    entries.removeWhere(
      (entry) =>
          entry.kind == _OfflineMutationKind.userUpsert &&
          entry.targetId == userId,
    );
    entries.add(
      _OfflineMutationEntry(
        id: _nextEntryId('user_upsert'),
        kind: _OfflineMutationKind.userUpsert,
        targetId: userId,
        payload: document,
        baseUpdatedAt: baseUpdatedAt,
        createdAtIso: DateTime.now().toUtc().toIso8601String(),
        retryCount: 0,
      ),
    );
    await _writeEntries(entries);
    _setStatus(_snapshotForEntries(entries));
    unawaited(flushPendingMutations());
  }

  Future<void> queueUserDelete({required String userId}) async {
    await initialize();
    final entries = await _readEntries();
    entries.removeWhere(
      (entry) =>
          (entry.kind == _OfflineMutationKind.userUpsert ||
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
          (entry.kind == _OfflineMutationKind.userUpsert ||
              entry.kind == _OfflineMutationKind.userDelete) &&
          entry.targetId == normalizedUserId,
    );
  }

  Future<void> queueBookingBillingStatusUpdate({
    required String bookingId,
    required String billingStatus,
    String? baseUpdatedAt,
  }) async {
    await initialize();
    final entries = await _readEntries();
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
        baseUpdatedAt: baseUpdatedAt,
        createdAtIso: DateTime.now().toUtc().toIso8601String(),
        retryCount: 0,
      ),
    );
    await _writeEntries(entries);
    _setStatus(_snapshotForEntries(entries));
    unawaited(flushPendingMutations());
  }

  Future<void> queueBookingBillingStatusUpdates(
    Map<String, String> statusesByBookingId, {
    Map<String, String?> baseUpdatedAtByBookingId = const {},
  }) async {
    await initialize();
    if (statusesByBookingId.isEmpty) {
      return;
    }
    final entries = await _readEntries();
    entries.removeWhere(
      (entry) => entry.kind == _OfflineMutationKind.bookingBillingStatusUpdate,
    );
    final now = DateTime.now().toUtc();
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
          baseUpdatedAt: baseUpdatedAtByBookingId[normalizedId],
          createdAtIso: now.toIso8601String(),
          retryCount: 0,
        ),
      );
    }
    await _writeEntries(entries);
    _setStatus(_snapshotForEntries(entries));
    unawaited(flushPendingMutations());
  }

  Future<void> queueCollectionDocumentUpsert({
    required String collectionKey,
    required String documentId,
    required Map<String, dynamic> document,
    String? baseUpdatedAt,
  }) async {
    await initialize();
    final entries = await _readEntries();
    final queuedBookingCreateIndex = collectionKey == 'bookings'
        ? entries.indexWhere(
            (entry) =>
                entry.kind == _OfflineMutationKind.bookingCreate &&
                entry.targetId == documentId,
          )
        : -1;
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
    entries.removeWhere(
      (entry) =>
          entry.kind == _OfflineMutationKind.collectionDocumentUpsert &&
          entry.collectionKey == collectionKey &&
          entry.targetId == documentId,
    );
    entries.add(
      _OfflineMutationEntry(
        id: _nextEntryId('vehicle_upsert'),
        kind: _OfflineMutationKind.collectionDocumentUpsert,
        targetId: documentId,
        collectionKey: collectionKey,
        payload: document,
        baseUpdatedAt: baseUpdatedAt,
        createdAtIso: DateTime.now().toUtc().toIso8601String(),
        retryCount: 0,
      ),
    );
    await _writeEntries(entries);
    _setStatus(_snapshotForEntries(entries));
    unawaited(flushPendingMutations());
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
    final entries = await _readEntries();
    entries.removeWhere(
      (entry) =>
          entry.kind == _OfflineMutationKind.collectionDocumentCreate &&
          entry.collectionKey == collectionKey &&
          entry.payload['submission_key']?.toString() == submissionKey,
    );
    entries.add(
      _OfflineMutationEntry(
        id: _nextEntryId('collection_create'),
        kind: _OfflineMutationKind.collectionDocumentCreate,
        targetId: provisionalId,
        collectionKey: collectionKey,
        payload: Map<String, dynamic>.from(document)
          ..['id'] = provisionalId
          ..['submission_key'] = submissionKey,
        createdAtIso: DateTime.now().toUtc().toIso8601String(),
        retryCount: 0,
      ),
    );
    await _writeEntries(entries);
    _setStatus(_snapshotForEntries(entries));
    unawaited(flushPendingMutations());
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
  }

  Future<void> queueCollectionDocumentDelete({
    required String collectionKey,
    required String documentId,
  }) async {
    await initialize();
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
                  entry.kind == _OfflineMutationKind.bookingCreate) &&
              entry.collectionKey == normalizedCollectionKey,
        )
        .map((entry) {
          final document = Map<String, dynamic>.from(entry.payload);
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
    if (_isFlushing || !currentNetworkStatus()) {
      return;
    }

    _isFlushing = true;
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
    }
  }

  Future<void> _applyEntry(_OfflineMutationEntry entry) async {
    switch (entry.kind) {
      case _OfflineMutationKind.userUpsert:
        await _throwIfConflict(
          _usersCollection,
          entry.targetId,
          baseUpdatedAt: entry.baseUpdatedAt,
          nextUpdatedAt: entry.payload['updated_at']?.toString(),
        );
        await _usersCollection.doc(entry.targetId).set(entry.payload);
      case _OfflineMutationKind.userDelete:
        await _usersCollection.doc(entry.targetId).delete();
      case _OfflineMutationKind.bookingBillingStatusUpdate:
        final nextStatus = entry.payload['billing_status']?.toString();
        if (nextStatus == null || nextStatus.trim().isEmpty) {
          return;
        }
        await _throwIfConflict(
          _bookingsCollection,
          entry.targetId,
          baseUpdatedAt: entry.baseUpdatedAt,
        );
        await _bookingsCollection.doc(entry.targetId).update({
          'billing_status': nextStatus.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      case _OfflineMutationKind.bookingCreate:
        await _applyOfflineBookingCreate(entry);
      case _OfflineMutationKind.collectionDocumentCreate:
        await _applyOfflineCollectionDocumentCreate(entry);
      case _OfflineMutationKind.collectionDocumentUpsert:
        final collection = _collectionForKey(entry.collectionKey);
        if (collection == null) {
          return;
        }
        await _throwIfConflict(
          collection,
          entry.targetId,
          baseUpdatedAt: entry.baseUpdatedAt,
          nextUpdatedAt: entry.payload['updated_at']?.toString(),
        );
        await collection
            .doc(entry.targetId)
            .set(entry.payload)
            .timeout(
              _remoteMutationTimeout,
              onTimeout: () => throw TimeoutException(
                'queued ${entry.collectionKey} write timeout for ${entry.targetId}',
              ),
            );
      case _OfflineMutationKind.collectionDocumentDelete:
        final collection = _collectionForKey(entry.collectionKey);
        if (collection == null) {
          return;
        }
        await collection.doc(entry.targetId).delete();
    }
  }

  Future<void> _applyOfflineBookingCreate(_OfflineMutationEntry entry) async {
    final submissionKey = entry.payload['submission_key']?.toString().trim();
    if (submissionKey == null || submissionKey.isEmpty) {
      throw Exception('Queued booking is missing its submission key.');
    }

    final bootstrapNextId = await _bootstrapNextIdIfCounterMissing(
      counterRef: _bookingsCounterRef,
      collection: _bookingsCollection,
    );
    await _firestore
        .runTransaction<void>((transaction) async {
          final idempotencyRef = _idManagementCollection.doc(
            _idempotencyDocumentId('bookings', submissionKey),
          );
          final idempotencySnapshot = await transaction.get(idempotencyRef);
          final existingId = int.tryParse(
            idempotencySnapshot.data()?['document_id']?.toString() ?? '',
          );

          final counterSnapshot = await transaction.get(_bookingsCounterRef);
          var nextId =
              int.tryParse(
                counterSnapshot.data()?['next_id']?.toString() ?? '',
              ) ??
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
          final finalDocument = Map<String, dynamic>.from(entry.payload)
            ..['id'] = finalId
            ..remove('local_sync_status');
          transaction.set(_bookingsCollection.doc(finalId), finalDocument);
          transaction.set(_bookingsCounterRef, {
            'next_id': nextId + 1,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, SetOptions(merge: true));
          transaction.set(idempotencyRef, {
            'kind': 'idempotency',
            'resource_key': 'bookings',
            'document_id': finalId,
            'submission_key': submissionKey,
            'created_at':
                idempotencySnapshot.data()?['created_at'] ??
                DateTime.now().toUtc().toIso8601String(),
            'synced_at': DateTime.now().toUtc().toIso8601String(),
          }, SetOptions(merge: true));
        })
        .timeout(
          _remoteMutationTimeout,
          onTimeout: () => throw TimeoutException(
            'queued booking create transaction timeout',
          ),
        );
  }

  Future<void> _applyOfflineCollectionDocumentCreate(
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
    await collection
        .doc(finalId)
        .set(
          Map<String, dynamic>.from(entry.payload)
            ..['id'] = finalId
            ..remove('submission_key')
            ..remove('local_sync_status'),
        );
  }

  CollectionReference<Map<String, dynamic>>? _collectionForKey(
    String? collectionKey,
  ) {
    return switch (collectionKey) {
      'users' => _usersCollection,
      'bookings' => _bookingsCollection,
      'role_access' => _firestore.collection('role_access'),
      'vehicle_makes' => _firestore.collection('vehicle_makes'),
      'vehicle_types' => _firestore.collection('vehicle_types'),
      'vehicle_sizes' => _firestore.collection('vehicle_sizes'),
      'status_forms' => _firestore.collection('status_forms'),
      'status_fields' => _firestore.collection('status_fields'),
      'statuses' => _firestore.collection('statuses'),
      _ => null,
    };
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

  Future<String> _resolvedStorageKey() async {
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

  Future<void> _flushPendingMutationsForStorageKey(
    String storageKey, {
    required bool updateStatus,
  }) async {
    final entries = await _readEntriesForStorageKey(storageKey);
    final activeEntries = entries.where((entry) => !entry.isBlocked).toList();
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

    final remaining = <_OfflineMutationEntry>[];
    var processed = 0;

    for (final entry in activeEntries) {
      try {
        await _applyEntry(entry);
      } catch (error) {
        final normalizedError = normalizeUserErrorText(
          error.toString(),
          fallback: 'Something went wrong. Please try again.',
        );
        if (_isConflictError(normalizedError)) {
          remaining.add(
            entry.copyWith(isBlocked: true, lastError: normalizedError),
          );
        } else if (_isRetryable(normalizedError)) {
          remaining.add(
            entry.copyWith(
              retryCount: entry.retryCount + 1,
              lastError: normalizedError,
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

    remaining.addAll(entries.where((entry) => entry.isBlocked));
    await _writeEntriesForStorageKey(storageKey, remaining);
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

  Future<void> _refreshStatusFromStorage() async {
    final entries = await _readEntries();
    _setStatus(_snapshotForEntries(entries));
  }

  Future<void> _throwIfConflict(
    CollectionReference<Map<String, dynamic>> collection,
    String documentId, {
    required String? baseUpdatedAt,
    String? nextUpdatedAt,
  }) async {
    final normalizedBase = baseUpdatedAt?.trim();
    if (normalizedBase == null || normalizedBase.isEmpty) {
      return;
    }
    final snapshot = await collection.doc(documentId).get();
    if (!snapshot.exists) {
      return;
    }
    final remoteUpdatedAt = snapshot.data()?['updated_at']?.toString().trim();
    if (remoteUpdatedAt == null || remoteUpdatedAt.isEmpty) {
      return;
    }
    if (remoteUpdatedAt.compareTo(normalizedBase) > 0 &&
        remoteUpdatedAt != (nextUpdatedAt?.trim() ?? '')) {
      throw Exception(
        'Sync conflict detected. This record changed remotely and needs review.',
      );
    }
  }

  OfflineQueueStatusSnapshot _snapshotForEntries(
    List<_OfflineMutationEntry> entries,
  ) {
    return _currentStatus.copyWith(
      pendingCount: entries.where((entry) => !entry.isBlocked).length,
      failedCount: entries.where((entry) => entry.isBlocked).length,
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
  bookingCreate,
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
    this.lastError,
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
  final String? lastError;

  _OfflineMutationEntry copyWith({
    int? retryCount,
    bool? isBlocked,
    String? baseUpdatedAt,
    bool clearBaseUpdatedAt = false,
    String? lastError,
    bool clearLastError = false,
  }) {
    return _OfflineMutationEntry(
      id: id,
      kind: kind,
      targetId: targetId,
      collectionKey: collectionKey,
      baseUpdatedAt: clearBaseUpdatedAt
          ? null
          : (baseUpdatedAt ?? this.baseUpdatedAt),
      payload: Map<String, dynamic>.from(payload),
      createdAtIso: createdAtIso,
      retryCount: retryCount ?? this.retryCount,
      isBlocked: isBlocked ?? this.isBlocked,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
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
      'last_error': lastError,
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
      lastError: map['last_error']?.toString(),
    );
  }
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
