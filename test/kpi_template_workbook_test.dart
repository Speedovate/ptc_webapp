import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/services/kpi/kpi_fleet_workbook.dart';
import 'package:webapp/services/kpi/kpi_template_workbook.dart';
import 'package:webapp/services/kpi/pm_kpi.dart';
import 'package:webapp/services/kpi/pm_kpi_store.dart';

XmlDocument document(Archive archive, String path) =>
    XmlDocument.parse(utf8.decode(archive.findFile(path)!.content));
XmlElement? cell(XmlDocument sheet, String ref) => sheet
    .findAllElements('c')
    .where((c) => c.getAttribute('r') == ref)
    .firstOrNull;
String? value(XmlDocument sheet, String ref) =>
    cell(sheet, ref)?.getElement('v')?.innerText;
String? text(XmlDocument sheet, String ref) =>
    cell(sheet, ref)?.getElement('is')?.innerText;

void main() {
  final template = File(KpiTemplateWorkbook.asset).readAsBytesSync();
  final source = ZipDecoder().decodeBytes(template);
  List<FleetMonth> entries(
    List<int> months, {
    int count = 4,
    int fuelCount = 1,
  }) {
    final makes = [
      for (var i = 0; i < count; i++)
        VehicleMake(id: '$i', code: 'PM ${i + 4}'),
    ];
    return [
      for (final month in months)
        for (final make in makes)
          FleetMonth(
            make,
            DateTime.utc(2026, month),
            KpiPeriod.month(2026, month),
            KpiStoredData(
              [],
              {},
              false,
              fuel: [
                for (var i = 0; i < fuelCount; i++)
                  {
                    'id': 'f$i',
                    'make_id': make.id,
                    'day': '2026-${month.toString().padLeft(2, '0')}-09',
                    'reference': 'PO ${make.id}-$i',
                    'amount': 100,
                    'liters': 2,
                    'price_per_liter': 50,
                  },
              ],
            ),
            [],
            makes,
          ),
    ];
  }

  test(
    'responsive export yields and preserves every worksheet and formula',
    () async {
      final data = entries([9, 10], count: 5, fuelCount: 10);
      final dates = KpiPeriod(
        DateTime.utc(2026, 9),
        DateTime.utc(2026, 10, 31),
      );
      final expected = ZipDecoder().decodeBytes(
        KpiTemplateWorkbook.fill(template, data, dates),
      );
      var yields = 0;
      final actual = ZipDecoder().decodeBytes(
        await KpiTemplateWorkbook.fillResponsive(
          template,
          data,
          dates,
          budget: Duration.zero,
          yieldToUi: () async {
            yields++;
            await Future<void>.delayed(Duration.zero);
          },
        ),
      );
      expect(yields, greaterThan(20));
      expect(
        actual.files.map((f) => f.name),
        expected.files.map((f) => f.name),
      );
      for (final file in expected.files) {
        expect(
          actual.findFile(file.name)!.content,
          file.content,
          reason: file.name,
        );
      }
    },
  );

  test(
    'selected month sheets retain original widths, merges, row heights and styles',
    () {
      for (var month = 1; month <= 12; month++) {
        final output = ZipDecoder().decodeBytes(
          KpiTemplateWorkbook.fill(
            template,
            entries([month]),
            KpiPeriod.month(2026, month),
          ),
        );
        expect(
          document(
            output,
            'xl/workbook.xml',
          ).findAllElements('sheet').map((s) => s.getAttribute('name')),
          [
            KpiTemplateWorkbook.ledgerNames[month - 1],
            'Monthly',
            KpiTemplateWorkbook.weeklyNames[month - 1],
          ],
        );
        expect(
          output.findFile('xl/styles.xml')!.content,
          source.findFile('xl/styles.xml')!.content,
        );
        for (final pair in [
          (1, month <= 9 ? month : 9),
          (3, month <= 9 ? month + 10 : 19),
        ]) {
          final actual = document(output, 'xl/worksheets/sheet${pair.$1}.xml');
          final original = document(
            source,
            'xl/worksheets/sheet${pair.$2}.xml',
          );
          for (final tag in [
            'cols',
            'sheetFormatPr',
            'pageMargins',
            'pageSetup',
            'mergeCells',
          ]) {
            expect(
              actual.rootElement.getElement(tag)?.toXmlString(),
              original.rootElement.getElement(tag)?.toXmlString(),
              reason: 'month $month $tag',
            );
          }
          for (final r in original.findAllElements('row')) {
            final ar = actual
                .findAllElements('row')
                .firstWhere((a) => a.getAttribute('r') == r.getAttribute('r'));
            expect(ar.getAttribute('ht'), r.getAttribute('ht'));
          }
          for (final c in original.findAllElements('c')) {
            expect(
              cell(actual, c.getAttribute('r')!)?.getAttribute('s'),
              c.getAttribute('s'),
              reason: 'month $month ${c.getAttribute('r')}',
            );
          }
        }
        final weekly = document(output, 'xl/worksheets/sheet3.xml');
        final total = month <= 2 ? 'C' : 'D';
        expect(double.parse(value(weekly, '${total}11')!), 100);
        expect(
          double.parse(value(weekly, '${total}13')!),
          closeTo(50000, 0.001),
        );
        expect(
          output.files.any((f) => f.name.contains('externalLink')),
          isFalse,
        );
        for (final f in output.files.where((f) => f.name.endsWith('.xml'))) {
          final doc = XmlDocument.parse(utf8.decode(f.content));
          expect(
            doc.findAllElements('c').where((c) => c.getAttribute('t') == 'e'),
            isEmpty,
          );
          expect(
            doc
                .findAllElements('f')
                .any(
                  (f) =>
                      f.innerText.contains('#REF!') ||
                      f.innerText.contains('[1]'),
                ),
            isFalse,
          );
        }
      }
    },
  );
  test(
    'extra PMs and fuel rows retain every transaction and valid shifted totals',
    () {
      final output = ZipDecoder().decodeBytes(
        KpiTemplateWorkbook.fill(
          template,
          entries([9], count: 6, fuelCount: 12),
          KpiPeriod.month(2026, 9),
        ),
      );
      final ledger = document(output, 'xl/worksheets/sheet1.xml');
      final weekly = document(output, 'xl/worksheets/sheet3.xml');
      final monthly = document(output, 'xl/worksheets/sheet2.xml');
      for (var i = 0; i < 6; i++) {
        for (var j = 0; j < 12; j++) {
          expect(
            ledger.findAllElements('t').where((t) => t.innerText == 'PO $i-$j'),
            hasLength(1),
          );
        }
        expect(text(weekly, 'B${10 + i * 10}'), 'PM ${i + 4}');
        expect(double.parse(value(weekly, 'D${11 + i * 10}')!), 1200);
        expect(double.parse(value(monthly, 'R${11 + i * 10}')!), 1200);
      }
      // Evaluate each ledger SUM against its actual referenced numeric cells.
      for (final c in ledger.findAllElements('c')) {
        final formula = c.getElement('f')?.innerText;
        if (formula == null) continue;
        final m = RegExp(
          r'^SUM\(([A-Z]+)(\d+):[A-Z]+(\d+)\)$',
        ).firstMatch(formula)!;
        var sum = 0.0;
        for (var r = int.parse(m[2]!); r <= int.parse(m[3]!); r++) {
          sum += double.tryParse(value(ledger, '${m[1]}$r') ?? '') ?? 0;
        }
        expect(
          double.parse(c.getElement('v')!.innerText),
          closeTo(sum, 0.0001),
          reason: formula,
        );
      }
    },
  );
  test(
    'source sample amounts and staff remarks are absent; missing admin cost stays blank',
    () {
      final output = ZipDecoder().decodeBytes(
        KpiTemplateWorkbook.fill(
          template,
          entries([4, 9]),
          KpiPeriod(DateTime.utc(2026, 4), DateTime.utc(2026, 9, 30)),
        ),
      );
      final weekly = document(output, 'xl/worksheets/sheet4.xml');
      expect(value(weekly, 'D58'), isNull);
      expect(value(weekly, 'D59'), '');
      expect(
        cell(weekly, 'D59')!.getElement('f')!.innerText,
        'IF(D58="","",D57-D58)',
      );
      for (final f in output.files.where(
        (f) => f.name.startsWith('xl/worksheets/'),
      )) {
        expect(utf8.decode(f.content), isNot(contains('TRANGKASO')));
        expect(utf8.decode(f.content), isNot(contains('SUSPENDED')));
      }
    },
  );
}
