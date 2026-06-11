import 'package:flutter/material.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';

class AppPageLoadingOverlay extends StatelessWidget {
  const AppPageLoadingOverlay({
    super.key,
    required this.child,
    required this.isVisible,
    this.message = 'Loading, please wait ...',
    this.padding = const EdgeInsets.all(24),
    this.opacity = 0.72,
  });

  final Widget child;
  final bool isVisible;
  final String message;
  final EdgeInsets padding;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedWidth = constraints.hasBoundedWidth;
        final hasBoundedHeight = constraints.hasBoundedHeight;
        final overlayChild = Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(ignoring: isVisible, child: child),
            if (isVisible)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: opacity),
                  child: AppPageLoading(
                    message: message,
                    compact: true,
                    padding: padding,
                  ),
                ),
              ),
          ],
        );

        if (!hasBoundedWidth || !hasBoundedHeight) {
          return overlayChild;
        }

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: overlayChild,
        );
      },
    );
  }
}
