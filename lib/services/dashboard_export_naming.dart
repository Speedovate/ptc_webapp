import 'package:webapp/services/dashboard_docx_export_service.dart';

String dashboardExportFileName(DashboardExportConfig config) {
  return switch (config.type) {
    DashboardExportDocumentType.bsRegular =>
      'BS-No.-${_sanitizeFileNamePart(config.billingStatementNumber)}-Regular.docx',
    DashboardExportDocumentType.bsHustling =>
      'BS-No.-${_sanitizeFileNamePart(config.billingStatementNumber)}-Hustling.docx',
    DashboardExportDocumentType.btRegular =>
      'BT-${_buildTransmittalDateToken(config.coveredStartDate)}-${_buildTransmittalDateToken(config.coveredEndDate)}-Regular.docx',
    DashboardExportDocumentType.btHustling =>
      'BT-${_buildTransmittalDateToken(config.coveredStartDate)}-${_buildTransmittalDateToken(config.coveredEndDate)}-Hustling.docx',
  };
}

String _sanitizeFileNamePart(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  return sanitized
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

String _buildTransmittalDateToken(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final year = (value.year % 100).toString().padLeft(2, '0');
  return '$month$day$year';
}
