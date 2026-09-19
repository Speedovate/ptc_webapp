import 'package:webapp/models/offline_queue_item.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_sync_status_service.dart';
import 'package:webapp/utils/functions.dart';

class OfflineCleanupQueueService {
  OfflineCleanupQueueService({
    BookingStorageBackend? backend,
    FirebaseStorage? storage,
    bool Function()? isOnline,
  }) : _backend = backend ?? createBookingStorageBackend(),
       _providedStorage = storage,
       _isOnline = isOnline ?? currentNetworkStatus;

  static final OfflineCleanupQueueService instance =
      OfflineCleanupQueueService();

  static const _storageKey = 'offline_cleanup_queue_v1';
  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';
  static const _retryInterval = Duration(seconds: 20);

  final BookingStorageBackend _backend;
  final FirebaseStorage? _providedStorage;
  final bool Function() _isOnline;
  Future<void> _queueMutationTail = Future<void>.value();
  FirebaseStorage get _storage => _providedStorage ?? FirebaseStorage.instance;
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
            title: 'Remove stored files',
            recordLabel: 'File cleanup',
            createdAt: DateTime.tryParse(entry.createdAtIso),
            hasError: entry.lastError?.isNotEmpty == true,
            errorMessage: entry.lastError,
            nextRetryAt: entry.nextRetryAt,
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
      unawaited(flushPendingCleanups());
    });
    _networkSubscription ??= networkStatusEvents().listen((isOnline) {
      if (isOnline && isAppVisible()) {
        unawaited(flushPendingCleanups());
      }
    });
    _isInitialized = true;
    unawaited(flushPendingCleanups());
  }

  Future<void> queueDeleteByPath(String storagePath) =>
      _enqueue(_OfflineCleanupKind.deleteByPath, storagePath);

  Future<void> queueDeleteFolder(
    String storagePath, {
    String? userScope,
    DateTime? actionAt,
  }) => _enqueue(
    _OfflineCleanupKind.deleteFolder,
    storagePath,
    userScope: userScope,
    occurredAt: actionAt,
  );

  Future<void> _enqueue(
    _OfflineCleanupKind kind,
    String storagePath, {
    String? userScope,
    DateTime? occurredAt,
  }) async {
    final normalized = storagePath.trim();
    if (normalized.isEmpty) {
      return;
    }
    final actionAt = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();
    // Pin the originating account before initialization or another queued write.
    final scope = userScope == null
        ? _resolvedStorageKey()
        : Future.value(_storageKeyForUserId(userScope));
    await initialize();
    final storageKey = await scope;
    await _serializeQueueMutation(() async {
      final entries = await _readEntriesForStorageKey(storageKey);
      entries.removeWhere(
        (entry) => entry.kind == kind && entry.targetPath == normalized,
      );
      entries.add(
        _OfflineCleanupEntry(
          id: _nextEntryId(kind.name),
          kind: kind,
          targetPath: normalized,
          createdAtIso: actionAt,
          retryCount: 0,
        ),
      );
      await _writeEntriesForStorageKey(storageKey, entries);
    });
    await _refreshStatusFromStorage();
    unawaited(flushPendingCleanups());
  }

  Future<T> _serializeQueueMutation<T>(Future<T> Function() action) {
    final next = _queueMutationTail.then((_) => action());
    _queueMutationTail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> flushPendingCleanups() async {
    await initialize();
    final active = _flushFuture;
    if (active != null) {
      return active;
    }
    if (!_isOnline()) {
      return;
    }
    final flush = _flushPendingCleanupsInternal();
    _flushFuture = flush;
    try {
      await flush;
    } finally {
      if (identical(_flushFuture, flush)) {
        _flushFuture = null;
      }
    }
  }

  Future<void> _flushPendingCleanupsInternal() async {
    try {
      await _queueMutationTail;
      final currentStorageKey = await _resolvedStorageKey();
      final storageKeys = await _allKnownStorageKeys();
      for (final storageKey in storageKeys) {
        await _flushPendingCleanupsForStorageKey(
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

  Future<void> _applyEntry(_OfflineCleanupEntry entry) async {
    switch (entry.kind) {
      case _OfflineCleanupKind.deleteByPath:
        await _deleteByPathNow(entry.targetPath);
      case _OfflineCleanupKind.deleteFolder:
        await _deleteFolderRecursively(entry.targetPath);
    }
  }

  Future<void> _deleteByPathNow(String storagePath) async {
    try {
      await _storage.ref(storagePath).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') {
        rethrow;
      }
    }
  }

  Future<void> _deleteFolderRecursively(String storagePath) async {
    try {
      final reference = _storage.ref(storagePath);
      final result = await reference.listAll();

      for (final item in result.items) {
        try {
          await item.delete();
        } on FirebaseException catch (error) {
          if (error.code != 'object-not-found') {
            rethrow;
          }
        }
      }

      for (final prefix in result.prefixes) {
        await _deleteFolderRecursively(prefix.fullPath);
      }
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') {
        rethrow;
      }
    }
  }

  Future<List<_OfflineCleanupEntry>> _readEntries() async {
    final rawEntries = await _backend.readStringList(
      await _resolvedStorageKey(),
    );
    return rawEntries
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .map(_OfflineCleanupEntry.fromMap)
        .toList();
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

  Future<List<_OfflineCleanupEntry>> _readEntriesForStorageKey(
    String storageKey,
  ) async {
    final rawEntries = await _backend.readStringList(storageKey);
    return rawEntries
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .map(_OfflineCleanupEntry.fromMap)
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
    List<_OfflineCleanupEntry> entries,
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

  Future<void> _flushPendingCleanupsForStorageKey(
    String storageKey, {
    required bool updateStatus,
  }) async {
    final entries = await _readEntriesForStorageKey(storageKey);
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
      return;
    }
    final originalIds = entries.map((entry) => entry.id).toSet();
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
      return;
    }

    final remaining = <_OfflineCleanupEntry>[];
    var processed = 0;
    for (final entry in entries) {
      try {
        if (entry.nextRetryAt?.isAfter(DateTime.now().toUtc()) == true) {
          remaining.add(entry);
          continue;
        }
        await _applyEntry(entry);
      } catch (error) {
        final normalizedError = normalizeUserErrorText(
          error.toString(),
          fallback: 'Something went wrong. Please try again.',
        );
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
      final latest = await _readEntriesForStorageKey(storageKey);
      final retainedIds = latest.map((entry) => entry.id).toSet();
      await _writeEntriesForStorageKey(storageKey, [
        ...remaining.where((entry) => retainedIds.contains(entry.id)),
        ...latest.where((entry) => !originalIds.contains(entry.id)),
      ]);
    });
    if (updateStatus) {
      _setStatus(
        _currentStatus.copyWith(
          pendingCount: remaining.length,
          isSyncing: false,
          processedInBatch: remaining.isEmpty ? entries.length : 0,
          totalInBatch: remaining.isEmpty ? entries.length : 0,
          lastSyncAt: remaining.length < entries.length ? DateTime.now() : null,
        ),
      );
    }
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
}

enum _OfflineCleanupKind { deleteByPath, deleteFolder }

class _OfflineCleanupEntry {
  const _OfflineCleanupEntry({
    required this.id,
    required this.kind,
    required this.targetPath,
    required this.createdAtIso,
    required this.retryCount,
    this.lastError,
    this.nextRetryAt,
  });

  final String id;
  final _OfflineCleanupKind kind;
  final String targetPath;
  final String createdAtIso;
  final int retryCount;
  final String? lastError;
  final DateTime? nextRetryAt;

  _OfflineCleanupEntry copyWith({
    int? retryCount,
    String? lastError,
    DateTime? nextRetryAt,
  }) {
    return _OfflineCleanupEntry(
      id: id,
      kind: kind,
      targetPath: targetPath,
      createdAtIso: createdAtIso,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'kind': kind.name,
      'target_path': targetPath,
      'created_at': createdAtIso,
      'retry_count': retryCount,
      'last_error': lastError,
      'next_retry_at': nextRetryAt?.toIso8601String(),
    };
  }

  factory _OfflineCleanupEntry.fromMap(Map<String, dynamic> map) {
    final kindName = map['kind']?.toString() ?? '';
    return _OfflineCleanupEntry(
      id: map['id']?.toString() ?? '',
      kind: _OfflineCleanupKind.values.firstWhere(
        (value) => value.name == kindName,
        orElse: () => _OfflineCleanupKind.deleteByPath,
      ),
      targetPath: map['target_path']?.toString() ?? '',
      createdAtIso: map['created_at']?.toString() ?? '',
      retryCount: map['retry_count'] is num
          ? (map['retry_count'] as num).toInt()
          : int.tryParse(map['retry_count']?.toString() ?? '') ?? 0,
      lastError: map['last_error']?.toString(),
      nextRetryAt: DateTime.tryParse(map['next_retry_at']?.toString() ?? ''),
    );
  }
}
