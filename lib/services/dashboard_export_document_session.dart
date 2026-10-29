import 'dart:convert';
import 'dart:typed_data';
import 'dashboard_docx_export_service.dart';

/// Reuses the exact DOCX bytes across preview and download until inputs change.
class DashboardExportDocumentSession {
  DashboardExportDocumentSession({
    Future<Uint8List> Function(DashboardDocxExportPayload)? buildDocument,
  }) : _build =
           buildDocument ?? DashboardDocxExportService.instance.buildDocument;

  final Future<Uint8List> Function(DashboardDocxExportPayload) _build;
  final Map<String, Future<Uint8List>> _documents = {};

  Future<Uint8List> docxFor(DashboardDocxExportPayload payload) {
    final key = _identity(payload);
    final existing = _documents[key];
    if (existing != null) return existing;
    final future = _build(payload).timeout(const Duration(seconds: 20));
    _documents[key] = future;
    return future.then(
      (bytes) => bytes,
      onError: (Object error, StackTrace stack) {
        if (identical(_documents[key], future)) _documents.remove(key);
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  void clear() => _documents.clear();

  String _identity(DashboardDocxExportPayload payload) {
    final c = payload.config;
    return jsonEncode([
      c.type.name,
      c.documentDate.toIso8601String(),
      c.coveredStartDate.toIso8601String(),
      c.coveredEndDate.toIso8601String(),
      c.billingStatementNumber,
      c.companyName,
      c.representativeName,
      c.greetingLine,
      c.preparedBy,
      c.preparedByTitle,
      c.approvedBy,
      c.approvedByTitle,
      c.bankName,
      c.accountName,
      c.accountNumber,
      payload.totalAmount,
      for (final row in payload.rows)
        [
          row.deliveryReceiptNumber,
          row.date,
          row.waybillNumber,
          row.vanNumber,
          row.vanSize,
          row.client,
          row.amount,
        ],
    ]);
  }
}
