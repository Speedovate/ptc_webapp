import 'sync_error_log_service.dart';
import 'package:webapp/services/firestore_transaction_errors.dart';
import 'package:webapp/services/offline_error_diagnostics.dart';
import 'package:webapp/models/offline_queue_item.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:webapp/services/booking_id_resolver.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/image_upload_processor.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_sync_status_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/utils/functions.dart';

class BookingOfflineUploadQueueService {
  BookingOfflineUploadQueueService({
    BookingStorageBackend? backend,
    FirebaseFirestore? firestore,
    PhotoStorageService? photoStorageService,
    Future<void> Function()? flushMutations,
    OfflineMutationQueueService? mutationQueue,
    Duration mutationFlushTimeout = _defaultMutationFlushTimeout,
    Future<Map<String, dynamic>?> Function(String bookingId)? bookingReader,
  }) : _backend = backend ?? createBookingStorageBackend(),
       _providedFirestore = firestore,
       _photoStorageService =
           photoStorageService ?? PhotoStorageService.instance,
       _flushMutations =
           flushMutations ??
           OfflineMutationQueueService.instance.flushPendingMutations,
       _mutationQueue = mutationQueue ?? OfflineMutationQueueService.instance,
       _mutationFlushTimeout = mutationFlushTimeout,
       _bookingReader = bookingReader;

  static final BookingOfflineUploadQueueService instance =
      BookingOfflineUploadQueueService();

  /// Reads a booking to confirm a staged photo is still wanted. Injected so the
  /// stalled-read path is testable without a hostile Firestore double, and so
  /// the caller can decide how long a confirmation is worth waiting for.
  final Future<Map<String, dynamic>?> Function(String bookingId)?
  _bookingReader;

  static const _storageKey = 'booking_pending_upload_queue_v1';
  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';
  static const _retryInterval = Duration(seconds: 20);

  /// Re-reading the booking to confirm a placeholder is a small single-document
  /// read, so it gets a generous budget. A phone on mobile data routinely needs
  /// more than a few seconds, and a stalled confirmation must never be mistaken
  /// for a failed upload.
  static const markerCheckTimeout = Duration(seconds: 20);
  static const _mutationCheckTimeout = Duration(seconds: 15);
  static const _localStoreTimeout = Duration(seconds: 20);
  static const _escalateWaitAfterCycles = 3;
  static const _defaultMutationFlushTimeout = Duration(minutes: 2);

  final BookingStorageBackend _backend;
  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final PhotoStorageService _photoStorageService;
  final Future<void> Function() _flushMutations;
  final OfflineMutationQueueService _mutationQueue;
  final Duration _mutationFlushTimeout;
  final ImageUploadProcessor _imageUploadProcessor =
      ImageUploadProcessor.instance;
  final AuthStorageBackend _authStorage = createAuthStorageBackend();

  bool _isInitialized = false;
  bool _isFlushing = false;
  final Map<String, int> _waitCycles = <String, int>{};
  Timer? _retryTimer;
  StreamSubscription<bool>? _networkSubscription;
  final StreamController<OfflineQueueStatusSnapshot> _statusController =
      StreamController<OfflineQueueStatusSnapshot>.broadcast();
  OfflineQueueStatusSnapshot _currentStatus =
      const OfflineQueueStatusSnapshot.idle();

