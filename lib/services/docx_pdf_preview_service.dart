import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class PdfPreviewException implements Exception {
  const PdfPreviewException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DocxPdfPreviewService {
  DocxPdfPreviewService({Uri? endpoint, http.Client? client})
    : _endpoint = endpoint ?? _configuredEndpoint(),
      _client = client ?? http.Client();

  final Uri? _endpoint;
  final http.Client _client;
  static const maxDocxBytes = 20 * 1024 * 1024;
  static const maxPdfBytes = 32 * 1024 * 1024;

  static Uri? _configuredEndpoint() {
    const endpoint = String.fromEnvironment('DOCX_PREVIEW_ENDPOINT');
    if (endpoint.isNotEmpty) return Uri.tryParse(endpoint);
    if (kDebugMode && {'localhost', '127.0.0.1'}.contains(Uri.base.host)) {
      return Uri.parse('http://127.0.0.1:8784/convert');
    }
    return null;
  }

  Future<Uint8List> convert(Uint8List docx) async {
    final endpoint = _endpoint;
    if (endpoint == null ||
        !endpoint.hasAuthority ||
        !['http', 'https'].contains(endpoint.scheme)) {
      throw const PdfPreviewException(
        'PDF preview is not configured yet. You can still download the editable Word file.',
      );
    }
    if (docx.isEmpty || docx.length > maxDocxBytes) {
      throw const PdfPreviewException(
        'This document is too large for PDF preview. Download the Word file instead.',
      );
    }
    http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'Content-Type':
                  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
              'Accept': 'application/pdf',
            },
            body: docx,
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const PdfPreviewException(
        'PDF conversion timed out. Please try again.',
      );
    } on http.ClientException {
      throw const PdfPreviewException(
        'Cannot reach the PDF preview service. Check your connection and try again.',
      );
    }
    if (response.statusCode == 429 || response.statusCode == 503) {
      throw const PdfPreviewException(
        'PDF conversion is busy or temporarily unavailable. Please try again shortly.',
      );
    }
    if (response.statusCode == 413) {
      throw const PdfPreviewException(
        'This document is too large for PDF preview. Download the Word file instead.',
      );
    }
    if (response.statusCode != 200) {
      throw const PdfPreviewException(
        'Could not convert the Word document to PDF. You can still download the editable Word file.',
      );
    }
    final pdf = response.bodyBytes;
    if (pdf.length < 5 ||
        pdf.length > maxPdfBytes ||
        String.fromCharCodes(pdf.take(5)) != '%PDF-') {
      throw const PdfPreviewException(
        'The preview service did not return a valid PDF. Please try again.',
      );
    }
    return pdf;
  }

  void close() => _client.close();
}
