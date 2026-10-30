import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import 'dashboard_docx_export_service.dart';

class DashboardXlsxBookingRow {
  const DashboardXlsxBookingRow({
    required this.bookingType,
    required this.pmNumber,
    required this.driver,
    required this.receipt,
    required this.date,
    required this.waybill,
    required this.van,
    required this.vanSize,
    required this.client,
    required this.amount,
  });

  final String bookingType,
      pmNumber,
      driver,
      receipt,
      waybill,
      van,
      vanSize,
      client;
  final DateTime? date;
  final double amount;
}

/// Uses the supplied spreadsheet's header, widths, fonts and number formats.
/// Values are written as text/numbers, never interpreted as user formulas.
class DashboardXlsxExportService {
  static const templatePath =
      'assets/export_templates/dashboard-trips-layout.xlsx';
  static const _ns =
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const _rel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  Future<Uint8List> buildWorkbook({
    required DashboardExportConfig config,
    required List<DashboardXlsxBookingRow> rows,
  }) async {
    final asset = await rootBundle.load(templatePath);
    final template = ZipDecoder().decodeBytes(asset.buffer.asUint8List());
    final archive = Archive();
    for (final path in [
      'xl/styles.xml',
      'xl/theme/theme1.xml',
      '_rels/.rels',
    ]) {
      archive.add(ArchiveFile.bytes(path, template.findFile(path)!.content));
    }
    final groups = <String, List<DashboardXlsxBookingRow>>{
      'Regular': [],
      'Hustling': [],
    };
    for (final row in rows) {
      final type = switch (row.bookingType.trim().toLowerCase()) {
        'regular' => 'Regular',
        'hustling' || 'husting' || 'hutling' => 'Hustling',
        _ => 'Unspecified',
      };
      (groups[type] ??= []).add(row);
    }
    final names = groups.keys.toList();
    for (var i = 0; i < names.length; i++) {
      final sheet = XmlDocument.parse(
        utf8.decode(template.findFile('xl/worksheets/sheet1.xml')!.content),
      );
      _populate(sheet, config, names[i], groups[names[i]]!);
      _write(archive, 'xl/worksheets/sheet${i + 1}.xml', sheet.toXmlString());
    }
    _write(
      archive,
      'xl/workbook.xml',
      '''<workbook xmlns="$_ns" xmlns:r="$_rel"><sheets>
      ${[for (var i = 0; i < names.length; i++) '<sheet name="${names[i]}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}
      </sheets><definedNames>${[for (var i = 0; i < names.length; i++) '<definedName name="_xlnm.Print_Area" localSheetId="$i">\'${names[i]}\'!\$A\$1:\$I\$${11 + groups[names[i]]!.length}</definedName>'].join()}
      </definedNames><calcPr fullCalcOnLoad="1"/></workbook>''',
    );
    _write(
      archive,
      'xl/_rels/workbook.xml.rels',
      '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      ${[for (var i = 0; i < names.length; i++) '<Relationship Id="rId${i + 1}" Type="$_rel/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}
      <Relationship Id="rId${names.length + 1}" Type="$_rel/styles" Target="styles.xml"/>
      <Relationship Id="rId${names.length + 2}" Type="$_rel/theme" Target="theme/theme1.xml"/>
      </Relationships>''',
    );
    _write(
      archive,
      '[Content_Types].xml',
      '''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
      <Override PartName="/xl/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
      ${[for (var i = 1; i <= names.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}
      </Types>''',
    );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  void _populate(
    XmlDocument sheet,
    DashboardExportConfig config,
    String name,
    List<DashboardXlsxBookingRow> rows,
  ) {
    final root = sheet.rootElement;
    final data = root.getElement('sheetData')!;
    final bodyTemplate = data
        .findElements('row')
        .firstWhere((row) => row.getAttribute('r') == '10')
        .copy();
    data.children.removeWhere(
      (node) => node is XmlElement && int.parse(node.getAttribute('r')!) >= 10,
    );
    void header(String ref, String text) {
      final cell = data.descendants.whereType<XmlElement>().firstWhere(
        (e) => e.name.local == 'c' && e.getAttribute('r') == ref,
      );
      _text(cell, text);
    }

    header('F1', 'Date: ${_longDate(config.documentDate)}');
    header(
      'F3',
      'Date Covered: ${_longDate(config.coveredStartDate)} – ${_longDate(config.coveredEndDate)}',
    );
    header('F5', 'To: ${config.companyName}');
    header('A8', name == 'Regular' ? 'REGULAR TRIP' : name.toUpperCase());
    var total = 0.0;
    for (var i = 0; i < rows.length; i++) {
      final value = rows[i];
      final rowNumber = i + 10;
      final row = bodyTemplate.copy()..setAttribute('r', '$rowNumber');
      row.setAttribute('ht', value.client.length > 60 ? '64' : '48');
      row.setAttribute('customHeight', '1');
      final cells = row.findElements('c').toList();
      final values = [
        value.pmNumber,
        value.driver,
        value.receipt,
        '',
        value.waybill,
        value.van,
        value.vanSize,
        value.client,
      ];
      for (var c = 0; c < cells.length; c++) {
        cells[c].setAttribute('r', '${String.fromCharCode(65 + c)}$rowNumber');
        if (c == 8) {
          _number(cells[c], value.amount);
        } else if (c == 3 && value.date != null) {
          final d = value.date!.toLocal();
          _number(
            cells[c],
            DateTime.utc(
              d.year,
              d.month,
              d.day,
            ).difference(DateTime.utc(1899, 12, 30)).inDays,
          );
        } else {
          _text(cells[c], c == 3 ? '-' : values[c]);
        }
      }
      total += value.amount;
      data.children.add(row);
    }
    final totalRow = rows.length + 10;
    final label = _cell('H$totalRow', '27');
    _text(label, 'TOTAL');
    final amount = _cell('I$totalRow', '28');
    _number(amount, total);
    amount.children.insert(
      0,
      XmlElement(XmlName.parts('f'), [], [
        XmlText(rows.isEmpty ? '0' : 'SUBTOTAL(109,I10:I${totalRow - 1})'),
      ]),
    );
    data.children.add(
      XmlElement(
        XmlName.parts('row'),
        [XmlAttribute(XmlName.parts('r'), '$totalRow')],
        [label, amount],
      ),
    );
    final merges = root.getElement('mergeCells')!;
    for (final col in ['H', 'I']) {
      merges.children.add(
        XmlElement(XmlName.parts('mergeCell'), [
          XmlAttribute(
            XmlName.parts('ref'),
            '$col$totalRow:$col${totalRow + 1}',
          ),
        ]),
      );
    }
    merges.setAttribute('count', '${merges.findElements('mergeCell').length}');
    root.getElement('dimension')!.setAttribute('ref', 'A1:I${totalRow + 1}');
    final view = root.getElement('sheetViews')!.getElement('sheetView')!;
    view.children.insert(
      0,
      XmlElement(XmlName.parts('pane'), [
        XmlAttribute(XmlName.parts('ySplit'), '9'),
        XmlAttribute(XmlName.parts('topLeftCell'), 'A10'),
        XmlAttribute(XmlName.parts('activePane'), 'bottomLeft'),
        XmlAttribute(XmlName.parts('state'), 'frozen'),
      ]),
    );
  }

  static XmlElement _cell(String ref, String style) =>
      XmlElement(XmlName.parts('c'), [
        XmlAttribute(XmlName.parts('r'), ref),
        XmlAttribute(XmlName.parts('s'), style),
      ]);
  static void _text(XmlElement cell, String value) {
    cell.setAttribute('t', 'inlineStr');
    cell.children
      ..clear()
      ..add(
        XmlElement(XmlName.parts('is'), [], [
          XmlElement(
            XmlName.parts('t'),
            [
              XmlAttribute(
                XmlName.parts(
                  'space',
                  prefix: 'xml',
                  namespaceUri: 'http://www.w3.org/XML/1998/namespace',
                ),
                'preserve',
              ),
            ],
            [XmlText(value)],
          ),
        ]),
      );
  }

  static void _number(XmlElement cell, num value) {
    cell.removeAttribute('t');
    cell.children
      ..clear()
      ..add(XmlElement(XmlName.parts('v'), [], [XmlText('$value')]));
  }

  static void _write(Archive archive, String path, String xml) =>
      archive.add(ArchiveFile.bytes(path, utf8.encode(xml)));
  static String _longDate(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}
