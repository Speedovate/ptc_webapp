import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'booking_id_resolver_test.dart' show MemoryBackend;
import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/offline_queue_item.dart';
import 'package:webapp/services/offline_sync_status_service.dart';
import 'package:webapp/widgets/shared/offline_queue_status_strip.dart';

void main() {
  testWidgets(
    'queue closes only after all persisted actions are gone and sync is idle',
    (tester) async {
      final changes = ValueNotifier<int>(0);
      addTearDown(changes.dispose);
      var syncing = false;
      var items = <OfflineQueueItem>[
        OfflineQueueItem(
          title: 'Send support message',
          recordLabel: 'Support',
          createdAt: DateTime(2026),
          hasError: true,
        ),
      ];
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => OfflineQueueDialog(
                  load: () async {
                    loads++;
                    return List.of(items);
                  },
                  syncChanges: changes,
                  isSyncing: () => syncing,
                ),
              ),
              child: const Text('Open queue'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open queue'));
      await tester.pumpAndSettle();
      changes.value++;
      await tester.pumpAndSettle();
      expect(find.text('Queued Actions'), findsOneWidget);
      syncing = true;
      items = [];
      changes.value++;
      await tester.pumpAndSettle();
      expect(find.text('Queued Actions'), findsOneWidget);
      syncing = false;
      changes.value++;
      await tester.pumpAndSettle();
      expect(find.text('Queued Actions'), findsNothing);
      expect(find.text('Open queue'), findsOneWidget);
      final completedLoads = loads;
      changes.value++;
      await tester.pumpAndSettle();
      expect(loads, completedLoads);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening retries once, rebuild and refresh do not retrigger', (
    tester,
  ) async {
    var attempts = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineQueueDialog(
          load: () async => [],
          retryFailedChat: () {
            attempts++;
            return pending.future;
          },
        ),
      ),
    );
    await tester.pump();
    expect(attempts, 1);
    expect(find.text('Retry failed chat'), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineQueueDialog(
          load: () async => [],
          retryFailedChat: () async {
            attempts++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  test(
    'failed support queue exposes its reason and retry deadline without modifying it',
    () async {
      final backend = MemoryBackend();
      const key = 'offline_media_sync_queue_v1::7';
      final payload = jsonEncode({
        'id': 'chat_1',
        'kind': 'supportMessage',
        'created_at': '2026-09-19T01:00:00Z',
        'last_error': 'permission-denied',
        'next_retry_at': '2026-09-19T01:20:00Z',
        'text': 'Keep this message',
      });
      await backend.writeStringList(key, [payload]);
      final service = OfflineMediaSyncService(
        backend: backend,
        isOnline: () => false,
      );
      final items = await service.readPendingItems('7');
      expect(items.single.title, 'Send support message');
      expect(items.single.errorMessage, 'permission-denied');
      expect(items.single.nextRetryAt, DateTime.utc(2026, 9, 19, 1, 20));
      expect(await backend.readStringList(key), [payload]);
      expect(await service.readPendingItems('8'), isEmpty);
    },
  );
  test('temporary identifiers have readable labels', () {
    expect(
      OfflineQueueItem.record('bookings', 'offline_booking_123'),
      'New booking · ID pending sync',
    );
    expect(
      OfflineQueueItem.record('chassis', '-23'),
      'New chassis · ID pending sync',
    );
    expect(OfflineQueueItem.record('bookings', '107'), 'Booking 107');
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
        hasError: true,
        errorMessage: 'permission-denied',
        nextRetryAt: DateTime(2026, 9, 19, 10, 50),
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
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text('Create booking'), findsOneWidget);
      expect(find.text('New booking · ID pending sync'), findsOneWidget);
      expect(
        find.textContaining(
          'Waiting to retry\npermission-denied\nNext retry after',
        ),
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
