import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';
import 'kpi_fleet_workbook.dart';
import 'kpi_report_export.dart';
import 'pm_kpi.dart';

/// Fills the supplied workbook's actual cell styles and layouts. The bundled
/// layout contains no source transactions, cached results or external links.
class KpiTemplateWorkbook {
  static const asset = 'assets/export_templates/kpi-2026-layout.xlsx';
  static const ledgerNames = [
    'Jan',
    'Feb',
    'March',
    'April ',
    'May',
    'JUNE',
    'JULY',
    'AUG',
    'SEPT',
    'OCT',
    'NOV',
    'DEC',
  ];
  static const weeklyNames = [
    'Weekly January',
    'Weekly-February',
    'Weekly-March',
    'Weekly-April',
    'Weekly-May',
    'Weekly-June',
    'Weekly-July',
    'Weekly-Aug',
    'Weekly-Sept',
    'Weekly-Oct',
    'Weekly-Nov',
    'Weekly-Dec',
  ];

  static Future<Uint8List> export(
    List<FleetMonth> data,
    KpiPeriod period,
  ) async {
    final bytes = await rootBundle.load(asset);
    return fillResponsive(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      data,
      period,
    );
  }

  static Uint8List fill(
    Uint8List template,
    List<FleetMonth> data,
    KpiPeriod period,
  ) {
    return _fillSteps(template, data, period).whereType<Uint8List>().last;
  }

  /// Yield between workbook blocks and archive members on web as well as native.
  /// compute() alone would still run on the browser UI thread.
  static Future<Uint8List> fillResponsive(
    Uint8List template,
    List<FleetMonth> data,
    KpiPeriod period, {
    Duration budget = const Duration(milliseconds: 4),
    Future<void> Function()? yieldToUi,
  }) async {
    final clock = Stopwatch()..start();
    Uint8List? result;
    for (final step in _fillSteps(template, data, period)) {
      if (step != null) result = step;
      if (clock.elapsed >= budget) {
        await (yieldToUi?.call() ?? Future<void>.delayed(Duration.zero));
        clock.reset();
      }
    }
    return result!;
  }

