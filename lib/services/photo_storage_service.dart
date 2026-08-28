import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:webapp/services/image_upload_processor.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/utils/functions.dart';

class PhotoStorageService {
  PhotoStorageService({
    FirebaseStorage? storage,
    OfflineCleanupQueueService? offlineCleanupQueueService,
  }) : _storage = storage ?? FirebaseStorage.instance,
       _offlineCleanupQueueService =
           offlineCleanupQueueService ?? OfflineCleanupQueueService.instance;

  static final PhotoStorageService instance = PhotoStorageService();

  final FirebaseStorage _storage;
  final ImageUploadProcessor _imageUploadProcessor =
      ImageUploadProcessor.instance;
  final OfflineCleanupQueueService _offlineCleanupQueueService;

  Future<Map<String, dynamic>> uploadBookingPhoto({
    required Uint8List bytes,
    required String bookingId,
    required String statusKey,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    if (!currentNetworkStatus()) {
      throw Exception('Please check your internet connection and try again.');
    }
    final processed = await _imageUploadProcessor.prepare(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final normalizedFileName = _sanitizeFileName(processed.fileName);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final extension = _fileExtension(normalizedFileName);
    final objectName = extension == null || extension.isEmpty
        ? '$timestamp'
        : '$timestamp.$extension';
    final storagePath =
        'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/$objectName';
    final metadata = SettableMetadata(
      contentType: processed.mimeType.trim().isNotEmpty
          ? processed.mimeType.trim()
          : _guessMimeType(extension),
    );
    try {
      final reference = _storage.ref(storagePath);
      await reference.putData(processed.bytes, metadata);
      final downloadUrl = await reference.getDownloadURL();
      return {
        'name': normalizedFileName,
        'download_url': downloadUrl,
        'storage_path': storagePath,
        'mime_type': metadata.contentType,
        'size': processed.size,
        'width': processed.width,
        'height': processed.height,
      };
    } on FirebaseException catch (error) {
      final normalizedError = userFacingErrorMessage(
        error,
        fallback: 'We could not upload the photo. Please try again.',
      );
      throw Exception(normalizedError);
    } catch (error) {
      final normalizedError = _normalizedUploadErrorMessage(error);
      throw Exception(normalizedError);
    }
  }

  Future<Map<String, dynamic>> uploadUserPhoto({
    required Uint8List bytes,
    required String userId,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    if (!currentNetworkStatus()) {
      throw Exception('Please check your internet connection and try again.');
    }
    final processed = await _imageUploadProcessor.prepare(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final normalizedFileName = _sanitizeFileName(processed.fileName);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final extension = _fileExtension(normalizedFileName);
    final objectName = extension == null || extension.isEmpty
        ? '$timestamp'
        : '$timestamp.$extension';
    final storagePath = 'users/$userId/$fieldKey/$objectName';
    final metadata = SettableMetadata(
      contentType: processed.mimeType.trim().isNotEmpty
          ? processed.mimeType.trim()
          : _guessMimeType(extension),
    );
    try {
      final reference = _storage.ref(storagePath);
      await reference.putData(processed.bytes, metadata);
      final downloadUrl = await reference.getDownloadURL();
      return {
        'name': normalizedFileName,
        'download_url': downloadUrl,
        'storage_path': storagePath,
        'mime_type': metadata.contentType,
        'size': processed.size,
        'width': processed.width,
        'height': processed.height,
      };
    } on FirebaseException catch (error) {
      final normalizedError = userFacingErrorMessage(
        error,
        fallback: 'We could not upload the photo. Please try again.',
      );
      throw Exception(normalizedError);
    } catch (error) {
      final normalizedError = _normalizedUploadErrorMessage(error);
      throw Exception(normalizedError);
    }
  }

  Future<void> deleteByPath(String? storagePath) async {
    final normalized = storagePath?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    if (!currentNetworkStatus()) {
      await _offlineCleanupQueueService.queueDeleteByPath(normalized);
      return;
    }
    try {
      await _storage.ref(normalized).delete();
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') {
        return;
      }
      final normalizedError = userFacingErrorMessage(
        error,
        fallback: 'We could not delete the photo right now.',
      ).toLowerCase();
      if (_isRetryableCleanupError(normalizedError)) {
        await _offlineCleanupQueueService.queueDeleteByPath(normalized);
        return;
      }
      rethrow;
    } catch (error) {
      final normalizedError = normalizeUserErrorText(
        error.toString(),
        fallback: 'We could not delete the photo right now.',
      ).toLowerCase();
      if (_isRetryableCleanupError(normalizedError)) {
        await _offlineCleanupQueueService.queueDeleteByPath(normalized);
        return;
      }
      rethrow;
    }
  }

  Future<void> deleteUserAssets(String? userId) async {
    final normalizedUserId = userId?.trim();
    if (normalizedUserId == null || normalizedUserId.isEmpty) {
      return;
    }
    final folderPath = 'users/$normalizedUserId';
    if (!currentNetworkStatus()) {
      await _offlineCleanupQueueService.queueDeleteFolder(folderPath);
      return;
    }
    try {
      await _deleteFolderRecursively(folderPath);
    } on FirebaseException catch (error) {
      final normalizedError = userFacingErrorMessage(
        error,
        fallback: 'We could not delete the user assets right now.',
      ).toLowerCase();
      if (_isRetryableCleanupError(normalizedError)) {
        await _offlineCleanupQueueService.queueDeleteFolder(folderPath);
        return;
      }
      rethrow;
    } catch (error) {
      final normalizedError = normalizeUserErrorText(
        error.toString(),
        fallback: 'We could not delete the user assets right now.',
      ).toLowerCase();
      if (_isRetryableCleanupError(normalizedError)) {
        await _offlineCleanupQueueService.queueDeleteFolder(folderPath);
        return;
      }
      rethrow;
    }
  }

  bool _isRetryableCleanupError(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized.contains('internet connection') ||
        normalized.contains('temporarily unavailable') ||
        normalized.contains('request took too long') ||
        normalized.contains('try again');
  }

  String _normalizedUploadErrorMessage(Object error) {
    final raw = error.toString().trim().toLowerCase();
    if (raw.contains('progressevent') ||
        raw.contains('network-request-failed') ||
        raw.contains('network error') ||
        raw.contains('failed to fetch') ||
        raw.contains('xmlhttprequest') ||
        raw.contains('clientexception') ||
        raw.contains('socketexception')) {
      return 'Please check your internet connection and try again.';
    }
    return userFacingErrorMessage(
      error,
      fallback: 'We could not upload the photo. Please try again.',
    );
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

  String _sanitizeFileName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'photo';
    }
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  String? _fileExtension(String value) {
    final index = value.lastIndexOf('.');
    if (index < 0 || index == value.length - 1) {
      return null;
    }
    return value.substring(index + 1).toLowerCase();
  }

  String _guessMimeType(String? extension) {
    return switch (extension?.toLowerCase()) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      _ => 'image/jpeg',
    };
  }
}
