import 'package:webapp/views/admin/admin_users.dart';
import 'package:webapp/widgets/shared/admin_modal_record_list.dart';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
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
      builder: (_) => OfflineQueueDialog(
        load: () => readOfflineQueueItems(userId),
        syncChanges: OfflineSyncStatusService.instance,
        isSyncing: () => OfflineSyncStatusService.instance.snapshot.isSyncing,
        retryFailedChat: () => OfflineMediaSyncService.instance
            .retryFailedSupportMessagesOnOpen(userId),
      ),
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
    if (!snapshot.hasPendingActions && !snapshot.hasFailedActions) {
      return const SizedBox.shrink();
    }
    final pending = snapshot.pendingActions;
    final title = !snapshot.isOnline
        ? 'Offline · $pending queued action${pending == 1 ? '' : 's'}'
        : snapshot.isSyncing
        ? 'Syncing saved actions'
        : '$pending actions waiting to sync';
    return Material(
      color: AppColors.primarySurfaceAlt,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                message: snapshot.hasFailedActions
                    ? '${snapshot.failedActions} action(s) need attention. Open the queue for details.'
                    : 'Saved changes stay on this device until they can sync.',
                child: Text(
                  snapshot.hasFailedActions
                      ? '$title · ${snapshot.failedActions} need attention'
                      : title,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onView,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryColor,
              ),
              child: const Text('View'),
            ),
          ],
        ),
      ),
    );
  }
}

class OfflineQueueDialog extends StatefulWidget {
  const OfflineQueueDialog({
    super.key,
    required this.load,
    this.retryFailedChat,
    this.syncChanges,
    this.isSyncing,
  });
  final Future<List<OfflineQueueItem>> Function() load;
  final Future<void> Function()? retryFailedChat;
  final Listenable? syncChanges;
  final bool Function()? isSyncing;
  @override
  State<OfflineQueueDialog> createState() => _OfflineQueueDialogState();
}

class _OfflineQueueDialogState extends State<OfflineQueueDialog> {
  late Future<List<OfflineQueueItem>> _items = _readItems();
  int _readGeneration = 0;
  bool _refreshScheduled = false;

  Future<List<OfflineQueueItem>> _readItems() async {
    final generation = ++_readGeneration;
    final items = await widget.load();
    if (mounted && items.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _readGeneration ||
            _retrying ||
            widget.isSyncing?.call() == true) {
          return;
        }
        final route = ModalRoute.of(context);
        if (route?.isCurrent == true && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
    return items;
  }

  void _onSyncChanged() {
    if (!mounted ||
        _refreshScheduled ||
        _retrying ||
        widget.isSyncing?.call() == true) {
      return;
    }
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (mounted) {
        setState(() {
          _items = _readItems();
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.syncChanges?.removeListener(_onSyncChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OfflineQueueDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncChanges != widget.syncChanges) {
      oldWidget.syncChanges?.removeListener(_onSyncChanged);
      widget.syncChanges?.addListener(_onSyncChanged);
    }
  }

  bool _retrying = false;
  String? _retryError;
  @override
  void initState() {
    super.initState();
    widget.syncChanges?.addListener(_onSyncChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.retryFailedChat != null) {
        _retryChat();
      }
    });
  }

  Future<void> _retryChat() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _retryError = null;
    });
    try {
      await widget.retryFailedChat!();
    } catch (error) {
      if (mounted) {
        setState(() {
          _retryError = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _retrying = false;
          _items = _readItems();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 960, maxHeight: 600),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: SelectableText(
                    'Queued Actions',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
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
                  return AdminModalRecordList(
                    titles: const ['Action', 'Record', 'DateTime', 'Status'],
                    wrappingColumn: 3,
                    selectableCells: true,
                    itemCount: items.length,
                    valuesAt: (index) {
                      final item = items[index];
                      final date = AdminUsersView.formatCreatedAt(
                        item.createdAt?.toLocal(),
                      );
                      return [
                        item.title,
                        item.recordLabel,
                        date,
                        [
                          item.statusLabel,
                          if (item.errorMessage?.trim().isNotEmpty == true)
                            item.errorMessage!.trim(),
                          if (item.nextRetryAt != null)
                            'Next retry after ${AdminUsersView.formatCreatedAtSingleLine(item.nextRetryAt!.toLocal())}',
                        ].join('\n'),
                      ];
                    },
                  );
                },
              ),
            ),
            if (_retryError != null)
              SelectableText(
                _retryError!,
                style: const TextStyle(color: AppColors.danger),
              ),
            if (_retrying) const Text('Syncing queued chat…'),
            TextButton(
              onPressed: _retrying
                  ? null
                  : () => setState(() {
                      _items = _readItems();
                    }),
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    ),
  );
}
