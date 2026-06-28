import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

enum DashboardExportDocumentType {
  bsRegular,
  btRegular,
  bsHustling,
  btHustling;

  bool get isBillingStatement => name.startsWith('bs');
  bool get isHustling => name.toLowerCase().contains('hustling');

  String get buttonLabel => switch (this) {
    DashboardExportDocumentType.bsRegular => 'BS Regular',
    DashboardExportDocumentType.btRegular => 'BT Regular',
    DashboardExportDocumentType.bsHustling => 'BS Hustling',
    DashboardExportDocumentType.btHustling => 'BT Hustling',
  };

  String get detailsLabel => isHustling ? 'Hustling' : 'Regular Trip';

  String get headingLabel => isHustling ? 'HUSTLING' : 'REGULAR TRIP';

  String get fileSlug => switch (this) {
    DashboardExportDocumentType.bsRegular => 'BS-Regular',
    DashboardExportDocumentType.btRegular => 'BT-Regular',
    DashboardExportDocumentType.bsHustling => 'BS-Hustling',
    DashboardExportDocumentType.btHustling => 'BT-Hustling',
  };

  String get templateAssetPath => switch (this) {
    DashboardExportDocumentType.bsRegular =>
      'assets/export_templates/bs-regular.docx',
    DashboardExportDocumentType.btRegular =>
      'assets/export_templates/bt-regular.docx',
    DashboardExportDocumentType.bsHustling =>
      'assets/export_templates/bs-hustling.docx',
    DashboardExportDocumentType.btHustling =>
      'assets/export_templates/bt-hustling.docx',
  };
}

class DashboardExportConfig {
  const DashboardExportConfig({
    required this.type,
    required this.documentDate,
    required this.coveredStartDate,
    required this.coveredEndDate,
    required this.billingStatementNumber,
    required this.companyName,
    required this.representativeName,
    required this.greetingLine,
    required this.preparedBy,
    required this.preparedByTitle,
    required this.approvedBy,
    required this.approvedByTitle,
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
  });

  final DashboardExportDocumentType type;
  final DateTime documentDate;
  final DateTime coveredStartDate;
  final DateTime coveredEndDate;
  final String billingStatementNumber;
  final String companyName;
  final String representativeName;
  final String greetingLine;
  final String preparedBy;
  final String preparedByTitle;
  final String approvedBy;
  final String approvedByTitle;
  final String bankName;
  final String accountName;
  final String accountNumber;
}

class DashboardExportBookingRow {
  const DashboardExportBookingRow({
    required this.deliveryReceiptNumber,
    required this.date,
    required this.waybillNumber,
    required this.vanNumber,
    required this.vanSize,
    required this.client,
    required this.amount,
  });

  final String deliveryReceiptNumber;
  final String date;
  final String waybillNumber;
  final String vanNumber;
  final String vanSize;
  final String client;
  final String amount;
}

class DashboardDocxExportPayload {
  const DashboardDocxExportPayload({
    required this.config,
    required this.rows,
    required this.totalAmount,
  });

  final DashboardExportConfig config;
  final List<DashboardExportBookingRow> rows;
  final String totalAmount;
}

class DashboardDocxExportService {
  DashboardDocxExportService._();

  static final DashboardDocxExportService instance =
      DashboardDocxExportService._();

  Future<Uint8List> buildDocument(DashboardDocxExportPayload payload) async {
    final asset = await rootBundle.load(payload.config.type.templateAssetPath);
    final templateBytes = asset.buffer.asUint8List();
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final documentXml = _readArchiveTextFile(archive, 'word/document.xml');
    final document = XmlDocument.parse(documentXml);

    if (payload.config.type.isBillingStatement) {
      _applyBillingStatementTemplate(document, payload);
      _applyBillingStatementHeaders(archive, payload.config);
    } else {
      _applyBillingTransmittalTemplate(document, payload);
    }

    _writeArchiveTextFile(archive, 'word/document.xml', document.toXmlString());
    final output = ZipEncoder().encode(archive);
    return Uint8List.fromList(output);
  }

