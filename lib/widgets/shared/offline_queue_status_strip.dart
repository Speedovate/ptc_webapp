import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:flutter/services.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';
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
import 'package:webapp/widgets/shared/catalog_conflict_review_dialog.dart';
import 'package:webapp/services/offline_error_diagnostics.dart';

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

Future<void> showOfflineQueueItems(
  BuildContext context,
  String userId,
) => showDialog<void>(
  context: context,
  builder: (_) => OfflineQueueDialog(
    load: () => readOfflineQueueItems(userId),
    resolveConflict: (id, keepLocal) async {
      final user = await AuthRequest.instance.getCurrentUser();
      if (user?.id != userId) {
        throw StateError('The active account has changed. Reopen the queue.');
      }
      if (!RoleAccessService.instance.canAccess('sync.read')) {
        throw StateError('You do not have access to resolve sync conflicts.');
      }
      if (id.startsWith(OfflineCleanupQueueService.claimedCleanupPrefix)) {
        // A claimed cleanup resolves against the server claim, not the local
        // queue, so it never goes through the mutation queue.
        await OfflineCleanupQueueService.instance.resolveClaimedCleanup(
          id,
          keepLocal: keepLocal,
        );
        return;
      }
      if (keepLocal) {
        await OfflineMutationQueueService.instance.retryBlockedConflict(id);
      } else {
        await OfflineMutationQueueService.instance.dismissBlockedConflict(id);
      }
    },
    canResolveConflicts: () =>
        RoleAccessService.instance.canAccess('sync.read'),
    reviewConflict: (id) async {
      Future<void> checkAccess() async {
        if ((await AuthRequest.instance.getCurrentUser())?.id != userId ||
            !RoleAccessService.instance.canAccess('sync.read') ||
            !RoleAccessService.instance.canAccess(
              'operations_catalog.update',
            )) {
          throw StateError('You do not have access to apply these settings.');
        }
      }

      await checkAccess();
      final service = OfflineMutationQueueService.instance;
      final review = await service.reviewCatalogConflict(id);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => CatalogConflictReviewDialog(
          review: review,
          onApply: () async {
            await checkAccess();
            await service.applyReviewedCatalogConflict(review);
          },
        ),
      );
    },
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
    this.resolveConflict,
    this.canResolveConflicts,
    this.reviewConflict,
  });
  final Future<List<OfflineQueueItem>> Function() load;
  final Future<void> Function()? retryFailedChat;
  final Listenable? syncChanges;
  final bool Function()? isSyncing;
  final Future<void> Function(String id, bool keepLocal)? resolveConflict;
  final bool Function()? canResolveConflicts;
  final Future<void> Function(String id)? reviewConflict;
  @override
  State<OfflineQueueDialog> createState() => _OfflineQueueDialogState();
}

class _OfflineQueueDialogState extends State<OfflineQueueDialog> {
  late Future<List<OfflineQueueItem>> _items = _readItems();
  int _readGeneration = 0;
  bool _refreshScheduled = false;
  bool _hadItems = false;
  bool _resolving = false;

  Future<List<OfflineQueueItem>> _readItems() async {
    final generation = ++_readGeneration;
    final items = await widget.load();
    if (items.isNotEmpty) {
      _hadItems = true;
    }
    if (mounted && items.isEmpty && _hadItems) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            generation != _readGeneration ||
            _retrying ||
            _resolving ||
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

  static List<String> _valuesForItem(OfflineQueueItem item) => [
    item.title,
    item.recordLabel,
    AdminUsersView.formatCreatedAt(item.createdAt?.toLocal()),
    [
      item.statusLabel,
      if (item.errorMessage?.trim().isNotEmpty == true)
        item.errorMessage!.trim(),
      if (item.diagnostics?.isNotEmpty == true)
        item.diagnostics!
      else if (item.hasError || item.isBlocked)
        'Stack trace: Not captured for this older failure.',
      if (item.nextRetryAt != null)
        'Next retry after ${AdminUsersView.formatCreatedAtSingleLine(item.nextRetryAt!.toLocal())}',
    ].join('\n'),
  ];

  Future<void> _copyItems(List<OfflineQueueItem> items) async {
    const labels = ['Action', 'Record', 'DateTime', 'Status'];
    final text = [
      'Queued Actions',
      for (final item in items)
        _valuesForItem(
          item,
        ).indexed.map((entry) => '${labels[entry.$1]}: ${entry.$2}').join('\n'),
      ?_retryError,
    ].join('\n\n');
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        AppSnackbar.showSuccess(context, 'Queued actions copied.');
      }
    } catch (_) {
      if (mounted) {
        AppSnackbar.showError(
          context,
          'Could not copy. Select the text to copy manually.',
        );
      }
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
    if (_retrying) {
      return;
    }
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

  Future<void> _resolveConflict(OfflineQueueItem item, bool keepLocal) async {
    if (_resolving || widget.canResolveConflicts?.call() != true) {
      return;
    }
    setState(() {
      _resolving = true;
      _retryError = null;
    });
    try {
      if (keepLocal &&
          item.collectionKey == 'operations_catalog' &&
          widget.reviewConflict != null) {
        await widget.reviewConflict!(item.conflictId!);
      } else {
        await widget.resolveConflict!(item.conflictId!, keepLocal);
      }
    } catch (error, stack) {
      final diagnostics = await offlineErrorDiagnostics(
        error: error,
        stack: stack,
        source: 'offline_queue_status_strip.dart',
        operation: keepLocal
            ? 'review/apply queued change'
            : 'discard queued change',
        entryId: item.conflictId ?? '',
        target: item.recordLabel,
        attempt: 1,
      );
      if (mounted) {
        setState(() {
          _retryError = diagnostics;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _resolving = false;
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
                    return const SelectableText(
                      'Could not read saved actions. Please refresh to try again.',
                    );
                  }
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return const SelectableText(
                      'No queued actions for this account.',
                    );
                  }
                  return AdminModalRecordList(
                    titles: const ['Action', 'Record', 'DateTime', 'Status'],
                    wrappingColumn: 3,
                    selectableCells: true,
                    itemCount: items.length,
                    valuesAt: (index) => _valuesForItem(items[index]),
                    cellBuilder: (row, column) {
                      final item = items[row];
                      if (column != 3 ||
                          !item.isBlocked ||
                          item.conflictId == null ||
                          widget.resolveConflict == null ||
                          widget.canResolveConflicts?.call() != true) {
                        return null;
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(_valuesForItem(item)[3]),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: _resolving
                                    ? null
                                    : () => _resolveConflict(item, false),
                                child: const Text('Discard local change'),
                              ),
                              TextButton(
                                onPressed: _resolving
                                    ? null
                                    : () => _resolveConflict(item, true),
                                child: Text(
                                  item.collectionKey == 'operations_catalog'
                                      ? 'Compare changes'
                                      : 'Keep local change',
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
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
            if (_retrying) const SelectableText('Syncing queued chat…'),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.end,
              children: [
                FutureBuilder<List<OfflineQueueItem>>(
                  future: _items,
                  builder: (context, snapshot) => TextButton.icon(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy'),
                    onPressed:
                        snapshot.connectionState == ConnectionState.done &&
                            !snapshot.hasError &&
                            (snapshot.data?.isNotEmpty ?? false)
                        ? () => _copyItems(snapshot.data!)
                        : null,
                  ),
                ),
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
          ],
        ),
      ),
    ),
  );
}
