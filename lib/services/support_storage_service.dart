import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/utils/functions.dart';

class SupportStorageService {
  SupportStorageService({FirebaseStorage? storage})
    : _providedStorage = storage;

  static final SupportStorageService instance = SupportStorageService();

  final FirebaseStorage? _providedStorage;
  FirebaseStorage get _storage => _providedStorage ?? FirebaseStorage.instance;

  Future<SupportAttachment> uploadAttachment({
    required Uint8List bytes,
    required String threadId,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    final normalizedFileName = _sanitizeFileName(fileName);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final objectName = '$timestamp-$normalizedFileName';
    final storagePath = 'support/$threadId/attachments/$objectName';
    final metadata = SettableMetadata(
      contentType: _resolvedMimeType(normalizedFileName, mimeType),
    );
    try {
      final reference = _storage.ref(storagePath);
      await reference.putData(bytes, metadata);
      final downloadUrl = await reference.getDownloadURL();
      return SupportAttachment(
        name: normalizedFileName,
        downloadUrl: downloadUrl,
        storagePath: storagePath,
        mimeType: metadata.contentType,
        size: size ?? bytes.length,
      );
    } on FirebaseException catch (error) {
      throw Exception(
        userFacingErrorMessage(
          error,
          fallback: 'We could not upload the attachment. Please try again.',
        ),
      );
    } catch (error) {
      throw Exception(
        userFacingErrorMessage(
          error,
          fallback: 'We could not upload the attachment. Please try again.',
        ),
      );
    }
  }

  String _sanitizeFileName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'attachment';
    }
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  String _resolvedMimeType(String fileName, String? explicitMimeType) {
    final normalizedExplicit = explicitMimeType?.trim();
    if (normalizedExplicit != null && normalizedExplicit.isNotEmpty) {
      return normalizedExplicit;
    }
    final extension = _fileExtension(fileName);
    return switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => 'application/octet-stream',
    };
  }

  String? _fileExtension(String value) {
    final index = value.lastIndexOf('.');
    if (index < 0 || index == value.length - 1) {
      return null;
    }
    return value.substring(index + 1).toLowerCase();
  }
}
