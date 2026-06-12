import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/dashboard_export_naming.dart';
import 'package:webapp/services/dashboard_docx_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DashboardDocxExportService', () {
    for (final type in DashboardExportDocumentType.values) {
      test('builds ${type.name} template', () async {
        final payload = DashboardDocxExportPayload(
          config: DashboardExportConfig(
            type: type,
            documentDate: DateTime(2026, 5, 18),
            coveredStartDate: DateTime(2026, 5, 9),
            coveredEndDate: DateTime(2026, 5, 15),
            billingStatementNumber: '2026-044',
            companyName: 'TEST COMPANY',
            representativeName: 'JUAN DELA CRUZ',
            greetingLine: 'Dear Sir/Madam:',
            preparedBy: 'Prepared By',
            preparedByTitle: 'Prepared Title',
            approvedBy: 'Approved By',
            approvedByTitle: 'Approved Title',
            bankName: 'Test Bank',
            accountName: 'Test Account',
            accountNumber: '1234567890',
          ),
          rows: const [
            DashboardExportBookingRow(
              deliveryReceiptNumber: '35666',
              date: '5/13/26',
              waybillNumber: 'CEP01626179',
              vanNumber: 'DRYU2903805',
              vanSize: '20 FTR',
              client: 'TEST CLIENT',
              amount: '342,705',
            ),
          ],
          totalAmount: '342,705',
        );

        final bytes = await DashboardDocxExportService.instance.buildDocument(
          payload,
        );

        expect(bytes, isNotEmpty);

        if (type.isBillingStatement) {
          final archive = ZipDecoder().decodeBytes(bytes);
          final headerFile = archive.files.firstWhere(
            (entry) => entry.name == 'word/header1.xml',
          );
          final headerXml = utf8.decode(headerFile.content);
          expect(headerXml, contains('2026-044'));
        }
      });
    }

    test('builds requested export filenames', () {
      final configBase = DashboardExportConfig(
        type: DashboardExportDocumentType.bsRegular,
        documentDate: DateTime(2026, 5, 18),
        coveredStartDate: DateTime(2026, 5, 9),
        coveredEndDate: DateTime(2026, 5, 15),
        billingStatementNumber: '12345',
        companyName: 'TEST COMPANY',
        representativeName: 'JUAN DELA CRUZ',
        greetingLine: 'Dear Sir/Madam:',
        preparedBy: 'Prepared By',
        preparedByTitle: 'Prepared Title',
        approvedBy: 'Approved By',
        approvedByTitle: 'Approved Title',
        bankName: 'Test Bank',
        accountName: 'Test Account',
        accountNumber: '1234567890',
      );

      expect(
        dashboardExportFileName(configBase),
        'BS-12345-Regular.docx',
      );
      expect(
        dashboardExportFileName(
          DashboardExportConfig(
            type: DashboardExportDocumentType.bsHustling,
            documentDate: configBase.documentDate,
            coveredStartDate: configBase.coveredStartDate,
            coveredEndDate: configBase.coveredEndDate,
            billingStatementNumber: '12345',
            companyName: configBase.companyName,
            representativeName: configBase.representativeName,
            greetingLine: configBase.greetingLine,
            preparedBy: configBase.preparedBy,
            preparedByTitle: configBase.preparedByTitle,
            approvedBy: configBase.approvedBy,
            approvedByTitle: configBase.approvedByTitle,
            bankName: configBase.bankName,
            accountName: configBase.accountName,
            accountNumber: configBase.accountNumber,
          ),
        ),
        'BS-12345-Hustling.docx',
      );
      expect(
        dashboardExportFileName(
          DashboardExportConfig(
            type: DashboardExportDocumentType.btRegular,
            documentDate: configBase.documentDate,
            coveredStartDate: configBase.coveredStartDate,
            coveredEndDate: configBase.coveredEndDate,
            billingStatementNumber: configBase.billingStatementNumber,
            companyName: configBase.companyName,
            representativeName: configBase.representativeName,
            greetingLine: configBase.greetingLine,
            preparedBy: configBase.preparedBy,
            preparedByTitle: configBase.preparedByTitle,
            approvedBy: configBase.approvedBy,
            approvedByTitle: configBase.approvedByTitle,
            bankName: configBase.bankName,
            accountName: configBase.accountName,
            accountNumber: configBase.accountNumber,
          ),
        ),
        'BT-12345-Regular.docx',
      );
      expect(
        dashboardExportFileName(
          DashboardExportConfig(
            type: DashboardExportDocumentType.btHustling,
            documentDate: configBase.documentDate,
            coveredStartDate: configBase.coveredStartDate,
            coveredEndDate: configBase.coveredEndDate,
            billingStatementNumber: configBase.billingStatementNumber,
            companyName: configBase.companyName,
            representativeName: configBase.representativeName,
            greetingLine: configBase.greetingLine,
            preparedBy: configBase.preparedBy,
            preparedByTitle: configBase.preparedByTitle,
            approvedBy: configBase.approvedBy,
            approvedByTitle: configBase.approvedByTitle,
            bankName: configBase.bankName,
            accountName: configBase.accountName,
            accountNumber: configBase.accountNumber,
          ),
        ),
        'BT-12345-Hustling.docx',
      );
    });
  });
}
