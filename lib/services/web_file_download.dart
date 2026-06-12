// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;

import 'package:archive/archive.dart';

void downloadTextDocument({
  required String fileName,
  required String content,
  String mimeType = 'application/msword;charset=utf-8',
}) {
  final bytes = utf8.encode(content);
  final blob = html.Blob(<dynamic>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

void downloadBytes({
  required String fileName,
  required Uint8List bytes,
  String mimeType =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
}) {
  final blob = html.Blob(<dynamic>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

void downloadZip({
  required String fileName,
  required Map<String, Uint8List> files,
}) {
  final archive = Archive();
  files.forEach((entryName, bytes) {
    archive.add(ArchiveFile.bytes(entryName, bytes));
  });
  final zippedBytes = Uint8List.fromList(ZipEncoder().encode(archive));
  final blob = html.Blob(<dynamic>[zippedBytes], 'application/zip');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
