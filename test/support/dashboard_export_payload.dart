import 'package:webapp/services/dashboard_docx_export_service.dart';

DashboardDocxExportPayload dashboardExportTestPayload(
  DashboardExportDocumentType type,
) => DashboardDocxExportPayload(
  config: DashboardExportConfig(
    type: type,
    documentDate: DateTime(2026, 10, 29),
    coveredStartDate: DateTime(2026, 10, 1),
    coveredEndDate: DateTime(2026, 10, 29),
    billingStatementNumber: '2026-123',
    companyName: 'MORETA SHIPPING LINES',
    representativeName: 'ADRYC CATAPANG',
    greetingLine: 'Dear Ma’am/Sir:',
    preparedBy: 'Amelita Jara',
    preparedByTitle: 'Sales & Operation',
    approvedBy: 'Evelyn N. Pua',
    approvedByTitle: 'General Manager',
    bankName: 'Test bank',
    accountName: 'Test account',
    accountNumber: '123456',
  ),
  rows: const [
    DashboardExportBookingRow(
      deliveryReceiptNumber: '37314',
      date: '10/6/26',
      waybillNumber: 'ICLMC02526016',
      vanNumber: 'MSLU3443206',
      vanSize: '20 FTR',
      client: 'SUB-CLIENT (BAGONG PAG-ASA - SAN MANUEL)',
      amount: '4,100',
    ),
  ],
  totalAmount: '4,100',
);
