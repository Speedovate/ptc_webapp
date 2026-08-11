import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_sync_status_service.dart';

class AppSyncStatusBanner extends StatelessWidget {
  const AppSyncStatusBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final service = OfflineSyncStatusService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final snapshot = service.snapshot;
        final showBanner =
            !snapshot.isOnline ||
            snapshot.hasFailedActions ||
            snapshot.hasPendingActions ||
            snapshot.isSyncing;
        return Stack(
          children: [
            child,
            IgnorePointer(
              ignoring: !showBanner,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    offset: showBanner ? Offset.zero : const Offset(0, -1.2),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: showBanner ? 1 : 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _SyncStatusPill(snapshot: snapshot),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SyncStatusPill extends StatelessWidget {
  const _SyncStatusPill({required this.snapshot});

  final OfflineSyncStatusSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool offlineWithPending =
        !snapshot.isOnline && snapshot.pendingActions > 0;
    final bool syncing = snapshot.isSyncing;
    final bool failed = snapshot.hasFailedActions;

    final Color backgroundColor;
    final Color borderColor;
    final Color textColor;
    final IconData leadingIcon;
    final String title;
    final String subtitle;

    if (failed) {
      backgroundColor = AppColors.dangerSurfaceAlt;
      borderColor = AppColors.dangerBorderAlt;
      textColor = AppColors.dangerStrong;
      leadingIcon = Icons.error_outline_rounded;
      title =
          '${snapshot.failedActions} sync issue${snapshot.failedActions == 1 ? '' : 's'} need review';
      subtitle =
          'Some offline changes were held back to avoid overwriting newer data.';
    } else if (syncing) {
      backgroundColor = const Color(0xFFFFFAEC);
      borderColor = const Color(0xFFF4D27A);
      textColor = const Color(0xFF6D4C00);
      leadingIcon = Icons.sync_rounded;
      title = snapshot.totalActionsInBatch > 0
          ? 'Syncing ${snapshot.processedActions}/${snapshot.totalActionsInBatch}'
          : 'Syncing offline actions';
      subtitle = 'Your queued changes are uploading in the background.';
    } else if (offlineWithPending) {
      backgroundColor = const Color(0xFFFFF4E8);
      borderColor = const Color(0xFFF4B266);
      textColor = const Color(0xFF7A4300);
      leadingIcon = Icons.cloud_off_rounded;
      title =
          '${snapshot.pendingActions} unsynced action${snapshot.pendingActions == 1 ? '' : 's'}';
      subtitle = 'Offline mode. We will sync everything once internet is back.';
    } else if (!snapshot.isOnline) {
      backgroundColor = AppColors.dangerSurfaceAlt;
      borderColor = AppColors.dangerBorderAlt;
      textColor = AppColors.dangerStrong;
      leadingIcon = Icons.portable_wifi_off_rounded;
      title = 'Offline mode';
      subtitle =
          'New changes will stay on this device until connectivity returns.';
    } else {
      backgroundColor = const Color(0xFFEFFAF3);
      borderColor = const Color(0xFFB7E1C3);
      textColor = const Color(0xFF20663C);
      leadingIcon = Icons.cloud_done_rounded;
      title =
          '${snapshot.pendingActions} offline action${snapshot.pendingActions == 1 ? '' : 's'} waiting';
      subtitle = 'Internet is back. Sync will resume automatically.';
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120E0A1F),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: syncing
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(textColor),
                        ),
                      )
                    : Icon(leadingIcon, color: textColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: textColor.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (failed) ...[
                const SizedBox(width: 12),
                IgnorePointer(
                  ignoring: false,
                  child: OutlinedButton(
                    onPressed: () => _showConflictReviewSheet(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: borderColor),
                      backgroundColor: Colors.white.withValues(alpha: 0.62),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Review'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showConflictReviewSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ConflictReviewSheet(),
    );
  }
}

class _ConflictReviewSheet extends StatefulWidget {
  const _ConflictReviewSheet();

  @override
  State<_ConflictReviewSheet> createState() => _ConflictReviewSheetState();
}

class _ConflictReviewSheetState extends State<_ConflictReviewSheet> {
  late Future<List<OfflineMutationConflictRecord>> _future;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<OfflineMutationConflictRecord>> _load() {
    return OfflineMutationQueueService.instance.getBlockedConflicts();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _retry(String id) async {
    setState(() {
      _isApplying = true;
    });
    try {
      await OfflineMutationQueueService.instance.retryBlockedConflict(id);
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }

  Future<void> _dismiss(String id) async {
    setState(() {
      _isApplying = true;
    });
    try {
      await OfflineMutationQueueService.instance.dismissBlockedConflict(id);
      await _refresh();
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Sync Review',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isApplying
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'These offline changes were paused because newer remote data was detected.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: FutureBuilder<List<OfflineMutationConflictRecord>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final conflicts =
                          snapshot.data ??
                          const <OfflineMutationConflictRecord>[];
                      if (conflicts.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'No blocked sync issues right now.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: conflicts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final conflict = conflicts[index];
                          return _ConflictCard(
                            conflict: conflict,
                            isBusy: _isApplying,
                            onRetry: () => _retry(conflict.id),
                            onDismiss: () => _dismiss(conflict.id),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflict,
    required this.isBusy,
    required this.onRetry,
    required this.onDismiss,
  });

  final OfflineMutationConflictRecord conflict;
  final bool isBusy;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (conflict.collectionKey?.isNotEmpty == true) conflict.collectionKey,
      conflict.targetId,
    ].whereType<String>().join(' • ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerSurfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.dangerBorderAlt),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            conflict.kind,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (conflict.lastError?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              conflict.lastError!,
              style: const TextStyle(
                color: AppColors.dangerStrong,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: isBusy ? null : onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: isBusy ? null : onDismiss,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
