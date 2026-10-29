import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:webapp/services/docx_pdf_preview_service.dart';
import 'package:webapp/services/dashboard_export_document_session.dart';
import 'package:webapp/services/dashboard_docx_export_service.dart';
import 'support/dashboard_export_payload.dart';

void main() {
  test(
    'conversion sends the exact DOCX bytes and accepts only PDF output',
    () async {
      final docx = Uint8List.fromList([80, 75, 3, 4, 1, 2, 3]);
      final pdf = utf8.encode('%PDF-1.7\ntest');
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.bodyBytes, docx);
        expect(
          request.headers['Content-Type'],
          contains('wordprocessingml.document'),
        );
        return http.Response.bytes(
          pdf,
          200,
          headers: {'content-type': 'application/pdf'},
        );
      });
      final service = DocxPdfPreviewService(
        endpoint: Uri.parse('https://preview.example/convert'),
        client: client,
      );
      addTearDown(service.close);
      expect(await service.convert(docx), pdf);
    },
  );

  for (final status in [413, 429, 503, 422]) {
    test('HTTP $status produces a retryable or actionable error', () async {
      final service = DocxPdfPreviewService(
        endpoint: Uri.parse('https://preview.example/convert'),
        client: MockClient(
          (_) async => http.Response('conversion failed', status),
        ),
      );
      addTearDown(service.close);
      await expectLater(
        service.convert(Uint8List.fromList([80, 75, 3, 4])),
        throwsA(isA<PdfPreviewException>()),
      );
    });
  }

  test('HTML responses are rejected instead of shown as PDF', () async {
    final service = DocxPdfPreviewService(
      endpoint: Uri.parse('https://preview.example/convert'),
      client: MockClient(
        (_) async => http.Response('<html>Not found</html>', 200),
      ),
    );
    addTearDown(service.close);
    await expectLater(
      service.convert(Uint8List.fromList([80, 75, 3, 4])),
      throwsA(isA<PdfPreviewException>()),
    );
  });

  test(
    'preview and export share bytes, while changed document inputs regenerate',
    () async {
      var builds = 0;
      final documents = DashboardExportDocumentSession(
        buildDocument: (_) async => Uint8List.fromList([++builds]),
      );
      final payload = dashboardExportTestPayload(
        DashboardExportDocumentType.bsRegular,
      );
      final preview = await documents.docxFor(payload);
      final download = await documents.docxFor(
        dashboardExportTestPayload(DashboardExportDocumentType.bsRegular),
      );
      expect(download, same(preview));
      expect(builds, 1);
      final changed = DashboardDocxExportPayload(
        config: payload.config,
        rows: payload.rows,
        totalAmount: '9,999',
      );
      expect(await documents.docxFor(changed), isNot(same(preview)));
      expect(builds, 2);
    },
  );

  test('failed generation can be retried', () async {
    var builds = 0;
    final documents = DashboardExportDocumentSession(
      buildDocument: (_) async {
        if (++builds == 1) throw StateError('build failed');
        return Uint8List.fromList([80, 75, 3, 4]);
      },
    );
    final payload = dashboardExportTestPayload(
      DashboardExportDocumentType.bsRegular,
    );
    await expectLater(documents.docxFor(payload), throwsStateError);
    expect(await documents.docxFor(payload), [80, 75, 3, 4]);
    expect(builds, 2);
  });
}
