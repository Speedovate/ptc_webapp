import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'export_file_service.dart';
import 'export_file_service_shared.dart';

Future<ExportFileResult> exportFiles(
  BuildContext context, {
  required String bundleFileName,
  required Map<String, Uint8List> files,
}) async {
  if (files.isEmpty) {
    throw StateError('There are no files available to export.');
  }

  final isMobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final box = context.findRenderObject() as RenderBox?;
  final shareOrigin = box == null
      ? null
      : box.localToGlobal(Offset.zero) & box.size;

  if (isMobile) {
    return _shareFiles(
      shareOrigin: shareOrigin,
      bundleFileName: bundleFileName,
      files: files,
    );
  }

  return _saveFilesToDownloads(
    bundleFileName: bundleFileName,
    files: files,
  );
}

Future<ExportFileResult> _shareFiles(
  {
  required Rect? shareOrigin,
  required String bundleFileName,
  required Map<String, Uint8List> files,
}) async {
  final tempDirectory = await getTemporaryDirectory();
  final exportedFiles = <XFile>[];

  if (files.length == 1) {
    final entry = files.entries.first;
    final file = await _writeBytesToFile(
      directory: tempDirectory,
      fileName: entry.key,
      bytes: entry.value,
    );
    exportedFiles.add(XFile(file.path));
  } else {
    final zipFile = await _writeBytesToFile(
      directory: tempDirectory,
      fileName: bundleFileName,
      bytes: buildExportZipBytes(files),
    );
    exportedFiles.add(XFile(zipFile.path));
  }

  await Share.shareXFiles(
    exportedFiles,
    subject: 'Paltranco Export',
    text: 'Paltranco Export',
    sharePositionOrigin: shareOrigin,
  );

  return ExportFileResult(
    message: files.length == 1
        ? 'Your document is ready to save or share.'
        : '${files.length} documents are ready to save or share as a ZIP file.',
    usedShareSheet: true,
  );
}

Future<ExportFileResult> _saveFilesToDownloads({
  required String bundleFileName,
  required Map<String, Uint8List> files,
}) async {
  final downloadsDirectory =
      await getDownloadsDirectory() ??
      await getApplicationDocumentsDirectory();

  if (files.length == 1) {
    final entry = files.entries.first;
    final file = await _writeBytesToFile(
      directory: downloadsDirectory,
      fileName: entry.key,
      bytes: entry.value,
    );
    return ExportFileResult(
      message: 'Your document has been saved.',
      savedPath: file.path,
    );
  }

  final zipFile = await _writeBytesToFile(
    directory: downloadsDirectory,
    fileName: bundleFileName,
    bytes: buildExportZipBytes(files),
  );
  return ExportFileResult(
    message: '${files.length} documents have been saved as a ZIP file.',
    savedPath: zipFile.path,
  );
}

Future<File> _writeBytesToFile({
  required Directory directory,
  required String fileName,
  required Uint8List bytes,
}) async {
  final sanitizedName = _sanitizeFileName(fileName);
  final file = await _resolveUniqueFile(directory, sanitizedName);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<File> _resolveUniqueFile(Directory directory, String fileName) async {
  final dotIndex = fileName.lastIndexOf('.');
  final hasExtension = dotIndex > 0;
  final baseName = hasExtension ? fileName.substring(0, dotIndex) : fileName;
  final extension = hasExtension ? fileName.substring(dotIndex) : '';

  var candidate = File('${directory.path}/$fileName');
  var counter = 1;
  while (await candidate.exists()) {
    candidate = File('${directory.path}/$baseName ($counter)$extension');
    counter += 1;
  }
  return candidate;
}

String _sanitizeFileName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*]+'), '-').trim();
  return sanitized.isEmpty ? 'export' : sanitized;
}