  CollectionReference<Map<String, dynamic>> get _bookingsCollection =>
      _firestore.collection('bookings');

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
            title: 'Upload booking photo',
            recordLabel: OfflineQueueItem.record('bookings', entry.bookingId),
            createdAt: DateTime.tryParse(entry.createdAtIso),
            hasError: entry.lastError?.isNotEmpty == true,
            errorMessage: entry.lastError,
            diagnostics: entry.diagnostics,
            pendingMessage: _PhotoWaitReason.fromKey(
              entry.waitReason,
            )?.pendingMessage,
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
    // A device store that never answers must not leave this queue permanently
    // uninitialized: every later timer, resume, and enqueue would keep waiting
    // on the same pending read with nothing reported to the user.
    await _backend.initialize().timeout(
      _localStoreTimeout,
      onTimeout: () =>
          throw TimeoutException('Local photo queue storage did not respond.'),
    );
    await _refreshStatusFromStorage();
    _retryTimer ??= Timer.periodic(_retryInterval, (_) {
      if (!isAppVisible()) return;
      unawaited(flushPendingUploads());
    });
    _networkSubscription ??= networkStatusEvents().listen((isOnline) {
      if (isOnline && isAppVisible()) {
        unawaited(flushPendingUploads());
      }
    });
    _isInitialized = true;
    unawaited(flushPendingUploads());
  }

  Future<void> _queueMutationTail = Future<void>.value();
  final Object _storageScopeKey = Object();

  Future<T> _mutateQueue<T>(
    Future<T> Function() action, {
    String? originatingStorageKey,
  }) {
    // Capture the originating account before waiting for another local write.
    final scope = originatingStorageKey == null
        ? _resolvedStorageKey()
        : Future.value(originatingStorageKey);
    final next = _queueMutationTail.then((_) async {
      final storageKey = await scope;
      return runZoned(action, zoneValues: {_storageScopeKey: storageKey});
    });
    _queueMutationTail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<Map<String, dynamic>> enqueueBookingPhoto({
    required String bookingId,
    required String statusKey,
    required String fieldKey,
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    int? size,
    bool waitForBookingCommit = false,
  }) async {
    final actionAt = DateTime.now().toUtc();
    final originatingStorageKey = await _resolvedStorageKey();
    await initialize();
    final processed = await _imageUploadProcessor.prepare(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );

    return _mutateQueue(() async {
      final entries = await _readEntries();
      final encodedBytes = base64Encode(processed.bytes);
      final staged = entries
          .where(
            (entry) =>
                entry.bookingId == bookingId &&
                entry.statusKey == statusKey &&
                entry.fieldKey == fieldKey &&
                entry.bytesBase64 == encodedBytes,
          )
          .firstOrNull;
      final entry =
          staged ??
          _PendingBookingUploadEntry(
            id: _nextEntryId(),
            waitingForCommit: waitForBookingCommit,
            bookingId: bookingId,
            statusKey: statusKey,
            fieldKey: fieldKey,
            bytesBase64: base64Encode(processed.bytes),
            fileName: processed.fileName,
            mimeType: processed.mimeType,
            size: processed.size,
            createdAtIso: actionAt.toIso8601String(),
            retryCount: 0,
            lastError: null,
          );

      if (staged == null) {
        entries.add(entry);
        await _writeEntries(entries);
      }
      _setStatus(_currentStatus.copyWith(pendingCount: entries.length));
      unawaited(flushPendingUploads());

      final resolvedMimeType = processed.mimeType.trim().isNotEmpty
          ? processed.mimeType.trim()
          : 'image/jpeg';
      final previewDataUrl =
          'data:$resolvedMimeType;base64,${base64Encode(processed.bytes)}';

      return {
        'name': processed.fileName,
        'download_url': previewDataUrl,
        'mime_type': processed.mimeType,
        'size': processed.size,
        'pending_upload': true,
        'pending_upload_id': entry.id,
      };
    }, originatingStorageKey: originatingStorageKey);
  }

  Future<void> flushPendingUploads() async {
    await initialize();
    if (_isFlushing || !currentNetworkStatus()) {
      return;
    }

    // Acquire ownership before awaiting dependencies: timer and resume events
    // must not both proceed into the same upload batch.
    _isFlushing = true;
    try {
      await _runFlushCycle();
    } on TimeoutException catch (error) {
      // Release the flush lock on a stalled dependency so the next timer,
      // resume, or reconnect can try again. Entries are only removed after a
      // confirmed apply, so an abandoned cycle never loses queued photos.
      unawaited(
        SyncErrorLogService.instance.report(
          error,
          StackTrace.current,
          source: 'booking_offline_upload_queue_service.dart',
          operation: 'bookingPhotoUploadCycle',
          details: {
            'mutation_flush_timeout_seconds': _mutationFlushTimeout.inSeconds,
            'released_flush_lock': true,
          },
        ),
      );
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

  Future<void> _runFlushCycle() async {
    // Persist pending-upload markers before replacing them with storage URLs.
    // The booking mutation flush has no internal deadline, so bound it here:
    // a stall there would otherwise hold this queue's flush lock forever and
    // silently disable every later retry.
    await _flushMutations().timeout(
      _mutationFlushTimeout,
      onTimeout: () => throw TimeoutException(
        'Queued booking changes did not sync in time; photos will retry.',
      ),
    );
    _markPendingAsSyncing();
    final currentStorageKey = await _resolvedStorageKey();
    final storageKeys = await _allKnownStorageKeys();
    for (final storageKey in storageKeys) {
      await _flushPendingUploadsForStorageKey(
        storageKey,
        updateStatus: storageKey == currentStorageKey,
      );
    }
    await _refreshStatusFromStorage();
  }

  Future<bool> _applyUploadedPhoto({
    required _PendingBookingUploadEntry entry,
    required Map<String, dynamic> uploadedValue,
  }) async {
    final documentRef = _bookingsCollection.doc(entry.bookingId);
    var applied = false;

    await runTransactionWithOriginalErrors(_firestore, (transaction) async {
      applied = false;
      final snapshot = await transaction.get(documentRef);
      if (!snapshot.exists) {
        return;
      }

      final currentData = documentData(snapshot);
      final statusOutputs = _statusOutputsFromBooking(currentData);
      if (statusOutputs == null) {
        return;
      }

      final currentField = _fieldValueFromStatusOutputs(
        statusOutputs,
        statusKey: entry.statusKey,
        fieldKey: entry.fieldKey,
      );
      final currentPendingId = _pendingUploadId(currentField);
      if (currentPendingId != entry.id) {
        return;
      }

      transaction.update(documentRef, {
        'status_outputs.${entry.statusKey}.fields.${entry.fieldKey}':
            uploadedValue,
        'status_outputs.${entry.statusKey}.fields.${entry.fieldKey}.pending_upload':
            FieldValue.delete(),
        'status_outputs.${entry.statusKey}.fields.${entry.fieldKey}.pending_upload_id':
            FieldValue.delete(),
        'media_synced_at': DateTime.now().toUtc().toIso8601String(),
      });
      applied = true;
    });

    return applied;
  }

  Future<bool> _shouldKeepEntryAfterFailure(
    _PendingBookingUploadEntry entry,
  ) async {
    try {
      final snapshot = await _bookingsCollection
          .doc(entry.bookingId)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!snapshot.exists) {
        return false;
      }
      final statusOutputs = _statusOutputsFromBooking(documentData(snapshot));
      final currentField = _fieldValueFromStatusOutputs(
        statusOutputs,
        statusKey: entry.statusKey,
        fieldKey: entry.fieldKey,
      );
      return _pendingUploadId(currentField) == entry.id;
    } catch (_) {
      return true;
    }
  }

  /// Returns true when a queued booking mutation still owns this booking, and
  /// null when the check itself could not finish. A failure here must never be
  /// read as "no pending write": uploading early would patch a booking that
  /// has no placeholder for this photo yet.
  Future<bool?> _hasPendingBookingMutation(
    String bookingId,
    String storageKey,
  ) async {
    try {
      return await _mutationQueue
          .hasPendingBookingMutation(bookingId, storageKey: storageKey)
          .timeout(_mutationCheckTimeout);
    } on TimeoutException {
      return null;
    } on Object {
      return true;
    }
  }

  /// A booking document written after this photo was staged can no longer
  /// carry its marker, and no queued booking write remains to restore it.
  bool _bookingOutlivedStagedPhoto(
    Map<String, dynamic> booking,
    _PendingBookingUploadEntry entry,
  ) {
    final bookingUpdatedAt = DateTime.tryParse('${booking['updated_at']}');
    final stagedAt = DateTime.tryParse(entry.createdAtIso);
    if (bookingUpdatedAt == null || stagedAt == null) {
      return false;
    }
    return bookingUpdatedAt.isAfter(stagedAt);
  }

  /// Records why this entry stayed on the device. A wait is normal for a few
  /// cycles while the booking write lands, so only the first wait and a change
  /// of reason are written back. Once the same wait survives
  /// `_escalateWaitAfterCycles` flush cycles it becomes a recorded error, so
  /// the entry surfaces in the queued actions list and the admin error log
  /// instead of waiting silently forever.
  ///
  /// The cycle count is kept in memory on purpose: persisting it every cycle
  /// would rewrite the stored base64 photo on every retry, and a count that is
  /// only written back on escalation can never reach that threshold.
  Future<_WaitOutcome> _noteWait(
    _PendingBookingUploadEntry entry,
    _PhotoWaitReason reason, {
    required String storageKey,
  }) async {
    final waitCount = (_waitCycles[entry.id] ?? entry.waitCount) + 1;
    _waitCycles[entry.id] = waitCount;
    final reasonChanged = entry.waitReason != reason.key;
    final escalate =
        entry.lastError == null && waitCount > _escalateWaitAfterCycles;
    final lastError =
        entry.lastError ??
        (escalate
            ? 'This photo is still waiting: ${reason.explanation}. '
                  'Open the booking, check the photo field, and retry the upload.'
            : null);
    String? diagnostics = entry.diagnostics;
    if (escalate) {
      diagnostics = await offlineErrorDiagnostics(
        error: StateError(
          'Queued booking photo made no progress: ${reason.explanation}.',
        ),
        stack: StackTrace.current,
        source: 'booking_offline_upload_queue_service.dart',
        operation: 'bookingPhotoUpload',
        entryId: entry.id,
        target:
            'bookings/${entry.bookingId}/${entry.statusKey}/${entry.fieldKey}',
        owner: storageKey.substring('$_storageKey::'.length),
        actionAt: entry.createdAtIso,
        attempt: entry.retryCount + 1,
        context: {
          'wait_reason': reason.key,
          'wait_cycles': waitCount,
          'booking_status': entry.statusKey,
          'field_key': entry.fieldKey,
          'media_size': entry.size,
        },
      );
    }
    return _WaitOutcome(
      entry.copyWith(
        waitCount: waitCount,
        waitReason: reason.key,
        lastError: lastError,
        diagnostics: diagnostics,
      ),
      persisted: waitCount == 1 || reasonChanged || escalate,
    );
  }

  Future<List<_PendingBookingUploadEntry>> _readEntries() async {
    final rawEntries = await _backend.readStringList(
      await _resolvedStorageKey(),
    );
    return rawEntries
        .map((entry) => jsonDecode(entry) as Map<String, dynamic>)
        .map(_PendingBookingUploadEntry.fromMap)
        .toList();
  }

  Future<void> _writeEntries(List<_PendingBookingUploadEntry> entries) async {
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

  Future<List<_PendingBookingUploadEntry>> _readEntriesForStorageKey(
    String storageKey,
  ) async {
    final rawEntries = await _backend.readStringList(storageKey);
    return rawEntries
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .map(_PendingBookingUploadEntry.fromMap)
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
    List<_PendingBookingUploadEntry> entries,
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

  Future<void> _flushPendingUploadsForStorageKey(
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

    var mutated = false;
    // Ids whose queued work has reached an end state: uploaded, or legitimately
    // reclaimed because the server already holds a newer photo. Either way the
    // crew has nothing left to do, so the original failure report must stop
    // asking for attention instead of lingering forever.
    final confirmedSuccesses = <String>{};
    final remaining = <_PendingBookingUploadEntry>[];
    var processed = 0;

    for (final sourceEntry in entries) {
      var entry = sourceEntry;
      try {
        if (BookingIdResolver.isTemporary(entry.bookingId)) {
          final resolved = await BookingIdResolver(
            firestore: _firestore,
          ).resolve(entry.bookingId);
          if (resolved == null) {
            final wait = await _noteWait(
              entry,
              _PhotoWaitReason.temporaryBookingId,
              storageKey: storageKey,
            );
            mutated = mutated || wait.persisted;
            remaining.add(wait.entry);
            continue;
          }
          entry = entry.copyWith(bookingId: resolved);
        }
        final hasPendingMutation = await _hasPendingBookingMutation(
          entry.bookingId,
          storageKey,
        );
        final hasProvisionalMutation = sourceEntry.bookingId != entry.bookingId
            ? await _hasPendingBookingMutation(
                sourceEntry.bookingId,
                storageKey,
              )
            : hasPendingMutation;
        final checkUnanswered =
            hasPendingMutation == null || hasProvisionalMutation == null;
        // A queued booking write owns this booking: the photo placeholder it
        // carries is not on the server yet, so uploading now would patch a
        // field that does not exist.
        if (checkUnanswered ||
            hasPendingMutation == true ||
            hasProvisionalMutation == true) {
          final wait = await _noteWait(
            entry,
            checkUnanswered
                ? _PhotoWaitReason.mutationCheckTimedOut
                : _PhotoWaitReason.bookingMutationPending,
            storageKey: storageKey,
          );
          mutated = mutated || wait.persisted;
          remaining.add(wait.entry);
          continue;
        }
        // This read only confirms the placeholder is still wanted. A slow answer
        // is not a failure: the bytes are already captured and safe, so a stalled
        // read must become a visible wait and retry. Throwing here used to mark
        // the photo failed - and lose an otherwise complete capture - on nothing
        // more than a slow connection.
        Map<String, dynamic>? markerData;
        try {
          final reader = _bookingReader;
          markerData = reader != null
              ? await reader(entry.bookingId).timeout(markerCheckTimeout)
              : (await _bookingsCollection
                        .doc(entry.bookingId)
                        .get()
                        .timeout(markerCheckTimeout))
                    .data();
        } catch (_) {
          final wait = await _noteWait(
            entry,
            _PhotoWaitReason.markerCheckTimedOut,
            storageKey: storageKey,
          );
          mutated = mutated || wait.persisted;
          remaining.add(wait.entry);
          continue;
        }
        if (markerData == null) {
          // The booking write that carries this photo has not landed yet.
          // Keep the bytes, but record why so the queue is never silent.
          final wait = await _noteWait(
            entry,
            _PhotoWaitReason.bookingMissing,
            storageKey: storageKey,
          );
          mutated = mutated || wait.persisted;
          remaining.add(wait.entry);
          continue;
        }
        final markerField = _fieldValueFromStatusOutputs(
          _statusOutputsFromBooking(markerData),
          statusKey: entry.statusKey,
          fieldKey: entry.fieldKey,
        );
        if (_pendingUploadId(markerField) != entry.id) {
          final superseded =
              !entry.waitingForCommit ||
              _bookingOutlivedStagedPhoto(markerData, entry);
          if (superseded) {
            // The placeholder that owned this entry is gone and no queued
            // booking write can bring it back. Reclaim the queued bytes
            // instead of waiting forever for a marker that never returns.
            mutated = true;
            // The photo was settled one way or another, so the failure that
            // queued it must stop asking the admin to act on it.
            confirmedSuccesses.add(entry.id);
            unawaited(
              SyncErrorLogService.instance.report(
                StateError(
                  'Dropped a queued booking photo that the server no longer accepts.',
                ),
                StackTrace.current,
                source: 'booking_offline_upload_queue_service.dart',
                operation: 'bookingPhotoUpload',
                target:
                    'bookings/${entry.bookingId}/${entry.statusKey}/${entry.fieldKey}',
                owner: storageKey.substring('$_storageKey::'.length),
                kind: 'queue_reclaimed',
                // The reclaim itself is the correct outcome, not a new problem,
                // so it is recorded for audit without demanding attention.
                attentionRequired: false,
                details: {
                  'reason': markerField == null
                      ? 'photo_field_missing'
                      : 'marker_superseded',
                  'server_photo_pending_upload_id':
                      _pendingUploadId(markerField) ?? 'none',
                  'queued_photo_id': entry.id,
                  'booking_updated_at': markerData['updated_at']?.toString(),
                  'photo_staged_at': entry.createdAtIso,
                },
              ),
            );
            continue;
          }
          final wait = await _noteWait(
            entry,
            markerField == null
                ? _PhotoWaitReason.photoFieldMissing
                : _PhotoWaitReason.markerSuperseded,
            storageKey: storageKey,
          );
          mutated = mutated || wait.persisted;
          remaining.add(wait.entry);
          continue;
        }
        entry = entry.copyWith(waitingForCommit: false, clearWaitReason: true);
        final upload = await _photoStorageService
            .uploadBookingPhoto(
              bytes: base64Decode(entry.bytesBase64),
              bookingId: entry.bookingId,
              statusKey: entry.statusKey,
              fieldKey: entry.fieldKey,
              fileName: entry.fileName,
              mimeType: entry.mimeType,
              size: entry.size,
            )
            .timeout(const Duration(seconds: 30));

        final applied = await _applyUploadedPhoto(
          entry: entry,
          uploadedValue: upload,
        ).timeout(const Duration(seconds: 15));

        if (!applied) {
          await _photoStorageService
              .deleteByPath(upload['storage_path']?.toString())
              .timeout(const Duration(seconds: 20));
        }

        if (applied) {
          confirmedSuccesses.addAll({
            if (entry.retryCount > 0 ||
                entry.lastError != null ||
                entry.waitCount > 0)
              entry.id,
          });
        }
        mutated = true;
      } catch (error, stackTrace) {
        final normalizedError = normalizeUserErrorText(
          error.toString(),
          fallback: 'Something went wrong. Please try again.',
        );
        final diagnostics = await offlineErrorDiagnostics(
          error: error,
          stack: stackTrace,
          source: 'booking_offline_upload_queue_service.dart',
          operation: 'bookingPhotoUpload',
          entryId: entry.id,
          target:
              'bookings/${entry.bookingId}/${entry.statusKey}/${entry.fieldKey}',
          attempt: entry.retryCount + 1,
          owner: storageKey.substring('$_storageKey::'.length),
          actionAt: entry.createdAtIso,
          context: {
            'booking_status': entry.statusKey,
            'field_key': entry.fieldKey,
            'media_size': entry.size,
          },
        );
        if (_isRetryableUploadError(normalizedError) ||
            normalizedError.toLowerCase().contains('sync conflict')) {
          // Persist the failure. Without this the entry keeps retrying with no
          // stored error, so the wait is indistinguishable from a fresh one.
          mutated = true;
          remaining.add(
            entry.copyWith(
              retryCount: entry.retryCount + 1,
              lastError: normalizedError,
              diagnostics: diagnostics,
            ),
          );
        } else {
          final shouldKeep =
              entry.waitingForCommit ||
              await _shouldKeepEntryAfterFailure(entry);
          if (shouldKeep) {
            // Persist the failure so a permanently failing upload is visible in
            // the queued actions list instead of retrying with no record.
            mutated = true;
            remaining.add(
              entry.copyWith(
                retryCount: entry.retryCount + 1,
                lastError: normalizedError,
                diagnostics: diagnostics,
              ),
            );
          } else {
            // The queued photo cannot be applied to this booking any more.
            // Reclaim the bytes, but never without a record: a silent discard
            // looks identical to a successful upload.
            mutated = true;
            confirmedSuccesses.add(entry.id);
            unawaited(
              SyncErrorLogService.instance.report(
                StateError(
                  'Dropped a queued booking photo that no longer applies.',
                ),
                StackTrace.current,
                source: 'booking_offline_upload_queue_service.dart',
                operation: 'bookingPhotoUpload',
                target:
                    'bookings/${entry.bookingId}/${entry.statusKey}/${entry.fieldKey}',
                owner: storageKey.substring('$_storageKey::'.length),
                kind: 'queue_reclaimed',
                // A photo the server will never accept is a settled outcome, not
                // an outstanding failure, so it must not keep asking for action.
                attentionRequired: false,
                details: {
                  'reason': 'upload_failed_permanently',
                  'error': normalizedError,
                  'queued_photo_id': entry.id,
                  'photo_staged_at': entry.createdAtIso,
                  'attempt': entry.retryCount + 1,
                },
              ),
            );
          }
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

    if (mutated || remaining.length != entries.length) {
      await _mutateQueue(() async {
        final latest = await _readEntriesForStorageKey(storageKey);
        final processedIds = entries.map((entry) => entry.id).toSet();
        final merged = [
          ...latest.where((entry) => !processedIds.contains(entry.id)),
          ...remaining,
        ];
        await _writeEntriesForStorageKey(storageKey, merged);
        final mergedIds = merged.map((entry) => entry.id).toSet();
        _waitCycles.removeWhere((id, _) => !mergedIds.contains(id));
      });
    }

    unawaited(
      SyncErrorLogService.instance.resolveQueueEntries(
        storageKey,
        confirmedSuccesses,
      ),
    );
    if (updateStatus) {
      _setStatus(
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

  Map<String, dynamic>? _statusOutputsFromBooking(
    Map<String, dynamic> booking,
  ) {
    final rawValue = booking['status_outputs'];
    if (rawValue is Map) {
      return Map<String, dynamic>.from(rawValue);
    }
    return null;
  }

  dynamic _fieldValueFromStatusOutputs(
    Map<String, dynamic>? statusOutputs, {
    required String statusKey,
    required String fieldKey,
  }) {
    final section = statusOutputs?[statusKey];
    if (section is! Map) {
      return null;
    }
    final fields = section['fields'];
    if (fields is! Map) {
      return null;
    }
    return fields[fieldKey];
  }

  String? _pendingUploadId(dynamic value) {
    final mapValue = value is Map<String, dynamic>
        ? value
        : value is Map
        ? Map<String, dynamic>.from(value)
        : null;
    final pendingId = mapValue?['pending_upload_id']?.toString().trim();
    if (pendingId == null || pendingId.isEmpty) {
      return null;
    }
    return pendingId;
  }

  bool _isRetryableUploadError(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized.contains('internet connection') ||
        normalized.contains('temporarily unavailable') ||
        normalized.contains('request took too long') ||
        normalized.contains('try again');
  }

  String _nextEntryId() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randomSuffix = Random().nextInt(0x100000000).toRadixString(16);
    return 'booking_upload_${timestamp}_$randomSuffix';
  }
}

class _PendingBookingUploadEntry {
  const _PendingBookingUploadEntry({
    required this.id,
    required this.bookingId,
    required this.statusKey,
    required this.fieldKey,
    required this.bytesBase64,
    required this.fileName,
    this.mimeType,
    this.size,
    required this.createdAtIso,
    required this.retryCount,
    this.lastError,
    this.diagnostics,
    this.waitingForCommit = false,
    this.waitCount = 0,
    this.waitReason,
  });

  final String id;
  final String bookingId;
  final String statusKey;
  final String fieldKey;
  final String bytesBase64;
  final String fileName;
  final String? mimeType;
  final int? size;
  final String createdAtIso;
  final int retryCount;
  final String? lastError;
  final String? diagnostics;
  final bool waitingForCommit;

  /// Flush cycles that made no progress for this entry. A wait is not a
  /// failure, but an endless wait without a recorded reason is
  /// indistinguishable from a stalled queue.
  final int waitCount;
  final String? waitReason;

  _PendingBookingUploadEntry copyWith({
    int? retryCount,
    String? lastError,
    String? diagnostics,
    String? bookingId,
    bool? waitingForCommit,
    int? waitCount,
    String? waitReason,
    bool clearWaitReason = false,
  }) {
    return _PendingBookingUploadEntry(
      id: id,
      waitingForCommit: waitingForCommit ?? this.waitingForCommit,
      bookingId: bookingId ?? this.bookingId,
      statusKey: statusKey,
      fieldKey: fieldKey,
      bytesBase64: bytesBase64,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
      createdAtIso: createdAtIso,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      diagnostics: diagnostics ?? this.diagnostics,
      waitCount: waitCount ?? this.waitCount,
      waitReason: clearWaitReason ? null : waitReason ?? this.waitReason,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'waiting_for_commit': waitingForCommit,
      'booking_id': bookingId,
      'status_key': statusKey,
      'field_key': fieldKey,
      'bytes_base64': bytesBase64,
      'file_name': fileName,
      'mime_type': mimeType,
      'size': size,
      'created_at': createdAtIso,
      'retry_count': retryCount,
      'last_error': lastError,
      'wait_count': waitCount,
      if (waitReason != null) 'wait_reason': waitReason,
      if (diagnostics != null) 'error_diagnostics': diagnostics,
    };
  }

  factory _PendingBookingUploadEntry.fromMap(Map<String, dynamic> map) {
    return _PendingBookingUploadEntry(
      id: map['id']?.toString() ?? '',
      waitingForCommit: map['waiting_for_commit'] == true,
      bookingId: map['booking_id']?.toString() ?? '',
      statusKey: map['status_key']?.toString() ?? '',
      fieldKey: map['field_key']?.toString() ?? '',
      bytesBase64: map['bytes_base64']?.toString() ?? '',
      fileName: map['file_name']?.toString() ?? 'photo',
      mimeType: map['mime_type']?.toString(),
      size: map['size'] is num
          ? (map['size'] as num).toInt()
          : int.tryParse(map['size']?.toString() ?? ''),
      createdAtIso: map['created_at']?.toString() ?? '',
      retryCount: map['retry_count'] is num
          ? (map['retry_count'] as num).toInt()
          : int.tryParse(map['retry_count']?.toString() ?? '') ?? 0,
      lastError: map['last_error']?.toString(),
      diagnostics: map['error_diagnostics']?.toString(),
      waitCount: map['wait_count'] is num
          ? (map['wait_count'] as num).toInt()
          : int.tryParse(map['wait_count']?.toString() ?? '') ?? 0,
      waitReason: map['wait_reason']?.toString(),
    );
  }
}

/// Why a flush cycle kept a photo on this device instead of uploading it.
/// Recorded on the entry so the queue can explain itself instead of waiting
/// forever behind one generic status line.
enum _PhotoWaitReason {
  temporaryBookingId(
    'temporary_booking_id',
    'the saved booking has no server ID yet',
    'Waiting for the booking ID to sync',
  ),
  bookingMutationPending(
    'booking_mutation_pending',
    'the booking changes carrying this photo are still queued',
    'Waiting for the booking update to sync',
  ),
  bookingMissing(
    'booking_missing',
    'the booking is not on the server yet',
    'Waiting for the booking to reach the server',
  ),
  photoFieldMissing(
    'photo_field_missing',
    'the booking on the server no longer has this photo field',
    'The server has no matching photo field',
  ),
  markerSuperseded(
    'marker_superseded',
    'this booking field already holds a newer photo',
    'A newer photo is already saved in this field',
  ),
  mutationCheckTimedOut(
    'mutation_check_timed_out',
    'the booking queue did not answer in time',
    'Waiting for the booking queue to respond',
  ),
  markerCheckTimedOut(
    'marker_check_timed_out',
    'the booking could not be re-read to confirm this photo is still wanted',
    'Waiting for the booking to be re-read',
  );

  const _PhotoWaitReason(this.key, this.explanation, this.pendingMessage);

  final String key;
  final String explanation;
  final String pendingMessage;

  static _PhotoWaitReason? fromKey(String? key) {
    if (key == null) return null;
    for (final reason in values) {
      if (reason.key == key) return reason;
    }
    return null;
  }
}

class _WaitOutcome {
  const _WaitOutcome(this.entry, {required this.persisted});

  final _PendingBookingUploadEntry entry;

  /// True when the stored entry changed enough to be worth rewriting the
  /// queue. Repeated waits with the same reason are not persisted, so a stuck
  /// photo never rewrites its own base64 payload every cycle.
  final bool persisted;
}
