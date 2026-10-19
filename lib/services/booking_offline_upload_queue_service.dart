import 'sync_error_log_service.dart';
import 'orphan_photo_recovery_service.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'booking_photo_marker_match.dart';
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
    Future<Map<String, dynamic>?> Function(String bookingId)?
    cachedBookingReader,
    DateTime Function()? now,
  }) : _backend = backend ?? createBookingStorageBackend(),
       _providedFirestore = firestore,
       _photoStorageService =
           photoStorageService ?? PhotoStorageService.instance,
       _flushMutations =
           flushMutations ??
           OfflineMutationQueueService.instance.flushPendingMutations,
       _mutationQueue = mutationQueue ?? OfflineMutationQueueService.instance,
       _mutationFlushTimeout = mutationFlushTimeout,
       _bookingReader = bookingReader,
       _cachedBookingReader = cachedBookingReader,
       _now = now ?? DateTime.now;

  static final BookingOfflineUploadQueueService instance =
      BookingOfflineUploadQueueService();

  /// Reads a booking to confirm a staged photo is still wanted. Injected so the
  /// stalled-read path is testable without a hostile Firestore double, and so
  /// the caller can decide how long a confirmation is worth waiting for.
  final Future<Map<String, dynamic>?> Function(String bookingId)?
  _bookingReader;
  final Future<Map<String, dynamic>?> Function(String bookingId)?
  _cachedBookingReader;

  static const _storageKey = 'booking_pending_upload_queue_v1';
  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';
  static const _retryInterval = Duration(seconds: 20);
  static const _missingPhotoRecheckInterval = Duration(minutes: 5);
  final DateTime Function() _now;
  final Map<String, DateTime> _missingPhotoRecheckAt = {};

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

  OrphanPhotoRecoveryService get orphanPhotoRecovery => _photoRecoveryService();

  OrphanPhotoRecoveryService _photoRecoveryService({bool automatic = false}) =>
      OrphanPhotoRecoveryService(
        backend: _backend,
        firestore: _firestore,
        photos: _photoStorageService,
        requireOwner: (owner) async {
          if (automatic) {
            if (!RegExp(r'^[0-9]+$').hasMatch(owner)) {
              throw StateError('The original queue owner cannot be verified.');
            }
            return;
          }
          await _authStorage.initialize();
          if (owner.isEmpty ||
              owner == 'signed_out' ||
              await _authStorage.readString(_currentUserIdKey) != owner) {
            throw StateError(
              'The active account changed. Reopen the queue for its owner.',
            );
          }
        },
        hasPending: (id, owner) =>
            _hasPendingBookingMutation(id, _storageKeyForUserId(owner)),
        withQueueLock: (action) => _mutateQueue(action),
        onResolved: (owner, id) async {
          await _refreshStatusFromStorage();
          unawaited(
            SyncErrorLogService.instance.resolveQueueEntries(
              _storageKeyForUserId(owner),
              {id},
            ),
          );
        },
      );

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
            photoRecoveryId:
                BookingIdResolver.isTemporary(entry.bookingId) &&
                    entry.waitReason == 'temporary_booking_id'
                ? entry.id
                : null,
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
      unawaited(flushPendingUploads(background: true));
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

  Future<void> flushPendingUploads({bool background = false}) async {
    await initialize();
    if (_isFlushing || !currentNetworkStatus()) {
      return;
    }

    // Acquire ownership before awaiting dependencies: timer and resume events
    // must not both proceed into the same upload batch.
    _isFlushing = true;
    try {
      await _runFlushCycle(background: background);
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

  Future<void> _runFlushCycle({required bool background}) async {
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
      final owner = storageKey.substring('$_storageKey::'.length);
      if (RegExp(r'^[0-9]+$').hasMatch(owner)) {
        await _photoRecoveryService(
          automatic: true,
        ).restoreUnassignedPending(owner);
      }
      await _flushPendingUploadsForStorageKey(
        storageKey,
        updateStatus: storageKey == currentStorageKey,
        background: background,
      );
      if (RegExp(r'^[0-9]+$').hasMatch(owner)) {
        await _photoRecoveryService(
          automatic: true,
        ).reconcileUnassigned(owner, (original, archive) async {
          var entry = _PendingBookingUploadEntry.fromMap(original);
          final lookup = <String, dynamic>{};
          var resolved = await BookingIdResolver(
            firestore: _firestore,
          ).resolve(entry.bookingId, lookupEvidence: lookup);
          resolved ??= await _resolvePhotoBookingByMarker(entry, lookup);
          if (resolved == null ||
              await _hasPendingBookingMutation(entry.bookingId, storageKey) !=
                  false ||
              await _hasPendingBookingMutation(resolved, storageKey) != false) {
            return null;
          }
          entry = entry.copyWith(bookingId: resolved);
          final data =
              (await _bookingsCollection
                      .doc(resolved)
                      .get(const GetOptions(source: Source.server))
                      .timeout(markerCheckTimeout))
                  .data();
          if (data == null) return null;
          if (bookingPhotoAlreadyUploadedInHistory(
            booking: data,
            bookingId: resolved,
            fieldKey: entry.fieldKey,
            fileName: entry.fileName,
            size: entry.size,
            mimeType: entry.mimeType,
          )) {
            return {'booking_id': resolved};
          }
          final photo = _fieldValueFromStatusOutputs(
            _statusOutputsFromBooking(data),
            statusKey: entry.statusKey,
            fieldKey: entry.fieldKey,
          );
          if (photo is! Map ||
              _pendingUploadId(photo) != entry.id ||
              photo['name'] != entry.fileName ||
              photo['size'] != entry.size ||
              photo['mime_type'] != entry.mimeType) {
            return null;
          }
          Map<String, dynamic>? uploaded;
          if (archive['association_booking_id'] == resolved &&
              archive['association_photo'] is Map) {
            uploaded = Map<String, dynamic>.from(archive['association_photo']);
          }
          uploaded ??= await _photoStorageService.uploadBookingPhoto(
            bytes: base64Decode(entry.bytesBase64),
            bookingId: resolved,
            statusKey: entry.statusKey,
            fieldKey: entry.fieldKey,
            fileName: entry.fileName,
            mimeType: entry.mimeType,
            size: entry.size,
          );
          archive.addAll({
            'association_booking_id': resolved,
            'association_photo': uploaded,
          });
          final key = OrphanPhotoRecoveryService.archiveKey(owner, entry.id);
          await _backend.writeStringList(key, [jsonEncode(archive)]);
          if (!await _applyUploadedPhoto(
            entry: entry,
            uploadedValue: uploaded,
            strictOriginalMetadata: true,
          )) {
            return null;
          }
          return {'booking_id': resolved};
        }, force: !background);
      }
    }
    await _refreshStatusFromStorage();
  }

  Future<bool> _applyUploadedPhoto({
    required _PendingBookingUploadEntry entry,
    required Map<String, dynamic> uploadedValue,
    bool recoverHistoricalPhoto = false,
    String? matchingPendingUploadId,
    String? owner,
    bool strictOriginalMetadata = false,
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
      if (recoverHistoricalPhoto) {
        final historyKey = 'photo__${entry.id}';
        final outputs = _statusOutputsFromBooking(currentData);
        if (outputs?[historyKey] != null) {
          // An earlier transaction may have committed before its response was lost.
          final existing = outputs![historyKey];
          applied = existing is Map && existing['upload_id'] == entry.id;
          return;
        }
        if (!_canRecoverHistoricalPhoto(entry, currentData)) {
          return;
        }
        transaction.update(documentRef, {
          'status_outputs.$historyKey': {
            'status_key': 'photo',
            'submitted_at': entry.createdAtIso,
            if (owner != null && owner != 'signed_out') 'submitted_by': owner,
            'recovered_photo': true,
            'original_status_key': entry.statusKey,
            'upload_id': entry.id,
            'fields': {entry.fieldKey: uploadedValue},
          },
        });
        applied = true;
        return;
      }
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
      if (strictOriginalMetadata &&
          (currentField is! Map ||
              currentField['name'] != entry.fileName ||
              currentField['size'] != entry.size ||
              currentField['mime_type'] != entry.mimeType)) {
        return;
      }
      if (matchingPendingUploadId != null) {
        // Recheck both ownership and image content after the Storage upload.
        if (currentPendingId != matchingPendingUploadId ||
            !bookingPendingPhotoMatchesBytes(
              photo: currentField,
              fileName: entry.fileName,
              size: entry.size,
              mimeType: entry.mimeType,
              bytesBase64: entry.bytesBase64,
            )) {
          return;
        }
      } else if (currentPendingId != entry.id) {
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

  // Preserve an older staged photo as photo-only history, never reconstruct a
  // missing delivery form or roll the current booking back to an older status.
  bool _canRecoverHistoricalPhoto(
    _PendingBookingUploadEntry entry,
    Map<String, dynamic> booking,
  ) {
    if (!entry.statusKey.startsWith('ongoing__') ||
        entry.fieldKey != 'delivery_form_photo') {
      return false;
    }
    final staged = DateTime.tryParse(entry.createdAtIso);
    final delivered = DateTime.tryParse('${booking['delivered_at']}');
    if (staged == null || delivered == null || !delivered.isAfter(staged)) {
      return false;
    }
    final outputs = _statusOutputsFromBooking(booking);
    if (outputs == null || outputs.containsKey(entry.statusKey)) {
      return false;
    }
    return outputs.values.whereType<Map>().any((event) {
      final form = event['status_form'];
      final fields = event['fields'];
      return form is Map &&
          form['next_status_key'] == 'delivered' &&
          fields is Map &&
          fields[entry.fieldKey] is Map;
    });
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
          .hasPendingBookingMutation(
            bookingId,
            storageKey:
                'offline_mutation_queue_v1::${storageKey.substring('$_storageKey::'.length)}',
          )
          .timeout(_mutationCheckTimeout);
    } on TimeoutException {
      return null;
    } on Object {
      return true;
    }
  }

  /// A retried form may have committed under another submission key. Resolve
  /// only a unique server booking that still owns this exact upload marker,
  /// original event, actor, client and metadata. Never synthesize a booking or
  /// replace a reservation/repair mapping. The upload transaction rechecks it.
  Future<String?> _resolvePhotoBookingByMarker(
    _PendingBookingUploadEntry entry,
    Map<String, dynamic> evidence,
  ) async {
    if (evidence['result'] != 'no_server_identity' ||
        evidence['reservation_exists'] != false ||
        evidence['repair_exists'] != false) {
      return null;
    }
    final parts = RegExp(
      r'^offline_booking_([0-9]+)_([0-9]+)_([0-9]+)_([0-9]+)$',
    ).firstMatch(entry.bookingId);
    if (parts == null ||
        entry.statusKey != 'book__${parts[4]}' ||
        entry.fieldKey != 'waybill_photo') {
      return null;
    }
    return BookingIdResolver(
      firestore: _firestore,
    ).resolveRecoveryEvidence(entry.bookingId, 'photo_marker_${entry.id}', () async {
      evidence['photo_marker_lookup'] = {
        'stage': 'query_started',
        'read_source': 'server',
      };
      final matches = await _bookingsCollection
          .where(
            'status_outputs.${entry.statusKey}.fields.${entry.fieldKey}.pending_upload_id',
            isEqualTo: entry.id,
          )
          .limit(2)
          .get(const GetOptions(source: Source.server));
      final markerEvidence = <String, dynamic>{
        'stage': 'completed',
        'match_count': matches.docs.length,
        'result': matches.docs.isEmpty ? 'no_photo_marker' : 'not_verified',
        'read_source': 'server',
      };
      evidence['photo_marker_lookup'] = markerEvidence;
      if (matches.docs.isEmpty) return null;
      if (matches.docs.length != 1) {
        throw StateError(
          'Sync conflict: more than one booking owns this photo marker. Local photo was preserved.',
        );
      }
      final match = matches.docs.single;
      final data = match.data();
      final event = _statusOutputsFromBooking(data)?[entry.statusKey];
      final photo = _fieldValueFromStatusOutputs(
        _statusOutputsFromBooking(data),
        statusKey: entry.statusKey,
        fieldKey: entry.fieldKey,
      );
      final key = data['submission_key'];
      final keyParts = key is String
          ? RegExp(
              r'^booking_([0-9]+)_([0-9]+)_([0-9]+)_([0-9]+)$',
            ).firstMatch(key)
          : null;
      if (!BookingIdResolver.isNumeric(match.id) ||
          data['id'] != match.id ||
          data['client_id'] != parts[2] ||
          keyParts == null ||
          keyParts[1] != parts[1] ||
          keyParts[2] != parts[2] ||
          keyParts[3] != parts[3] ||
          event is! Map ||
          event['status_key'] != 'book' ||
          event['submitted_by'] != parts[1] ||
          photo is! Map ||
          photo['pending_upload'] != true ||
          photo['pending_upload_id'] != entry.id ||
          photo['name'] != entry.fileName ||
          photo['size'] != entry.size ||
          photo['mime_type'] != entry.mimeType) {
        throw StateError(
          'Sync conflict: photo marker ownership or metadata is inconsistent. Local photo was preserved.',
        );
      }
      markerEvidence.addAll({
        'result': 'confirmed_exact_photo_marker',
        'canonical_id': match.id,
      });
      return match.id;
    });
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
    Map<String, dynamic>? serverDocument,
    Object? readError,
    StackTrace? readStack,
    Map<String, dynamic>? identityLookup,
  }) async {
    if (reason == _PhotoWaitReason.photoFieldMissing ||
        reason == _PhotoWaitReason.markerSuperseded) {
      // A missing target cannot be repaired by polling every 20 seconds.
      // Keep the bytes and allow explicit retry/reconnect to check immediately.
      _missingPhotoRecheckAt['$storageKey/${entry.id}'] = _now().add(
        _missingPhotoRecheckInterval,
      );
    }
    final waitCount = (_waitCycles[entry.id] ?? entry.waitCount) + 1;
    _waitCycles[entry.id] = waitCount;
    final reasonChanged = entry.waitReason != reason.key;
    final missingOriginal =
        identityLookup?['stage'] == 'completed' &&
        identityLookup?['result'] == 'no_server_identity' &&
        identityLookup?['photo_marker_lookup'] is Map &&
        identityLookup?['photo_marker_lookup']['result'] == 'no_photo_marker' &&
        identityLookup?['original_cached_submission_available'] == false;
    const missingOriginalMessage =
        'The original booking submission is missing. The photo and original timestamps remain saved. Recovery storage is only a backup; this booking is not synced. The operation remains pending until its booking attachment is confirmed.';
    if (missingOriginal && entry.lastError != missingOriginalMessage) {
      // Preserve the exact earlier record, including bytes and error time,
      // before replacing a stale connectivity message with current evidence.
      final owner = storageKey.substring('$_storageKey::'.length);
      final archiveKey = OrphanPhotoRecoveryService.originalEvidenceKey(
        owner,
        entry.id,
      );
      try {
        if ((await _backend.readStringList(archiveKey)).isEmpty) {
          final original = (await _backend.readStringList(storageKey))
              .where((raw) => (jsonDecode(raw) as Map)['id'] == entry.id)
              .toList();
          if (original.length != 1) {
            return _WaitOutcome(entry, persisted: false);
          }
          await _backend.writeStringList(archiveKey, [original.single]);
        }
      } catch (_) {
        // A failed archive is not permission to replace the only remaining
        // original failure record with a new diagnostic message.
        return _WaitOutcome(entry, persisted: false);
      }
    }
    final escalate =
        entry.lastError == null && waitCount > _escalateWaitAfterCycles;
    final lastError = missingOriginal
        ? missingOriginalMessage
        : (escalate || (reasonChanged && entry.lastError != null))
        ? 'This photo is still waiting: ${reason.explanation}. '
              'Open the booking, check the photo field, and retry the upload.'
        : entry.lastError;
    String? diagnostics = entry.diagnostics;
    final enrich =
        lastError != null &&
        (reasonChanged ||
            lastError != entry.lastError ||
            !(entry.diagnostics ?? '').contains('photo_dependency_state_v2') ||
            (identityLookup != null &&
                (!(entry.diagnostics ?? '').contains(
                      'booking_identity_lookup_v1',
                    ) ||
                    (identityLookup.containsKey('photo_marker_lookup') &&
                        !(entry.diagnostics ?? '').contains(
                          'photo_marker_lookup',
                        )) ||
                    (identityLookup['stage'] == 'completed' &&
                        !(entry.diagnostics ?? '').contains(
                          '"result":"${identityLookup['result']}"',
                        )))) ||
            (readError != null &&
                !(entry.diagnostics ?? '').contains('marker_read_failure')));
    if (escalate || enrich) {
      final evidence = <String, dynamic>{};
      try {
        evidence['pending_booking_actions'] = await _mutationQueue
            .pendingBookingEvidence(
              entry.bookingId,
              storageKey:
                  'offline_mutation_queue_v1::${storageKey.substring('$_storageKey::'.length)}',
            )
            .timeout(_mutationCheckTimeout);
      } catch (error) {
        evidence['dependency_evidence_error'] = error.toString();
      }
      // Cache evidence can still contain the original delivery action even
      // when reading the mutation queue fails. Inspect it independently.
      try {
        final cached = await FirestoreCacheStore.instance
            .readDocumentMaps('bookings')
            .timeout(_localStoreTimeout);
        final matches = (cached ?? <Map<String, dynamic>>[])
            .where((row) => row['id']?.toString() == entry.bookingId)
            .toList();
        evidence['cached_booking_available'] = matches.length == 1;
        if (matches.length == 1) evidence['cached_booking'] = matches.single;
      } catch (error) {
        evidence['cached_booking_evidence_error'] = error.toString();
      }
      diagnostics = await offlineErrorDiagnostics(
        error:
            readError ??
            StateError(
              missingOriginal
                  ? missingOriginalMessage
                  : 'Queued booking photo made no progress: ${reason.explanation}.',
            ),
        stack: readStack ?? StackTrace.current,
        source: 'booking_offline_upload_queue_service.dart',
        operation: 'bookingPhotoUpload',
        entryId: entry.id,
        target:
            'bookings/${entry.bookingId}/${entry.statusKey}/${entry.fieldKey}',
        owner: storageKey.substring('$_storageKey::'.length),
        actionAt: entry.createdAtIso,
        attempt: entry.retryCount + 1,
        context: {
          'diagnostic_schema': 'photo_dependency_state_v2',
          if (readError != null)
            'marker_read_failure': {
              'error': readError.toString(),
              'type': readError.runtimeType.toString(),
              if (readError is FirebaseException) ...{
                'plugin': readError.plugin,
                'code': readError.code,
                'message': readError.message,
              },
              'stage': 'booking_photo_marker_read',
              'cache_fallback': 'no_exact_marker',
            },
          ...evidence,
          'identity_lookup': ?identityLookup,
          'wait_reason': reason.key,
          'wait_cycles': waitCount,
          'booking_status': entry.statusKey,
          'field_key': entry.fieldKey,
          'media_size': entry.size,
          'queued_photo_id': entry.id,
          'photo_staged_at': entry.createdAtIso,
          'waiting_for_commit': entry.waitingForCommit,
          if (serverDocument != null) ...{'server_document': serverDocument},
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
      persisted: waitCount == 1 || reasonChanged || escalate || enrich,
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
    required bool background,
  }) async {
    final entries = await _readEntriesForStorageKey(storageKey);
    entries.sort((a, b) {
      final order = (DateTime.tryParse(a.createdAtIso) ?? DateTime(1900))
          .compareTo(DateTime.tryParse(b.createdAtIso) ?? DateTime(1900));
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    final liveKeys = entries.map((e) => '$storageKey/${e.id}').toSet();
    _missingPhotoRecheckAt.removeWhere(
      (key, _) => key.startsWith('$storageKey/') && !liveKeys.contains(key),
    );
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
    // Complete local work only after a confirmed server upload or preserved
    // history. Missing markers and permanent errors are not acknowledgements.
    final confirmedSuccesses = <String>{};
    final remaining = <_PendingBookingUploadEntry>[];
    var processed = 0;

    for (final sourceEntry in entries) {
      var entry = sourceEntry;
      final identityLookup = <String, dynamic>{
        'schema': 'booking_identity_lookup_v1',
        'lookup_started': false,
        'result': 'deferred_or_shared_lookup',
      };
      // A newer photo for this booking must not overtake an unresolved older one.
      if (remaining.any((older) => older.bookingId == entry.bookingId)) {
        remaining.add(entry);
        continue;
      }
      final recheckKey = '$storageKey/${entry.id}';
      final recheckAt = _missingPhotoRecheckAt[recheckKey];
      if (background && recheckAt != null && _now().isBefore(recheckAt)) {
        remaining.add(entry);
        continue;
      }
      _missingPhotoRecheckAt.remove(recheckKey);
      try {
        if (BookingIdResolver.isTemporary(entry.bookingId)) {
          // Local creates must commit before looking for a remote identity.
          // An offline resolver read cannot help a still-pending local create.
          final dependency = await _hasPendingBookingMutation(
            entry.bookingId,
            storageKey,
          );
          if (dependency != false) {
            final wait = await _noteWait(
              entry,
              dependency == null
                  ? _PhotoWaitReason.mutationCheckTimedOut
                  : _PhotoWaitReason.bookingMutationPending,
              storageKey: storageKey,
            );
            mutated = mutated || wait.persisted;
            remaining.add(wait.entry);
            continue;
          }
          var resolved = await BookingIdResolver(
            firestore: _firestore,
          ).resolve(entry.bookingId, lookupEvidence: identityLookup);
          resolved ??= await _resolvePhotoBookingByMarker(
            entry,
            identityLookup,
          );
          if (resolved == null) {
            final cachedReader = _cachedBookingReader;
            final candidates = cachedReader != null
                ? [
                    await cachedReader(
                      entry.bookingId,
                    ).timeout(_localStoreTimeout),
                  ]
                : (await FirestoreCacheStore.instance
                          .readDocumentMaps('bookings')
                          .timeout(_localStoreTimeout)) ??
                      <Map<String, dynamic>>[];
            final cached = candidates
                .whereType<Map<String, dynamic>>()
                .where((row) => row['id']?.toString() == entry.bookingId)
                .toList();
            identityLookup['original_cached_submission_available'] =
                cached.length == 1;
            final owner = storageKey.substring('$_storageKey::'.length);
            if (cached.isEmpty &&
                entry.waitReason == 'temporary_booking_id' &&
                entry.waitCount >= 3 &&
                identityLookup['stage'] == 'completed' &&
                identityLookup['result'] == 'no_server_identity' &&
                identityLookup['photo_marker_lookup'] is Map &&
                identityLookup['photo_marker_lookup']['result'] ==
                    'no_photo_marker' &&
                RegExp(r'^[0-9]+$').hasMatch(owner)) {
              await _photoRecoveryService(
                automatic: true,
              ).archiveUnassigned(owner: owner, entryId: entry.id);
              final wait = await _noteWait(
                entry,
                _PhotoWaitReason.temporaryBookingId,
                storageKey: storageKey,
                identityLookup: identityLookup,
              );
              remaining.add(wait.entry);
              mutated = mutated || wait.persisted;
              continue;
            }
            if (cached.length == 1 &&
                cached.single['client_status'] == 'pending' &&
                cached.single['driver_status'] == 'pending' &&
                cached.single['helper_status'] == 'pending' &&
                cached.single['driver_id'] == null &&
                cached.single['helper_id'] == null &&
                cached.single['vehicle_make_id'] == null &&
                cached.single['chassis_id'] == null &&
                _statusOutputsFromBooking(cached.single)?.length == 1) {
              final photo = _fieldValueFromStatusOutputs(
                _statusOutputsFromBooking(cached.single),
                statusKey: entry.statusKey,
                fieldKey: entry.fieldKey,
              );
              if (photo is Map &&
                  _pendingUploadId(photo) == entry.id &&
                  photo['name'] == entry.fileName &&
                  photo['size'] == entry.size &&
                  photo['mime_type'] == entry.mimeType) {
                resolved = await _mutationQueue.recoverOriginalBookingIdentity(
                  temporaryId: entry.bookingId,
                  document: cached.single,
                  owner: storageKey.substring('$_storageKey::'.length),
                );
              }
            }
          }
          if (resolved == null) {
            final wait = await _noteWait(
              entry,
              _PhotoWaitReason.temporaryBookingId,
              storageKey: storageKey,
              identityLookup: identityLookup,
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
        } catch (error, stack) {
          // A cached positive match may start an upload, but can never authorize
          // a booking write or discard. The transaction below rechecks the live
          // marker before touching the field. Missing/stale cache keeps bytes.
          if (error is TimeoutException ||
              (error is FirebaseException &&
                  const {
                    'unavailable',
                    'deadline-exceeded',
                  }.contains(error.code))) {
            try {
              final reader = _cachedBookingReader;
              final cached = reader != null
                  ? await reader(entry.bookingId).timeout(_localStoreTimeout)
                  : (await _bookingsCollection
                            .doc(entry.bookingId)
                            .get(const GetOptions(source: Source.cache))
                            .timeout(_localStoreTimeout))
                        .data();
              if (cached != null &&
                  cached['id']?.toString() == entry.bookingId &&
                  matchingBookingPhotoStatus(
                        booking: cached,
                        uploadId: entry.id,
                        fieldKey: entry.fieldKey,
                        fileName: entry.fileName,
                        size: entry.size,
                        mimeType: entry.mimeType,
                      ) !=
                      null) {
                markerData = cached;
              }
            } catch (_) {
              // Cache is optional; preserve the original read failure below.
            }
          }
          if (markerData == null) {
            final wait = await _noteWait(
              entry,
              error is TimeoutException
                  ? _PhotoWaitReason.markerCheckTimedOut
                  : _PhotoWaitReason.markerReadFailed,
              storageKey: storageKey,
              readError: error,
              readStack: stack,
            );
            mutated = mutated || wait.persisted;
            remaining.add(wait.entry);
            continue;
          }
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
        final recoveredStatus = matchingBookingPhotoStatus(
          booking: markerData,
          uploadId: entry.id,
          fieldKey: entry.fieldKey,
          fileName: entry.fileName,
          size: entry.size,
          mimeType: entry.mimeType,
        );
        if (recoveredStatus != null && recoveredStatus != entry.statusKey) {
          entry = entry.copyWith(statusKey: recoveredStatus);
          mutated = true;
        }
        final markerField = _fieldValueFromStatusOutputs(
          _statusOutputsFromBooking(markerData),
          statusKey: entry.statusKey,
          fieldKey: entry.fieldKey,
        );
        final historicalKey = 'photo__${entry.id}';
        if (bookingPhotoAlreadyUploaded(
              photo: markerField,
              bookingId: entry.bookingId,
              statusKey: entry.statusKey,
              fieldKey: entry.fieldKey,
              fileName: entry.fileName,
              size: entry.size,
              mimeType: entry.mimeType,
            ) ||
            (_pendingUploadId(markerField) != entry.id &&
                bookingPhotoAlreadyUploadedInHistory(
                  booking: markerData,
                  bookingId: entry.bookingId,
                  fieldKey: entry.fieldKey,
                  fileName: entry.fileName,
                  size: entry.size,
                  mimeType: entry.mimeType,
                ))) {
          confirmedSuccesses.add(entry.id);
          mutated = true;
          continue;
        }
        final historical = _statusOutputsFromBooking(
          markerData,
        )?[historicalKey];
        if (historical is Map && historical['upload_id'] == entry.id) {
          confirmedSuccesses.add(entry.id);
          mutated = true;
          continue;
        }
        final recoverHistoricalPhoto = _canRecoverHistoricalPhoto(
          entry,
          markerData,
        );
        final matchingPendingUploadId =
            _pendingUploadId(markerField) != entry.id &&
                bookingPendingPhotoMatchesBytes(
                  photo: markerField,
                  fileName: entry.fileName,
                  size: entry.size,
                  mimeType: entry.mimeType,
                  bytesBase64: entry.bytesBase64,
                )
            ? _pendingUploadId(markerField)
            : null;
        final recoveringMatchingPhoto = matchingPendingUploadId != null;
        if (_pendingUploadId(markerField) != entry.id &&
            !recoverHistoricalPhoto &&
            !recoveringMatchingPhoto) {
          // An unrelated newer booking edit does not prove that this staged
          // photo was committed or intentionally removed.
          final wait = await _noteWait(
            entry,
            markerField == null
                ? _PhotoWaitReason.photoFieldMissing
                : _PhotoWaitReason.markerSuperseded,
            storageKey: storageKey,
            serverDocument: markerData,
          );
          mutated = mutated || wait.persisted;
          remaining.add(wait.entry);
          continue;
        }
        if (!recoverHistoricalPhoto && !recoveringMatchingPhoto) {
          entry = entry.copyWith(
            waitingForCommit: false,
            clearWaitReason: true,
          );
        }
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
          recoverHistoricalPhoto: recoverHistoricalPhoto,
          matchingPendingUploadId: matchingPendingUploadId,
          owner: storageKey.substring('$_storageKey::'.length),
        ).timeout(const Duration(seconds: 15));

        if (!applied) {
          await _photoStorageService
              .deleteByPath(upload['storage_path']?.toString())
              .timeout(const Duration(seconds: 20));
          remaining.add(entry);
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
            if (identityLookup['lookup_started'] == true)
              'identity_lookup': identityLookup,
          },
        );
        if (BookingIdResolver.isTemporary(sourceEntry.bookingId) &&
            sourceEntry.lastError != null) {
          try {
            final owner = storageKey.substring('$_storageKey::'.length);
            final key = OrphanPhotoRecoveryService.originalEvidenceKey(
              owner,
              sourceEntry.id,
            );
            await _mutateQueue(() async {
              if ((await _backend.readStringList(key)).isNotEmpty) return;
              final original = (await _backend.readStringList(storageKey))
                  .where(
                    (raw) => (jsonDecode(raw) as Map)['id'] == sourceEntry.id,
                  )
                  .toList();
              if (original.length != 1) {
                throw StateError('Original photo changed.');
              }
              await _backend.writeStringList(key, original);
              final saved = await _backend.readStringList(key);
              if (saved.length != 1 || saved.single != original.single) {
                throw StateError('Original photo evidence was not saved.');
              }
            });
          } catch (_) {
            // Current failure was logged above. Do not replace the only local
            // copy of the first error when its evidence cannot be archived.
            remaining.add(sourceEntry);
            continue;
          }
        }
        // Every unconfirmed failure retains the only durable local copy.
        mutated = true;
        remaining.add(
          entry.copyWith(
            retryCount: entry.retryCount + 1,
            lastError: normalizedError,
            diagnostics: diagnostics,
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

    if (mutated || remaining.length != entries.length) {
      await _mutateQueue(() async {
        final latest = await _readEntriesForStorageKey(storageKey);
        final processedIds = entries.map((entry) => entry.id).toSet();
        final merged = [
          ...latest.where((entry) => !processedIds.contains(entry.id)),
          // A reviewed recovery can complete while this older flush is reading
          // the server. Never resurrect an entry already archived and completed.
          ...remaining.where(
            (entry) => latest.any((current) => current.id == entry.id),
          ),
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
    String? statusKey,
    bool? waitingForCommit,
    int? waitCount,
    String? waitReason,
    bool clearWaitReason = false,
  }) {
    return _PendingBookingUploadEntry(
      id: id,
      waitingForCommit: waitingForCommit ?? this.waitingForCommit,
      bookingId: bookingId ?? this.bookingId,
      statusKey: statusKey ?? this.statusKey,
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
  ),
  markerReadFailed(
    'marker_read_failed',
    'the booking read failed before the photo could be verified',
    'Waiting for the booking read to succeed',
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
