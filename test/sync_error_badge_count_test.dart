import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/services/sync_error_badge_count.dart';

void main() {
  test(
    'badge excludes obsolete KPI reports but retains legacy failures',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 4; i++) {
        await db.collection('sync_error_logs').doc('kpi$i').set({
          'attention_required': true,
          'kind': 'kpi_diagnostic',
        });
      }
      expect(await loadSyncErrorBadgeCount(db), 0);
      await db.collection('sync_error_logs').doc('queue').set({
        'attention_required': true,
        'kind': 'queue_failure',
      });
      await db.collection('sync_error_logs').doc('legacy').set({
        'attention_required': true,
      });
      await db.collection('sync_error_logs').doc('inactive').set({
        'attention_required': false,
        'kind': 'queue_failure',
      });
      expect(await loadSyncErrorBadgeCount(db), 2);
    },
  );
}
