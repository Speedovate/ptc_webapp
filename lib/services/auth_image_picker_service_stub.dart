import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'auth_image_picker_service.dart';

Future<AuthPickedImage?> pickAuthImage(AuthImagePickSource source) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  final file = result?.files.singleOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null) {
    return null;
  }
  return AuthPickedImage(
    bytes: Uint8List.fromList(bytes),
    fileName: file.name,
    size: file.size,
    mimeType: file.extension == null ? null : _mimeTypeFromExtension(file.extension!),
  );
}

String _mimeTypeFromExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    default:
      return 'image/jpeg';
  }
}
