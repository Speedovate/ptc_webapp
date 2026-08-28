import 'dart:typed_data';

import 'auth_image_picker_service_stub.dart'
    if (dart.library.html) 'auth_image_picker_service_web.dart' as impl;

enum AuthImagePickSource { camera, gallery }

class AuthPickedImage {
  const AuthPickedImage({
    required this.bytes,
    required this.fileName,
    required this.size,
    this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final int size;
  final String? mimeType;
}

Future<AuthPickedImage?> pickAuthImage(AuthImagePickSource source) {
  return impl.pickAuthImage(source);
}
