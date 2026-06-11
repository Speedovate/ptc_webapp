import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/app_version_service.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/collapsible_sidebar.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/app_profile_avatar.dart';

class PlatformShell extends StatelessWidget {
  const PlatformShell({
    super.key,
    required this.scaffoldKey,
    required this.user,
    required this.title,
    required this.sidebar,
    required this.body,
    required this.isCompact,
    required this.showRail,
    required this.onToggleNavigation,
    required this.onProfile,
    required this.onLogout,
    this.logoutLabel = 'Logout',
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final UserModel user;
  final String title;
  final Widget sidebar;
  final Widget body;
  final bool isCompact;
  final bool showRail;
  final VoidCallback onToggleNavigation;
  final VoidCallback onProfile;
  final VoidCallback onLogout;
  final String logoutLabel;

  static const double sidebarHeaderHeight = 72;

  @override
  Widget build(BuildContext context) {
    final expandMainContent = isCompact || !showRail;

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: AppColors.primarySurface,
      body: SafeArea(
        child: Row(
          children: [
            CollapsibleSidebar(
              isVisible: showRail,
              width: 280,
              color: AppColors.primaryColor,
              child: sidebar,
            ),
            Expanded(
              child: Padding(
                padding: expandMainContent
                    ? EdgeInsets.zero
                    : const EdgeInsets.fromLTRB(20, 28, 20, 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primarySurfaceAlt,
                    borderRadius: BorderRadius.circular(
                      expandMainContent ? 0 : 32,
                    ),
                    boxShadow: expandMainContent
                        ? null
                        : const [
                            BoxShadow(
                              color: Color(0x120E0A1F),
                              blurRadius: 30,
                              offset: Offset(0, 16),
                            ),
                          ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      expandMainContent ? 0 : 32,
                    ),
                    child: Scaffold(
                      backgroundColor: Colors.white,
                      appBar: PreferredSize(
                        preferredSize: const Size.fromHeight(
                          PlatformShell.sidebarHeaderHeight,
                        ),
                        child: PlatformAppBar(
                          title: title,
                          user: user,
                          isCompact: isCompact,
                          onMenuPressed: () {
                            if (isCompact) {
                              scaffoldKey.currentState?.openDrawer();
                              return;
                            }
                            onToggleNavigation();
                          },
                          onProfile: onProfile,
                          onLogout: onLogout,
                          logoutLabel: logoutLabel,
                        ),
                      ),
                      body: body,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      drawer: isCompact ? Drawer(width: 250, child: sidebar) : null,
    );
  }
}

class PlatformAppBar extends StatelessWidget {
  const PlatformAppBar({
    super.key,
    required this.title,
    required this.user,
    required this.isCompact,
    required this.onMenuPressed,
    required this.onProfile,
    required this.onLogout,
    required this.logoutLabel,
  });

  final String title;
  final UserModel user;
  final bool isCompact;
  final VoidCallback onMenuPressed;
  final VoidCallback onProfile;
  final VoidCallback onLogout;
  final String logoutLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: PlatformShell.sidebarHeaderHeight,
      padding: const EdgeInsets.fromLTRB(16, 14, 20, 14),
      decoration: const BoxDecoration(color: AppColors.primaryColor),
      child: Row(
        children: [
          AppMousePressable(
            borderRadius: BorderRadius.circular(16),
            onTap: onMenuPressed,
            child: Builder(
              builder: (context) => AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: appPressableActive(context)
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.white12,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.menu_rounded, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          PlatformProfileChip(
            user: user,
            compact: isCompact,
            onProfile: onProfile,
            onLogout: onLogout,
            logoutLabel: logoutLabel,
          ),
        ],
      ),
    );
  }
}

class PlatformSidebarContainer extends StatelessWidget {
  const PlatformSidebarContainer({
    super.key,
    required this.onBrandTap,
    required this.children,
  });

  final VoidCallback onBrandTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryColor,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlatformSidebarBrandTile(onTap: onBrandTap),
          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlatformSidebarBrandTile extends StatelessWidget {
  const PlatformSidebarBrandTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppMousePressable(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Builder(
        builder: (context) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: PlatformShell.sidebarHeaderHeight,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: appPressableActive(context)
                ? AppColors.primarySurfaceAlt.withValues(alpha: 0.32)
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 120) {
                return const Center(
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryColor,
                    child: Icon(
                      Icons.local_shipping_rounded,
                      color: Colors.white,
                    ),
                  ),
                );
              }

              return Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryColor,
                    child: Icon(
                      Icons.local_shipping_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Paltranco',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.primaryColor,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        FutureBuilder<String>(
                          future: AppVersionService.sidebarVersionLabel,
                          builder: (context, snapshot) {
                            final versionLabel =
                                snapshot.data ?? 'Version 1.0.0 (1)';
                            return Text(
                              versionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.primaryColor,
                                fontSize: 12,
                                height: 1.2,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class PlatformProfileChip extends StatelessWidget {
  const PlatformProfileChip({
    super.key,
    required this.user,
    required this.onProfile,
    required this.onLogout,
    required this.logoutLabel,
    this.compact = false,
  });

  final UserModel user;
  final VoidCallback onProfile;
  final VoidCallback onLogout;
  final String logoutLabel;
  final bool compact;

  double _measureTextWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();

    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    const nameStyle = TextStyle(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    const emailStyle = adminDropdownDisplayTextStyle;
    const profileStyle = TextStyle(
      color: AppColors.primaryColor,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    const logoutStyle = TextStyle(
      color: Color(0xFFD94B4B),
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    const dropdownHorizontalPadding = 20.0;
    const dropdownRightShift = 9.0;
    const dropdownRightGap = 0.0;
    final popupMaxWidth = (MediaQuery.sizeOf(context).width - 48).clamp(
      0.0,
      360.0,
    );
    final popupContentMaxWidth = (popupMaxWidth - dropdownRightGap).clamp(
      0.0,
      popupMaxWidth,
    );

    final displayName = user.name?.trim().isNotEmpty == true ? user.name! : '-';
    final displayRole = formatPlatformRole(user.role).trim().isNotEmpty
        ? formatPlatformRole(user.role)
        : 'User';
    final displayEmail = user.email?.trim().isNotEmpty == true
        ? user.email!
        : '-';
    final displayRoleAndName = '$displayRole | $displayName';
    final contentWidth =
        ([
                  _measureTextWidth(context, displayRoleAndName, nameStyle),
                  _measureTextWidth(context, displayEmail, emailStyle),
                  _measureTextWidth(context, 'Profile', profileStyle),
                  _measureTextWidth(context, logoutLabel, logoutStyle),
                ].reduce((a, b) => a > b ? a : b) +
                (dropdownHorizontalPadding * 2) +
                6)
            .clamp(0.0, popupContentMaxWidth);

    return PopupMenuButton<void>(
      tooltip: '',
      offset: const Offset(0, 56),
      constraints: BoxConstraints(minWidth: 0, maxWidth: popupMaxWidth),
      menuPadding: EdgeInsets.zero,
      clipBehavior: Clip.none,
      elevation: 0,
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          height: 0,
          padding: EdgeInsets.zero,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(right: dropdownRightGap),
              child: Transform.translate(
                offset: const Offset(dropdownRightShift, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.primaryBorder),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            dropdownHorizontalPadding,
                            16,
                            dropdownHorizontalPadding,
                            0,
                          ),
                          child: Text(
                            displayRoleAndName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nameStyle,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            dropdownHorizontalPadding,
                            0,
                            dropdownHorizontalPadding,
                            16,
                          ),
                          child: Text(
                            displayEmail,
                            softWrap: false,
                            style: emailStyle,
                          ),
                        ),
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: AppColors.primaryBorder,
                        ),
                        PlatformProfileDropdownActionRow(
                          onTap: () {
                            Navigator.of(context).pop();
                            onProfile();
                          },
                          child: const Padding(
                            padding: EdgeInsets.fromLTRB(
                              dropdownHorizontalPadding,
                              16,
                              dropdownHorizontalPadding,
                              16,
                            ),
                            child: Text('Profile', style: profileStyle),
                          ),
                        ),
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: AppColors.primaryBorder,
                        ),
                        PlatformProfileDropdownActionRow(
                          onTap: () {
                            Navigator.of(context).pop();
                            onLogout();
                          },
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(18),
                            bottomRight: Radius.circular(18),
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              dropdownHorizontalPadding,
                              16,
                              dropdownHorizontalPadding,
                              16,
                            ),
                            child: Text(logoutLabel, style: logoutStyle),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!compact) ...[
              Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    user.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    formatPlatformRole(user.role),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primarySurfaceAlt,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
            ],
            AppProfileAvatar(
              photo: user.photo,
              fallbackText: platformInitials(user.name),
              radius: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class PlatformProfileDropdownActionRow extends StatefulWidget {
  const PlatformProfileDropdownActionRow({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.behavior = HitTestBehavior.opaque,
  });

  final VoidCallback onTap;
  final Widget child;
  final BorderRadius borderRadius;
  final HitTestBehavior behavior;

  @override
  State<PlatformProfileDropdownActionRow> createState() =>
      _PlatformProfileDropdownActionRowState();
}

class _PlatformProfileDropdownActionRowState
    extends State<PlatformProfileDropdownActionRow> {
  final ValueNotifier<bool> _isHovered = ValueNotifier(false);
  final ValueNotifier<bool> _isPressed = ValueNotifier(false);

  @override
  void dispose() {
    _isHovered.dispose();
    _isPressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) {
        _isHovered.value = false;
        _isPressed.value = false;
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: _isHovered,
        builder: (context, isHovered, _) {
          return ValueListenableBuilder<bool>(
            valueListenable: _isPressed,
            builder: (context, isPressed, _) {
              final backgroundColor = isPressed
                  ? AppColors.primarySurfaceAlt.withValues(alpha: 0.38)
                  : isHovered
                  ? AppColors.primarySurfaceAlt.withValues(alpha: 0.22)
                  : Colors.transparent;

              return GestureDetector(
                behavior: widget.behavior,
                onTapDown: (_) => _isPressed.value = true,
                onTapUp: (_) => _isPressed.value = false,
                onTapCancel: () => _isPressed.value = false,
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: widget.borderRadius,
                  ),
                  child: widget.child,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String formatPlatformRole(String? role) {
  if (role == null || role.isEmpty) {
    return '';
  }

  return role
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String platformInitials(String? value) {
  if (value == null || value.isEmpty) {
    return '';
  }

  final parts = value
      .split(' ')
      .where((part) => part.trim().isNotEmpty)
      .take(2)
      .toList();

  if (parts.isEmpty) {
    return '';
  }

  return parts.map((part) => part[0].toUpperCase()).join();
}