  void _applyBillingTransmittalTemplate(
    XmlDocument document,
    DashboardDocxExportPayload payload,
  ) {
    final config = payload.config;
    _replaceFirstParagraph(
      document,
      (text) => _looksLikeLongDate(text),
      _longDate(config.documentDate),
    );
    _replaceFirstParagraph(
      document,
      (text) => text.trim().toUpperCase() == 'MORETA SHIPPING LINES',
      config.companyName.toUpperCase(),
    );

    final table = _findTableByHeaders(document, const [
      'DATE COVERED',
      'SOA NO.',
      'DETAILS',
      'AMOUNT (Php)',
    ]);
    if (table == null) {
      throw StateError('We could not find the billing transmittal table.');
    }
    final rows = _childElements(table, 'tr');
    if (rows.length < 2) {
      throw StateError('The billing transmittal template is incomplete.');
    }
    final cells = _childElements(rows[1], 'tc');
    if (cells.length < 4) {
      throw StateError('The billing transmittal row is incomplete.');
    }
    _setCellText(
      cells[0],
      '${_longDate(config.coveredStartDate)} – ${_longDate(config.coveredEndDate)}',
    );
    _setCellText(cells[1], config.billingStatementNumber);
    _setCellText(cells[2], config.type.detailsLabel);
    _setCellText(cells[3], payload.totalAmount);

    _replaceSignatureBlock(
      document,
      preparedBy: config.preparedBy,
      preparedByTitle: config.preparedByTitle,
      approvedBy: config.approvedBy,
      approvedByTitle: config.approvedByTitle,
    );
  }

  void _applyBillingStatementTemplate(
    XmlDocument document,
    DashboardDocxExportPayload payload,
  ) {
    final config = payload.config;
    _replaceFirstParagraph(
      document,
      (text) => _looksLikeLongDate(text),
      _longDate(config.documentDate),
    );
    _replaceFirstParagraph(
      document,
      (text) => text.trim().toUpperCase() == 'MORETA SHIPPING LINES',
      config.companyName.toUpperCase(),
    );
    _replaceFirstParagraph(
      document,
      (text) => text.trim().toUpperCase() == 'MR. LEANDRO DONGOR',
      config.representativeName.toUpperCase(),
    );
    _replaceFirstParagraph(
      document,
      (text) => text.trim().toLowerCase().startsWith('dear'),
      config.greetingLine,
    );
    _replaceFirstParagraph(
      document,
      (text) =>
          text.trim().toUpperCase() == 'REGULAR TRIP' ||
          text.trim().toUpperCase() == 'HUSTLING',
      config.type.headingLabel,
    );

    final table = _findTableByHeaders(document, const [
      'DR NO.',
      'DATE',
      'WAYBILL NO.',
      'VAN NO.',
      'VAN SIZE',
      'CLIENT',
      'AMOUNT (PHP)',
    ]);
    if (table == null) {
      throw StateError('We could not find the billing statement table.');
    }
    _replaceBillingStatementRows(table, payload.rows, payload.totalAmount);

    _replaceBankDetails(
      document,
      bankName: config.bankName,
      accountName: config.accountName,
      accountNumber: config.accountNumber,
    );
    _replaceSignatureBlock(
      document,
      preparedBy: config.preparedBy,
      preparedByTitle: config.preparedByTitle,
      approvedBy: config.approvedBy,
      approvedByTitle: config.approvedByTitle,
    );
  }

  void _applyBillingStatementHeaders(
    Archive archive,
    DashboardExportConfig config,
  ) {
    final headerPaths = archive.files
        .map((file) => file.name)
        .where(
          (name) =>
              name.startsWith('word/header') && name.toLowerCase().endsWith('.xml'),
        )
        .toList();
    for (final path in headerPaths) {
      final headerXml = _readArchiveTextFile(archive, path);
      final header = XmlDocument.parse(headerXml);
      var labelFound = false;
      var valueReplaced = false;
      for (final paragraph in header.findAllElements('w:p')) {
        final text = _paragraphText(paragraph).trim();
        if (text.isEmpty) {
          continue;
        }
        if (text == 'Billing Statement No.') {
          labelFound = true;
          continue;
        }
        if (labelFound && _looksLikeBillingStatementNumber(text)) {
          _setParagraphText(paragraph, config.billingStatementNumber);
          valueReplaced = true;
          break;
        }
      }
      if (valueReplaced) {
        _writeArchiveTextFile(archive, path, header.toXmlString());
      }
    }
  }

