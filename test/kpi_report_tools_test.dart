import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';
import 'package:webapp/views/admin/kpi_import_dialog.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/kpi/kpi_report_export.dart';
import 'package:webapp/services/kpi/kpi_workbook_import.dart';
import 'package:webapp/services/kpi/kpi_payroll_summary.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:xml/xml.dart';

Uint8List workbook() {
  final a = Archive();
  void add(String name, String contents) =>
      a.add(ArchiveFile.bytes(name, utf8.encode(contents)));
  add(
    'xl/workbook.xml',
    '<workbook xmlns:r="r"><sheets><sheet name="Jan" r:id="r1"/><sheet name="Weekly January" r:id="r2"/></sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Target="worksheets/sheet1.xml"/></Relationships>',
  );
  add('xl/worksheets/sheet1.xml', '''<worksheet><sheetData>
  <row r="3"><c r="E3" t="inlineStr"><is><t>Salary</t></is></c><c r="H3" t="inlineStr"><is><t>Description</t></is></c></row>
  <row r="4"><c r="A4" t="inlineStr"><is><t>PM 4</t></is></c></row>
  <row r="5"><c r="A5" t="inlineStr"><is><t>week 1</t></is></c><c r="B5" t="inlineStr"><is><t>PO-1</t></is></c><c r="D5"><v>1000</v></c><c r="E5" t="inlineStr"><is><t>JAN 2-9,2026</t></is></c><c r="F5"><v>1500</v></c><c r="G5" t="inlineStr"><is><t>REF-77</t></is></c><c r="H5" t="inlineStr"><is><t>Diesel top-up Roxas</t></is></c></row>
  <row r="12"><c r="D12"><f>SUM(D5:D11)</f><v>1000</v></c></row>
  <row r="14"><c r="A14" t="inlineStr"><is><t>PM 5</t></is></c></row>
  <row r="15"><c r="A15" t="inlineStr"><is><t>week 1</t></is></c><c r="D15"><v>2000</v></c></row>
  </sheetData></worksheet>''');
  return Uint8List.fromList(ZipEncoder().encode(a));
}

class ImportPreviewStore extends PmKpiStore {
  @override
  bool get canEdit => true;
  @override
  bool get canEditFuel => true;
}

void main() {
  for (final width in [375.0, 1200.0]) {
    testWidgets('import preview requires admin dates and split at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KpiImportDialog(
              make: const VehicleMake(id: '1', code: 'PM4'),
              store: ImportPreviewStore(),
              bookings: [],
              pickWorkbook: () async => workbook(),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose Excel'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AdminModalRecordList>(find.byType(AdminModalRecordList))
            .itemCount,
        2,
      );
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Import Selected'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test(
    'workbook preview excludes totals, other PMs and weekly duplicate sheets',
    () {
      final rows = KpiWorkbookImport.parse(workbook(), 'PM4');
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.amount), [1000, 1500]);
      expect(rows.every((r) => !r.valid && !r.selected), true);
      expect(rows.first.liters, isNull); // Salary date is not fuel liters.
      expect(
        rows.first.description,
        'Diesel top-up Roxas',
        reason:
            'the Description column is located from its header, not assumed',
      );
      final salary = rows.last;
      salary.date = DateTime.utc(2026, 1, 9);
      salary.driver = 1000;
      salary.helper = 500;
      expect(salary.valid, true);
      salary.helper = 400;
      expect(salary.valid, false);
      expect(
        KpiWorkbookImport.parse(workbook(), 'PM4').first.key,
        rows.first.key,
      );
    },
  );
  test(
    'Excel preserves text literally and numeric amounts; PDF has valid offsets',
    () {
      final sheets = <String, List<List<Object?>>>{
        'Summary': [
          ['Name', 'Amount'],
          ['=formula & <literal>', 123.45],
        ],
      };
      final xlsx = ZipDecoder().decodeBytes(KpiReportExport.excel(sheets));
      final xml = XmlDocument.parse(
        utf8.decode(xlsx.findFile('xl/worksheets/sheet1.xml')!.content),
      );
      expect(xml.findAllElements('t').last.innerText, '=formula & <literal>');
      expect(xml.findAllElements('f'), isEmpty);
      expect(xml.findAllElements('v').single.innerText, '123.45');
      final pdf = ascii.decode(KpiReportExport.pdf(sheets));
      expect(pdf, startsWith('%PDF-1.4'));
      final offset = int.parse(
        RegExp(r'startxref\n(\d+)').firstMatch(pdf)!.group(1)!,
      );
      expect(pdf.substring(offset), startsWith('xref'));
    },
  );
  test('payroll summary respects fixed weeks and selected range', () {
    final day = KpiDay(DateTime.utc(2026, 9, 22), [], {
      'salary_confirmed': true,
      'trip_signature': '[]',
      'driver_salary': 555,
      'helper_salary': 505,
      'trip_rates': [
        {'driver': 100, 'helper': 50},
      ],
    });
    final result = PmKpi(
      period: KpiPeriod(DateTime.utc(2026, 9, 24), DateTime.utc(2026, 9, 28)),
      days: [day],
      revenue: 0,
      bookingCount: 0,
      issues: {},
      threshold: 0,
    );
    expect(KpiPayrollSummary.rows(result).single, [
      '2026-09-24 – 2026-09-28',
      100.0,
      455.0,
      50.0,
      455.0,
      1060.0,
      'Confirmed',
    ]);
  });
  final path = Platform.environment['KPI_WORKBOOK_PATH'];
  if (path != null) {
    test('provided workbook can be previewed for every PM', () {
      for (final pm in ['PM4', 'PM5', 'PM6', 'PM7']) {
        final rows = KpiWorkbookImport.parse(File(path).readAsBytesSync(), pm);
        expect(rows, isNotEmpty);
        expect(rows.any((r) => r.kind == 'Fuel'), true);
        expect(rows.any((r) => r.kind == 'Salary'), true);
        expect(rows.every((r) => !r.selected), true);
      }
    });
  }
}
