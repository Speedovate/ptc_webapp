// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'auth_image_picker_service.dart';

Future<AuthPickedImage?> pickAuthImage(AuthImagePickSource source) async {
  if (source == AuthImagePickSource.gallery) {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.isEmpty) {
      return null;
    }
    return AuthPickedImage(
      bytes: Uint8List.fromList(bytes),
      fileName: file.name,
      size: file.size,
      mimeType: file.extension == null ? null : _mimeTypeFromExtension(file.extension!),
    );
  }

  final completer = Completer<AuthPickedImage?>();
  final input = html.FileUploadInputElement()
    ..accept = 'image/*';
  input.setAttribute('capture', 'environment');

  input.onChange.first.then((_) {
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return;
    }
    final reader = html.FileReader();
    reader.onLoadEnd.first.then((_) {
      final result = reader.result;
      if (result is! ByteBuffer) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        return;
      }
      final bytes = Uint8List.view(result);
      if (!completer.isCompleted) {
        completer.complete(
          AuthPickedImage(
            bytes: Uint8List.fromList(bytes),
            fileName: file.name,
            size: file.size,
            mimeType: file.type.isNotEmpty ? file.type : null,
          ),
        );
      }
    });
    reader.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });
    reader.readAsArrayBuffer(file);
  });

  input.click();
  return completer.future;
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
