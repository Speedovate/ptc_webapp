import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/booking.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/booking_repository.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/utils/functions.dart';

class BookingRequest implements BookingRepository {
  BookingRequest({
    FirebaseFirestore? firestore,
    AuthRequest? authRequest,
    VehicleRequest? vehicleRequest,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _authRequest = authRequest ?? AuthRequest.instance,
       _vehicleRequest = vehicleRequest ?? VehicleRequest.instance;

  static final BookingRequest instance = BookingRequest();
  static const _bookingsResourceKey = 'bookings';

  final FirebaseFirestore _firestore;
  final AuthRequest _authRequest;
  final VehicleRequest _vehicleRequest;
  final PhotoStorageService _photoStorageService = PhotoStorageService.instance;
  final BookingOfflineUploadQueueService _offlineUploadQueueService =
      BookingOfflineUploadQueueService.instance;
  final OfflineMutationQueueService _offlineMutationQueueService =
      OfflineMutationQueueService.instance;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );

  CollectionReference<Map<String, dynamic>> get _bookingsCollection =>
      _firestore.collection('bookings');

  @override
  Future<void> initialize() async {
    await _offlineUploadQueueService.initialize();
  }

  @override
  Future<List<Booking>> getBookings() async {
    return _runRequest(() async {
      final documents = await _cache.getDocuments(
        resourceKey: _bookingsResourceKey,
        fetchDocuments: () async {
          final snapshot = await _bookingsCollection.get();
          return snapshot.docs.map(documentData).toList();
        },
      );
      return _inflateBookings(documents);
    }, fallback: 'We could not load the bookings right now.');
  }

  @override
  Stream<List<Booking>> watchBookings() {
    return _bookingsCollection.snapshots().asyncMap((snapshot) async {
      final documents = snapshot.docs.map(documentData).toList();
      await _cache.writeDocuments(
        resourceKey: _bookingsResourceKey,
        documents: documents,
      );
      return _inflateBookings(documents);
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
      final nextId = normalizedId ?? await _nextBookingId();
      final existingBookingData = await _getExistingBookingData(nextId);
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
      );
      final document = _toFirestoreMap(saved);
      await _bookingsCollection.doc(nextId).set(document);
      await _cache.upsertDocument(
        resourceKey: _bookingsResourceKey,
        document: document,
      );
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
      final existingBookingData = await _getExistingBookingData(normalizedId);
      final normalizedBillingStatus = _normalizedBillingStatus(billingStatus);
      if (currentNetworkStatus()) {
        await _bookingsCollection.doc(normalizedId).update({
          'billing_status': normalizedBillingStatus,
        });
      } else {
        await _offlineMutationQueueService.queueBookingBillingStatusUpdate(
          bookingId: normalizedId,
          billingStatus: normalizedBillingStatus,
          baseUpdatedAt: existingBookingData?['updated_at']?.toString(),
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
      }
      final bookings = await getBookings();
      final updated = bookings
          .where((booking) => booking.id == normalizedId)
          .firstOrNull;
      if (updated != null) {
        return updated;
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
      final batch = _firestore.batch();
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
        await _offlineMutationQueueService.queueBookingBillingStatusUpdates(
          normalizedStatusesByBookingId,
          baseUpdatedAtByBookingId: {
            for (final document
                in cachedDocuments ?? const <Map<String, dynamic>>[])
              if (normalizeId(document['id']?.toString()) != null)
                normalizeId(document['id']?.toString())!: document['updated_at']
                    ?.toString(),
          },
        );
      } else {
        for (final entry in normalizedStatusesByBookingId.entries) {
          batch.update(_bookingsCollection.doc(entry.key), {
            'billing_status': entry.value,
          });
        }
        await batch.commit();
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
    }, fallback: 'We could not update the billing statuses right now.');
  }

  Future<Map<String, dynamic>?> _getExistingBookingData(
    String bookingId,
  ) async {
    final snapshot = await _bookingsCollection.doc(bookingId).get();
    if (!snapshot.exists) {
      return null;
    }
    return documentData(snapshot);
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
    try {
      return await _photoStorageService.uploadBookingPhoto(
        bytes: bytes,
        bookingId: bookingId,
        statusKey: statusKey.trim(),
        fieldKey: fieldKey.trim(),
        fileName: resolvedFileName,
        mimeType: mimeType?.isNotEmpty == true ? mimeType : null,
        size: size,
      );
    } catch (error) {
      final normalizedError = normalizeUserErrorText(
        error.toString(),
        fallback: '',
      ).toLowerCase();
      if (!_isQueueableUploadError(normalizedError)) {
        rethrow;
      }
      return _offlineUploadQueueService.enqueueBookingPhoto(
        bytes: bytes,
        bookingId: bookingId,
        statusKey: statusKey.trim(),
        fieldKey: fieldKey.trim(),
        fileName: resolvedFileName,
        mimeType: mimeType?.isNotEmpty == true ? mimeType : null,
        size: size,
      );
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
    final users = await _authRequest.getUsers();
    final makes = await _vehicleRequest.getMakes();
    await _vehicleRequest.getSizes();
    final userById = {for (final item in users) item.id ?? '': item};
    final makeById = {for (final item in makes) item.id ?? '': item};
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
    final snapshot = await _bookingsCollection.get();
    final highest = snapshot.docs
        .map((doc) => int.tryParse(documentData(doc)['id']?.toString() ?? ''))
        .whereType<int>()
        .fold<int>(0, (max, value) => value > max ? value : max);
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

  int? _toInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  bool _isQueueableUploadError(String normalizedError) {
    return normalizedError.contains('internet connection') ||
        normalizedError.contains('temporarily unavailable') ||
        normalizedError.contains('request took too long');
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
