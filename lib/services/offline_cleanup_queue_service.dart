import 'sync_error_log_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'booking_photo_cleanup.dart';
import 'package:webapp/services/offline_error_diagnostics.dart';
import 'package:webapp/services/firestore_transaction_errors.dart';
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
    FirebaseFirestore? firestore,
    bool Function()? isOnline,
    Duration operationTimeout = const Duration(seconds: 30),
    Duration flushTimeout = const Duration(minutes: 2),
    Duration localStorageTimeout = const Duration(seconds: 30),
  }) : _backend = backend ?? createBookingStorageBackend(),
       _providedStorage = storage,
       _providedFirestore = firestore,
       _isOnline = isOnline ?? currentNetworkStatus,
       _operationTimeout = operationTimeout,
       _flushTimeout = flushTimeout,
       _localStorageTimeout = localStorageTimeout;

  static final OfflineCleanupQueueService instance =
      OfflineCleanupQueueService();

  static const _storageKey = 'offline_cleanup_queue_v1';
  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';
  static const _retryInterval = Duration(seconds: 20);

  /// Namespaces a cleanup review id so the queue dialog can route the action to
  /// this queue instead of the mutation queue.
  static const claimedCleanupPrefix = 'cleanup:';

  final BookingStorageBackend _backend;
  final FirebaseStorage? _providedStorage;
  final FirebaseFirestore? _providedFirestore;
  final bool Function() _isOnline;
  final Duration _operationTimeout;
  final Duration _flushTimeout;
  final Duration _localStorageTimeout;
  Future<void> _queueMutationTail = Future<void>.value();
  FirebaseStorage get _storage => _providedStorage ?? FirebaseStorage.instance;
  final AuthStorageBackend _authStorage = createAuthStorageBackend();

  bool _isInitialized = false;
  Future<void>? _flushFuture;

  /// Incremented per flush. A flush that outlives its timeout and a newer flush
  /// must not publish status over the newer attempt.
  int _flushGeneration = 0;

  /// Entry ids the user explicitly confirmed may act on a claim whose object
  /// still exists. Kept in memory so a plain retry never does.
  final Set<String> _confirmedClaimRetries = <String>{};
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
        .map((entry) {
          // A cleanup that is still claimed while its object exists cannot
          // resolve itself. It is surfaced as a review item so the queued
          // work has an explicit resolution instead of retrying forever.
          final needsReview = isClaimedCleanupReview(entry.lastError);
          return OfflineQueueItem(
            title: 'Remove stored files',
            recordLabel: 'File cleanup',
            createdAt: DateTime.tryParse(entry.createdAtIso),
            hasError: entry.lastError?.isNotEmpty == true,
            isBlocked: needsReview,
            conflictId: needsReview ? '$claimedCleanupPrefix${entry.id}' : null,
            errorMessage: entry.lastError,
            diagnostics: entry.diagnostics,
            nextRetryAt: entry.nextRetryAt,
          );
        })
        .toList(growable: false);
  }

  /// A claimed cleanup whose object still exists needs a human decision: retry
  /// the deletion, or discard the queued work and release the server claim.
  static bool isClaimedCleanupReview(String? lastError) =>
      (lastError ?? '').contains('cleanup is still claimed');

  /// Retry a claimed cleanup with an explicit instruction to delete the object,
  /// or discard the queued work and release both server bookkeeping fields.
  /// Returns false when the entry no longer exists for this account.
  Future<bool> resolveClaimedCleanup(
    String conflictId, {
    required bool keepLocal,
    String? storageKey,
  }) async {
    final entryId = conflictId.startsWith(claimedCleanupPrefix)
        ? conflictId.substring(claimedCleanupPrefix.length)
        : conflictId;
    if (entryId.isEmpty) {
      return false;
    }
    final scope = storageKey ?? await _resolvedStorageKey();
    final entries = await _readEntriesForStorageKey(scope);
    final entry = entries.where((entry) => entry.id == entryId).firstOrNull;
    if (entry == null) {
      return false;
    }
    if (keepLocal) {
      // The user confirmed the deletion, so the next attempt may act on a
      // claim that still holds an existing object.
      _confirmedClaimRetries.add(entryId);
      await _serializeQueueMutation(() async {
        await _writeEntriesForStorageKey(scope, [
          for (final candidate in entries)
            if (candidate.id == entryId)
              candidate.copyWith(
                clearLastError: true,
                clearDiagnostics: true,
                clearNextRetryAt: true,
                retryCount: 0,
              )
            else
              candidate,
        ]);
      });
      unawaited(flushPendingCleanups());
      return true;
    }

    // Discarding the local work item must also release the server claim, or the
    // booking stays blocked for every other device.
    final target = _parseBookingPhotoTarget(entry.targetPath);
    if (target != null) {
      final firestore = _providedFirestore ?? FirebaseFirestore.instance;
      final ref = firestore.collection('bookings').doc(target.bookingId);
      await runTransactionWithOriginalErrors<void>(firestore, (
        transaction,
      ) async {
        final snapshot = await transaction.get(ref);
        if (snapshot.data() == null) {
          return;
        }
        transaction.update(ref, {
          'photo_cleanup_paths': FieldValue.arrayRemove([target.path]),
          'photo_cleanup_claims': FieldValue.arrayRemove([target.path]),
        });
      }).timeout(_operationTimeout);
    }
    _confirmedClaimRetries.remove(entryId);
    await _serializeQueueMutation(() async {
      final latest = await _readEntriesForStorageKey(scope);
      final retained = latest
          .where((candidate) => candidate.id != entryId)
          .toList(growable: false);
      await _writeEntriesForStorageKey(scope, retained);
      _setStatus(
        _currentStatus.copyWith(
          pendingCount: retained.length,
          failedCount: retained
              .where((candidate) => candidate.lastError != null)
              .length,
        ),
      );
    });
    unawaited(
      SyncErrorLogService.instance.resolveQueueEntries(scope, {entryId}),
    );
    return true;
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
    // A device store that never answers must not leave this queue permanently
    // uninitialized: every later retry, resume, and enqueue would keep waiting on
    // the same pending read with nothing reported to the user.
    await _backend.initialize().timeout(
      _localStorageTimeout,
      onTimeout: () => throw TimeoutException(
        'Local cleanup queue storage did not respond.',
      ),
    );
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

  Future<void> queueBookingPhotoDelete(String bookingId, String path) async {
    final target = _bookingPhotoTargetFromValues(bookingId, path);
    if (target == null) return;
    await _enqueue(
      _OfflineCleanupKind.bookingPhoto,
      jsonEncode({'booking_id': target.bookingId, 'path': target.path}),
    );
  }

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
    final generation = ++_flushGeneration;
    final flush = _flushPendingCleanupsInternal(
      generation,
    ).timeout(_flushTimeout);
    _flushFuture = flush;
    try {
      await flush;
    } on TimeoutException catch (error, stack) {
      // A stuck local read, Storage request, or Firestore callback must not
      // hold the cleanup lock forever. The entry remains persisted and the
      // normal retry timer/network signal can make another bounded attempt.
      unawaited(
        SyncErrorLogService.instance.report(
          error,
          stack,
          source: 'offline_cleanup_queue_service.dart',
          operation: 'cleanup flush timeout',
          kind: 'cleanup_flush_timeout',
        ),
      );
      _setStatus(
        _currentStatus.copyWith(
          isSyncing: false,
          processedInBatch: 0,
          totalInBatch: 0,
        ),
      );
    } finally {
      if (identical(_flushFuture, flush)) {
        _flushFuture = null;
      }
    }
  }

  void _setStatusForGeneration(
    int generation,
    OfflineQueueStatusSnapshot nextStatus,
  ) {
    if (generation != _flushGeneration) {
      return;
    }
    _setStatus(nextStatus);
  }

  Future<void> _flushPendingCleanupsInternal(int generation) async {
    try {
      await _queueMutationTail;
      final currentStorageKey = await _resolvedStorageKey();
      final storageKeys = await _allKnownStorageKeys();
      for (final storageKey in storageKeys) {
        await _flushPendingCleanupsForStorageKey(
          storageKey,
          updateStatus: storageKey == currentStorageKey,
          generation: generation,
        );
      }
      await _refreshStatusFromStorage();
    } finally {
      if (_currentStatus.isSyncing && generation == _flushGeneration) {
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

  Future<_CleanupApplyResult> _applyEntry(_OfflineCleanupEntry entry) async {
    switch (entry.kind) {
      case _OfflineCleanupKind.bookingPhoto:
        final target = _parseBookingPhotoTarget(entry.targetPath);
        // A persisted malformed target is terminal. Retrying it can never make
        // a blank or unsafe Storage path valid.
        if (target == null) return _CleanupApplyResult.alreadyResolved;
        final firestore = _providedFirestore ?? FirebaseFirestore.instance;
        final ref = firestore.collection('bookings').doc(target.bookingId);

        // Preflight recovered work against the current server state before
        // reopening a transaction for work another attempt already completed.
        // Fresh work skips the extra read; the transaction recheck below always
        // decides, and read failures still flow through the transient path.
        if (entry.retryCount > 0 || entry.lastError != null) {
          final current = await ref
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 10));
          final state = _bookingCleanupState(current.data(), target.path);
          if (state != _BookingCleanupState.pending) {
            if (state == _BookingCleanupState.claimed) {
              return _recoverClaimedBookingPhoto(
                ref,
                target.path,
                entryId: entry.id,
                cleanupQueuedAtIso: entry.createdAtIso,
              );
            }
            return _CleanupApplyResult.alreadyResolved;
          }
        }

        final claimed = await runTransactionWithOriginalErrors<bool>(
          firestore,
          (transaction) async {
            final snapshot = await transaction.get(ref);
            if (_bookingCleanupState(snapshot.data(), target.path) !=
                _BookingCleanupState.pending) {
              return false;
            }
            transaction.update(ref, {
              'photo_cleanup_claims': FieldValue.arrayUnion([target.path]),
            });
            return true;
          },
        ).timeout(const Duration(seconds: 10));
        if (!claimed) {
          return _recoverClaimedBookingPhoto(
            ref,
            target.path,
            entryId: entry.id,
            cleanupQueuedAtIso: entry.createdAtIso,
          );
        }
        await _deleteByPathNow(
          target.path,
        ).timeout(const Duration(seconds: 20));
        // A claim is only a lease for the delete operation. Once Storage has
        // confirmed deletion, remove both the work item and the claim in the
        // same Firestore update. Leaving either field behind can block future
        // booking edits or make a later retry falsely appear complete.
        await ref
            .update({
              'photo_cleanup_paths': FieldValue.arrayRemove([target.path]),
              'photo_cleanup_claims': FieldValue.arrayRemove([target.path]),
            })
            .timeout(const Duration(seconds: 10));
        return _CleanupApplyResult.deleted;
      case _OfflineCleanupKind.deleteByPath:
        await _deleteByPathNow(entry.targetPath).timeout(_operationTimeout);
        return _CleanupApplyResult.deleted;
      case _OfflineCleanupKind.deleteFolder:
        await _deleteFolderRecursively(
          entry.targetPath,
        ).timeout(_operationTimeout);
        return _CleanupApplyResult.deleted;
    }
  }

  /// A retry can encounter a claim left by an earlier attempt. Never delete a
  /// path merely because it is claimed: first decide whether the object that is
  /// still there is the one this cleanup was queued to remove.
  ///
  /// Storage records when an object was created, and the entry records when the
  /// cleanup was queued. An object that predates the cleanup is the superseded
  /// photo the entry was created for, so the deletion can be finished without a
  /// human. An object created *after* the cleanup means the path was written
  /// again, and deleting it would destroy current content: that case still
  /// needs an explicit confirmation.
  Future<_CleanupApplyResult> _recoverClaimedBookingPhoto(
    DocumentReference<Map<String, dynamic>> ref,
    String path, {
    String? entryId,
    String? cleanupQueuedAtIso,
  }) async {
    final current = await ref
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    final state = _bookingCleanupState(current.data(), path);
    if (state != _BookingCleanupState.claimed) {
      return state == _BookingCleanupState.pending
          ? (_throwCleanupRace(path))
          : _CleanupApplyResult.alreadyResolved;
    }

    final object = await _storageObjectAge(path);
    if (object.exists) {
      final queuedAt = DateTime.tryParse(cleanupQueuedAtIso ?? '');
      // Only positive proof allows an unattended delete: the object must have a
      // creation time, the cleanup must have a queue time, and the object must
      // be older than the cleanup. Anything unknown - a metadata response with
      // no timestamp, a missing queue time - is treated as "might be current
      // content" and needs the explicit confirmation instead.
      final isSupersededObject =
          object.createdAt != null &&
          queuedAt != null &&
          !object.createdAt!.isAfter(queuedAt);
      if (!isSupersededObject) {
        // The path holds content this cleanup cannot prove is superseded, so
        // deleting now could destroy a current photo. Require the explicit
        // confirmation the queued-actions list sets for this id.
        if (entryId == null || !_confirmedClaimRetries.remove(entryId)) {
          throw StateError(
            'Sync conflict: cleanup is still claimed and the photo at this path '
            'cannot be proven older than the cleanup. Review the queued cleanup '
            'before retrying.',
          );
        }
      }
      await _deleteByPathNow(path).timeout(_operationTimeout);
    }

    final finalized = await runTransactionWithOriginalErrors<bool>(
      _firestoreOrProvided(),
      (transaction) async {
        final snapshot = await transaction.get(ref);
        final latestState = _bookingCleanupState(snapshot.data(), path);
        if (latestState == _BookingCleanupState.notPending ||
            latestState == _BookingCleanupState.referenced ||
            latestState == _BookingCleanupState.malformed) {
          return false;
        }
        if (latestState != _BookingCleanupState.claimed) {
          throw StateError(
            'Sync conflict: cleanup claim changed while it was being recovered.',
          );
        }
        transaction.update(ref, {
          'photo_cleanup_paths': FieldValue.arrayRemove([path]),
          'photo_cleanup_claims': FieldValue.arrayRemove([path]),
        });
        return true;
      },
    ).timeout(const Duration(seconds: 10));
    return finalized
        ? _CleanupApplyResult.deleted
        : _CleanupApplyResult.alreadyResolved;
  }

  FirebaseFirestore _firestoreOrProvided() =>
      _providedFirestore ?? FirebaseFirestore.instance;

  /// Whether the object at [path] is still there, and when it was written.
  /// [createdAt] is null when the object exists but Storage reported no
  /// creation time; that is deliberately not the same as "absent".
  Future<({bool exists, DateTime? createdAt})> _storageObjectAge(
    String path,
  ) async {
    try {
      final metadata = await _storage
          .ref(path)
          .getMetadata()
          .timeout(const Duration(seconds: 10));
      return (exists: true, createdAt: metadata.timeCreated);
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') {
        return (exists: false, createdAt: null);
      }
      rethrow;
    }
  }

  Never _throwCleanupRace(String path) {
    throw StateError(
      'Sync conflict: cleanup state changed while processing $path. '
      'The queue will retry without deleting the photo.',
    );
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

  /// Classifies the server state before acting on a cleanup path. In
  /// particular, `claimed` is not equivalent to `notPending`: it may mean that
  /// a previous delete committed but its bookkeeping update timed out.
  static _BookingCleanupState _bookingCleanupState(
    Map<String, dynamic>? booking,
    String path,
  ) {
    if (booking == null) return _BookingCleanupState.notPending;
    final cleanupPaths = booking['photo_cleanup_paths'];
    if (cleanupPaths is! List) return _BookingCleanupState.malformed;
    if (!cleanupPaths.whereType<String>().contains(path)) {
      return _BookingCleanupState.notPending;
    }
    if (BookingPhotoCleanup.references(
      booking['status_outputs'],
    ).contains(path)) {
      return _BookingCleanupState.referenced;
    }
    final claims = booking['photo_cleanup_claims'];
    if (claims == null) return _BookingCleanupState.pending;
    if (claims is! List) return _BookingCleanupState.malformed;
    return claims.whereType<String>().contains(path)
        ? _BookingCleanupState.claimed
        : _BookingCleanupState.pending;
  }

  _BookingPhotoTarget? _parseBookingPhotoTarget(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final bookingId = decoded['booking_id'];
    final path = decoded['path'];
    if ((bookingId is! String && bookingId is! num) || path is! String) {
      return null;
    }
    return _bookingPhotoTargetFromValues(bookingId.toString(), path);
  }

  _BookingPhotoTarget? _bookingPhotoTargetFromValues(
    String bookingId,
    String path,
  ) {
    final normalizedId = normalizeId(bookingId);
    final normalizedPath = path.trim();
    if (normalizedId == null ||
        !RegExp(r'^\d+$').hasMatch(normalizedId) ||
        int.tryParse(normalizedId) == 0 ||
        !_isSafeBookingPhotoPath(normalizedId, normalizedPath)) {
      return null;
    }
    return _BookingPhotoTarget(bookingId: normalizedId, path: normalizedPath);
  }

  bool _isSafeBookingPhotoPath(String bookingId, String path) {
    final prefix = 'bookings/$bookingId/status_outputs/';
    if (!path.startsWith(prefix) ||
        path.contains('//') ||
        path.contains('\\') ||
        path.contains('?') ||
        path.contains('#') ||
        path.endsWith('/')) {
      return false;
    }
    if (path.codeUnits.any((unit) => unit < 32)) return false;
    final segments = path.split('/');
    return segments.length >= 6 &&
        segments[0] == 'bookings' &&
        segments[1] == bookingId &&
        segments[2] == 'status_outputs' &&
        segments.every(
          (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
        );
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
    required int generation,
  }) async {
    final entries = await _readEntriesForStorageKey(storageKey);
    final now = DateTime.now().toUtc();
    final hasDueWork = entries.any(
      (entry) => entry.nextRetryAt?.isAfter(now) != true,
    );
    if (!hasDueWork) {
      if (updateStatus) {
        _setStatusForGeneration(
          generation,
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
      _setStatusForGeneration(
        generation,
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

    final confirmedSuccesses = <String>{};
    final remaining = <_OfflineCleanupEntry>[];
    var processed = 0;
    for (final entry in entries) {
      try {
        if (entry.nextRetryAt?.isAfter(DateTime.now().toUtc()) == true) {
          remaining.add(entry);
          continue;
        }
        await _applyEntry(entry).timeout(_operationTimeout);
        // A terminal no-op (malformed target, already claimed, or already
        // removed) is also a completed action and must clear old diagnostics.
        confirmedSuccesses.add(entry.id);
      } catch (error, stackTrace) {
        final normalizedError = normalizeUserErrorText(
          error.toString(),
          fallback: 'Something went wrong. Please try again.',
        );
        final retryable =
            error is TimeoutException || _isRetryable(normalizedError);
        final delaySeconds = retryable
            ? min(1200, 20 * pow(2, min(entry.retryCount, 6)).toInt())
            : 1200;
        remaining.add(
          entry.copyWith(
            retryCount: entry.retryCount + 1,
            lastError: normalizedError,
            diagnostics: await offlineErrorDiagnostics(
              error: error,
              stack: stackTrace,
              source: 'offline_cleanup_queue_service.dart',
              operation: entry.kind.name,
              entryId: entry.id,
              target: entry.targetPath,
              attempt: entry.retryCount + 1,
              owner: storageKey.substring('$_storageKey::'.length),
              actionAt: entry.createdAtIso,
              context: {'next_retry_delay_seconds': delaySeconds},
            ),
            nextRetryAt: DateTime.now().toUtc().add(
              Duration(seconds: delaySeconds),
            ),
          ),
        );
      } finally {
        processed++;
        if (updateStatus) {
          _setStatusForGeneration(
            generation,
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

    unawaited(
      SyncErrorLogService.instance.resolveQueueEntries(
        storageKey,
        confirmedSuccesses,
      ),
    );
    if (updateStatus) {
      _setStatusForGeneration(
        generation,
        _currentStatus.copyWith(
          pendingCount: remaining.length,
          failedCount: remaining
              .where((entry) => entry.lastError != null)
              .length,
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
        normalized.contains('timeoutexception') ||
        normalized.contains('timeout') ||
        normalized.contains('future not completed') ||
        normalized.contains('network') ||
        normalized.contains('try again');
  }

  String _nextEntryId(String prefix) {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomSuffix = Random().nextInt(0x100000000).toRadixString(16);
    return '${prefix}_${timestamp}_$randomSuffix';
  }
}

enum _OfflineCleanupKind { deleteByPath, deleteFolder, bookingPhoto }

enum _CleanupApplyResult { deleted, alreadyResolved }

enum _BookingCleanupState {
  pending,
  claimed,
  notPending,
  referenced,
  malformed,
}

class _BookingPhotoTarget {
  const _BookingPhotoTarget({required this.bookingId, required this.path});

  final String bookingId;
  final String path;
}

class _OfflineCleanupEntry {
  const _OfflineCleanupEntry({
    required this.id,
    required this.kind,
    required this.targetPath,
    required this.createdAtIso,
    required this.retryCount,
    this.lastError,
    this.diagnostics,
    this.nextRetryAt,
  });

  final String id;
  final _OfflineCleanupKind kind;
  final String targetPath;
  final String createdAtIso;
  final int retryCount;
  final String? lastError;
  final String? diagnostics;
  final DateTime? nextRetryAt;

  _OfflineCleanupEntry copyWith({
    int? retryCount,
    String? lastError,
    String? diagnostics,
    DateTime? nextRetryAt,
    bool clearLastError = false,
    bool clearDiagnostics = false,
    bool clearNextRetryAt = false,
  }) {
    return _OfflineCleanupEntry(
      id: id,
      kind: kind,
      targetPath: targetPath,
      createdAtIso: createdAtIso,
      retryCount: retryCount ?? this.retryCount,
      lastError: clearLastError ? null : lastError ?? this.lastError,
      diagnostics: clearDiagnostics ? null : diagnostics ?? this.diagnostics,
      nextRetryAt: clearNextRetryAt ? null : nextRetryAt ?? this.nextRetryAt,
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
      if (diagnostics != null) 'error_diagnostics': diagnostics,
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
      diagnostics: map['error_diagnostics']?.toString(),
      nextRetryAt: DateTime.tryParse(map['next_retry_at']?.toString() ?? ''),
    );
  }
}
