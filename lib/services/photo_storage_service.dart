import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

class PhotoStorageService {
  PhotoStorageService({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  static final PhotoStorageService instance = PhotoStorageService();

  final FirebaseStorage _storage;

  Future<Map<String, dynamic>> uploadBookingPhoto({
    required Uint8List bytes,
    required String bookingId,
    required String statusKey,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    final normalizedFileName = _sanitizeFileName(fileName);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final extension = _fileExtension(normalizedFileName);
    final objectName = extension == null || extension.isEmpty
        ? '$timestamp'
        : '$timestamp.$extension';
    final storagePath =
        'bookings/$bookingId/status_outputs/$statusKey/$fieldKey/$objectName';
    final metadata = SettableMetadata(
      contentType: mimeType?.trim().isNotEmpty == true
          ? mimeType!.trim()
          : _guessMimeType(extension),
    );
    final reference = _storage.ref(storagePath);
    await reference.putData(bytes, metadata);
    final downloadUrl = await reference.getDownloadURL();

    return {
      'name': normalizedFileName,
      'download_url': downloadUrl,
      'storage_path': storagePath,
      'mime_type': metadata.contentType,
      'size': size ?? bytes.length,
    };
  }

  Future<Map<String, dynamic>> uploadUserPhoto({
    required Uint8List bytes,
    required String userId,
    required String fieldKey,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    final normalizedFileName = _sanitizeFileName(fileName);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final extension = _fileExtension(normalizedFileName);
    final objectName = extension == null || extension.isEmpty
        ? '$timestamp'
        : '$timestamp.$extension';
    final storagePath = 'users/$userId/$fieldKey/$objectName';
    final metadata = SettableMetadata(
      contentType: mimeType?.trim().isNotEmpty == true
          ? mimeType!.trim()
          : _guessMimeType(extension),
    );
    final reference = _storage.ref(storagePath);
    await reference.putData(bytes, metadata);
    final downloadUrl = await reference.getDownloadURL();

    return {
      'name': normalizedFileName,
      'download_url': downloadUrl,
      'storage_path': storagePath,
      'mime_type': metadata.contentType,
      'size': size ?? bytes.length,
    };
  }

  Future<void> deleteByPath(String? storagePath) async {
    final normalized = storagePath?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    try {
      await _storage.ref(normalized).delete();
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
