import 'package:flutter/material.dart';

class AppRefreshStrip extends StatelessWidget {
  const AppRefreshStrip({
    super.key,
    required this.isVisible,
    this.padding = const EdgeInsets.only(bottom: 14),
    this.height = 3,
  });

  final bool isVisible;
  final EdgeInsetsGeometry padding;
  final double height;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
