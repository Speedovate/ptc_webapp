import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

class ExcelReportCell {
  const ExcelReportCell(this.value, {this.formula, this.style = 0});
  final Object? value;
  final String? formula;
  final int style;
}

/// Report data comes from the full selected period, never the visible page.
class KpiReportExport {
  static String _xml(Object? value) => (value ?? '')
      .toString()
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static Uint8List excel(
    Map<String, List<List<Object?>>> sheets, {
    bool styled = false,
  }) {
    final archive = Archive();
    void add(String path, String value) =>
        archive.add(ArchiveFile.bytes(path, utf8.encode(value)));
    add(
      '[Content_Types].xml',
      '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${List.generate(sheets.length, (i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}${styled ? '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' : ''}</Types>',
    );
    add(
      '_rels/.rels',
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    );
    add(
      'xl/workbook.xml',
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sheets.keys.indexed.map((e) => '<sheet name="${_xml(e.$2)}" sheetId="${e.$1 + 1}" r:id="rId${e.$1 + 1}"/>').join()}</sheets></workbook>',
    );
    add(
      'xl/_rels/workbook.xml.rels',
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${List.generate(sheets.length, (i) => '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join()}${styled ? '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' : ''}</Relationships>',
    );
    if (styled) {
      add('xl/styles.xml', _styles);
    }
    for (final sheet in sheets.values.indexed) {
      final rows = sheet.$2.indexed.map((row) {
        final isHeader =
            styled &&
            row.$2.any(
              (v) =>
                  v == 'ITEM' ||
                  v == 'PO No. / Ref' ||
                  v == 'FUEL' && row.$2.contains('Salary') ||
                  v == 'DATA STATUS',
            );
        final cells = row.$2.indexed.map((entry) {
          final wrapped = entry.$2;
          final value = wrapped is ExcelReportCell ? wrapped.value : wrapped;
          final formula = wrapped is ExcelReportCell ? wrapped.formula : null;
          final style = !styled
              ? 0
              : isHeader
              ? 1
              : wrapped is ExcelReportCell
              ? wrapped.style
              : value is num
              ? 2
              : 0;
          final ref = '${_column(entry.$1 + 1)}${row.$1 + 1}';
          final attrs = 'r="$ref" s="$style"';
          if (value is num && value.isFinite) {
            return '<c $attrs>${formula == null ? '' : '<f>${_xml(formula)}</f>'}<v>$value</v></c>';
          }
          return '<c $attrs t="inlineStr"><is><t xml:space="preserve">${_xml(value)}</t></is></c>';
        }).join();
        return '<row r="${row.$1 + 1}" ht="42" customHeight="1">$cells</row>';
      }).join();
      final merges = <String>[];
      if (styled) {
        for (final row in sheet.$2.indexed) {
          if (row.$2.length >= 12 &&
              row.$2[1] == 'FUEL' &&
              row.$2[7] == 'Salary') {
            final r = row.$1 + 1;
            merges.addAll(['B$r:E$r', 'H$r:I$r', 'J$r:L$r']);
          }
        }
      }
      final mergedXml = merges.isEmpty
          ? ''
          : '<mergeCells count="${merges.length}">${merges.map((r) => '<mergeCell ref="$r"/>').join()}</mergeCells>';
      add(
        'xl/worksheets/sheet${sheet.$1 + 1}.xml',
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="6" topLeftCell="A7" state="frozen"/></sheetView></sheetViews><cols><col min="1" max="1" width="15" customWidth="1"/><col min="2" max="3" width="38" customWidth="1"/><col min="4" max="40" width="20" customWidth="1"/></cols><sheetData>$rows</sheetData>$mergedXml<pageMargins left="0.25" right="0.25" top="0.4" bottom="0.4" header="0.2" footer="0.2"/><pageSetup orientation="landscape" paperSize="9" fitToWidth="1" fitToHeight="0"/></worksheet>',
      );
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _column(int n) {
    var result = '';
    while (n > 0) {
      n--;
      result = String.fromCharCode(65 + n % 26) + result;
      n ~/= 26;
    }
    return result;
  }

  static const _styles =
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF6236EA"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="1"><border><left style="thin"><color rgb="FFDDDDDD"/></left><right style="thin"><color rgb="FFDDDDDD"/></right><top style="thin"><color rgb="FFDDDDDD"/></top><bottom style="thin"><color rgb="FFDDDDDD"/></bottom><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>'
      '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="10" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';

  /// Printable multipage PDF using standard built-in fonts, no network assets.
  /// Amounts use PHP; Unicode names are retained in the Excel export.
  static Uint8List pdf(Map<String, List<List<Object?>>> sheets) {
    final lines = <String>[];
    for (final sheet in sheets.entries) {
      lines.add('PALTRANCO - ${sheet.key}');
      for (final row in sheet.value) {
        final text = row
            .map((v) => v is double ? v.toStringAsFixed(2) : '${v ?? ''}')
            .join(' | ')
            .replaceAll('₱', 'PHP ')
            .replaceAll('−', '-')
            .replaceAll('—', '-')
            .replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF]'), ' ');
        for (var start = 0; start < text.length; start += 115) {
          lines.add(text.substring(start, (start + 115).clamp(0, text.length)));
        }
        if (text.isEmpty) lines.add('');
      }
      lines.add('');
    }
    final pages = <List<String>>[];
    for (var i = 0; i < lines.length; i += 44) {
      pages.add(lines.sublist(i, (i + 44).clamp(0, lines.length)));
    }
    if (pages.isEmpty) pages.add([]);
    final objects = <String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Count ${pages.length} /Kids [${List.generate(pages.length, (i) => '${4 + i * 2} 0 R').join(' ')}] >>',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>',
    ];
    for (final page in pages.indexed) {
      final stream = StringBuffer('BT /F1 9 Tf 12 TL 32 560 Td\n');
      for (final line in page.$2) {
        final escaped = line
            .replaceAll('\\', '\\\\')
            .replaceAll('(', '\\(')
            .replaceAll(')', '\\)');
        stream.writeln('($escaped) Tj T*');
      }
      stream.writeln('ET');
      final data = stream.toString();
      objects.add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 842 595] /Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + page.$1 * 2} 0 R >>',
      );
      objects.add(
        '<< /Length ${latin1.encode(data).length} >>\nstream\n${data}endstream',
      );
    }
    final output = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    for (final object in objects.indexed) {
      offsets.add(output.length);
      output.write('${object.$1 + 1} 0 obj\n${object.$2}\nendobj\n');
    }
    final xref = output.length;
    output.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
    for (final offset in offsets.skip(1)) {
      output.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
    }
    output.write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
    );
    return Uint8List.fromList(latin1.encode(output.toString()));
  }
}
