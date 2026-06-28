import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';

class SidebarMenuItem extends StatelessWidget {
  const SidebarMenuItem({
    super.key,
    required this.label,
    required this.icon,
    this.isSelected = false,
    this.isChild = false,
    this.trailing,
    this.children = const [],
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isChild;
  final Widget? trailing;
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasChildren = children.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(left: 0, bottom: hasChildren ? 8 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppMousePressable(
            onTapDownAction: () {
              final dismissedDropdown =
                  AdminDropdownMenuCoordinator.dismissActiveMenu();
              if (!dismissedDropdown) {
                onTap?.call();
                return;
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onTap?.call();
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Builder(
              builder: (context) => AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: EdgeInsets.symmetric(
                  horizontal: isChild ? 14 : 16,
                  vertical: isChild ? 12 : 14,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primarySurfaceAlt.withValues(alpha: 0.22)
                      : appPressableActive(context)
                      ? Colors.white.withValues(alpha: 0.24)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primarySurfaceAlt.withValues(alpha: 0.32)
                        : Colors.transparent,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final iconOnlyThreshold = trailing == null ? 80.0 : 140.0;
                    if (constraints.maxWidth < iconOnlyThreshold) {
                      return Center(
                        child: Icon(icon, color: Colors.white, size: 20),
                      );
                    }

                    return Row(
                      children: [
                        Icon(
                          icon,
                          color: Colors.white,
                          size: isChild ? 18 : 20,
                        ),
                        SizedBox(width: isChild ? 10 : 12),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: isChild
                                  ? FontWeight.w500
                                  : FontWeight.w600,
                              fontSize: isChild ? 14 : null,
                            ),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 10),
                          trailing!,
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (hasChildren) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
