import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/booking_chassis_lifecycle.dart';
import 'package:webapp/services/firestore_public_document_fetcher.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_queue_coordinator_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/utils/functions.dart';

class BookingRequest implements BookingRepository {
  BookingRequest({
    FirebaseFirestore? firestore,
    AuthRequest? authRequest,
    VehicleRequest? vehicleRequest,
    FirestorePublicDocumentFetcher? firestorePublicDocumentFetcher,
  }) : _providedFirestore = firestore,
       _authRequest = authRequest ?? AuthRequest.instance,
       _vehicleRequest = vehicleRequest ?? VehicleRequest.instance,
       _firestorePublicDocumentFetcher =
           firestorePublicDocumentFetcher ??
           createFirestorePublicDocumentFetcher();

  static final BookingRequest instance = BookingRequest();
  static const _bookingsResourceKey = 'bookings';
  static const Duration _startupTimeout = Duration(seconds: 30);
  static const Duration _queuedReadTimeout = Duration(seconds: 1);
  static const Duration _remoteSaveTimeout = Duration(seconds: 30);
  static const Duration _photoUploadTimeout = Duration(minutes: 1);
  static const Duration _webSingleDocumentTimeout = Duration(seconds: 30);
  static const Duration _webMutationTimeout = Duration(seconds: 30);
  static const Duration _webNextIdTimeout = Duration(seconds: 30);
  static const Duration _bookingReservationUiGracePeriod = Duration(seconds: 5);
  static const Duration _bookingWriteUiGracePeriod = Duration(seconds: 5);
  static bool _didKickOffBackgroundQueueInitialization = false;
  static List<Booking> _memoryBookings = const [];
  static bool _hasResolvedBookings = false;
  static bool _isRefreshingFromVersionSignal = false;
  static bool _hasAuthoritativeOnlineSync = false;
  static bool _isPersistedCacheTrustedOnline = false;
  Future<void>? _backgroundRefreshFuture;
  Future<List<Booking>>? _activeGetBookingsFuture;
  Future<void>? _metaSyncFuture;
  final Map<String, Stopwatch> _pendingBookingWriteTraces =
      <String, Stopwatch>{};
  StreamSubscription<String?>? _bookingsVersionSignalSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _bookingsRealtimeSubscription;
  Completer<void>? _initialRealtimeSyncCompleter;

