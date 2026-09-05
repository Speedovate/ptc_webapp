import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/services/offline_sync_status_service.dart';

class AppSyncStatusBanner extends StatelessWidget {
  const AppSyncStatusBanner({super.key, required this.child, this.currentUser});

  final Widget child;
  final UserModel? currentUser;

  @override
  Widget build(BuildContext context) {
    // Authenticated platform shells render sync state in their sidebar footer,
    // replacing Install instead of overlaying another bottom control.
    if (currentUser != null) {
      return child;
    }
    final service = OfflineSyncStatusService.instance;
    final canReadSync = currentUser == null
        ? true
        : RoleAccessService.instance.canAccess(
            'sync.read',
            role: currentUser?.role,
          );
    if (!canReadSync) {
      return child;
    }
    final usesAdminShell = RoleAccessService.instance.usesAdminShell(
      role: currentUser?.role,
    );
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final primarySnapshot = usesAdminShell
            ? service.knownSessionSnapshot
            : service.snapshot;
        final fallbackSnapshot = service.snapshot;
        final snapshot =
            usesAdminShell &&
                !_shouldShowBannerFor(primarySnapshot) &&
                _shouldShowBannerFor(fallbackSnapshot)
            ? fallbackSnapshot
            : primarySnapshot;
        final showBanner = _shouldShowBannerFor(snapshot);
        final anchorToSidebarBottom = usesAdminShell;
        final safePadding = MediaQuery.paddingOf(context);
        // Match the login/register card: 24px gutters and a 460px max width.
        final authCardWidth = (MediaQuery.sizeOf(context).width - 48).clamp(
          0.0,
          460.0,
        );
        return Stack(
          children: [
            child,
            IgnorePointer(
              ignoring: !showBanner,
              child: SafeArea(
                child: Align(
                  alignment: anchorToSidebarBottom
                      ? Alignment.bottomLeft
                      : Alignment.bottomCenter,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    offset: showBanner
                        ? Offset.zero
                        : anchorToSidebarBottom
                        ? const Offset(-0.12, 1.2)
                        : const Offset(0, 1.2),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: showBanner ? 1 : 0,
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: 16 + safePadding.bottom,
                        ),
                        child: SizedBox(
                          width: anchorToSidebarBottom ? 248 : authCardWidth,
                          child: _SyncStatusPill(
                            snapshot: snapshot,
                            currentUser: currentUser,
                            maxWidth: anchorToSidebarBottom
                                ? 248
                                : authCardWidth,
                          ),
                        ),
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

  bool _shouldShowBannerFor(OfflineSyncStatusSnapshot snapshot) {
    return !snapshot.isOnline ||
        snapshot.hasFailedActions ||
        snapshot.hasPendingActions ||
        snapshot.isSyncing;
  }
}

class _SyncStatusPill extends StatelessWidget {
  const _SyncStatusPill({
    required this.snapshot,
    required this.currentUser,
    required this.maxWidth,
  });

  final OfflineSyncStatusSnapshot snapshot;
  final UserModel? currentUser;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compactSidebarBanner = RoleAccessService.instance.usesAdminShell(
      role: currentUser?.role,
    );
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
          ? snapshot.processedActions == 0
                ? 'Syncing ${snapshot.totalActionsInBatch} action${snapshot.totalActionsInBatch == 1 ? '' : 's'}'
                : 'Syncing ${snapshot.processedActions}/${snapshot.totalActionsInBatch}'
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
      constraints: BoxConstraints(maxWidth: maxWidth),
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
                      style:
                          (compactSidebarBanner
                                  ? theme.textTheme.bodyMedium
                                  : theme.textTheme.bodyLarge)
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                    ),
                    if (!compactSidebarBanner) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textColor.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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

  Future<void> _showConflictReviewSheet(BuildContext context) =>
      showOfflineConflictReviewSheet(context);
}

Future<void> showOfflineConflictReviewSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _ConflictReviewSheet(),
  );
}

class _ConflictReviewSheet extends StatefulWidget {
  const _ConflictReviewSheet();

  @override
  State<_ConflictReviewSheet> createState() => _ConflictReviewSheetState();
}

class _ConflictReviewSheetState extends State<_ConflictReviewSheet> {
  late Future<List<OfflineMutationConflictRecord>> _future;
  bool _isApplying = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<OfflineMutationConflictRecord>> _load() {
    return OfflineMutationQueueService.instance.getBlockedConflicts();
  }

  Future<List<OfflineMutationConflictRecord>> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    return next;
  }

  Future<void> _retry(String id) async {
    setState(() {
      _isApplying = true;
      _actionError = null;
    });
    try {
      await OfflineMutationQueueService.instance.retryBlockedConflict(id);
      final remaining = await _refresh();
      if (mounted && remaining.isEmpty) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _actionError = 'We could not update this offline action. Try again.';
        });
      }
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
      _actionError = null;
    });
    try {
      await OfflineMutationQueueService.instance.dismissBlockedConflict(id);
      final remaining = await _refresh();
      if (mounted && remaining.isEmpty) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _actionError = 'We could not discard this offline action. Try again.';
        });
      }
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
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
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
                              : () => Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_actionError != null) ...[
                      Text(
                        _actionError!,
                        style: const TextStyle(
                          color: AppColors.dangerStrong,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Flexible(
                      child: FutureBuilder<List<OfflineMutationConflictRecord>>(
                        future: _future,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
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
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
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
    final presentation = _syncActionPresentation(conflict);
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
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  presentation.icon,
                  color: AppColors.dangerStrong,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      presentation.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      presentation.recordLabel,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'A newer version was found online. Choose which change to keep.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isBusy ? null : onDismiss,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerStrong,
                    side: const BorderSide(color: AppColors.dangerBorderAlt),
                  ),
                  child: isBusy
                      ? const _SyncActionProgress()
                      : const Text('Discard local change'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: isBusy ? null : onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: isBusy
                      ? const _SyncActionProgress()
                      : const Text('Keep local change'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncActionProgress extends StatelessWidget {
  const _SyncActionProgress();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2.2),
    );
  }
}

class _SyncActionPresentation {
  const _SyncActionPresentation({
    required this.title,
    required this.recordLabel,
    required this.icon,
  });

  final String title;
  final String recordLabel;
  final IconData icon;
}

_SyncActionPresentation _syncActionPresentation(
  OfflineMutationConflictRecord conflict,
) {
  final collection = _syncCollectionLabel(conflict.collectionKey);
  final recordLabel = conflict.targetId.trim().isEmpty
      ? '$collection record'
      : '$collection #${conflict.targetId}';

  switch (conflict.kind) {
    case 'userUpsert':
      return _SyncActionPresentation(
        title: 'Update user profile',
        recordLabel: recordLabel,
        icon: Icons.person_outline_rounded,
      );
    case 'userDelete':
      return _SyncActionPresentation(
        title: 'Remove user',
        recordLabel: recordLabel,
        icon: Icons.person_remove_outlined,
      );
    case 'bookingBillingStatusUpdate':
      return _SyncActionPresentation(
        title: 'Update booking billing',
        recordLabel: recordLabel,
        icon: Icons.receipt_long_outlined,
      );
    case 'supportThreadReadMarkerUpsert':
      return _SyncActionPresentation(
        title: 'Mark support conversation read',
        recordLabel: 'Support conversation',
        icon: Icons.mark_chat_read_outlined,
      );
    case 'bookingCreate':
      return _SyncActionPresentation(
        title: 'Create booking',
        recordLabel: recordLabel,
        icon: Icons.add_task_outlined,
      );
    case 'chassisAssignment':
      return _SyncActionPresentation(
        title: 'Update chassis assignment',
        recordLabel: recordLabel,
        icon: Icons.rv_hookup_outlined,
      );
    case 'chassisDelete':
      return _SyncActionPresentation(
        title: 'Remove chassis',
        recordLabel: recordLabel,
        icon: Icons.delete_outline_rounded,
      );
    case 'collectionDocumentCreate':
      return _SyncActionPresentation(
        title: 'Create $collection',
        recordLabel: recordLabel,
        icon: Icons.add_circle_outline_rounded,
      );
    case 'collectionDocumentDelete':
      return _SyncActionPresentation(
        title: 'Remove $collection',
        recordLabel: recordLabel,
        icon: Icons.delete_outline_rounded,
      );
    case 'collectionDocumentUpsert':
    default:
      return _SyncActionPresentation(
        title: 'Update $collection',
        recordLabel: recordLabel,
        icon: Icons.edit_outlined,
      );
  }
}

String _syncCollectionLabel(String? collectionKey) {
  switch (collectionKey?.trim()) {
    case 'users':
      return 'User';
    case 'bookings':
      return 'Booking';
    case 'chassis':
      return 'Chassis';
    case 'vehicle_makes':
      return 'Vehicle make';
    case 'vehicle_types':
      return 'Vehicle type';
    case 'vehicle_sizes':
      return 'Vehicle size';
    case 'statuses':
      return 'Status';
    case 'status_forms':
      return 'Flow form';
    case 'status_fields':
      return 'Flow field';
    case 'role_access':
      return 'Role permission';
    default:
      return 'Record';
  }
}
