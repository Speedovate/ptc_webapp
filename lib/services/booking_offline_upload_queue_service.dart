import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/repositories/local/booking_storage_backend.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/utils/functions.dart';

class BookingOfflineUploadQueueService {
  BookingOfflineUploadQueueService({
    BookingStorageBackend? backend,
    FirebaseFirestore? firestore,
    PhotoStorageService? photoStorageService,
  }) : _backend = backend ?? createBookingStorageBackend(),
       _firestore = firestore ?? FirebaseFirestore.instance,
       _photoStorageService = photoStorageService ?? PhotoStorageService.instance;

  static final BookingOfflineUploadQueueService instance =
      BookingOfflineUploadQueueService();

  static const _storageKey = 'booking_pending_upload_queue_v1';
  static const _retryInterval = Duration(seconds: 20);

  final BookingStorageBackend _backend;
  final FirebaseFirestore _firestore;
  final PhotoStorageService _photoStorageService;

  bool _isInitialized = false;
  bool _isFlushing = false;
  Timer? _retryTimer;

  CollectionReference<Map<String, dynamic>> get _bookingsCollection =>
      _firestore.collection('bookings');

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    await _backend.initialize();
    _retryTimer ??= Timer.periodic(_retryInterval, (_) {
      unawaited(flushPendingUploads());
    });
    _isInitialized = true;
    unawaited(flushPendingUploads());
  }

  Future<Map<String, dynamic>> enqueueBookingPhoto({
    required String bookingId,
    required String statusKey,
    required String fieldKey,
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    await initialize();

    final entry = _PendingBookingUploadEntry(
      id: _nextEntryId(),
      bookingId: bookingId,
      statusKey: statusKey,
      fieldKey: fieldKey,
      bytesBase64: base64Encode(bytes),
      fileName: fileName,
      mimeType: mimeType,
      size: size ?? bytes.length,
      createdAtIso: DateTime.now().toUtc().toIso8601String(),
      retryCount: 0,
      lastError: null,
    );

    final entries = await _readEntries();
    entries.add(entry);
    await _writeEntries(entries);
    unawaited(flushPendingUploads());

    return {
      'name': fileName,
      'mime_type': mimeType,
      'size': size ?? bytes.length,
      'pending_upload': true,
      'pending_upload_id': entry.id,
    };
  }

  Future<void> flushPendingUploads() async {
    await initialize();
    if (_isFlushing) {
      return;
    }

    _isFlushing = true;
    try {
      var entries = await _readEntries();
      if (entries.isEmpty) {
        return;
      }

      var mutated = false;
      final remaining = <_PendingBookingUploadEntry>[];

      for (final entry in entries) {
        try {
          final upload = await _photoStorageService.uploadBookingPhoto(
            bytes: base64Decode(entry.bytesBase64),
            bookingId: entry.bookingId,
            statusKey: entry.statusKey,
            fieldKey: entry.fieldKey,
            fileName: entry.fileName,
            mimeType: entry.mimeType,
            size: entry.size,
          );

          final applied = await _applyUploadedPhoto(
            entry: entry,
            uploadedValue: upload,
          );

          if (!applied) {
            await _photoStorageService.deleteByPath(
              upload['storage_path']?.toString(),
            );
          }

          mutated = true;
        } catch (error) {
          final normalizedError = normalizeUserErrorText(
            error.toString(),
            fallback: 'Something went wrong. Please try again.',
          );

          if (_isRetryableUploadError(normalizedError)) {
            remaining.add(
              entry.copyWith(
                retryCount: entry.retryCount + 1,
                lastError: normalizedError,
              ),
            );
          } else {
            final shouldKeep = await _shouldKeepEntryAfterFailure(entry);
            if (shouldKeep) {
              remaining.add(
                entry.copyWith(
                  retryCount: entry.retryCount + 1,
                  lastError: normalizedError,
                ),
              );
            } else {
              mutated = true;
            }
          }
        }
      }

      if (mutated || remaining.length != entries.length) {
        await _writeEntries(remaining);
      }
    } finally {
      _isFlushing = false;
    }
  }

  Future<bool> _applyUploadedPhoto({
    required _PendingBookingUploadEntry entry,
    required Map<String, dynamic> uploadedValue,
  }) async {
    final documentRef = _bookingsCollection.doc(entry.bookingId);
    var applied = false;

    await _firestore.runTransaction((transaction) async {
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      applied = true;
    });

    return applied;
  }

  Future<bool> _shouldKeepEntryAfterFailure(
    _PendingBookingUploadEntry entry,
  ) async {
    try {
      final snapshot = await _bookingsCollection.doc(entry.bookingId).get();
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

  Future<List<_PendingBookingUploadEntry>> _readEntries() async {
    final rawEntries = await _backend.readStringList(_storageKey);
    return rawEntries
        .map((entry) => jsonDecode(entry) as Map<String, dynamic>)
        .map(_PendingBookingUploadEntry.fromMap)
        .toList();
  }

  Future<void> _writeEntries(List<_PendingBookingUploadEntry> entries) {
    return _backend.writeStringList(
      _storageKey,
      entries.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }

  Map<String, dynamic>? _statusOutputsFromBooking(Map<String, dynamic> booking) {
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
    final randomSuffix = Random().nextInt(1 << 32).toRadixString(16);
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

  _PendingBookingUploadEntry copyWith({
    int? retryCount,
    String? lastError,
  }) {
    return _PendingBookingUploadEntry(
      id: id,
      bookingId: bookingId,
      statusKey: statusKey,
      fieldKey: fieldKey,
      bytesBase64: bytesBase64,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
      createdAtIso: createdAtIso,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
    };
  }

  factory _PendingBookingUploadEntry.fromMap(Map<String, dynamic> map) {
    return _PendingBookingUploadEntry(
      id: map['id']?.toString() ?? '',
      bookingId: map['booking_id']?.toString() ?? '',
      statusKey: map['status_key']?.toString() ?? '',
      fieldKey: map['field_key']?.toString() ?? '',
      bytesBase64: map['bytes_base64']?.toString() ?? '',
      fileName: map['file_name']?.toString() ?? 'photo',
      mimeType: map['mime_type']?.toString(),
      size: map['size'] is num ? (map['size'] as num).toInt() : int.tryParse(map['size']?.toString() ?? ''),
      createdAtIso: map['created_at']?.toString() ?? '',
      retryCount: map['retry_count'] is num
          ? (map['retry_count'] as num).toInt()
          : int.tryParse(map['retry_count']?.toString() ?? '') ?? 0,
      lastError: map['last_error']?.toString(),
    );
  }
}
