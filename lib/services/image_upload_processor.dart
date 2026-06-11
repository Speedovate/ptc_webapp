import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:image/image.dart' as img;

class ProcessedUploadImage {
  const ProcessedUploadImage({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int size;
  final int width;
  final int height;
}

class ImageUploadProcessor {
  ImageUploadProcessor._();

  static const int maxLongSide = 1080;
  static const int jpegQuality = 88;

  static final ImageUploadProcessor instance = ImageUploadProcessor._();

  Future<ProcessedUploadImage> prepare({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
  }) async {
    // Let the UI paint the loading overlay before any CPU-heavy processing.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    final task = _ImageUploadTask(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );

    if (kIsWeb) {
      return _prepareUploadImageForWeb(task);
    }

    return compute(_prepareUploadImage, task);
  }
}

class _ImageUploadTask {
  const _ImageUploadTask({
    required this.bytes,
    required this.fileName,
    this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mimeType;
}

ProcessedUploadImage _prepareUploadImage(_ImageUploadTask task) {
  final trimmedFileName = task.fileName.trim();
  final normalizedFileName = trimmedFileName.isEmpty
      ? 'photo.jpg'
      : '${(() {
          final dotIndex = trimmedFileName.lastIndexOf('.');
          final baseName = dotIndex <= 0 ? trimmedFileName : trimmedFileName.substring(0, dotIndex);
          return baseName;
        })()}.jpg';

  final decoded = img.decodeImage(task.bytes);
  if (decoded == null) {
    return ProcessedUploadImage(
      bytes: task.bytes,
      fileName: normalizedFileName,
      mimeType: 'image/jpeg',
      size: task.bytes.length,
      width: 0,
      height: 0,
    );
  }

  final currentLongSide = decoded.width >= decoded.height
      ? decoded.width
      : decoded.height;
  final resized = currentLongSide <= ImageUploadProcessor.maxLongSide
      ? decoded
      : decoded.width >= decoded.height
      ? img.copyResize(decoded, width: ImageUploadProcessor.maxLongSide)
      : img.copyResize(decoded, height: ImageUploadProcessor.maxLongSide);

  final encoded = Uint8List.fromList(
    img.encodeJpg(resized, quality: ImageUploadProcessor.jpegQuality),
  );

  return ProcessedUploadImage(
    bytes: encoded,
    fileName: normalizedFileName,
    mimeType: 'image/jpeg',
    size: encoded.length,
    width: resized.width,
    height: resized.height,
  );
}

Future<ProcessedUploadImage> _prepareUploadImageForWeb(
  _ImageUploadTask task,
) async {
  final trimmedFileName = task.fileName.trim();
  final fallbackFileName = trimmedFileName.isEmpty ? 'photo' : trimmedFileName;

  ui.Codec? codec;
  ui.Image? image;

  try {
    codec = await ui.instantiateImageCodec(task.bytes);
    final frame = await codec.getNextFrame();
    image = frame.image;

    final width = image.width;
    final height = image.height;
    final currentLongSide = width >= height ? width : height;

    if (currentLongSide <= ImageUploadProcessor.maxLongSide) {
      return ProcessedUploadImage(
        bytes: task.bytes,
        fileName: fallbackFileName,
        mimeType: (task.mimeType?.trim().isNotEmpty ?? false)
            ? task.mimeType!.trim()
            : 'image/jpeg',
        size: task.bytes.length,
        width: width,
        height: height,
      );
    }

    final resizeScale = ImageUploadProcessor.maxLongSide / currentLongSide;
    final targetWidth = (width * resizeScale).round().clamp(1, width);
    final targetHeight = (height * resizeScale).round().clamp(1, height);

    image.dispose();
    image = null;
    codec.dispose();
    codec = await ui.instantiateImageCodec(
      task.bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      allowUpscaling: false,
    );
    final resizedFrame = await codec.getNextFrame();
    image = resizedFrame.image;

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final encodedBytes = byteData?.buffer.asUint8List();
    if (encodedBytes == null) {
      return ProcessedUploadImage(
        bytes: task.bytes,
        fileName: fallbackFileName,
        mimeType: (task.mimeType?.trim().isNotEmpty ?? false)
            ? task.mimeType!.trim()
            : 'image/jpeg',
        size: task.bytes.length,
        width: targetWidth,
        height: targetHeight,
      );
    }

    final normalizedBaseName = (() {
      final dotIndex = fallbackFileName.lastIndexOf('.');
      if (dotIndex <= 0) {
        return fallbackFileName;
      }
      return fallbackFileName.substring(0, dotIndex);
    })();

    return ProcessedUploadImage(
      bytes: encodedBytes,
      fileName: '$normalizedBaseName.png',
      mimeType: 'image/png',
      size: encodedBytes.length,
      width: targetWidth,
      height: targetHeight,
    );
  } catch (_) {
    return ProcessedUploadImage(
      bytes: task.bytes,
      fileName: fallbackFileName,
      mimeType: (task.mimeType?.trim().isNotEmpty ?? false)
          ? task.mimeType!.trim()
          : 'image/jpeg',
      size: task.bytes.length,
      width: 0,
      height: 0,
    );
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
