import 'package:flutter/material.dart';
import 'package:webapp/models/offline_queue_item.dart';
import 'package:webapp/services/offline_sync_status_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';

Future<List<OfflineQueueItem>> readOfflineQueueItems(String userId) async {
  final batches = await Future.wait([
    OfflineMutationQueueService.instance.readPendingItems(userId),
    OfflineMediaSyncService.instance.readPendingItems(userId),
    BookingOfflineUploadQueueService.instance.readPendingItems(userId),
    OfflineCleanupQueueService.instance.readPendingItems(userId),
  ]);
  final items = batches.expand((items) => items).toList();
  items.sort(
    (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
      a.createdAt ?? DateTime(1970),
    ),
  );
  return items;
}

Future<void> showOfflineQueueItems(BuildContext context, String userId) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          OfflineQueueDialog(load: () => readOfflineQueueItems(userId)),
    );

/// Uses the existing status notifier; queue payloads are read only on demand.
class OfflineQueueStatusStrip extends StatelessWidget {
  const OfflineQueueStatusStrip({
    super.key,
    required this.snapshot,
    required this.onView,
  });
  final OfflineSyncStatusSnapshot snapshot;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    if (snapshot.isOnline &&
        !snapshot.hasPendingActions &&
        !snapshot.hasFailedActions &&
        !snapshot.isSyncing) {
      return const SizedBox.shrink();
    }
    final pending = snapshot.pendingActions;
    final title = !snapshot.isOnline
        ? 'Offline · $pending queued action${pending == 1 ? '' : 's'}'
        : snapshot.isSyncing
        ? 'Syncing saved actions'
        : '$pending actions waiting to sync';
    return Material(
      color: const Color(0xFFFFF4E8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              snapshot.hasFailedActions
                  ? '${snapshot.failedActions} action(s) need attention. Open the queue for details.'
                  : !snapshot.isOnline
                  ? 'Saved changes stay on this device until they can sync.'
                  : 'Changes remain on this device until syncing succeeds.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onView,
                child: const Text('View queued actions'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OfflineQueueDialog extends StatefulWidget {
  const OfflineQueueDialog({super.key, required this.load});
  final Future<List<OfflineQueueItem>> Function() load;
  @override
  State<OfflineQueueDialog> createState() => _OfflineQueueDialogState();
}

class _OfflineQueueDialogState extends State<OfflineQueueDialog> {
  late Future<List<OfflineQueueItem>> _items = widget.load();
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
      child: SelectionArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Queued actions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Text(
                'Actions saved on this device for your account. Refresh to see the latest sync results.',
              ),
              const SizedBox(height: 12),
              Flexible(
                child: FutureBuilder<List<OfflineQueueItem>>(
                  future: _items,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Text(
                        'Could not read saved actions. Please refresh to try again.',
                      );
                    }
                    final items = snapshot.data ?? [];
                    if (items.isEmpty) {
                      return const Text('No queued actions for this account.');
                    }
                    return ListView.separated(
                      itemCount: items.length,
                      primary: false,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final at = item.createdAt?.toLocal();
                        final date = at == null
                            ? 'Saved time unavailable'
                            : '${MaterialLocalizations.of(context).formatMediumDate(at)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at))}';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(item.recordLabel),
                              Text(date),
                              Text(item.statusLabel),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _items = widget.load();
                }),
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
