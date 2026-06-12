import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'export_file_service_stub.dart'
    if (dart.library.html) 'export_file_service_web.dart'
    if (dart.library.io) 'export_file_service_io.dart' as impl;

const String exportDocxMimeType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const String exportZipMimeType = 'application/zip';

class ExportFileResult {
  const ExportFileResult({
    required this.message,
    this.savedPath,
    this.usedShareSheet = false,
  });

  final String message;
  final String? savedPath;
  final bool usedShareSheet;
}

class ExportFilePayload {
  const ExportFilePayload({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
}

class ExportFileService {
  const ExportFileService._();

  static Future<ExportFileResult> export(
    BuildContext context, {
    required String bundleFileName,
    required Map<String, Uint8List> files,
  }) {
    return impl.exportFiles(
      context,
      bundleFileName: bundleFileName,
      files: files,
    );
  }
}
