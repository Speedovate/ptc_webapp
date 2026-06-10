import 'package:flutter/material.dart';
import 'package:webapp/constants/app_colors.dart';

class CollapsibleSidebar extends StatelessWidget {
  const CollapsibleSidebar({
    super.key,
    required this.isVisible,
    this.width = 260,
    this.color = AppColors.primaryColor,
    this.child,
    this.duration = const Duration(milliseconds: 240),
  });

  final bool isVisible;
  final double width;
  final Color color;
  final Widget? child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      width: isVisible ? width : 0,
      height: MediaQuery.of(context).size.height,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: color),
      child: isVisible ? child : null,
    );
  }
}
