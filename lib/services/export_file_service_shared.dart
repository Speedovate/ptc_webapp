import 'dart:typed_data';

import 'package:archive/archive.dart';

Uint8List buildExportZipBytes(Map<String, Uint8List> files) {
  final archive = Archive();
  files.forEach((entryName, bytes) {
    archive.add(ArchiveFile.bytes(entryName, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
