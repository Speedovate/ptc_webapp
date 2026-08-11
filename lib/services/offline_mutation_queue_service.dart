import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
       _firestore = firestore ?? FirebaseFirestore.instance;

  static final OfflineMutationQueueService instance =
      OfflineMutationQueueService();

  static const _storageKey = 'offline_mutation_queue_v1';
  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';
  static const _retryInterval = Duration(seconds: 20);

  final BookingStorageBackend _backend;
  final FirebaseFirestore _firestore;
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
    debugPrint(
      '[OfflineQueueScope] mutation scoped statuses ${statuses.entries.map((entry) => '${entry.key}:${entry.value.pendingCount}/${entry.value.failedCount}').join(', ')}',
    );
    return statuses;
  }

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _bookingsCollection =>
      _firestore.collection('bookings');

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
      await _refreshStatusFromStorage();
      debugPrint(
        '[OfflineQueueScope] mutation initialize refresh '
        'storageKey=${await _resolvedStorageKey()} '
        'pending=${_currentStatus.pendingCount}',
      );
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
    debugPrint(
      '[OfflineQueueScope] mutation initialize first-run '
      'storageKey=${await _resolvedStorageKey()} '
      'pending=${_currentStatus.pendingCount}',
    );
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

  Future<void> queueCollectionDocumentDelete({
    required String collectionKey,
    required String documentId,
  }) async {
    await initialize();
    final entries = await _readEntries();
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

  Future<void> flushPendingMutations() async {
    await initialize();
    if (_isFlushing || !currentNetworkStatus()) {
      debugPrint(
        '[OfflineQueueScope] mutation flush skipped '
        'storageKey=${await _resolvedStorageKey()} '
        'isFlushing=$_isFlushing online=${currentNetworkStatus()}',
      );
      return;
    }

    _isFlushing = true;
    try {
      final currentStorageKey = await _resolvedStorageKey();
      final storageKeys = await _allKnownStorageKeys();
      debugPrint(
        '[OfflineQueueScope] mutation flush all '
        'current=$currentStorageKey storageKeys=$storageKeys',
      );
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
        await collection.doc(entry.targetId).set(entry.payload);
      case _OfflineMutationKind.collectionDocumentDelete:
        final collection = _collectionForKey(entry.collectionKey);
        if (collection == null) {
          return;
        }
        await collection.doc(entry.targetId).delete();
    }
  }

  CollectionReference<Map<String, dynamic>>? _collectionForKey(
    String? collectionKey,
  ) {
    return switch (collectionKey) {
      'bookings' => _bookingsCollection,
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
    final rawEntries = await _backend.readStringList(await _resolvedStorageKey());
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
    final knownUsers = await _authStorage.readStringList(_knownSessionUserIdsKey);
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
    debugPrint(
      '[OfflineQueueScope] mutation flush start '
      'storageKey=$storageKey entries=${entries.length}',
    );
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
          remaining.add(entry.copyWith(isBlocked: true, lastError: normalizedError));
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
