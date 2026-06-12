import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'export_file_service.dart';

Future<ExportFileResult> exportFiles(
  BuildContext context, {
  required String bundleFileName,
  required Map<String, Uint8List> files,
}) async {
  throw UnsupportedError('Export is not available on this platform.');
}
