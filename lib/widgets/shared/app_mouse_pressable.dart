import 'package:flutter/material.dart';

class AppMousePressable extends StatefulWidget {
  const AppMousePressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.behavior = HitTestBehavior.deferToChild,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final HitTestBehavior behavior;
  final MouseCursor cursor;

  @override
  State<AppMousePressable> createState() => _AppMousePressableState();
}

class _AppMousePressableState extends State<AppMousePressable> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final hasAction = widget.onTap != null;
    return MouseRegion(
      cursor: hasAction ? widget.cursor : MouseCursor.defer,
      onEnter: hasAction ? (_) => setState(() => _isHovered = true) : null,
      onExit: hasAction
          ? (_) => setState(() {
              _isHovered = false;
              _isPressed = false;
            })
          : null,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: hasAction ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: hasAction ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: hasAction
            ? () => setState(() => _isPressed = false)
            : null,
        onTap: widget.onTap,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          descendantsAreFocusable: false,
          child: _PressableScope(
            isHovered: _isHovered,
            isPressed: _isPressed,
            borderRadius: widget.borderRadius,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _PressableScope extends InheritedWidget {
  const _PressableScope({
    required this.isHovered,
    required this.isPressed,
    required this.borderRadius,
    required super.child,
  });

  final bool isHovered;
  final bool isPressed;
  final BorderRadius? borderRadius;

  static _PressableScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_PressableScope>();
  }

  @override
  bool updateShouldNotify(_PressableScope oldWidget) {
    return isHovered != oldWidget.isHovered ||
        isPressed != oldWidget.isPressed ||
        borderRadius != oldWidget.borderRadius;
  }
}

bool appPressableHovered(BuildContext context) =>
    _PressableScope.maybeOf(context)?.isHovered ?? false;

bool appPressablePressed(BuildContext context) =>
    _PressableScope.maybeOf(context)?.isPressed ?? false;

bool appPressableActive(BuildContext context) {
  final scope = _PressableScope.maybeOf(context);
  return (scope?.isHovered ?? false) || (scope?.isPressed ?? false);
}
