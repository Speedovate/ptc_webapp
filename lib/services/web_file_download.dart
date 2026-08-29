// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';

Future<void> downloadTextDocument({
  required String fileName,
  required String content,
  String mimeType = 'application/msword;charset=utf-8',
}) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob(<dynamic>[bytes], mimeType);
  await _downloadBlob(fileName: fileName, blob: blob);
}

Future<void> downloadBytes({
  required String fileName,
  required Uint8List bytes,
  String mimeType =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
}) async {
  final blob = html.Blob(<dynamic>[bytes], mimeType);
  await _downloadBlob(fileName: fileName, blob: blob);
}

Future<void> downloadZip({
  required String fileName,
  required Map<String, Uint8List> files,
}) async {
  final archive = Archive();
  files.forEach((entryName, bytes) {
    archive.add(ArchiveFile.bytes(entryName, bytes));
  });
  final zippedBytes = Uint8List.fromList(ZipEncoder().encode(archive));
  final blob = html.Blob(<dynamic>[zippedBytes], 'application/zip');
  await _downloadBlob(fileName: fileName, blob: blob);
}

Future<void> _downloadBlob({
  required String fileName,
  required html.Blob blob,
}) async {
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  anchor.remove();
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  html.Url.revokeObjectUrl(url);
}
