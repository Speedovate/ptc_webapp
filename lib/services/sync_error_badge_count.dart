import 'package:cloud_firestore/cloud_firestore.dart';

/// Exclude the historical KPI diagnostics removed by the Error Logs page.
/// Aggregates avoid downloading the full diagnostic payloads for the sidebar.
Future<int> loadSyncErrorBadgeCount(FirebaseFirestore db) async {
  final active = db
      .collection('sync_error_logs')
      .where('attention_required', isEqualTo: true);
  final counts = await Future.wait([
    active.count().get(),
    active.where('kind', isEqualTo: 'kpi_diagnostic').count().get(),
  ]);
  final count = (counts[0].count ?? 0) - (counts[1].count ?? 0);
  // Independent aggregates can overlap a concurrent cleanup.
  return count < 0 ? 0 : count;
}
