import 'dart:io';
import 'package:http/io_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/dashboard_docx_export_service.dart';
import 'package:webapp/services/dashboard_export_document_session.dart';
import 'package:webapp/services/docx_pdf_preview_service.dart';
import 'support/dashboard_export_payload.dart';

class _LiveHttpOverrides extends HttpOverrides {}

const _endpoint = String.fromEnvironment('PDF_PREVIEW_TEST_ENDPOINT');
const _artifacts = String.fromEnvironment('PDF_PREVIEW_ARTIFACT_DIR');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final type in DashboardExportDocumentType.values) {
    test(
      'real LibreOffice PDF conversion of ${type.name} preserves DOCX download',
      () async {
        final documents = DashboardExportDocumentSession();
        final converter = DocxPdfPreviewService(
          endpoint: Uri.parse(_endpoint),
          client: IOClient(_LiveHttpOverrides().createHttpClient(null)),
        );
        addTearDown(converter.close);
        final payload = dashboardExportTestPayload(type);
        final original = await documents.docxFor(payload);
        final pdf = await converter.convert(original);
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
        expect(pdf.length, greaterThan(1000));
        expect(await documents.docxFor(payload), same(original));
        expect(original.take(4), [80, 75, 3, 4]);
        if (_artifacts.isNotEmpty) {
          await Directory(_artifacts).create(recursive: true);
          await File('$_artifacts/${type.name}.docx').writeAsBytes(original);
          await File('$_artifacts/${type.name}.pdf').writeAsBytes(pdf);
        }
      },
      skip: _endpoint.isEmpty,
    );
  }
}