  void _replaceBillingStatementRows(
    XmlElement table,
    List<DashboardExportBookingRow> rows,
    String totalAmount,
  ) {
    final tableRows = _childElements(table, 'tr');
    if (tableRows.length < 3) {
      throw StateError('The billing statement table is missing rows.');
    }
    final templateRow = tableRows[1].copy();
    final totalRow = tableRows.last;

    for (var index = tableRows.length - 2; index >= 1; index--) {
      tableRows[index].parent?.children.remove(tableRows[index]);
    }

    for (final row in rows) {
      final nextRow = templateRow.copy();
      final cells = _childElements(nextRow, 'tc');
      if (cells.length < 7) {
        throw StateError('A billing statement row is missing cells.');
      }
      _setCellText(cells[0], row.deliveryReceiptNumber);
      _setCellText(cells[1], row.date);
      _setCellText(cells[2], row.waybillNumber);
      _setCellText(cells[3], row.vanNumber);
      _setCellText(cells[4], row.vanSize);
      _setCellText(cells[5], row.client);
      _setCellText(cells[6], row.amount);
      totalRow.parent?.children.insert(
        totalRow.parent!.children.indexOf(totalRow),
        nextRow,
      );
    }

    final totalCells = _childElements(totalRow, 'tc');
    if (totalCells.isNotEmpty) {
      _setCellText(totalCells.last, totalAmount);
    }
  }

  void _replaceBankDetails(
    XmlDocument document, {
    required String bankName,
    required String accountName,
    required String accountNumber,
  }) {
    final table = _findTableContainingText(document, 'Bank Details:');
    if (table == null) {
      throw StateError('We could not find the bank details table.');
    }

    for (final row in _childElements(table, 'tr')) {
      final cells = _childElements(row, 'tc');
      if (cells.length < 3) {
        continue;
      }
      final label = _cellText(cells.first).trim();
      if (label == 'Bank Name') {
        _setCellText(cells[2], bankName);
      } else if (label == 'Account Name') {
        _setCellText(cells[2], accountName);
      } else if (label == 'Account Number') {
        _setCellText(cells[2], accountNumber);
      }
    }
  }

  void _replaceSignatureBlock(
    XmlDocument document, {
    required String preparedBy,
    required String preparedByTitle,
    required String approvedBy,
    required String approvedByTitle,
  }) {
    final table = _findTableContainingText(document, 'Prepared by:');
    if (table == null) {
      throw StateError('We could not find the signature section.');
    }

    final rows = _childElements(table, 'tr');
    if (rows.length < 4) {
      throw StateError('The signature section is incomplete.');
    }

    final nameCells = _childElements(rows[2], 'tc');
    final titleCells = _childElements(rows[3], 'tc');
    if (nameCells.length >= 2) {
      _setCellText(nameCells[0], preparedBy);
      _setCellText(nameCells[1], approvedBy);
    }
    if (titleCells.length >= 2) {
      _setCellText(titleCells[0], preparedByTitle);
      _setCellText(titleCells[1], approvedByTitle);
    }
  }

  void _replaceFirstParagraph(
    XmlDocument document,
    bool Function(String text) predicate,
    String replacement,
  ) {
    for (final paragraph in document.findAllElements('w:p')) {
      final text = _paragraphText(paragraph).trim();
      if (text.isEmpty) {
        continue;
      }
      if (predicate(text)) {
        _setParagraphText(paragraph, replacement);
        return;
      }
    }
    throw StateError('We could not find a paragraph to replace.');
  }

