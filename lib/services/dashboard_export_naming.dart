import 'package:webapp/services/dashboard_docx_export_service.dart';

String dashboardExportFileName(DashboardExportConfig config) {
  return switch (config.type) {
    DashboardExportDocumentType.bsRegular =>
      'BS-${_sanitizeFileNamePart(config.billingStatementNumber)}-Regular.docx',
    DashboardExportDocumentType.bsHustling =>
      'BS-${_sanitizeFileNamePart(config.billingStatementNumber)}-Hustling.docx',
    DashboardExportDocumentType.btRegular =>
      'BT-${_sanitizeFileNamePart(config.billingStatementNumber)}-Regular.docx',
    DashboardExportDocumentType.btHustling =>
      'BT-${_sanitizeFileNamePart(config.billingStatementNumber)}-Hustling.docx',
  };
}

String _sanitizeFileNamePart(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  return sanitized
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
