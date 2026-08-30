import 'dart:async';

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
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _authRequest = authRequest ?? AuthRequest.instance,
       _vehicleRequest = vehicleRequest ?? VehicleRequest.instance,
       _firestorePublicDocumentFetcher =
           firestorePublicDocumentFetcher ??
           createFirestorePublicDocumentFetcher();

  static final BookingRequest instance = BookingRequest();
  static const _bookingsResourceKey = 'bookings';
  static const Duration _startupTimeout = Duration(seconds: 6);
  static const Duration _queuedReadTimeout = Duration(seconds: 1);
  static const Duration _remoteSaveTimeout = Duration(seconds: 12);
  static const Duration _photoUploadTimeout = Duration(minutes: 1);
  static bool _didKickOffBackgroundQueueInitialization = false;
  static List<Booking> _memoryBookings = const [];
  static bool _hasResolvedBookings = false;
  static bool _isRefreshingFromVersionSignal = false;
  StreamSubscription<String?>? _bookingsVersionSignalSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _bookingsRealtimeSnapshotSubscription;

  static bool get hasHydratedBookings => _memoryBookings.isNotEmpty;
  static bool get hasResolvedBookings => _hasResolvedBookings;
  static int get hydratedBookingCount => _memoryBookings.length;
  static List<Booking> get hydratedBookingsSnapshot =>
      List<Booking>.unmodifiable(_memoryBookings);

  final FirebaseFirestore _firestore;
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

  @override
  Future<void> initialize() async {
    if (_didKickOffBackgroundQueueInitialization) {
      return;
    }
    _didKickOffBackgroundQueueInitialization = true;
    _ensureRemoteRealtimeCacheSync();
    if (currentNetworkStatus()) {
      unawaited(
        _refreshBookingsCacheInBackground().catchError((error, stackTrace) {}),
      );
    }
    unawaited(
      OfflineQueueCoordinatorService.instance.initialize().then((_) {
      }).catchError((error, stackTrace) {
      }),
    );
  }

  void _ensureRemoteRealtimeCacheSync() {
    if (_bookingsVersionSignalSubscription != null) {
      _ensureBookingsRealtimeSnapshotSync();
      return;
    }
    _bookingsVersionSignalSubscription = _cache
        .watchResourceVersion(_bookingsResourceKey)
        .listen((version) {
          unawaited(_handleBookingsVersionSignal(version));
        }, onError: (_, _) {});
    _ensureBookingsRealtimeSnapshotSync();
  }

  void _ensureBookingsRealtimeSnapshotSync() {
    if (_bookingsRealtimeSnapshotSubscription != null) {
      return;
    }
    _bookingsRealtimeSnapshotSubscription = _bookingsCollection
        .snapshots()
        .listen((snapshot) {
          unawaited(_handleBookingsRealtimeSnapshot(snapshot));
        }, onError: (_, _) {});
  }

  Future<void> _handleBookingsRealtimeSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    try {
      final documents = snapshot.docs.map(documentData).toList(growable: false);
      await _cache.writeDocuments(
        resourceKey: _bookingsResourceKey,
        documents: documents,
      );
      await _primeMemoryBookingsFromCache();
      _bookingCacheUpdates.add(null);
    } catch (_) {
      // Keep UI usable even if realtime reconciliation fails.
    }
  }

  Future<void> _handleBookingsVersionSignal(String? remoteVersion) async {
    final shouldRefresh = await _cache.hasRemoteVersionMismatch(
      _bookingsResourceKey,
      remoteVersion,
    );
    if (!shouldRefresh || _isRefreshingFromVersionSignal) {
      return;
    }
    _isRefreshingFromVersionSignal = true;
    try {
      await _refreshBookingsCacheInBackground();
    } finally {
      _isRefreshingFromVersionSignal = false;
    }
  }

  @override
  Future<List<Booking>> getBookings() async {
    return _runRequest(() async {
      await initialize();
      if (_memoryBookings.isNotEmpty) {
        if (currentNetworkStatus()) {
          unawaited(_refreshBookingsCacheInBackground());
        }
        return List<Booking>.from(_memoryBookings);
      }
      List<Map<String, dynamic>> documents;
      try {
        documents = await _cache.getDocumentsVerifiedOnlineFirst(
          resourceKey: _bookingsResourceKey,
          fetchDocuments: () async {
            final sdkCachedDocuments = await _readCollectionSdkCacheOnly(
              _bookingsCollection,
            );
            if (sdkCachedDocuments.isNotEmpty && !currentNetworkStatus()) {
              return sdkCachedDocuments;
            }
            final snapshot = await _bookingsCollection.get().timeout(
              _startupTimeout,
              onTimeout: () => throw TimeoutException('bookings fetch timeout'),
            );
            return snapshot.docs.map(documentData).toList(growable: false);
          },
        );
        _bookingCacheUpdates.add(null);
      } catch (error) {
        if (currentNetworkStatus()) {
          try {
            documents = await _fetchCollectionDocumentsViaPublicRest('bookings');
            await _cache.writeDocuments(
              resourceKey: _bookingsResourceKey,
              documents: documents,
            );
            _bookingCacheUpdates.add(null);
          } catch (_) {
            final lateCachedDocuments = await _cache.readDocuments(
              _bookingsResourceKey,
            );
            if (lateCachedDocuments != null) {
              documents = lateCachedDocuments;
            } else {
              rethrow;
            }
          }
        } else {
          final lateCachedDocuments = await _cache.readDocuments(
            _bookingsResourceKey,
          );
          if (lateCachedDocuments != null) {
            documents = lateCachedDocuments;
          } else {
            rethrow;
          }
        }
      }
      final queuedDocuments = await _readQueuedBookingDocumentsSafe();
      final visibleDocuments = _mergeQueuedPendingBookingDocuments(
        existingDocuments: documents,
        queuedDocuments: queuedDocuments,
      );
      return _cacheInflatedBookings(visibleDocuments);
    }, fallback: 'We could not load the bookings right now.');
  }

  @override
  Stream<List<Booking>> watchBookings() {
    return Stream<List<Booking>>.multi((controller) {
      Future<void> emitCachedBookings() async {
        if (_memoryBookings.isNotEmpty && !controller.isClosed) {
          controller.add(List<Booking>.from(_memoryBookings));
        }
        final cachedDocuments = await _cache.readDocuments(_bookingsResourceKey);
        if (controller.isClosed) {
          return;
        }
        if (cachedDocuments == null || cachedDocuments.isEmpty) {
          if (currentNetworkStatus()) {
            unawaited(_refreshBookingsCacheInBackground());
          }
          return;
        }
        final queuedDocuments = await _readQueuedBookingDocumentsSafe();
        final visibleDocuments = _mergeQueuedPendingBookingDocuments(
          existingDocuments: cachedDocuments,
          queuedDocuments: queuedDocuments,
        );
        if (!_sameBookingDocumentSet(cachedDocuments, visibleDocuments)) {
          await _cache.writeDocuments(
            resourceKey: _bookingsResourceKey,
            documents: visibleDocuments,
          );
        }
        controller.add(await _cacheInflatedBookings(visibleDocuments));
      }

      unawaited(emitCachedBookings());

      final localSubscription = _bookingCacheUpdates.stream.listen((_) {
        unawaited(emitCachedBookings());
      }, onError: (_) {});

      controller.onCancel = () async {
        await localSubscription.cancel();
      };
    });
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
      final nextId = normalizedId ?? await _nextBookingId();
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
      final saved = booking.copyWith(
        id: nextId,
        createdAt: booking.createdAt ?? now,
        billingStatus: _normalizedBillingStatus(booking.billingStatus),
        statusOutputs: persistedStatusOutputs,
        updatedAt: now,
        localSyncStatus: currentNetworkStatus() ? null : 'queued',
      );
      final document = _toFirestoreMap(saved);
      final cacheDocument = _toCacheDocument(saved);
      final baseUpdatedAtIso = existingBookingData?['updated_at']?.toString();
      if (currentNetworkStatus()) {
        await _writeBookingOnline(nextId, document);
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentUpsert(
          collectionKey: _bookingsResourceKey,
          documentId: nextId,
          document: document,
          baseUpdatedAt: baseUpdatedAtIso,
        );
      }
      await _cache.upsertDocument(
        resourceKey: _bookingsResourceKey,
        document: cacheDocument,
      );
      _upsertMemoryBooking(saved);
      _bookingCacheUpdates.add(null);
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
          ? const Duration(seconds: 2)
          : const Duration(seconds: 6);
      final snapshot = await _bookingsCollection.doc(bookingId).get().timeout(
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
        const Duration(seconds: 12),
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
    final restSuccessCount = restResult ? normalizedStatusesByBookingId.length : 0;
    if (restSuccessCount == normalizedStatusesByBookingId.length) {
      return;
    }

    Object? lastError;
    var successCount = 0;
    for (final entry in normalizedStatusesByBookingId.entries) {
      try {
        await _bookingsCollection.doc(entry.key).set({
          'billing_status': entry.value,
          'updated_at': nowIso,
        }, SetOptions(merge: true)).timeout(
          const Duration(seconds: 8),
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
      final restOnlySucceeded = await _writeBillingStatusesViaRest(
        {bookingId: billingStatus},
        nowIso: nowIso,
      );
      if (restOnlySucceeded) {
        return;
      }
    }
    try {
      await _bookingsCollection.doc(bookingId).set({
        'billing_status': billingStatus,
        'updated_at': nowIso,
      }, SetOptions(merge: true)).timeout(
        const Duration(seconds: 12),
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
          fields: {
            'billing_status': billingStatus,
            'updated_at': nowIso,
          },
          updateMaskFieldPaths: const ['billing_status', 'updated_at'],
        )
        .timeout(
          const Duration(seconds: 8),
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
                const Duration(seconds: 4),
                onTimeout: () => throw TimeoutException(
                  'billing rest patch timeout for ${entry.key}',
                ),
              );
          if (!success) {
            throw Exception('billing rest patch returned false for ${entry.key}');
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
    if (kIsWeb) {
      try {
        final patched = await _firestorePublicDocumentFetcher
            .patchDocument(
              'bookings/$bookingId',
              fields: document,
              updateMaskFieldPaths: document.keys.toList(growable: false),
            )
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw TimeoutException(
                'booking remote rest patch timeout for $bookingId',
              ),
            );
        if (patched) {
          return;
        }
      } catch (error) {
        // Fall through to the SDK write path below.
      }
    }

    try {
      await _bookingsCollection.doc(bookingId).set(document).timeout(
        _remoteSaveTimeout,
        onTimeout: () => throw TimeoutException(
          'booking remote write timeout for $bookingId',
        ),
      );
      return;
    } catch (error) {
      if (!kIsWeb) {
        rethrow;
      }
    }

    final patched = await _firestorePublicDocumentFetcher
        .patchDocument(
          'bookings/$bookingId',
          fields: document,
          updateMaskFieldPaths: document.keys.toList(growable: false),
        )
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw TimeoutException(
            'booking remote rest patch timeout for $bookingId',
          ),
        );
    if (!patched) {
      throw Exception('booking remote rest patch returned false for $bookingId');
    }
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
    final cachedUserDocuments =
        await _cache.readDocuments('users') ?? const <Map<String, dynamic>>[];
    final cachedMakeDocuments =
        await _cache.readDocuments('vehicle_makes') ??
        const <Map<String, dynamic>>[];
    final cachedTypeDocuments =
        await _cache.readDocuments('vehicle_types') ??
        const <Map<String, dynamic>>[];

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
          document['id']!.toString().trim(): Map<String, dynamic>.from(document),
    };
    final makeById = <String, VehicleMake>{
      for (final document in cachedMakeDocuments)
        if ((document['id']?.toString().trim() ?? '').isNotEmpty)
          document['id']!.toString().trim(): VehicleMake.fromMap({
            ...document,
            if (document['type'] == null)
              'type': typeById[document['type_id']?.toString().trim()],
            if (document['driver'] == null)
              'driver': userById[document['driver_id']?.toString().trim()]?.toMap(),
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
    return bookings;
  }

  Future<void> _refreshBookingsCacheInBackground() async {
    try {
      List<Map<String, dynamic>> documents;
      try {
        final snapshot = await _bookingsCollection.get().timeout(
          _startupTimeout,
          onTimeout: () => throw TimeoutException('bookings refresh timeout'),
        );
        documents = snapshot.docs.map(documentData).toList(growable: false);
      } catch (_) {
        documents = await _fetchCollectionDocumentsViaPublicRest('bookings');
      }
      await _cache.writeDocuments(
        resourceKey: _bookingsResourceKey,
        documents: documents,
      );
      await _primeMemoryBookingsFromCache();
      _bookingCacheUpdates.add(null);
    } catch (_) {
      // Background refresh failures should not block cached booking reads.
    }
  }

  Future<List<Booking>> _cacheInflatedBookings(
    List<Map<String, dynamic>> visibleDocuments,
  ) async {
    final bookings = await _inflateBookings(visibleDocuments);
    _memoryBookings = List<Booking>.from(bookings);
    _hasResolvedBookings = true;
    return bookings;
  }

  Future<void> _primeMemoryBookingsFromCache() async {
    final cachedDocuments = await _cache.readDocuments(_bookingsResourceKey);
    if (cachedDocuments == null) {
      _memoryBookings = const [];
      _hasResolvedBookings = true;
      return;
    }
    if (cachedDocuments.isEmpty) {
      _memoryBookings = const [];
      _hasResolvedBookings = true;
      return;
    }
    final queuedDocuments = await _readQueuedBookingDocumentsSafe();
    final visibleDocuments = _mergeQueuedPendingBookingDocuments(
      existingDocuments: cachedDocuments,
      queuedDocuments: queuedDocuments,
    );
    await _cacheInflatedBookings(visibleDocuments);
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
      return await _offlineMutationQueueService
          .readQueuedCollectionDocuments(collectionKey: _bookingsResourceKey)
          .timeout(_queuedReadTimeout, onTimeout: () {
            return const <Map<String, dynamic>>[];
          });
    } catch (error) {
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
      'status_outputs': booking.statusOutputs,
      'created_at': booking.createdAt?.toIso8601String(),
      'updated_at': booking.updatedAt?.toIso8601String(),
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
      statusOutputs: map['status_outputs'] is Map
          ? Map<String, dynamic>.from(map['status_outputs'] as Map)
          : null,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
      localSyncStatus: map['local_sync_status']?.toString(),
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
      if (kIsWeb) {
        final remoteDocuments = await _fetchCollectionDocumentsViaPublicRest(
          'bookings',
        ).timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw TimeoutException('booking next-id rest timeout'),
        );
        remoteHighest = remoteDocuments
            .map((doc) => int.tryParse(doc['id']?.toString() ?? ''))
            .whereType<int>()
            .fold<int>(0, (max, value) => value > max ? value : max);
      } else {
        final snapshot = await _bookingsCollection.get().timeout(
          const Duration(seconds: 8),
          onTimeout: () => throw TimeoutException('booking next-id sdk timeout'),
        );
        remoteHighest = snapshot.docs
            .map((doc) => int.tryParse(documentData(doc)['id']?.toString() ?? ''))
            .whereType<int>()
            .fold<int>(0, (max, value) => value > max ? value : max);
      }
    } catch (error) {
      // Keep the cached highest id when remote lookup is unavailable.
    }
    final highest = remoteHighest > cachedHighest ? remoteHighest : cachedHighest;
    return '${highest + 1}';
  }

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

  Future<List<Map<String, dynamic>>> _fetchCollectionDocumentsViaPublicRest(
    String collectionPath,
  ) async {
    return _firestorePublicDocumentFetcher.fetchCollectionDocuments(
      collectionPath,
    );
  }

  Future<List<Map<String, dynamic>>> _readCollectionSdkCacheOnly(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    try {
      final snapshot = await collection
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 1));
      return snapshot.docs.map(documentData).toList(growable: false);
    } catch (_) {
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
}