  static bool get hasHydratedBookings => _memoryBookings.isNotEmpty;
  static bool get hasResolvedBookings => _hasResolvedBookings;
  static bool get hasAuthoritativeBookings =>
      !currentNetworkStatus() || _hasAuthoritativeOnlineSync;
  static bool get isAuthoritativeSyncInFlight =>
      instance._backgroundRefreshFuture != null ||
      !(instance._initialRealtimeSyncCompleter?.isCompleted ?? true);
  static int get hydratedBookingCount => _memoryBookings.length;
  static List<Booking> get hydratedBookingsSnapshot =>
      List<Booking>.unmodifiable(_memoryBookings);

  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  final AuthRequest _authRequest;
  final VehicleRequest _vehicleRequest;
  final FirestorePublicDocumentFetcher _firestorePublicDocumentFetcher;
  final PhotoStorageService _photoStorageService = PhotoStorageService.instance;
  final BookingOfflineUploadQueueService _offlineUploadQueueService =
      BookingOfflineUploadQueueService.instance;
  final OfflineMutationQueueService _offlineMutationQueueService =
      OfflineMutationQueueService.instance;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );
  final StreamController<void> _bookingCacheUpdates =
      StreamController<void>.broadcast();

  CollectionReference<Map<String, dynamic>> get _bookingsCollection =>
      _firestore.collection('bookings');
  DocumentReference<Map<String, dynamic>> get _bookingsCounterRef =>
      _firestore.collection('manage_count').doc('bookings_counter');
  CollectionReference<Map<String, dynamic>> get _idManagementCollection =>
      _firestore.collection('manage_id');

  @override
  Future<void> initialize() async {
    if (_didKickOffBackgroundQueueInitialization) {
      _log('initialize skip already-started');
      return;
    }
    _didKickOffBackgroundQueueInitialization = true;
    _log('initialize start online=${currentNetworkStatus()}');
    _ensureBookingsCacheSync();
    _ensureBookingsRealtimeSync();
    if (currentNetworkStatus()) {
      _hasAuthoritativeOnlineSync = false;
      unawaited(_syncPersistedCacheTrustFromMetaSignal());
    }
    unawaited(
      OfflineQueueCoordinatorService.instance
          .initialize()
          .then((_) {})
          .catchError((error, stackTrace) {}),
    );
    _log('initialize done');
  }

  void _ensureBookingsCacheSync() {
    if (_bookingsVersionSignalSubscription != null) {
      return;
    }
    _bookingsVersionSignalSubscription = _cache
        .watchResourceVersion(_bookingsResourceKey)
        .listen(
          (version) {
            unawaited(_handleBookingsVersionSignal(version));
          },
          onError: (error, stackTrace) {
            _log('version signal error error=$error');
          },
        );
  }

  Future<void> _handleBookingsVersionSignal(String? remoteVersion) async {
    _log('version signal received version=${remoteVersion ?? "-"}');
    final shouldRefresh = await _cache.hasRemoteVersionMismatch(
      _bookingsResourceKey,
      remoteVersion,
    );
    _log(
      'version signal evaluate shouldRefresh=$shouldRefresh refreshing=$_isRefreshingFromVersionSignal',
    );
    if (!shouldRefresh || _isRefreshingFromVersionSignal) {
      return;
    }
    _isRefreshingFromVersionSignal = true;
    try {
      if (shouldRefresh) {
        await _invalidatePersistedBookingsCache(
          reason: 'version-signal-mismatch',
          remoteVersion: remoteVersion,
        );
      }
      await _refreshBookingsCacheInBackground();
      _bookingCacheUpdates.add(null);
    } finally {
      _isRefreshingFromVersionSignal = false;
    }
  }

  @override
  Future<List<Booking>> getBookings() async {
    final existing = _activeGetBookingsFuture;
    if (existing != null) {
      _log('getBookings join-inflight');
      return existing;
    }
    final future = _runRequest(() async {
      await initialize();
      await _waitForPersistedCacheTrustSync();
      _log(
        'getBookings enter online=${currentNetworkStatus()} memory=${_memoryBookings.length} resolved=$_hasResolvedBookings',
      );
      if ((_memoryBookings.isNotEmpty || _hasResolvedBookings) &&
          (!currentNetworkStatus() ||
              _hasAuthoritativeOnlineSync ||
              _isPersistedCacheTrustedOnline)) {
        _log(
          'getBookings returning hydrated source memory=${_memoryBookings.length} resolved=$_hasResolvedBookings',
        );
        if (currentNetworkStatus() && _bookingsRealtimeSubscription == null) {
          unawaited(_refreshBookingsCacheInBackground());
        }
        return List<Booking>.from(_memoryBookings);
      }
      List<Map<String, dynamic>> documents;
      try {
        documents = await _fetchBookingsViaSdkOnly();
        _log('getBookings sdk-only resolved docs=${documents.length}');
        _bookingCacheUpdates.add(null);
      } catch (error) {
        _log('getBookings sdk-only fetch error error=$error');
        final lateCachedDocuments = await _cache.readDocuments(
          _bookingsResourceKey,
        );
        if (lateCachedDocuments != null && !currentNetworkStatus()) {
          _log(
            'getBookings offline using cached docs=${lateCachedDocuments.length}',
          );
          documents = lateCachedDocuments;
        } else {
          rethrow;
        }
      }
      final queuedDocuments = await _readQueuedBookingDocumentsSafe();
      final visibleDocuments = _mergeQueuedPendingBookingDocuments(
        existingDocuments: documents,
        queuedDocuments: queuedDocuments,
      );
      _log(
        'getBookings merge result base=${documents.length} queued=${queuedDocuments.length} visible=${visibleDocuments.length}',
      );
      return _cacheInflatedBookings(visibleDocuments);
    }, fallback: 'We could not load the bookings right now.');
    _activeGetBookingsFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_activeGetBookingsFuture, future)) {
        _activeGetBookingsFuture = null;
      }
    }
  }

  @override
  Stream<List<Booking>> watchBookings() {
    return Stream<List<Booking>>.multi((controller) {
      String? lastEmissionFingerprint;

      void emitIfChanged(List<Booking> bookings, {required String source}) {
        final fingerprint = _bookingEmissionFingerprint(bookings);
        if (fingerprint == lastEmissionFingerprint) {
          _log(
            'watchBookings skip unchanged source=$source count=${bookings.length}',
          );
          return;
        }
        lastEmissionFingerprint = fingerprint;
        controller.add(bookings);
      }

      Future<void> emitCachedBookings({
        bool allowBackgroundRefresh = false,
      }) async {
        _log(
          'watchBookings emit start allowRefresh=$allowBackgroundRefresh online=${currentNetworkStatus()} memory=${_memoryBookings.length} resolved=$_hasResolvedBookings',
        );
        final canTrustVisibleCache =
            !currentNetworkStatus() ||
            _hasAuthoritativeOnlineSync ||
            _isPersistedCacheTrustedOnline;
        if ((_memoryBookings.isNotEmpty || _hasResolvedBookings) &&
            canTrustVisibleCache &&
            !controller.isClosed) {
          _log('watchBookings emit memory docs=${_memoryBookings.length}');
          emitIfChanged(List<Booking>.from(_memoryBookings), source: 'memory');
        }
        final cachedDocuments = await _cache.readDocuments(
          _bookingsResourceKey,
        );
        _log('watchBookings cached docs=${cachedDocuments?.length ?? -1}');
        if (controller.isClosed) {
          return;
        }
        if (!canTrustVisibleCache && currentNetworkStatus()) {
          _log(
            'watchBookings skip cached emit reason=awaiting-authoritative-sync cached=${cachedDocuments?.length ?? -1}',
          );
          // A missing local cache may render as an immediate provisional empty
          // state. The realtime source replaces it once Firestore responds.
          if ((cachedDocuments == null || cachedDocuments.isEmpty) &&
              !controller.isClosed) {
            emitIfChanged(const <Booking>[], source: 'provisional-empty');
          }
          return;
        }
        if (cachedDocuments == null || cachedDocuments.isEmpty) {
          if (!controller.isClosed) {
            _memoryBookings = const [];
            if (!currentNetworkStatus()) {
              _hasResolvedBookings = true;
            }
            emitIfChanged(const <Booking>[], source: 'empty-cache');
          }
          return;
        }
        final queuedDocuments = await _readQueuedBookingDocumentsSafe();
        final visibleDocuments = _mergeQueuedPendingBookingDocuments(
          existingDocuments: cachedDocuments,
          queuedDocuments: queuedDocuments,
        );
        _log(
          'watchBookings merge result base=${cachedDocuments.length} queued=${queuedDocuments.length} visible=${visibleDocuments.length}',
        );
        if (!_sameBookingDocumentSet(cachedDocuments, visibleDocuments)) {
          await _cache.writeDocuments(
            resourceKey: _bookingsResourceKey,
            documents: visibleDocuments,
          );
        }
        emitIfChanged(
          await _cacheInflatedBookings(visibleDocuments),
          source: 'cache',
        );
      }

      unawaited(emitCachedBookings(allowBackgroundRefresh: true));

      final localSubscription = _bookingCacheUpdates.stream.listen((_) {
        _log('watchBookings local cache update event');
        unawaited(emitCachedBookings());
      }, onError: (_) {});

      controller.onCancel = () async {
        await localSubscription.cancel();
      };
    });
  }

  Future<void> waitForAuthoritativeSync({
    Duration timeout = _startupTimeout,
  }) async {
    await initialize();
    await _waitForPersistedCacheTrustSync();
    if (!currentNetworkStatus() || _hasAuthoritativeOnlineSync) {
      return;
    }
    final backgroundRefresh = _backgroundRefreshFuture;
    if (backgroundRefresh != null) {
      try {
        await backgroundRefresh.timeout(timeout, onTimeout: () => null);
      } catch (_) {
        // Keep the shared read path alive and let callers decide on fallback.
      }
    }
    await _waitForInitialRealtimeSync();
  }

  @override
  Future<List<Booking>> getBookingsForClient(String clientId) async {
    return _runRequest(() async {
      final bookings = await getBookings();
      return bookings
          .where((booking) => booking.client?.id == clientId)
          .toList();
    }, fallback: 'We could not load the bookings right now.');
  }

  @override
  Future<Booking> saveBooking(Booking booking) async {
    return _runRequest(() async {
      await initialize();
      final normalizedId = normalizeId(booking.id);
      final isCreatingBooking = normalizedId == null;
      final submissionKey = isCreatingBooking
          ? (_normalizedSubmissionKey(booking.submissionKey) ??
                _newSubmissionKey())
          : booking.submissionKey;
      var queueRemoteWrite = !currentNetworkStatus();
      _log(
        'save start create=$isCreatingBooking online=${currentNetworkStatus()} id=${normalizedId ?? "-"}',
      );
      String nextId;
      if (normalizedId != null) {
        nextId = normalizedId;
      } else if (queueRemoteWrite) {
        nextId = _offlineBookingId(submissionKey!);
      } else {
        try {
          nextId = await _reserveNextBookingId(
            submissionKey: submissionKey!,
          ).timeout(_bookingReservationUiGracePeriod);
        } on TimeoutException {
          // Keep the booking usable immediately when the SDK transaction is
          // stalled; the same submission key makes the queued retry idempotent.
          queueRemoteWrite = true;
          nextId = _offlineBookingId(submissionKey!);
          _log('save reservation deferred to offline queue key=$submissionKey');
        }
      }
      _log('save id ready id=$nextId');
      final existingBookingData = isCreatingBooking
          ? null
          : await _getExistingBookingData(nextId);
      final now = DateTime.now();
      final persistedStatusOutputs = await _persistPhotoFields(
        booking.statusOutputs,
        bookingId: nextId,
        existingStatusOutputs: _statusOutputsFromFirestoreMap(
          existingBookingData,
        ),
      );
      _log('save media ready id=$nextId');
      var saved = booking.copyWith(
        id: nextId,
        createdAt: booking.createdAt ?? now,
        billingStatus: _normalizedBillingStatus(booking.billingStatus),
        statusOutputs: persistedStatusOutputs,
        updatedAt: now,
        localSyncStatus: queueRemoteWrite ? 'queued' : null,
        submissionKey: submissionKey,
      );
      var document = _toFirestoreMap(saved);
      var cacheDocument = _toCacheDocument(saved);
      final baseUpdatedAtIso = existingBookingData?['updated_at']?.toString();
      if (!queueRemoteWrite) {
        _log('save firestore set start id=$nextId');
        try {
          await _writeBookingOnline(nextId, document).timeout(
            _bookingWriteUiGracePeriod,
            onTimeout: () => throw TimeoutException(
              'booking write acknowledgement is still pending for $nextId',
            ),
          );
          _log('save firestore set done id=$nextId');
        } catch (error) {
          if (!_isQueueableBookingWriteError(error)) {
            rethrow;
          }
          // The SDK request can remain pending in the browser even while the
          // app is online. Preserve the reserved document ID in our durable
          // queue instead of making the user wait for that acknowledgement.
          queueRemoteWrite = true;
          saved = saved.copyWith(localSyncStatus: 'queued');
          document = _toFirestoreMap(saved);
          cacheDocument = _toCacheDocument(saved);
          _writeTrace('sdk set deferred to app queue id=$nextId error=$error');
        }
      }
      if (queueRemoteWrite) {
        if (isCreatingBooking && nextId.startsWith('offline_')) {
          await _offlineMutationQueueService.queueOfflineBookingCreate(
            provisionalId: nextId,
            submissionKey: submissionKey!,
            document: document,
          );
        } else {
          await _offlineMutationQueueService.queueCollectionDocumentUpsert(
            collectionKey: _bookingsResourceKey,
            documentId: nextId,
            document: document,
            baseUpdatedAt: baseUpdatedAtIso,
          );
        }
      }
      await _cache.upsertDocument(
        resourceKey: _bookingsResourceKey,
        document: cacheDocument,
      );
      _upsertMemoryBooking(saved);
      _bookingCacheUpdates.add(null);
      _log('save finish id=$nextId sync=${saved.localSyncStatus ?? "online"}');
      return saved;
    }, fallback: 'We could not save the booking right now.');
  }

  @override
  Future<Booking> updateBillingStatus(String bookingId, String billingStatus) {
    return _runRequest(() async {
      final normalizedId = normalizeId(bookingId);
      if (normalizedId == null) {
        throw Exception('We could not update the billing status right now.');
      }
      final existingBookingData = await _getCachedBookingData(normalizedId);
      final normalizedBillingStatus = _normalizedBillingStatus(billingStatus);
      if (currentNetworkStatus()) {
        await _writeBillingStatusesOnline({
          normalizedId: normalizedBillingStatus,
        });
      } else {
        throw Exception(
          'You need an internet connection to update the billing status.',
        );
      }
      if (existingBookingData != null) {
        final updatedDocument = Map<String, dynamic>.from(existingBookingData)
          ..['billing_status'] = normalizedBillingStatus
          ..['updated_at'] = DateTime.now().toIso8601String();
        await _cache.upsertDocument(
          resourceKey: _bookingsResourceKey,
          document: updatedDocument,
        );
        await _primeMemoryBookingsFromCache();
        _bookingCacheUpdates.add(null);
        return _bookingFromFirestoreMap(
          updatedDocument,
          userById: await _userById(),
          makeById: await _makeById(),
        );
      }
      final refreshedBookingData = await _getExistingBookingData(normalizedId);
      if (refreshedBookingData == null) {
        throw Exception('We could not update the billing status right now.');
      }
      return _bookingFromFirestoreMap(
        refreshedBookingData,
        userById: await _userById(),
        makeById: await _makeById(),
      );
    }, fallback: 'We could not update the billing status right now.');
  }

  @override
  Future<void> updateBillingStatuses(Map<String, String> statusesByBookingId) {
    return _runRequest(() async {
      if (statusesByBookingId.isEmpty) {
        return;
      }
      final normalizedStatusesByBookingId = <String, String>{};
      for (final entry in statusesByBookingId.entries) {
        final normalizedId = normalizeId(entry.key);
        if (normalizedId == null) {
          continue;
        }
        normalizedStatusesByBookingId[normalizedId] = _normalizedBillingStatus(
          entry.value,
        );
      }
      final cachedDocuments = await _cache.readDocuments(_bookingsResourceKey);
      if (!currentNetworkStatus()) {
        throw Exception(
          'You need an internet connection to update billing statuses.',
        );
      } else {
        await _writeBillingStatusesOnline(normalizedStatusesByBookingId);
      }
      if (cachedDocuments == null) {
        await _cache.touch(_bookingsResourceKey);
        return;
      }
      final nowIso = DateTime.now().toIso8601String();
      final updatedDocuments = cachedDocuments.map((document) {
        final documentId = normalizeId(document['id']?.toString());
        if (documentId == null) {
          return Map<String, dynamic>.from(document);
        }
        final nextStatus = normalizedStatusesByBookingId[documentId];
        if (nextStatus == null) {
          return Map<String, dynamic>.from(document);
        }
        return Map<String, dynamic>.from(document)
          ..['billing_status'] = _normalizedBillingStatus(nextStatus)
          ..['updated_at'] = nowIso;
      }).toList();
      await _cache.writeDocuments(
        resourceKey: _bookingsResourceKey,
        documents: updatedDocuments,
      );
      await _primeMemoryBookingsFromCache();
      _bookingCacheUpdates.add(null);
    }, fallback: 'We could not update the billing statuses right now.');
  }

  Future<Map<String, dynamic>?> _getExistingBookingData(
    String bookingId,
  ) async {
    final cached = await _getCachedBookingData(bookingId);
    if (cached != null || !currentNetworkStatus()) {
      return cached;
    }
    try {
      final fetchTimeout = kIsWeb
          ? _webSingleDocumentTimeout
          : const Duration(seconds: 6);
      final getOptions = kIsWeb && currentNetworkStatus()
          ? const GetOptions(source: Source.server)
          : null;
      final snapshot = await _bookingsCollection
          .doc(bookingId)
          .get(getOptions)
          .timeout(
            fetchTimeout,
            onTimeout: () => throw TimeoutException(
              'booking existing data fetch timeout for $bookingId',
            ),
          );
      if (!snapshot.exists) {
        return cached;
      }
      return documentData(snapshot);
    } catch (error) {
      return cached;
    }
  }

  Future<Map<String, dynamic>?> _getCachedBookingData(String bookingId) async {
    final cachedDocuments = await _cache.readDocuments(_bookingsResourceKey);
    if (cachedDocuments == null) {
      return null;
    }
    for (final document in cachedDocuments) {
      if (normalizeId(document['id']?.toString()) == bookingId) {
        return Map<String, dynamic>.from(document);
      }
    }
    return null;
  }

  Map<String, dynamic>? _statusOutputsFromFirestoreMap(
    Map<String, dynamic>? bookingData,
  ) {
    final rawValue = bookingData?['status_outputs'];
    if (rawValue is Map) {
      return Map<String, dynamic>.from(rawValue);
    }
    return null;
  }

  Future<void> _writeBillingStatusesOnline(
    Map<String, String> normalizedStatusesByBookingId,
  ) async {
    if (normalizedStatusesByBookingId.isEmpty) {
      return;
    }
    if (kIsWeb) {
      final restOnlySucceeded = await _writeBillingStatusesViaRest(
        normalizedStatusesByBookingId,
      );
      if (restOnlySucceeded) {
        return;
      }
    }
    if (normalizedStatusesByBookingId.length == 1) {
      final entry = normalizedStatusesByBookingId.entries.first;
      await _writeSingleBillingStatusOnline(entry.key, entry.value);
      return;
    }
    final nowIso = DateTime.now().toIso8601String();
    final batch = _firestore.batch();
    for (final entry in normalizedStatusesByBookingId.entries) {
      batch.set(_bookingsCollection.doc(entry.key), {
        'billing_status': entry.value,
        'updated_at': nowIso,
      }, SetOptions(merge: true));
    }
    try {
      await batch.commit().timeout(
        _webMutationTimeout,
        onTimeout: () => throw TimeoutException('billing batch commit timeout'),
      );
      return;
    } catch (_) {
      // Fall through to REST and sequential fallback writes.
    }

    final restResult = await _writeBillingStatusesViaRest(
      normalizedStatusesByBookingId,
      nowIso: nowIso,
    );
    final restSuccessCount = restResult
        ? normalizedStatusesByBookingId.length
        : 0;
    if (restSuccessCount == normalizedStatusesByBookingId.length) {
      return;
    }

    Object? lastError;
    var successCount = 0;
    for (final entry in normalizedStatusesByBookingId.entries) {
      try {
        await _bookingsCollection
            .doc(entry.key)
            .set({
              'billing_status': entry.value,
              'updated_at': nowIso,
            }, SetOptions(merge: true))
            .timeout(
              _webMutationTimeout,
              onTimeout: () => throw TimeoutException(
                'billing sequential write timeout for ${entry.key}',
              ),
            );
        successCount += 1;
      } catch (error) {
        lastError = error;
      }
    }
    if (successCount == 0) {
      final finalError = lastError;
      if (finalError != null) {
        throw finalError;
      }
    }
  }

  Future<void> _writeSingleBillingStatusOnline(
    String bookingId,
    String billingStatus,
  ) async {
    final nowIso = DateTime.now().toIso8601String();
    if (kIsWeb) {
      final restOnlySucceeded = await _writeBillingStatusesViaRest({
        bookingId: billingStatus,
      }, nowIso: nowIso);
      if (restOnlySucceeded) {
        return;
      }
    }
    try {
      await _bookingsCollection
          .doc(bookingId)
          .set({
            'billing_status': billingStatus,
            'updated_at': nowIso,
          }, SetOptions(merge: true))
          .timeout(
            _webMutationTimeout,
            onTimeout: () => throw TimeoutException(
              'billing single write timeout for $bookingId',
            ),
          );
      return;
    } catch (_) {
      // Fall through to the REST patch fallback on web.
    }

    final restPatched = await _firestorePublicDocumentFetcher
        .patchDocument(
          'bookings/$bookingId',
          fields: {'billing_status': billingStatus, 'updated_at': nowIso},
          updateMaskFieldPaths: const ['billing_status', 'updated_at'],
        )
        .timeout(
          _webMutationTimeout,
          onTimeout: () => throw TimeoutException(
            'billing single rest patch timeout for $bookingId',
          ),
        );
    if (!restPatched) {
      throw Exception(
        'billing single rest patch returned false for $bookingId',
      );
    }
  }

  Future<bool> _writeBillingStatusesViaRest(
    Map<String, String> normalizedStatusesByBookingId, {
    String? nowIso,
  }) async {
    if (normalizedStatusesByBookingId.isEmpty) {
      return true;
    }
    final effectiveNowIso = nowIso ?? DateTime.now().toIso8601String();
    final results = await Future.wait(
      normalizedStatusesByBookingId.entries.map((entry) async {
        try {
          final success = await _firestorePublicDocumentFetcher
              .patchDocument(
                'bookings/${entry.key}',
                fields: {
                  'billing_status': entry.value,
                  'updated_at': effectiveNowIso,
                },
                updateMaskFieldPaths: const ['billing_status', 'updated_at'],
              )
              .timeout(
                _webMutationTimeout,
                onTimeout: () => throw TimeoutException(
                  'billing rest patch timeout for ${entry.key}',
                ),
              );
          if (!success) {
            throw Exception(
              'billing rest patch returned false for ${entry.key}',
            );
          }
          return true;
        } catch (error) {
          return false;
        }
      }),
    );
    final successCount = results.where((value) => value).length;
    return successCount == normalizedStatusesByBookingId.length;
  }

  Future<Map<String, dynamic>?> _persistPhotoFields(
    Map<String, dynamic>? statusOutputs, {
    required String bookingId,
    required Map<String, dynamic>? existingStatusOutputs,
  }) async {
    if (statusOutputs == null) {
      if (existingStatusOutputs != null) {
        await _deleteObsoletePhotos(
          previousStatusOutputs: existingStatusOutputs,
          nextStatusOutputs: null,
        );
      }
      return null;
    }

    final nextStatusOutputs = <String, dynamic>{};
    for (final sectionEntry in statusOutputs.entries) {
      final sectionValue = sectionEntry.value;
      if (sectionValue is! Map) {
        nextStatusOutputs[sectionEntry.key] = sectionValue;
        continue;
      }
      final nextSection = Map<String, dynamic>.from(sectionValue);
      final fieldsValue = sectionValue['fields'];
      if (fieldsValue is Map) {
        final nextFields = <String, dynamic>{};
        for (final fieldEntry in fieldsValue.entries) {
          nextFields[fieldEntry.key.toString()] = await _persistPhotoValue(
            fieldEntry.value,
            bookingId: bookingId,
            statusKey: sectionEntry.key,
            fieldKey: fieldEntry.key.toString(),
          );
        }
        nextSection['fields'] = nextFields;
      }
      nextStatusOutputs[sectionEntry.key] = nextSection;
    }

    await _deleteObsoletePhotos(
      previousStatusOutputs: existingStatusOutputs,
      nextStatusOutputs: nextStatusOutputs,
    );
    return nextStatusOutputs;
  }

  Future<dynamic> _persistPhotoValue(
    dynamic value, {
    required String bookingId,
    required String statusKey,
    required String fieldKey,
  }) async {
    final mapValue = value is Map<String, dynamic>
        ? Map<String, dynamic>.from(value)
        : value is Map
        ? Map<String, dynamic>.from(value)
        : null;
    final bytes = decodePhotoBytes(mapValue);
    if (mapValue == null || bytes == null) {
      return value;
    }
    final fileName = mapValue['name']?.toString().trim();
    final mimeType = mapValue['mime_type']?.toString().trim();
    final size = _toInt(mapValue['size']) ?? bytes.length;
    final resolvedFileName = fileName?.isNotEmpty == true ? fileName! : 'photo';
    if (!currentNetworkStatus()) {
      final queuedValue = await _offlineUploadQueueService.enqueueBookingPhoto(
        bytes: bytes,
        bookingId: bookingId,
        statusKey: statusKey.trim(),
        fieldKey: fieldKey.trim(),
        fileName: resolvedFileName,
        mimeType: mimeType?.isNotEmpty == true ? mimeType : null,
        size: size,
      );
      return queuedValue;
    }
    try {
      final uploaded = await _photoStorageService
          .uploadBookingPhoto(
            bytes: bytes,
            bookingId: bookingId,
            statusKey: statusKey.trim(),
            fieldKey: fieldKey.trim(),
            fileName: resolvedFileName,
            mimeType: mimeType?.isNotEmpty == true ? mimeType : null,
            size: size,
          )
          .timeout(
            _photoUploadTimeout,
            onTimeout: () => throw TimeoutException(
              'booking photo upload timeout for $bookingId/$statusKey/$fieldKey',
            ),
          );
      return uploaded;
    } catch (error) {
      final normalizedError = normalizeUserErrorText(
        error.toString(),
        fallback: '',
      ).toLowerCase();
      if (!_isQueueableUploadError(normalizedError)) {
        rethrow;
      }
      final queuedValue = await _offlineUploadQueueService.enqueueBookingPhoto(
        bytes: bytes,
        bookingId: bookingId,
        statusKey: statusKey.trim(),
        fieldKey: fieldKey.trim(),
        fileName: resolvedFileName,
        mimeType: mimeType?.isNotEmpty == true ? mimeType : null,
        size: size,
      );
      return queuedValue;
    }
  }

  Future<void> _writeBookingOnline(
    String bookingId,
    Map<String, dynamic> document,
  ) async {
    final stopwatch = Stopwatch()..start();
    _pendingBookingWriteTraces[bookingId] = stopwatch;
    _writeTrace(
      'sdk set start id=$bookingId online=${currentNetworkStatus()} '
      'fields=${document.keys.length}',
    );
    try {
      await _firestore
          .runTransaction<void>(
            (transaction) => _writeBookingAndChassisTransaction(
              transaction: transaction,
              bookingId: bookingId,
              document: document,
            ),
          )
          .timeout(
            _remoteSaveTimeout,
            onTimeout: () => throw TimeoutException(
              'booking remote write timeout for $bookingId',
            ),
          );
      _writeTrace(
        'sdk set acknowledged id=$bookingId elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
    } catch (error) {
      _writeTrace(
        'sdk set error id=$bookingId elapsedMs=${stopwatch.elapsedMilliseconds} error=$error',
      );
      rethrow;
    }
  }

  Future<void> _writeBookingAndChassisTransaction({
    required Transaction transaction,
    required String bookingId,
    required Map<String, dynamic> document,
  }) async {
    final bookingRef = _bookingsCollection.doc(bookingId);
    final existingBooking = await transaction.get(bookingRef);
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
    DocumentSnapshot<Map<String, dynamic>>? displacedBooking;
    if (nextChassisId != null) {
      nextChassis = await transaction.get(
        _firestore.collection('chassis').doc(nextChassisId),
      );
      if (!nextChassis.exists) {
        throw StateError('The selected chassis no longer exists.');
      }
      final displacedBookingId = normalizeId(
        nextChassis.data()?['current_booking_id']?.toString(),
      );
      if (displacedBookingId != null && displacedBookingId != bookingId) {
        displacedBooking = await transaction.get(
          _bookingsCollection.doc(displacedBookingId),
        );
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    if (previousChassisId != null && previousChassisId != nextChassisId) {
      transaction.set(
        _firestore.collection('chassis').doc(previousChassisId),
        {
          'current_booking_id': FieldValue.delete(),
          'current_driver_id': FieldValue.delete(),
          'current_status': 'ready',
          'updated_at': now,
        },
        SetOptions(merge: true),
      );
    }
    if (displacedBooking?.exists == true) {
      transaction.set(displacedBooking!.reference, {
        'chassis_id': FieldValue.delete(),
        'updated_at': now,
      }, SetOptions(merge: true));
    }
    if (nextChassis != null) {
      transaction.set(
        nextChassis.reference,
        lifecycle == null
            ? _defaultChassisAssignmentPatch(
                bookingId: bookingId,
                bookingDocument: document,
                now: now,
              )
            : _lifecycleChassisPatch(
                instruction: lifecycle,
                bookingId: bookingId,
                bookingDocument: document,
                now: now,
              ),
        SetOptions(merge: true),
      );
    }
    transaction.set(bookingRef, document);
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

  bool _isQueueableBookingWriteError(Object error) {
    if (error is TimeoutException) {
      return true;
    }
    final normalizedError = normalizeUserErrorText(
      error.toString(),
      fallback: '',
    ).toLowerCase();
    return _isQueueableUploadError(normalizedError);
  }

  Future<void> _deleteObsoletePhotos({
    required Map<String, dynamic>? previousStatusOutputs,
    required Map<String, dynamic>? nextStatusOutputs,
  }) async {
    final previousPaths = _collectPhotoStoragePaths(previousStatusOutputs);
    final nextPaths = _collectPhotoStoragePaths(nextStatusOutputs);
    for (final entry in previousPaths.entries) {
      if (nextPaths[entry.key] == entry.value) {
        continue;
      }
      await _photoStorageService.deleteByPath(entry.value);
    }
  }

  Map<String, String> _collectPhotoStoragePaths(
    Map<String, dynamic>? statusOutputs,
  ) {
    final paths = <String, String>{};
    if (statusOutputs == null) {
      return paths;
    }
    for (final sectionEntry in statusOutputs.entries) {
      final section = sectionEntry.value;
      if (section is! Map) {
        continue;
      }
      final fields = section['fields'];
      if (fields is! Map) {
        continue;
      }
      for (final fieldEntry in fields.entries) {
        final storagePath = photoStoragePath(fieldEntry.value);
        if (storagePath == null) {
          continue;
        }
        paths['${sectionEntry.key}/${fieldEntry.key}'] = storagePath;
      }
    }
    return paths;
  }

  Future<List<Booking>> _inflateBookings(
    List<Map<String, dynamic>> documents,
  ) async {
    _log(
      'inflate start sourceDocs=${documents.length} ids=${documents.map((doc) => normalizeId(doc["id"]?.toString()) ?? "-").join(",")}',
    );
    final cachedUserDocuments =
        await _cache.readDocuments('users') ?? const <Map<String, dynamic>>[];
    final cachedMakeDocuments =
        await _cache.readDocuments('vehicle_makes') ??
        const <Map<String, dynamic>>[];
    final cachedTypeDocuments =
        await _cache.readDocuments('vehicle_types') ??
        const <Map<String, dynamic>>[];
    _log(
      'inflate relations cachedUsers=${cachedUserDocuments.length} cachedMakes=${cachedMakeDocuments.length} cachedTypes=${cachedTypeDocuments.length}',
    );

    if (cachedUserDocuments.isEmpty) {
      unawaited(
        _authRequest.getUsers().catchError((error, stackTrace) {
          return const <UserModel>[];
        }),
      );
    }
    if (cachedMakeDocuments.isEmpty) {
      unawaited(
        _vehicleRequest.getMakes().catchError((error, stackTrace) {
          return const <VehicleMake>[];
        }),
      );
    }
    if (cachedTypeDocuments.isEmpty) {
      unawaited(
        _vehicleRequest.getTypes().catchError((error, stackTrace) {
          return const <VehicleCatalogItem>[];
        }),
      );
    }
    unawaited(
      _vehicleRequest.getSizes().catchError((error, stackTrace) {
        return const <VehicleCatalogItem>[];
      }),
    );

    final userById = <String, UserModel>{
      for (final document in cachedUserDocuments)
        if ((document['id']?.toString().trim() ?? '').isNotEmpty)
          document['id']!.toString().trim(): UserModel.fromMap(document),
    };
    final typeById = <String, Map<String, dynamic>>{
      for (final document in cachedTypeDocuments)
        if ((document['id']?.toString().trim() ?? '').isNotEmpty)
          document['id']!.toString().trim(): Map<String, dynamic>.from(
            document,
          ),
    };
    final makeById = <String, VehicleMake>{
      for (final document in cachedMakeDocuments)
        if ((document['id']?.toString().trim() ?? '').isNotEmpty)
          document['id']!.toString().trim(): VehicleMake.fromMap({
            ...document,
            if (document['type'] == null)
              'type': typeById[document['type_id']?.toString().trim()],
            if (document['driver'] == null)
              'driver': userById[document['driver_id']?.toString().trim()]
                  ?.toMap(),
          }),
    };
    final bookings = documents
        .map(
          (doc) => _bookingFromFirestoreMap(
            doc,
            userById: userById,
            makeById: makeById,
          ),
        )
        .toList();
    _log(
      'inflate mapped count=${bookings.length} ids=${bookings.map((booking) => normalizeId(booking.id) ?? "-").join(",")} clientIds=${bookings.map((booking) => normalizeId(booking.client?.id) ?? "-").join(",")}',
    );
    bookings.sort((a, b) {
      final createdComparison = _compareLatestFirst(a.createdAt, b.createdAt);
      if (createdComparison != 0) {
        return createdComparison;
      }
      final aId = int.tryParse(a.id ?? '');
      final bId = int.tryParse(b.id ?? '');
      if (aId != null && bId != null) {
        return bId.compareTo(aId);
      }
      return (b.id ?? '').compareTo(a.id ?? '');
    });
    _log(
      'inflate finish count=${bookings.length} sortedIds=${bookings.map((booking) => normalizeId(booking.id) ?? "-").join(",")}',
    );
    return bookings;
  }

  void _ensureBookingsRealtimeSync() {
    if (_bookingsRealtimeSubscription != null) {
      return;
    }
    _initialRealtimeSyncCompleter ??= Completer<void>();
    _log('realtime sync subscribe includeMetadataChanges=true');
    _bookingsRealtimeSubscription = _bookingsCollection
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            unawaited(_handleRealtimeSnapshot(snapshot));
          },
          onError: (error, stackTrace) {
            _log('realtime sync error error=$error');
            if (!(_initialRealtimeSyncCompleter?.isCompleted ?? true)) {
              _initialRealtimeSyncCompleter?.complete();
            }
          },
        );
  }

  Future<void> _syncPersistedCacheTrustFromMetaSignal() async {
    final existing = _metaSyncFuture;
    if (existing != null) {
      return existing;
    }
    final future = _runPersistedCacheTrustSync();
    _metaSyncFuture = future;
    try {
      await future;
    } finally {
      if (identical(_metaSyncFuture, future)) {
        _metaSyncFuture = null;
      }
    }
  }

  Future<void> _runPersistedCacheTrustSync() async {
    if (!currentNetworkStatus()) {
      _isPersistedCacheTrustedOnline = false;
      return;
    }
    final localVersion = await _cache.readStoredVersion(_bookingsResourceKey);
    final remoteVersion = await _cache
        .readRemoteVersionSafe(_bookingsResourceKey)
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
    _log(
      'meta trust evaluate local=${localVersion ?? "-"} remote=${remoteVersion ?? "-"}',
    );
    if (remoteVersion == null || remoteVersion.isEmpty) {
      _isPersistedCacheTrustedOnline = true;
      return;
    }
    final matches = localVersion == remoteVersion;
    _isPersistedCacheTrustedOnline = matches;
    if (matches) {
      _log('meta trust accepted version=$remoteVersion');
      return;
    }
    await _invalidatePersistedBookingsCache(
      reason: 'meta-version-mismatch',
      remoteVersion: remoteVersion,
    );
  }

  Future<void> _waitForPersistedCacheTrustSync() async {
    final future = _metaSyncFuture;
    if (future == null) {
      return;
    }
    try {
      await future.timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {}
  }

  Future<void> _invalidatePersistedBookingsCache({
    required String reason,
    String? remoteVersion,
  }) async {
    _log(
      'persisted cache invalidate start reason=$reason remoteVersion=${remoteVersion ?? "-"}',
    );
    _isPersistedCacheTrustedOnline = false;
    _memoryBookings = const [];
    _hasResolvedBookings = false;
    await _cache.clearResource(_bookingsResourceKey);
    _bookingCacheUpdates.add(null);
    _log('persisted cache invalidate done reason=$reason');
  }

  Future<void> _handleRealtimeSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final eventStopwatch = Stopwatch()..start();
    final online = currentNetworkStatus();
    final fromCache = snapshot.metadata.isFromCache;
    final hasPendingWrites = snapshot.metadata.hasPendingWrites;
    final shouldApply = !online || (!fromCache && !hasPendingWrites);
    if (hasPendingWrites || _pendingBookingWriteTraces.isNotEmpty) {
      _writeTrace(
        'realtime snapshot docs=${snapshot.docs.length} fromCache=$fromCache '
        'pendingWrites=$hasPendingWrites apply=$shouldApply '
        'trackedWrites=${_pendingBookingWriteTraces.keys.join(",")}',
      );
    }
    if (online && hasPendingWrites) {
      // Keep the last server-confirmed list visible. A local pending write is
      // not authoritative, but it must not erase unrelated booking rows.
      _writeTrace('realtime pending write ignored; retained confirmed list');
      return;
    }
    if (!shouldApply) {
      return;
    }
    final documents = snapshot.docs.map(documentData).toList(growable: false);
    _log(
      'realtime sync documentData mapped docs=${documents.length} elapsedMs=${eventStopwatch.elapsedMilliseconds}',
    );
    await _cache.writeDocuments(
      resourceKey: _bookingsResourceKey,
      documents: documents,
    );
    _log(
      'realtime sync cache write docs=${documents.length} elapsedMs=${eventStopwatch.elapsedMilliseconds}',
    );
    if (online && !fromCache) {
      _hasAuthoritativeOnlineSync = true;
      if (_pendingBookingWriteTraces.isNotEmpty) {
        final writeIds = _pendingBookingWriteTraces.entries
            .map((entry) => '${entry.key}:${entry.value.elapsedMilliseconds}ms')
            .join(',');
        _writeTrace('realtime server acknowledgement writes=$writeIds');
        _pendingBookingWriteTraces.clear();
      }
    }
    await _primeMemoryBookingsFromCache();
    _bookingCacheUpdates.add(null);
    _log(
      'realtime sync apply done docs=${documents.length} authoritative=$_hasAuthoritativeOnlineSync elapsedMs=${eventStopwatch.elapsedMilliseconds}',
    );
    if (!(_initialRealtimeSyncCompleter?.isCompleted ?? true)) {
      _initialRealtimeSyncCompleter?.complete();
    }
  }

  Future<void> _waitForInitialRealtimeSync() async {
    final completer = _initialRealtimeSyncCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    try {
      await completer.future.timeout(_startupTimeout, onTimeout: () => null);
    } catch (_) {
      // Keep the request path alive and fall back to direct fetch.
    }
  }

  Future<void> _refreshBookingsCacheInBackground({
    bool forceServer = false,
    String reason = 'general',
  }) async {
    if (_backgroundRefreshFuture != null) {
      _log('refresh background skip reason=in-flight');
      return _backgroundRefreshFuture;
    }
    final completer = Completer<void>();
    _backgroundRefreshFuture = completer.future;
    final refreshStopwatch = Stopwatch()..start();
    _log(
      'refresh background start reason=$reason forceServer=$forceServer elapsedMs=${refreshStopwatch.elapsedMilliseconds}',
    );
    try {
      List<Map<String, dynamic>> documents;
      try {
        _log(
          'refresh background sdk fetch start forceServer=$forceServer elapsedMs=${refreshStopwatch.elapsedMilliseconds}',
        );
        final snapshot =
            await _fetchAuthoritativeBookingsSnapshot(
              forceServer: forceServer,
            ).timeout(
              _startupTimeout,
              onTimeout: () =>
                  throw TimeoutException('bookings refresh timeout'),
            );
        if (currentNetworkStatus() && snapshot.metadata.hasPendingWrites) {
          _log('refresh background skip pending local booking write');
          return;
        }
        documents = snapshot.docs.map(documentData).toList(growable: false);
        _log(
          'refresh background sdk get done docs=${snapshot.docs.length} fromCache=${snapshot.metadata.isFromCache} pendingWrites=${snapshot.metadata.hasPendingWrites} elapsedMs=${refreshStopwatch.elapsedMilliseconds}',
        );
        _log(
          'refresh background source=sdk docs=${documents.length} elapsedMs=${refreshStopwatch.elapsedMilliseconds}',
        );
        _log(
          'firestore sdk bookings present=${documents.isNotEmpty} count=${documents.length}',
        );
        if (currentNetworkStatus()) {
          _hasAuthoritativeOnlineSync = true;
          _isPersistedCacheTrustedOnline = true;
        }
      } catch (error) {
        _log(
          'refresh background sdk fetch error error=$error elapsedMs=${refreshStopwatch.elapsedMilliseconds}',
        );
        rethrow;
      }
      await _cache.writeDocuments(
        resourceKey: _bookingsResourceKey,
        documents: documents,
      );
      _log(
        'refresh background cache write docs=${documents.length} elapsedMs=${refreshStopwatch.elapsedMilliseconds}',
      );
      await _primeMemoryBookingsFromCache();
      _log(
        'refresh background applied memory=${_memoryBookings.length} elapsedMs=${refreshStopwatch.elapsedMilliseconds}',
      );
      _bookingCacheUpdates.add(null);
    } catch (error) {
      _log(
        'refresh background error error=$error elapsedMs=${refreshStopwatch.elapsedMilliseconds}',
      );
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      _backgroundRefreshFuture = null;
      _log(
        'refresh background finish elapsedMs=${refreshStopwatch.elapsedMilliseconds}',
      );
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>>
  _fetchAuthoritativeBookingsSnapshot({bool forceServer = false}) {
    final options = forceServer && currentNetworkStatus()
        ? const GetOptions(source: Source.server)
        : null;
    _log(
      'authoritative snapshot request start forceServer=$forceServer online=${currentNetworkStatus()} source=${options?.source ?? "default"}',
    );
    return _bookingsCollection.get(options);
  }

  Future<List<Map<String, dynamic>>> _fetchBookingsViaSdkOnly() async {
    final fetchStopwatch = Stopwatch()..start();
    _log(
      'getBookings sdk-only fetch start elapsedMs=${fetchStopwatch.elapsedMilliseconds}',
    );
    final sdkCachedDocuments = await _readCollectionSdkCacheOnly(
      _bookingsCollection,
    );
    _log(
      'getBookings sdk-only cache docs=${sdkCachedDocuments.length} elapsedMs=${fetchStopwatch.elapsedMilliseconds}',
    );
    if (sdkCachedDocuments.isNotEmpty && !currentNetworkStatus()) {
      return sdkCachedDocuments;
    }
    final snapshot =
        await _fetchAuthoritativeBookingsSnapshot(
          forceServer: currentNetworkStatus(),
        ).timeout(
          _startupTimeout,
          onTimeout: () => throw TimeoutException('bookings fetch timeout'),
        );
    _log(
      'getBookings sdk-only get done docs=${snapshot.docs.length} fromCache=${snapshot.metadata.isFromCache} pendingWrites=${snapshot.metadata.hasPendingWrites} elapsedMs=${fetchStopwatch.elapsedMilliseconds}',
    );
    if (currentNetworkStatus() && snapshot.metadata.hasPendingWrites) {
      _log('getBookings sdk-only skip pending local booking write');
      return const <Map<String, dynamic>>[];
    }
    final documents = snapshot.docs.map(documentData).toList(growable: false);
    _log(
      'getBookings sdk-only documentData mapped docs=${documents.length} elapsedMs=${fetchStopwatch.elapsedMilliseconds}',
    );
    await _cache.writeDocuments(
      resourceKey: _bookingsResourceKey,
      documents: documents,
    );
    if (currentNetworkStatus()) {
      _hasAuthoritativeOnlineSync = true;
      _isPersistedCacheTrustedOnline = true;
    }
    return documents;
  }

  Future<List<Booking>> _cacheInflatedBookings(
    List<Map<String, dynamic>> visibleDocuments,
  ) async {
    _log(
      'cache inflate start visible=${visibleDocuments.length} ids=${visibleDocuments.map((doc) => normalizeId(doc["id"]?.toString()) ?? "-").join(",")}',
    );
    final bookings = await _inflateBookings(visibleDocuments);
    _memoryBookings = List<Booking>.from(bookings);
    _hasResolvedBookings = true;
    _log(
      'cache inflate finish memory=${_memoryBookings.length} ids=${_memoryBookings.map((booking) => normalizeId(booking.id) ?? "-").join(",")}',
    );
    return bookings;
  }

  Future<void> _primeMemoryBookingsFromCache() async {
    final cachedDocuments = await _cache.readDocuments(_bookingsResourceKey);
    if (cachedDocuments == null) {
      _memoryBookings = const [];
      _hasResolvedBookings = true;
      _log('prime memory result cached=null memory=0');
      return;
    }
    if (cachedDocuments.isEmpty) {
      _memoryBookings = const [];
      _hasResolvedBookings = true;
      _log('prime memory result cached=0 memory=0');
      return;
    }
    final queuedDocuments = await _readQueuedBookingDocumentsSafe();
    final visibleDocuments = _mergeQueuedPendingBookingDocuments(
      existingDocuments: cachedDocuments,
      queuedDocuments: queuedDocuments,
    );
    _log(
      'prime memory visible docs=${visibleDocuments.length} ids=${visibleDocuments.map((doc) => normalizeId(doc["id"]?.toString()) ?? "-").join(",")}',
    );
    await _cacheInflatedBookings(visibleDocuments);
    _log(
      'prime memory result cached=${cachedDocuments.length} queued=${queuedDocuments.length} visible=${visibleDocuments.length} memory=${_memoryBookings.length}',
    );
  }

  void _upsertMemoryBooking(Booking booking) {
    final bookingId = normalizeId(booking.id);
    if (bookingId == null) {
      return;
    }
    final nextBookings = List<Booking>.from(_memoryBookings);
    final existingIndex = nextBookings.indexWhere(
      (item) => normalizeId(item.id) == bookingId,
    );
    if (existingIndex >= 0) {
      nextBookings[existingIndex] = booking;
    } else {
      nextBookings.add(booking);
    }
    nextBookings.sort((a, b) {
      final createdComparison = _compareLatestFirst(a.createdAt, b.createdAt);
      if (createdComparison != 0) {
        return createdComparison;
      }
      final aId = int.tryParse(a.id ?? '');
      final bId = int.tryParse(b.id ?? '');
      if (aId != null && bId != null) {
        return bId.compareTo(aId);
      }
      return (b.id ?? '').compareTo(a.id ?? '');
    });
    _memoryBookings = nextBookings;
    _hasResolvedBookings = true;
  }

  Future<List<Map<String, dynamic>>> _readQueuedBookingDocumentsSafe() async {
    try {
      final queued = await _offlineMutationQueueService
          .readQueuedCollectionDocuments(collectionKey: _bookingsResourceKey)
          .timeout(
            _queuedReadTimeout,
            onTimeout: () {
              return const <Map<String, dynamic>>[];
            },
          );
      _log('queued documents read count=${queued.length}');
      return queued;
    } catch (error) {
      _log('queued documents read error error=$error');
      return const <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic> _toFirestoreMap(Booking booking) {
    return {
      'id': booking.id,
      'client_id': booking.client?.id,
      'client_status': booking.clientStatus,
      'billing_status': _normalizedBillingStatus(booking.billingStatus),
      'driver_status': booking.driverStatus,
      'helper_status': booking.helperStatus,
      'vehicle_make_id': booking.vehicleMake?.id,
      'driver_id': booking.driver?.id,
      'helper_id': booking.helper?.id,
      'chassis_id': booking.chassisId,
      'status_outputs': booking.statusOutputs,
      'delivered_at': booking.deliveredAt?.toUtc().toIso8601String(),
      'created_at': booking.createdAt?.toIso8601String(),
      'updated_at': booking.updatedAt?.toIso8601String(),
      'submission_key': booking.submissionKey,
    };
  }

  Map<String, dynamic> _toCacheDocument(Booking booking) {
    return {
      ..._toFirestoreMap(booking),
      if ((booking.localSyncStatus ?? '').trim().isNotEmpty)
        'local_sync_status': booking.localSyncStatus,
    };
  }

  Booking _bookingFromFirestoreMap(
    Map<String, dynamic> map, {
    required Map<String, UserModel> userById,
    required Map<String, VehicleMake> makeById,
  }) {
    return Booking(
      id: map['id']?.toString(),
      client: userById[map['client_id']?.toString()],
      clientStatus: map['client_status']?.toString(),
      billingStatus: _normalizedBillingStatus(
        map['billing_status']?.toString(),
      ),
      driverStatus: map['driver_status']?.toString(),
      helperStatus: map['helper_status']?.toString(),
      vehicleMake: makeById[map['vehicle_make_id']?.toString()],
      driver: userById[map['driver_id']?.toString()],
      helper: userById[map['helper_id']?.toString()],
      chassisId: map['chassis_id']?.toString(),
      statusOutputs: map['status_outputs'] is Map
          ? Map<String, dynamic>.from(map['status_outputs'] as Map)
          : null,
      deliveredAt: _toDateTime(map['delivered_at']),
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
      localSyncStatus: map['local_sync_status']?.toString(),
      submissionKey: map['submission_key']?.toString(),
    );
  }

  Future<Map<String, UserModel>> _userById() async {
    final users = await _authRequest.getUsers();
    return {for (final item in users) item.id ?? '': item};
  }

  Future<Map<String, VehicleMake>> _makeById() async {
    final makes = await _vehicleRequest.getMakes();
    await _vehicleRequest.getSizes();
    return {for (final item in makes) item.id ?? '': item};
  }

  String _normalizedBillingStatus(String? value) {
    return (value?.trim().toLowerCase() == 'billed') ? 'billed' : 'unbilled';
  }

  Future<String> _nextBookingId() async {
    final cachedDocuments = await _cache.readDocuments(_bookingsResourceKey);
    final cachedHighest = (cachedDocuments ?? const <Map<String, dynamic>>[])
        .map((doc) => int.tryParse(doc['id']?.toString() ?? ''))
        .whereType<int>()
        .fold<int>(0, (max, value) => value > max ? value : max);
    if (!currentNetworkStatus()) {
      return '${cachedHighest + 1}';
    }
    var remoteHighest = cachedHighest;
    try {
      final snapshot = await _bookingsCollection.get().timeout(
        _webNextIdTimeout,
        onTimeout: () => throw TimeoutException('booking next-id sdk timeout'),
      );
      remoteHighest = snapshot.docs
          .map((doc) => int.tryParse(documentData(doc)['id']?.toString() ?? ''))
          .whereType<int>()
          .fold<int>(0, (max, value) => value > max ? value : max);
    } catch (error) {
      // Keep the cached highest id when remote lookup is unavailable.
    }
    final highest = remoteHighest > cachedHighest
        ? remoteHighest
        : cachedHighest;
    return '${highest + 1}';
  }

  Future<String> _reserveNextBookingId({required String submissionKey}) async {
    if (!currentNetworkStatus()) {
      // Offline creates retain the existing queued-write behavior. A server
      // transaction is not available until the device reconnects.
      return _nextBookingId();
    }

    final idempotencyRef = _idManagementCollection.doc(
      _idempotencyDocumentId('bookings', submissionKey),
    );
    final bootstrapNextId = await _bootstrapNextBookingIdIfCounterMissing();
    _log('booking id reservation start key=$submissionKey');
    final reservation = await _firestore
        .runTransaction<_BookingIdReservation>((transaction) async {
          final idempotencySnapshot = await transaction.get(idempotencyRef);
          final priorId = int.tryParse(
            idempotencySnapshot.data()?['document_id']?.toString() ?? '',
          );
          if (priorId != null && priorId > 0) {
            return _BookingIdReservation('$priorId', reused: true);
          }

          final counterSnapshot = await transaction.get(_bookingsCounterRef);
          final counterNextId = int.tryParse(
            counterSnapshot.data()?['next_id']?.toString() ?? '',
          );
          var reservedId = counterNextId ?? bootstrapNextId;
          // Do not query the full bookings collection before every create.
          // This keeps the ID reservation to small document reads and avoids
          // the web SDK collection-read timeout seen on booking submission.
          while ((await transaction.get(
            _bookingsCollection.doc('$reservedId'),
          )).exists) {
            reservedId++;
          }
          final nowIso = DateTime.now().toIso8601String();
          transaction.set(_bookingsCounterRef, {
            'next_id': reservedId + 1,
            'updated_at': nowIso,
          }, SetOptions(merge: true));
          transaction.set(idempotencyRef, {
            'kind': 'idempotency',
            'resource_key': 'bookings',
            'document_id': '$reservedId',
            'submission_key': submissionKey,
            'created_at': nowIso,
          });
          return _BookingIdReservation('$reservedId');
        })
        .timeout(
          _webNextIdTimeout,
          onTimeout: () =>
              throw TimeoutException('booking id reservation timeout'),
        );
    _log(
      'booking id reservation id=${reservation.id} reused=${reservation.reused}',
    );
    return reservation.id;
  }

  Future<int> _bootstrapNextBookingIdIfCounterMissing() async {
    final counterSnapshot = await _bookingsCounterRef.get().timeout(
      _webNextIdTimeout,
      onTimeout: () => throw TimeoutException('booking counter read timeout'),
    );
    final existingNextId = int.tryParse(
      counterSnapshot.data()?['next_id']?.toString() ?? '',
    );
    if (counterSnapshot.exists &&
        existingNextId != null &&
        existingNextId > 0) {
      return existingNextId;
    }
    final bookingsSnapshot = await _bookingsCollection.get().timeout(
      _webNextIdTimeout,
      onTimeout: () => throw TimeoutException('booking ID bootstrap timeout'),
    );
    final highestId = bookingsSnapshot.docs
        .map(
          (document) =>
              int.tryParse(documentData(document)['id']?.toString() ?? ''),
        )
        .whereType<int>()
        .fold<int>(0, (highest, id) => id > highest ? id : highest);
    return highestId + 1;
  }

  String? _normalizedSubmissionKey(String? value) {
    final normalized = value?.trim();
    return normalized?.isNotEmpty == true ? normalized : null;
  }

  String _newSubmissionKey() =>
      'booking_${DateTime.now().microsecondsSinceEpoch}';

  String _idempotencyDocumentId(String resourceKey, String submissionKey) =>
      '${resourceKey}_${base64UrlEncode(utf8.encode(submissionKey))}';

  String _offlineBookingId(String submissionKey) =>
      'offline_${submissionKey.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  int _compareLatestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return b.compareTo(a);
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }

  Future<List<Map<String, dynamic>>> _readCollectionSdkCacheOnly(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    try {
      _log('sdk cache-only read start path=${collection.path}');
      final snapshot = await collection
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 1));
      final documents = snapshot.docs.map(documentData).toList(growable: false);
      _log(
        'sdk cache-only read done path=${collection.path} docs=${documents.length}',
      );
      return documents;
    } catch (error) {
      _log('sdk cache-only read error path=${collection.path} error=$error');
      return const <Map<String, dynamic>>[];
    }
  }

  int? _toInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  List<Map<String, dynamic>> _mergeQueuedPendingBookingDocuments({
    required List<Map<String, dynamic>> existingDocuments,
    required List<Map<String, dynamic>> queuedDocuments,
  }) {
    final documentsById = <String, Map<String, dynamic>>{
      for (final document in existingDocuments)
        if (normalizeId(document['id']?.toString()) != null)
          normalizeId(document['id']?.toString())!: Map<String, dynamic>.from(
            document,
          ),
    };
    for (final document in queuedDocuments) {
      final id = normalizeId(document['id']?.toString());
      if (id == null) {
        continue;
      }
      documentsById[id] = Map<String, dynamic>.from(document);
    }
    final merged = documentsById.values.toList(growable: false);
    merged.sort((left, right) {
      final leftDate = _toDateTime(left['created_at'] ?? left['updated_at']);
      final rightDate = _toDateTime(right['created_at'] ?? right['updated_at']);
      final byDate = _compareLatestFirst(leftDate, rightDate);
      if (byDate != 0) {
        return byDate;
      }
      final leftId = normalizeId(left['id']?.toString()) ?? '';
      final rightId = normalizeId(right['id']?.toString()) ?? '';
      return rightId.compareTo(leftId);
    });
    return merged;
  }

  bool _sameBookingDocumentSet(
    List<Map<String, dynamic>> left,
    List<Map<String, dynamic>> right,
  ) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (mapEquals(left[index], right[index])) {
        continue;
      }
      return false;
    }
    return true;
  }

  String _bookingEmissionFingerprint(List<Booking> bookings) {
    return bookings
        .map(
          (booking) => [
            normalizeId(booking.id) ?? '-',
            booking.updatedAt?.toUtc().toIso8601String() ?? '-',
            booking.createdAt?.toUtc().toIso8601String() ?? '-',
            booking.clientStatus?.trim().toLowerCase() ?? '-',
            booking.driverStatus?.trim().toLowerCase() ?? '-',
            booking.helperStatus?.trim().toLowerCase() ?? '-',
            booking.chassisId?.trim() ?? '-',
            booking.localSyncStatus?.trim().toLowerCase() ?? '-',
          ].join('|'),
        )
        .join('||');
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

  Future<T> _runRequest<T>(
    Future<T> Function() action, {
    required String fallback,
  }) async {
    try {
      return await action();
    } on FirebaseException catch (error) {
      throw Exception(userFacingErrorMessage(error, fallback: fallback));
    } catch (error) {
      throw Exception(userFacingErrorMessage(error, fallback: fallback));
    }
  }

  void _log(String message) {
    // Temporary diagnostics removed.
  }

  void _writeTrace(String message) {
    // Temporary diagnostics removed.
  }
}

class _BookingIdReservation {
  const _BookingIdReservation(this.id, {this.reused = false});

  final String id;
  final bool reused;
}
