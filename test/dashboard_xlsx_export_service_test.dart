import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/dashboard_docx_export_service.dart';
import 'package:webapp/services/dashboard_xlsx_export_service.dart';
import 'package:xml/xml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Excel workbook follows sample layout and preserves all trip types',
    () async {
      final config = DashboardExportConfig(
        type: DashboardExportDocumentType.bsRegular,
        documentDate: DateTime(2026, 10, 30),
        coveredStartDate: DateTime(2026, 10, 1),
        coveredEndDate: DateTime(2026, 10, 29),
        billingStatementNumber: '',
        companyName: 'MORETA SHIPPING LINES',
        representativeName: '',
        greetingLine: '',
        preparedBy: '',
        preparedByTitle: '',
        approvedBy: '',
        approvedByTitle: '',
        bankName: '',
        accountName: '',
        accountNumber: '',
      );
      final bytes = await DashboardXlsxExportService().buildWorkbook(
        config: config,
        rows: [
          DashboardXlsxBookingRow(
            bookingType: 'Regular',
            pmNumber: 'PM 7',
            driver: 'Driver',
            receipt: '037314',
            date: DateTime(2026, 10, 6),
            waybill: 'ICLMC02526016',
            van: 'MSLU3443206',
            vanSize: '20 FTR',
            client: 'NEW PANAY (BAGONG PAG-ASA - SAN MANUEL)',
            amount: 4100,
          ),
          DashboardXlsxBookingRow(
            bookingType: 'Hustling',
            pmNumber: 'PM 6',
            driver: 'Other',
            receipt: '037315',
            date: DateTime(2026, 10, 7),
            waybill: '=BAD',
            van: 'IPXU123',
            vanSize: '20 FTR',
            client: 'OTHER',
            amount: 1350,
          ),
          DashboardXlsxBookingRow(
            bookingType: '-',
            pmNumber: '-',
            driver: '-',
            receipt: '037316',
            date: null,
            waybill: '-',
            van: '-',
            vanSize: '-',
            client: 'UNKNOWN',
            amount: 0,
          ),
        ],
      );
      final zip = ZipDecoder().decodeBytes(bytes);
      final workbook = utf8.decode(zip.findFile('xl/workbook.xml')!.content);
      expect(workbook, contains('name="Regular"'));
      expect(workbook, contains('name="Hustling"'));
      expect(workbook, contains('name="Unspecified"'));
      final regular = XmlDocument.parse(
        utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content),
      );
      final hustling = XmlDocument.parse(
        utf8.decode(zip.findFile('xl/worksheets/sheet2.xml')!.content),
      );
      final unspecified = XmlDocument.parse(
        utf8.decode(zip.findFile('xl/worksheets/sheet3.xml')!.content),
      );
      String cell(XmlDocument sheet, String ref) => sheet.descendants
          .whereType<XmlElement>()
          .firstWhere((e) => e.name.local == 'c' && e.getAttribute('r') == ref)
          .innerText;
      expect(cell(regular, 'A9'), 'PM NO.');
      expect(cell(regular, 'C10'), '037314');
      expect(cell(regular, 'D10'), '46301'); // 2026-10-06 Excel date
      expect(cell(regular, 'H10'), 'NEW PANAY (BAGONG PAG-ASA - SAN MANUEL)');
      expect(cell(regular, 'I10'), '4100.0');
      expect(cell(regular, 'I11'), contains('SUBTOTAL(109,I10:I10)'));
      expect(cell(hustling, 'E10'), '=BAD'); // text, never a formula
      expect(cell(unspecified, 'C10'), '037316');
      expect(
        utf8.decode(zip.findFile('xl/styles.xml')!.content),
        contains('numFmts'),
      );
    },
  );
}