  XmlElement? _findTableByHeaders(
    XmlDocument document,
    List<String> expectedHeaders,
  ) {
    for (final table in document.findAllElements('w:tbl')) {
      final rows = _childElements(table, 'tr');
      if (rows.isEmpty) {
        continue;
      }
      final headerCells = _childElements(rows.first, 'tc');
      final headers = headerCells
          .map((cell) => _cellText(cell).trim())
          .where((text) => text.isNotEmpty)
          .toList();
      if (headers.length != expectedHeaders.length) {
        continue;
      }
      var matches = true;
      for (var index = 0; index < expectedHeaders.length; index++) {
        if (headers[index] != expectedHeaders[index]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return table;
      }
    }
    return null;
  }

  XmlElement? _findTableContainingText(XmlDocument document, String text) {
    for (final table in document.findAllElements('w:tbl')) {
      if (_tableText(table).contains(text)) {
        return table;
      }
    }
    return null;
  }

  String _tableText(XmlElement table) {
    final buffer = StringBuffer();
    for (final textNode in table.findAllElements('w:t')) {
      buffer.write(textNode.innerText);
    }
    return buffer.toString();
  }

  String _cellText(XmlElement cell) {
    final buffer = StringBuffer();
    for (final node in cell.descendants.whereType<XmlElement>()) {
      if (node.name.qualified == 'w:br') {
        buffer.write('\n');
      } else if (node.name.qualified == 'w:t') {
        buffer.write(node.innerText);
      }
    }
    return buffer.toString();
  }

  String _paragraphText(XmlElement paragraph) {
    final buffer = StringBuffer();
    for (final node in paragraph.children.whereType<XmlElement>()) {
      if (node.name.qualified == 'w:r') {
        for (final runNode in node.children.whereType<XmlElement>()) {
          if (runNode.name.qualified == 'w:br') {
            buffer.write('\n');
          } else if (runNode.name.qualified == 'w:t') {
            buffer.write(runNode.innerText);
          }
        }
      }
    }
    return buffer.toString();
  }

  void _setCellText(XmlElement cell, String text) {
    final cellProperties = cell.getElement('w:tcPr')?.copy();
    final paragraphs = _childElements(cell, 'p');
    final paragraphTemplate = paragraphs.isNotEmpty
        ? paragraphs.first.copy()
        : XmlElement(XmlName.qualified('w:p'));

    cell.children.clear();
    if (cellProperties != null) {
      cell.children.add(cellProperties);
    }
    final paragraph = paragraphTemplate.copy();
    _setParagraphText(paragraph, text);
    cell.children.add(paragraph);
  }

  void _setParagraphText(XmlElement paragraph, String text) {
    final paragraphProperties = paragraph.getElement('w:pPr')?.copy();
    XmlElement? runProperties;

    for (final run in _childElements(paragraph, 'r')) {
      final candidate = run.getElement('w:rPr');
      if (candidate != null) {
        runProperties = candidate.copy();
        break;
      }
    }

    paragraph.children.clear();
    if (paragraphProperties != null) {
      paragraph.children.add(paragraphProperties);
    }

    final lines = text.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final runChildren = <XmlNode>[];
      if (runProperties != null) {
        runChildren.add(runProperties.copy());
      }
      if (index > 0) {
        runChildren.add(XmlElement(XmlName.qualified('w:br')));
      }
      runChildren.add(
        XmlElement(
          XmlName.qualified('w:t'),
          _preserveWhitespace(lines[index])
              ? [XmlAttribute(XmlName.qualified('xml:space'), 'preserve')]
              : const [],
          [XmlText(lines[index])],
        ),
      );
      paragraph.children.add(
        XmlElement(XmlName.qualified('w:r'), const [], runChildren),
      );
    }
  }

  bool _preserveWhitespace(String text) {
    return text.startsWith(' ') || text.endsWith(' ');
  }

  List<XmlElement> _childElements(XmlElement element, String localName) {
    return element.children
        .whereType<XmlElement>()
        .where((child) => child.name.local == localName)
        .toList();
  }

  bool _looksLikeLongDate(String text) {
    return RegExp(
      r'^(January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4}$',
    ).hasMatch(text.trim());
  }

  bool _looksLikeBillingStatementNumber(String text) {
    return RegExp(r'^\d{4}-\d{3,}$').hasMatch(text.trim());
  }

  String _readArchiveTextFile(Archive archive, String path) {
    final file = archive.files.firstWhere(
      (entry) => entry.name == path,
      orElse: () => throw StateError('Missing required template entry: $path'),
    );
    return utf8.decode(file.content as List<int>);
  }

  void _writeArchiveTextFile(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    final index = archive.files.indexWhere((entry) => entry.name == path);
    if (index == -1) {
      throw StateError('Missing required template entry: $path');
    }
    final existingFile = archive[index];
    final nextFile = ArchiveFile(path, bytes.length, bytes)
      ..compression = existingFile.compression
      ..compressionLevel = existingFile.compressionLevel
      ..comment = existingFile.comment
      ..crc32 = existingFile.crc32
      ..creationTime = existingFile.creationTime
      ..groupId = existingFile.groupId
      ..lastModTime = existingFile.lastModTime
      ..mode = existingFile.mode
      ..ownerId = existingFile.ownerId
      ..symbolicLink = existingFile.symbolicLink;
    archive[index] = nextFile;
  }
}

String dashboardExportErrorMessage(Object error) {
  if (error is StateError) {
    final message = error.message.toString().trim();
    if (message.isNotEmpty) {
      return message;
    }
  }
  return 'We could not export the document right now.';
}

String dashboardExportLongDate(DateTime value) {
  return _longDate(value);
}

String dashboardExportShortDate(DateTime value) {
  final year = (value.year % 100).toString().padLeft(2, '0');
  return '${value.month}/${value.day}/$year';
}

String dashboardExportCurrency(double value) {
  final rounded = value.round();
  final sign = rounded < 0 ? '-' : '';
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length; index++) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }

  return '$sign${buffer.toString()}';
}

String _longDate(DateTime value) {
  const months = <String>[
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
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}