  static Iterable<Uint8List?> _fillSteps(
    Uint8List template,
    List<FleetMonth> data,
    KpiPeriod period,
  ) sync* {
    final source = ZipDecoder().decodeBytes(template);
    _Sheet layout(int index) => _Sheet(
      XmlDocument.parse(
        utf8.decode(source.findFile('xl/worksheets/sheet$index.xml')!.content),
      ),
    );
    final months = data.map((d) => d.month).toSet().toList()..sort();
    final makes = {for (final d in data) d.make.id: d.make}.values.toList();
    final multiYear = period.start.year != period.end.year;
    String name(DateTime month, bool weekly) =>
        '${(weekly ? weeklyNames : ledgerNames)[month.month - 1]}${multiYear ? ' ${month.year}' : ''}';
    final ledgers = <String, _Sheet>{};
    final weeklies = <String, _Sheet>{};
    for (final month in months) {
      final entries = data.where((d) => d.month == month).toList();
      final ledger = layout(month.month <= 9 ? month.month : 9);
      yield* _ledger(ledger, entries, month);
      ledgers[name(month, false)] = ledger;
      final weekly = layout(month.month <= 9 ? month.month + 10 : 19);
      yield* _weekly(weekly, entries, month);
      weeklies[name(month, true)] = weekly;
    }
    final monthly = layout(10);
    yield* _monthly(
      monthly,
      data,
      months,
      makes.map((m) => m.id!).toList(),
      multiYear,
    );
    final sheets = {...ledgers, 'Monthly': monthly, ...weeklies};
    final archive = ZipDecoder().decodeBytes(
      KpiReportExport.excel({
        for (final key in sheets.keys) key: <List<Object?>>[],
      }, styled: true),
    );
    void add(String path, List<int> bytes) =>
        archive.add(ArchiveFile.bytes(path, bytes));
    add('xl/styles.xml', source.findFile('xl/styles.xml')!.content);
    add('xl/theme/theme1.xml', source.findFile('xl/theme/theme1.xml')!.content);
    final rels = XmlDocument.parse(
      utf8.decode(archive.findFile('xl/_rels/workbook.xml.rels')!.content),
    );
    rels.rootElement.children.add(
      XmlElement(XmlName.parts('Relationship'), [
        XmlAttribute(XmlName.parts('Id'), 'rIdTheme'),
        XmlAttribute(
          XmlName.parts('Type'),
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme',
        ),
        XmlAttribute(XmlName.parts('Target'), 'theme/theme1.xml'),
      ]),
    );
    add('xl/_rels/workbook.xml.rels', utf8.encode(rels.toXmlString()));
    final types = XmlDocument.parse(
      utf8.decode(archive.findFile('[Content_Types].xml')!.content),
    );
    types.rootElement.children.add(
      XmlElement(XmlName.parts('Override'), [
        XmlAttribute(XmlName.parts('PartName'), '/xl/theme/theme1.xml'),
        XmlAttribute(
          XmlName.parts('ContentType'),
          'application/vnd.openxmlformats-officedocument.theme+xml',
        ),
      ]),
    );
    add('[Content_Types].xml', utf8.encode(types.toXmlString()));
    final workbook = XmlDocument.parse(
      utf8.decode(archive.findFile('xl/workbook.xml')!.content),
    );
    final printAreas = XmlElement(XmlName.parts('definedNames'));
    for (final entry in sheets.entries.indexed) {
      final sheet = entry.$2.value;
      yield null;
      sheet.finish();
      add(
        'xl/worksheets/sheet${entry.$1 + 1}.xml',
        utf8.encode(sheet.doc.toXmlString()),
      );
      final area = XmlElement(
        XmlName.parts('definedName'),
        [
          XmlAttribute(XmlName.parts('name'), '_xlnm.Print_Area'),
          XmlAttribute(XmlName.parts('localSheetId'), '${entry.$1}'),
        ],
        [XmlText("'${entry.$2.key.replaceAll("'", "''")}'!${sheet.dimension}")],
      );
      printAreas.children.add(area);
    }
    workbook.rootElement.children.add(printAreas);
    workbook.rootElement.children.add(
      XmlElement(XmlName.parts('calcPr'), [
        XmlAttribute(XmlName.parts('calcMode'), 'auto'),
        XmlAttribute(XmlName.parts('fullCalcOnLoad'), '1'),
      ]),
    );
    add('xl/workbook.xml', utf8.encode(workbook.toXmlString()));
    final output = OutputMemoryStream();
    final encoder = ZipEncoder()..startEncode(output);
    for (final file in archive) {
      yield null;
      encoder.add(file);
    }
    encoder.endEncode(comment: archive.comment);
    yield output.getBytes();
  }

  static List<PmKpi?> _weeks(FleetMonth d) => [
    for (var w = 1; w <= 4; w++)
      if (KpiFleetWorkbook.overlap(
            d.period,
            KpiPeriod.week(d.month.year, d.month.month, w),
          )
          case final dates?)
        d.calculate(dates)
      else
        null,
  ];

  static Iterable<Uint8List?> _ledger(
    _Sheet sheet,
    List<FleetMonth> entries,
    DateTime month,
  ) sync* {
    // Header positions vary in the supplied January–September layouts.
    var headers =
        sheet.cells
            .where((c) => RegExp(r'^PM\s*\d+$').hasMatch(sheet.text(c)))
            .map(_Sheet.rowOf)
            .toList()
          ..sort();
    final salary = sheet.cells.firstWhere((c) => sheet.text(c) == 'Salary');
    final salaryDateCol = _Sheet.colOf(salary);
    final salaryCol = salaryDateCol + 1;
    final maintenanceCol = salaryCol + 3;
    sheet.set(1, 2, '${ledgerNames[month.month - 1].trim()} ${month.year}');
    // Repeat the last original block for fleets larger than the sample's four PMs.
    while (headers.length < entries.length) {
      yield null;
      final start = headers.last - 1;
      final end = sheet.maxRow;
      final height = end - start + 1;
      sheet.cloneRows(start, end, end + 1);
      headers.add(headers.last + height);
    }
    for (var i = headers.length - 1; i >= 0; i--) {
      final header = headers[i];
      sheet.set(1, header, i < entries.length ? entries[i].label : null);
      if (i >= entries.length) continue;
      yield null;
      final d = entries[i];
      final fuel = d.stored.fuel.where((f) {
        final day = DateTime.tryParse('${f['day']}T00:00:00Z');
        return f['voided'] != true && day != null && d.period.contains(day);
      }).toList()..sort((a, b) => '${a['day']}'.compareTo('${b['day']}'));
      // Legacy daily KPI fuel has no PO rows; include its recorded amount too.
      for (final day in d.report.days) {
        if (day.record['fuel_source'] != 'ledger' && day.fuel != 0) {
          fuel.add({
            'day': kpiDayKey(day.date),
            'amount': day.fuel,
            'reference': 'Daily KPI',
          });
        }
      }
      fuel.sort((a, b) => '${a['day']}'.compareTo('${b['day']}'));
      final start = header + 1;
      var end = i + 1 < headers.length ? headers[i + 1] - 2 : sheet.maxRow;
      final anchors =
          sheet.cells
              .where(
                (c) =>
                    _Sheet.colOf(c) == 1 &&
                    _Sheet.rowOf(c) >= start &&
                    _Sheet.rowOf(c) <= end &&
                    RegExp(r'^week \d+$').hasMatch(sheet.text(c)),
              )
              .map(_Sheet.rowOf)
              .toList()
            ..sort();
      if (anchors.isEmpty) anchors.addAll(List.generate(5, (w) => start + w));
      // Some original January blocks end at the fifth week, without a total.
      if (end <= anchors.last) {
        sheet.insertRows(end + 1, 1, start);
        end++;
      }
      final reports = _weeks(d);
      for (var w = 4; w >= 0; w--) {
        final row = anchors[w];
        final next = w == 4 ? end : anchors[w + 1];
        final dates = w < 4
            ? KpiFleetWorkbook.overlap(
                d.period,
                KpiPeriod.week(month.year, month.month, w + 1),
              )
            : null;
        final items = dates == null
            ? <Map<String, dynamic>>[]
            : fuel
                  .where(
                    (f) =>
                        dates.contains(DateTime.parse('${f['day']}T00:00:00Z')),
                  )
                  .toList();
        final capacity = next - row;
        if (items.length > capacity) {
          sheet.insertRows(next, items.length - capacity, row);
          end += items.length - capacity;
        }
        sheet.set(1, row, 'week ${w + 1}');
        for (final item in items.indexed) {
          if (item.$1 % 100 == 0) yield null;
          final at = row + item.$1;
          final f = item.$2;
          sheet.set(2, at, f['reference']);
          sheet.set(3, at, f['day']);
          sheet.set(4, at, kpiMoney(f['amount']));
          if (salaryDateCol > 5) sheet.set(5, at, kpiMoney(f['liters']));
          if (salaryDateCol > 6) {
            sheet.set(6, at, kpiMoney(f['price_per_liter']));
          }
          if (salaryDateCol > 7) sheet.set(7, at, f['notes']);
        }
        if (dates != null && reports[w] != null) {
          sheet.set(
            salaryDateCol,
            row,
            '${kpiDayKey(dates.start)} – ${kpiDayKey(dates.end)}',
          );
          sheet.set(
            salaryCol,
            row,
            reports[w]!.driverSalary + reports[w]!.helperSalary,
          );
          sheet.set(maintenanceCol, row, reports[w]!.maintenance);
        }
      }
      final last = end - 1;
      for (final col in [
        4,
        if (salaryDateCol > 5) 5,
        salaryCol,
        maintenanceCol,
      ]) {
        final total = col == 4
            ? d.report.fuel
            : col == 5
            ? fuel.fold<double>(0, (s, f) => s + (kpiMoney(f['liters']) ?? 0))
            : col == salaryCol
            ? d.report.driverSalary + d.report.helperSalary
            : d.report.maintenance;
        sheet.set(
          col,
          end,
          total,
          formula:
              'SUM(${_Sheet.column(col)}$start:${_Sheet.column(col)}$last)',
        );
      }
    }
  }

  static void _extendPmBlocks(_Sheet sheet, int count) {
    if (count <= 4) return;
    sheet.insertRows(50, (count - 4) * 10, 49);
    for (var i = 4; i < count; i++) {
      sheet.cloneRows(40, 49, 10 + i * 10, replace: true);
    }
  }

  static Iterable<Uint8List?> _weekly(
    _Sheet sheet,
    List<FleetMonth> entries,
    DateTime month,
  ) sync* {
    _extendPmBlocks(sheet, entries.length);
    final unit = month.month <= 2 ? 1 : 2;
    final label = unit + 1, total = unit + 2;
    final columns = [unit + 4, unit + 6, unit + 8, unit + 9];
    sheet.set(
      unit,
      4,
      'MONTH OF ${ledgerNames[month.month - 1].trim()} ${month.year}',
    );
    sheet.set(total, 9, ledgerNames[month.month - 1].trim().toUpperCase());
    for (var i = 0; i < (entries.length > 4 ? entries.length : 4); i++) {
      final start = 10 + i * 10;
      sheet.set(unit, start, i < entries.length ? entries[i].label : null);
      if (i >= entries.length) continue;
      yield null;
      final d = entries[i];
      final reports = _weeks(d);
      for (var j = 0; j < 9; j++) {
        final row = start + j;
        // Keep the template's labels, except the configurable target percentage.
        if (j == 7) {
          sheet.set(
            label,
            row,
            'TARGET  GROSS INCOME ( TARGET- ${d.report.ratingRules.targetLabel}%)',
          );
        }
        for (var w = 0; w < 4; w++) {
          sheet.set(
            columns[w],
            row,
            reports[w] == null ? null : KpiFleetWorkbook.values(reports[w]!)[j],
          );
        }
        sheet.set(
          total,
          row,
          KpiFleetWorkbook.values(d.report)[j],
          formula:
              'SUM(${columns.map((c) => '${_Sheet.column(c)}$row').join(',')})',
        );
        if (j > 0 && j < 8) {
          sheet.set(
            total + 1,
            row,
            d.report.revenue == 0
                ? 0
                : KpiFleetWorkbook.values(d.report)[j] / d.report.revenue,
            formula:
                'IFERROR(${_Sheet.column(total)}$row/${_Sheet.column(total)}$start,0)',
          );
        }
      }
    }
    _footer(sheet, entries, total, label);
  }

  static void _footer(
    _Sheet sheet,
    List<FleetMonth> entries,
    int col,
    int label,
  ) {
    final totals = List<double>.filled(9, 0);
    for (final d in entries) {
      final values = KpiFleetWorkbook.values(d.report);
      for (var i = 0; i < 9; i++) {
        totals[i] += values[i];
      }
    }
    for (final cell in sheet.cells.toList()) {
      if (_Sheet.colOf(cell) != label ||
          _Sheet.rowOf(cell) <
              10 + (entries.length > 4 ? entries.length : 4) * 10) {
        continue;
      }
      final text = sheet.text(cell).trim().toUpperCase();
      final index = switch (text) {
        'REVENUE' => 0,
        'FUEL' => 1,
        'SALARY' => 2,
        'TRUCK DEPRECIATION' => 3,
        'MAINTENANCE' => 4,
        'TOTAL DIRECT EXPENSES' => 5,
        'TOTAL GROSS INCOME' => 6,
        _ => -1,
      };
      final row = _Sheet.rowOf(cell);
      if (index >= 0) {
        sheet.set(
          col,
          row,
          totals[index],
          formula:
              'SUM(${List.generate(entries.length, (i) => '${_Sheet.column(col)}${10 + i * 10 + index}').join(',')})',
        );
      }
      if (text == 'ESTIMATED NET INCOME') {
        final c = _Sheet.column(col);
        sheet.set(
          col,
          row,
          null,
          formula: 'IF($c${row - 1}="","",$c${row - 2}-$c${row - 1})',
        );
      }
      // Admin cost has no app data source: keep it blank instead of exporting
      // the template's historical 160,000 and an invented net income.
    }
  }

  static Iterable<Uint8List?> _monthly(
    _Sheet sheet,
    List<FleetMonth> data,
    List<DateTime> months,
    List<String> ids,
    bool multiYear,
  ) sync* {
    _extendPmBlocks(sheet, ids.length);
    if (multiYear || months.any((m) => m.month == 1)) {
      sheet.root
          .getElement('mergeCells')
          ?.children
          .removeWhere(
            (node) =>
                node is XmlElement &&
                RegExp(r'^B\d+:C\d+$').hasMatch(node.getAttribute('ref') ?? ''),
          );
    }
    if (multiYear) {
      for (final cell
          in sheet.cells
              .where((c) => _Sheet.rowOf(c) == 9 && _Sheet.colOf(c) >= 3)
              .toList()) {
        sheet.set(_Sheet.colOf(cell), 9, null);
      }
    }
    sheet.set(
      1,
      4,
      'FOR THE YEAR ${months.map((m) => m.year).toSet().join(' – ')}',
    );
    for (var i = 0; i < (ids.length > 4 ? ids.length : 4); i++) {
      final entries = i < ids.length
          ? data.where((d) => d.make.id == ids[i]).toList()
          : <FleetMonth>[];
      sheet.set(1, 10 + i * 10, entries.isEmpty ? null : entries.first.label);
    }
    for (final entry in months.indexed) {
      yield null;
      final month = entry.$2;
      // Original Monthly has January at C, then value/% pairs starting D.
      final col = multiYear
          ? 3 + entry.$1 * 2
          : month.month == 1
          ? 3
          : month.month * 2;
      sheet.set(
        col,
        9,
        '${ledgerNames[month.month - 1].trim().toUpperCase()}${multiYear ? ' ${month.year}' : ''}',
      );
      final reports = data.where((d) => d.month == month).toList();
      for (final d in reports) {
        yield null;
        final start = 10 + ids.indexOf(d.make.id!) * 10;
        for (var j = 0; j < 9; j++) {
          final value = KpiFleetWorkbook.values(d.report)[j];
          final weeklyName =
              '${weeklyNames[month.month - 1]}${multiYear ? ' ${month.year}' : ''}';
          final totalColumn = month.month <= 2 ? 'C' : 'D';
          sheet.set(
            col,
            start + j,
            value,
            formula:
                "'${weeklyName.replaceAll("'", "''")}'!$totalColumn${start + j}",
          );
          if (month.month != 1 || multiYear) {
            sheet.set(
              col + 1,
              start + j,
              d.report.revenue == 0 ? 0 : value / d.report.revenue,
              formula:
                  'IFERROR(${_Sheet.column(col)}${start + j}/${_Sheet.column(col)}$start,0)',
            );
          }
        }
      }
      _footer(sheet, reports, col, 2);
    }
  }
}

class _Sheet {
  _Sheet(this.doc);
  final XmlDocument doc;
  XmlElement get root => doc.rootElement;
  XmlElement get data => root.getElement('sheetData')!;
  Iterable<XmlElement> get rows => data.findElements('row');
  Iterable<XmlElement> get cells => data.findAllElements('c');
  int get maxRow => rows
      .map((r) => int.parse(r.getAttribute('r')!))
      .fold(0, (a, b) => a > b ? a : b);
  String get dimension => root.getElement('dimension')!.getAttribute('ref')!;
  static int rowOf(XmlElement c) =>
      int.parse(RegExp(r'\d+').firstMatch(c.getAttribute('r')!)![0]!);
  static int colOf(XmlElement c) => c
      .getAttribute('r')!
      .replaceAll(RegExp('[0-9]'), '')
      .codeUnits
      .fold(0, (v, c) => v * 26 + c - 64);
  static String column(int c) {
    var s = '';
    while (c > 0) {
      c--;
      s = String.fromCharCode(65 + c % 26) + s;
      c ~/= 26;
    }
    return s;
  }

  String text(XmlElement c) => c.getElement('is')?.innerText ?? '';

  void set(int col, int row, Object? value, {String? formula}) {
    var r = rows.where((e) => e.getAttribute('r') == '$row').firstOrNull;
    if (r == null) {
      r = XmlElement(XmlName.parts('row'), [
        XmlAttribute(XmlName.parts('r'), '$row'),
      ]);
      data.children.add(r);
    }
    final ref = '${column(col)}$row';
    var cell = r
        .findElements('c')
        .where((c) => c.getAttribute('r') == ref)
        .firstOrNull;
    if (cell == null) {
      final nearby = r
          .findElements('c')
          .where((c) => colOf(c) == col - 2)
          .firstOrNull;
      cell = XmlElement(XmlName.parts('c'), [
        XmlAttribute(XmlName.parts('r'), ref),
        if (nearby?.getAttribute('s') case final style?)
          XmlAttribute(XmlName.parts('s'), style),
      ]);
      r.children.add(cell);
    }
    cell.children.clear();
    cell.removeAttribute('t');
    if (value == null) {
      if (formula != null) {
        cell.setAttribute('t', 'str');
        cell.children.add(
          XmlElement(XmlName.parts('f'), [], [XmlText(formula)]),
        );
        cell.children.add(XmlElement(XmlName.parts('v'), [], [XmlText('')]));
      }
      return;
    }
    if (value is num && value.isFinite) {
      if (formula != null) {
        cell.children.add(
          XmlElement(XmlName.parts('f'), [], [XmlText(formula)]),
        );
      }
      cell.children.add(
        XmlElement(XmlName.parts('v'), [], [XmlText('$value')]),
      );
    } else {
      cell.setAttribute('t', 'inlineStr');
      cell.children.add(
        XmlElement(XmlName.parts('is'), [], [
          XmlElement(
            XmlName.parts('t'),
            [XmlAttribute(XmlName.parts('space', prefix: 'xml'), 'preserve')],
            [XmlText('$value')],
          ),
        ]),
      );
    }
  }

  void _moveRow(XmlElement row, int delta) {
    row.setAttribute('r', '${int.parse(row.getAttribute('r')!) + delta}');
    for (final c in row.findElements('c')) {
      c.setAttribute('r', '${column(colOf(c))}${rowOf(c) + delta}');
      final formula = c.getElement('f');
      if (formula != null) {
        final shifted = formula.innerText.replaceAllMapped(
          RegExp(r'([A-Z]+)([0-9]+)'),
          (m) => '${m[1]}${int.parse(m[2]!) + delta}',
        );
        formula.children.clear();
        formula.children.add(XmlText(shifted));
      }
    }
  }

  void cloneRows(int start, int end, int destination, {bool replace = false}) {
    final copies = rows
        .where((r) {
          final n = int.parse(r.getAttribute('r')!);
          return n >= start && n <= end;
        })
        .map((r) => r.copy())
        .toList();
    if (replace) {
      data.children.removeWhere(
        (r) =>
            r is XmlElement &&
            int.parse(r.getAttribute('r')!) >= destination &&
            int.parse(r.getAttribute('r')!) <= destination + end - start,
      );
    }
    for (final row in copies) {
      _moveRow(row, destination - start);
      data.children.add(row);
    }
    final merges = root.getElement('mergeCells');
    for (final m
        in merges?.findElements('mergeCell').toList() ?? <XmlElement>[]) {
      final ref = m.getAttribute('ref')!;
      final nums = RegExp(
        r'\d+',
      ).allMatches(ref).map((m) => int.parse(m[0]!)).toList();
      if (nums.every((n) => n >= start && n <= end)) {
        merges!.children.add(
          XmlElement(XmlName.parts('mergeCell'), [
            XmlAttribute(
              XmlName.parts('ref'),
              ref.replaceAllMapped(
                RegExp(r'\d+'),
                (m) => '${int.parse(m[0]!) + destination - start}',
              ),
            ),
          ]),
        );
      }
    }
  }

  void insertRows(int at, int count, int styleRow) {
    final prototype = rows
        .firstWhere((r) => r.getAttribute('r') == '$styleRow')
        .copy();
    for (final row in rows.toList()) {
      if (int.parse(row.getAttribute('r')!) >= at) _moveRow(row, count);
    }
    for (final m in root.findAllElements('mergeCell')) {
      m.setAttribute(
        'ref',
        m.getAttribute('ref')!.replaceAllMapped(RegExp(r'\d+'), (m) {
          final n = int.parse(m[0]!);
          return '${n >= at ? n + count : n}';
        }),
      );
    }
    for (var i = 0; i < count; i++) {
      final row = prototype.copy();
      _moveRow(row, at + i - styleRow);
      for (final c in row.findElements('c')) {
        c.children.clear();
        c.removeAttribute('t');
      }
      data.children.add(row);
    }
  }

  void finish() {
    final sorted = rows.toList()
      ..sort(
        (a, b) => int.parse(
          a.getAttribute('r')!,
        ).compareTo(int.parse(b.getAttribute('r')!)),
      );
    data.children.clear();
    data.children.addAll(sorted);
    for (final row in sorted) {
      final sortedCells = row.findElements('c').toList()
        ..sort((a, b) => colOf(a).compareTo(colOf(b)));
      row.children.clear();
      row.children.addAll(sortedCells);
    }
    final maxCol = cells.map(colOf).fold(1, (a, b) => a > b ? a : b);
    root
        .getElement('dimension')!
        .setAttribute('ref', 'A1:${column(maxCol)}$maxRow');
    final merges = root.getElement('mergeCells');
    merges?.setAttribute('count', '${merges.findElements('mergeCell').length}');
  }
}
