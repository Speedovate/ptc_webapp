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
  }) : _backend = backend ?? createBookingStorageBackend(),
       _providedStorage = storage;

  static final OfflineCleanupQueueService instance =
      OfflineCleanupQueueService();

  static const _storageKey = 'offline_cleanup_queue_v1';
  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';
  static const _retryInterval = Duration(seconds: 20);

  final BookingStorageBackend _backend;
  final FirebaseStorage? _providedStorage;
  FirebaseStorage get _storage => _providedStorage ?? FirebaseStorage.instance;
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

  Future<void> initialize() async {
    await _authStorage.initialize();
    if (_isInitialized) {
      await _refreshStatusFromStorage();
      return;
    }
    await _backend.initialize();
    await _refreshStatusFromStorage();
    _retryTimer ??= Timer.periodic(_retryInterval, (_) {
      unawaited(flushPendingCleanups());
    });
    _networkSubscription ??= networkStatusEvents().listen((isOnline) {
      if (isOnline) {
        unawaited(flushPendingCleanups());
      }
    });
    _isInitialized = true;
    unawaited(flushPendingCleanups());
  }

  Future<void> queueDeleteByPath(String storagePath) async {
    final normalized = storagePath.trim();
    if (normalized.isEmpty) {
      return;
    }
    await initialize();
    final entries = await _readEntries();
    entries.removeWhere(
      (entry) =>
          entry.kind == _OfflineCleanupKind.deleteByPath &&
          entry.targetPath == normalized,
    );
    entries.add(
      _OfflineCleanupEntry(
        id: _nextEntryId('delete_path'),
        kind: _OfflineCleanupKind.deleteByPath,
        targetPath: normalized,
        createdAtIso: DateTime.now().toUtc().toIso8601String(),
        retryCount: 0,
      ),
    );
    await _writeEntries(entries);
    _setStatus(_currentStatus.copyWith(pendingCount: entries.length));
    unawaited(flushPendingCleanups());
  }

  Future<void> queueDeleteFolder(String storagePath) async {
    final normalized = storagePath.trim();
    if (normalized.isEmpty) {
      return;
    }
    await initialize();
    final entries = await _readEntries();
    entries.removeWhere(
      (entry) =>
          entry.kind == _OfflineCleanupKind.deleteFolder &&
          entry.targetPath == normalized,
    );
    entries.add(
      _OfflineCleanupEntry(
        id: _nextEntryId('delete_folder'),
        kind: _OfflineCleanupKind.deleteFolder,
        targetPath: normalized,
        createdAtIso: DateTime.now().toUtc().toIso8601String(),
        retryCount: 0,
      ),
    );
    await _writeEntries(entries);
    _setStatus(_currentStatus.copyWith(pendingCount: entries.length));
    unawaited(flushPendingCleanups());
  }

  Future<void> flushPendingCleanups() async {
    await initialize();
    if (_isFlushing || !currentNetworkStatus()) {
      return;
    }
    _isFlushing = true;
    try {
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

  Future<void> _writeEntries(List<_OfflineCleanupEntry> entries) async {
    await _backend.writeStringList(
      await _resolvedStorageKey(),
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
      failedCount: 0,
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
        await _applyEntry(entry);
      } catch (error) {
        final normalizedError = normalizeUserErrorText(
          error.toString(),
          fallback: 'Something went wrong. Please try again.',
        );
        if (_isRetryable(normalizedError)) {
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
              pendingCount: remaining.length + (entries.length - processed),
              isSyncing: true,
              processedInBatch: processed,
              totalInBatch: entries.length,
            ),
          );
        }
      }
    }

    await _writeEntriesForStorageKey(storageKey, remaining);
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
    _setStatus(_currentStatus.copyWith(pendingCount: entries.length));
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
  });

  final String id;
  final _OfflineCleanupKind kind;
  final String targetPath;
  final String createdAtIso;
  final int retryCount;
  final String? lastError;

  _OfflineCleanupEntry copyWith({int? retryCount, String? lastError}) {
    return _OfflineCleanupEntry(
      id: id,
      kind: kind,
      targetPath: targetPath,
      createdAtIso: createdAtIso,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
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
    );
  }
}
