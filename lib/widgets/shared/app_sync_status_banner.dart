import 'package:webapp/widgets/shared/offline_queue_status_strip.dart';
import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
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
      subtitle = 'Some saved actions could not sync. Review the details.';
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
      showOfflineConflictReviewSheet(context, userId: currentUser?.id);
}

Future<void> showOfflineConflictReviewSheet(
  BuildContext context, {
  String? userId,
}) async {
  final accountId = userId ?? (await AuthRequest.instance.getCurrentUser())?.id;
  if (!context.mounted || accountId == null || accountId.trim().isEmpty) {
    return;
  }
  await showOfflineQueueItems(context, accountId);
}
