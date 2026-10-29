import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'pdf_document_view_stub.dart'
    if (dart.library.html) 'pdf_document_view_web.dart'
    as impl;

class PdfDocumentView extends StatelessWidget {
  const PdfDocumentView({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) => impl.buildPdfDocumentView(bytes);
}
