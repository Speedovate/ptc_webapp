import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'dart:typed_data';
import 'package:webapp/widgets/shared/pdf_document_view.dart';
import 'package:webapp/services/dashboard_export_document_session.dart';
import 'package:webapp/services/docx_pdf_preview_service.dart';
import 'support/dashboard_export_payload.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/dashboard_docx_export_service.dart';
import 'package:webapp/widgets/shared/dashboard_export_preview.dart';

void main() {
  testWidgets(
    'conversion failure can retry without changing the Word download',
    (tester) async {
      var attempts = 0;
      final converted = <Uint8List>[];
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardExportPreview(
            payloads: [
              dashboardExportTestPayload(DashboardExportDocumentType.bsRegular),
            ],
            convertToPdf: (bytes) async {
              converted.add(bytes);
              if (++attempts == 1) {
                throw const PdfPreviewException('Converter busy');
              }
              return Uint8List.fromList(utf8.encode('%PDF-1.7\npreview'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Converter busy'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfDocumentView), findsOneWidget);
      expect(converted.first, same(converted.last));
    },
  );
  for (final width in [400.0, 1200.0]) {
    testWidgets('preview reviews and switches documents at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final converted = <Uint8List>[];
      final session = DashboardExportDocumentSession();
      final pdf = Uint8List.fromList(utf8.encode('%PDF-1.7\npreview'));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => DashboardExportPreview(
                    documents: session,
                    convertToPdf: (bytes) async {
                      converted.add(bytes);
                      return pdf;
                    },
                    payloads: [
                      dashboardExportTestPayload(
                        DashboardExportDocumentType.bsRegular,
                      ),
                      dashboardExportTestPayload(
                        DashboardExportDocumentType.btHustling,
                      ),
                    ],
                  ),
                ),
                child: const Text('Open preview'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open preview'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final statement = tester.widget<PdfDocumentView>(
        find.byType(PdfDocumentView),
      );
      expect(
        tester.getSize(find.byType(PdfDocumentView)).height,
        greaterThan(900 * 0.85),
        reason: 'The PDF should occupy most of the available screen height',
      );
      expect(statement.bytes, same(pdf));
      expect(converted, hasLength(1));
      final downloadBytes = await session.docxFor(
        dashboardExportTestPayload(DashboardExportDocumentType.bsRegular),
      );
      expect(downloadBytes, same(converted.single));
      String documentText(Uint8List bytes) {
        final archive = ZipDecoder().decodeBytes(bytes);
        final xml = XmlDocument.parse(
          utf8.decode(archive.findFile('word/document.xml')!.content),
        );
        return xml
            .findAllElements('w:t')
            .map((node) => node.innerText)
            .join(' ');
      }

      final statementText = documentText(converted.single);
      expect(statementText, contains('MORETA SHIPPING LINES'));
      expect(statementText, contains('ADRYC CATAPANG'));
      expect(
        statementText,
        contains('SUB-CLIENT (BAGONG PAG-ASA - SAN MANUEL)'),
      );
      expect(statementText, contains('4,100'));
      expect(statementText, contains('123456'));
      expect(statementText, contains('Amelita Jara'));

      await tester.tap(find.text('BT Hustling'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(PdfDocumentView), findsOneWidget);
      expect(converted, hasLength(2));
      final transmittalText = documentText(converted.last);
      expect(transmittalText, contains('BILLING TRANSMITTAL'));
      expect(transmittalText, contains('Hustling Trip'));
      expect(transmittalText, contains('4,100'));
      expect(transmittalText, isNot(contains('ADRYC CATAPANG')));
      expect(transmittalText, contains('DATE COVERED'));

      await tester.tap(find.text('BS Regular'));
      await tester.pumpAndSettle();
      expect(
        converted,
        hasLength(2),
        reason: 'Switching back reuses the converted PDF',
      );
      await tester.tap(find.byTooltip('Back to export'));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardExportPreview), findsNothing);
      expect(find.text('Open preview'), findsOneWidget);
    });
  }
}
