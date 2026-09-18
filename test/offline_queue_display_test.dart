import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/offline_queue_item.dart';
import 'package:webapp/services/offline_sync_status_service.dart';
import 'package:webapp/widgets/shared/offline_queue_status_strip.dart';

void main() {
  test('temporary identifiers have readable labels', () {
    expect(
      OfflineQueueItem.record('bookings', 'offline_booking_123'),
      'New booking · ID pending sync',
    );
    expect(
      OfflineQueueItem.record('chassis', '-23'),
      'New chassis · ID pending sync',
    );
    expect(OfflineQueueItem.record('bookings', '107'), 'Booking #107');
  });
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets('offline queue remains visible and readable at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var loads = 0;
      final item = OfflineQueueItem(
        title: 'Create booking',
        recordLabel: 'New booking · ID pending sync',
        createdAt: DateTime(2026, 9, 19, 10, 30),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  OfflineQueueStatusStrip(
                    snapshot: const OfflineSyncStatusSnapshot(
                      isOnline: false,
                      pendingActions: 1,
                      failedActions: 0,
                      isSyncing: false,
                      processedActions: 0,
                      totalActionsInBatch: 0,
                    ),
                    onView: () => showDialog<void>(
                      context: context,
                      builder: (_) => OfflineQueueDialog(
                        load: () async {
                          loads++;
                          return [item];
                        },
                      ),
                    ),
                  ),
                  const Expanded(child: Text('Page content')),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Offline · 1 queued action'), findsOneWidget);
      expect(loads, 0);
      await tester.tap(find.text('View queued actions'));
      await tester.pumpAndSettle();
      expect(find.text('Create booking'), findsOneWidget);
      expect(find.text('New booking · ID pending sync'), findsOneWidget);
      expect(
        find.text('Saved on this device · Waiting to sync'),
        findsOneWidget,
      );
      expect(loads, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(loads, 1);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
