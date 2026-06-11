import 'package:flutter/material.dart';

class AdminIconActionButton extends StatefulWidget {
  const AdminIconActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.backgroundColor,
    this.iconColor = Colors.white,
    this.size = 38,
    this.iconSize = 18,
    this.borderRadius = 12,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color iconColor;
  final double size;
  final double iconSize;
  final double borderRadius;

  @override
  State<AdminIconActionButton> createState() => _AdminIconActionButtonState();
}

class _AdminIconActionButtonState extends State<AdminIconActionButton> {
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
              final color = isPressed
                  ? _pressColor(widget.backgroundColor)
                  : isHovered
                  ? _hoverColor(widget.backgroundColor)
                  : widget.backgroundColor;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: widget.onTap == null
                    ? null
                    : (_) => _isPressed.value = true,
                onTapUp: widget.onTap == null
                    ? null
                    : (_) => _isPressed.value = false,
                onTapCancel: widget.onTap == null
                    ? null
                    : () => _isPressed.value = false,
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                  ),
                  child: Icon(
                    widget.icon,
                    size: widget.iconSize,
                    color: widget.iconColor,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _pressColor(Color color, [double amount = 0.16]) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color _hoverColor(Color color, [double amount = 0.16]) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}
