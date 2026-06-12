import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'export_file_service.dart';
import 'web_file_download.dart';

Future<ExportFileResult> exportFiles(
  BuildContext context, {
  required String bundleFileName,
  required Map<String, Uint8List> files,
}) async {
  if (files.isEmpty) {
    throw StateError('There are no files available to export.');
  }

  if (files.length == 1) {
    final entry = files.entries.first;
    downloadBytes(
      fileName: entry.key,
      bytes: entry.value,
      mimeType: exportDocxMimeType,
    );
    return const ExportFileResult(
      message: 'Your document has been downloaded.',
    );
  }

  downloadZip(
    fileName: bundleFileName,
    files: files,
  );
  return ExportFileResult(
    message: '${files.length} documents have been downloaded as a ZIP file.',
  );
}
