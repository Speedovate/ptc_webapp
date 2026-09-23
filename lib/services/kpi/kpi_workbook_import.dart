import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'pm_kpi.dart';

class KpiImportRow {
  KpiImportRow({
    required this.sheet,
    required this.row,
    required this.make,
    required this.kind,
    required this.amount,
    required this.reference,
    this.date,
    this.liters,
    this.price,
    this.notes = '',
    this.period = '',
  });
  final String sheet, make, kind, reference, notes, period;
  final int row;
  final double amount;
  DateTime? date;
  final double? liters, price;
  double? driver, helper;
  bool selected = false;
  bool imported = false;
  String? error;
  String get key {
    final text = jsonEncode([
      sheet.trim().toLowerCase(),
      row,
      make,
      kind,
      amount,
      reference,
    ]);
    return base64Url.encode(utf8.encode(text)).replaceAll('=', '');
  }

  bool get valid =>
      date != null &&
      !date!.isAfter(kpiDate(DateTime.now())) &&
      (kind == 'Fuel' ||
          (driver != null &&
              helper != null &&
              driver! >= 0 &&
              helper! >= 0 &&
              ((driver! + helper!) - amount).abs() < 0.005));
}

/// Reads the supplied PALTRANCO monthly ledger sheets, not calculated weekly
/// or monthly summaries, to avoid importing the same source amounts twice.
class KpiWorkbookImport {
  static List<KpiImportRow> parse(Uint8List bytes, String makeCode) {
    if (bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('Workbook must be under 10 MB.');
    }
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.files.fold<int>(0, (sum, f) => sum + f.size) >
        40 * 1024 * 1024) {
      throw const FormatException('Workbook contents are too large.');
    }
    XmlDocument read(String path) {
      final file = archive.findFile(path);
      if (file == null) throw FormatException('Missing Excel part: $path');
      return XmlDocument.parse(utf8.decode(file.content));
    }

    final sharedFile = archive.findFile('xl/sharedStrings.xml');
    final shared = sharedFile == null
        ? <String>[]
        : read('xl/sharedStrings.xml')
              .findAllElements('si')
              .map((e) => e.findAllElements('t').map((t) => t.innerText).join())
              .toList();
    final relationships = {
      for (final e in read(
        'xl/_rels/workbook.xml.rels',
      ).findAllElements('Relationship'))
        e.getAttribute('Id'): e.getAttribute('Target')!,
    };
    final output = <KpiImportRow>[];
    for (final sheet in read('xl/workbook.xml').findAllElements('sheet')) {
      final name = sheet.getAttribute('name')!;
      if (name.toLowerCase().startsWith('weekly') ||
          name.toLowerCase() == 'monthly') {
        continue;
      }
      final target = relationships[sheet.getAttribute('r:id')];
      if (target == null) continue;
      final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      var pm = '', salaryColumn = '', salaryDateColumn = '';
      for (final row in read(path).findAllElements('row')) {
        final cells = <String, String>{};
        final formulas = <String, String>{};
        for (final cell in row.findElements('c')) {
          final col = (cell.getAttribute('r') ?? '').replaceAll(
            RegExp('[0-9]'),
            '',
          );
          var value = cell.getElement('v')?.innerText ?? '';
          if (cell.getAttribute('t') == 's') value = shared[int.parse(value)];
          if (cell.getAttribute('t') == 'inlineStr') {
            value = cell.getElement('is')?.innerText ?? '';
          }
          cells[col] = value;
          formulas[col] = cell.getElement('f')?.innerText ?? '';
        }
        final first = cells['A']?.trim() ?? '';
        if (RegExp(r'^PM\s*\d+$', caseSensitive: false).hasMatch(first)) {
          pm = first.replaceAll(' ', '').toUpperCase();
          continue;
        }
        for (final entry in cells.entries) {
          if (entry.value.trim().toLowerCase() == 'salary') {
            salaryDateColumn = entry.key;
            salaryColumn = String.fromCharCode(entry.key.codeUnitAt(0) + 1);
          }
        }
        if (pm != makeCode.replaceAll(' ', '').toUpperCase()) continue;
        final week = RegExp(
          r'^week\s+(\d+)',
          caseSensitive: false,
        ).firstMatch(first);
        if (week != null && int.parse(week.group(1)!) > 5) continue;
        final number = int.tryParse(row.getAttribute('r') ?? '') ?? 0;
        final fuel = kpiMoney(cells['D']);
        if (fuel != null &&
            fuel > 0 &&
            !(formulas['D'] ?? '').toUpperCase().contains('SUM(') &&
            (first.toLowerCase().startsWith('week') ||
                (cells['B'] ?? '').isNotEmpty ||
                kpiMoney(cells['E']) != null)) {
          final rawDate = cells['C'] ?? '';
          final serial = double.tryParse(rawDate);
          final date = serial != null && serial > 30000 && serial < 80000
              ? DateTime.utc(1899, 12, 30).add(Duration(days: serial.floor()))
              : DateTime.tryParse(rawDate);
          output.add(
            KpiImportRow(
              sheet: name,
              row: number,
              make: pm,
              kind: 'Fuel',
              amount: fuel,
              reference: cells['B'] ?? '',
              date: date == null
                  ? null
                  : DateTime.utc(date.year, date.month, date.day),
              liters: salaryDateColumn == 'E' ? null : kpiMoney(cells['E']),
              price: ['G', 'H'].contains(salaryDateColumn)
                  ? kpiMoney(cells['F'])
                  : null,
              notes: salaryDateColumn == 'H' ? cells['G'] ?? '' : '',
              period: first,
            ),
          );
        }
        final salary = kpiMoney(cells[salaryColumn]);
        if (salary != null &&
            salary > 0 &&
            first.toLowerCase().startsWith('week')) {
          output.add(
            KpiImportRow(
              sheet: name,
              row: number,
              make: pm,
              kind: 'Salary',
              amount: salary,
              reference: '',
              period: cells[salaryDateColumn] ?? first,
            ),
          );
        }
        if (output.length > 3000) {
          throw const FormatException(
            'Import at most 3,000 entries at a time.',
          );
        }
      }
    }
    return output;
  }
}
