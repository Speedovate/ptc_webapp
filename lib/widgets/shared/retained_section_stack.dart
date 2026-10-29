import 'package:webapp/widgets/shared/app_selection_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Retains drafts and subscriptions, while only laying out and painting the
/// selected page in a bounded viewport. Unbounded hosts keep normal sizing.
class RetainedSectionStack extends StatelessWidget {
  const RetainedSectionStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final pages = [
      for (var i = 0; i < children.length; i++)
        RepaintBoundary(
          key: children[i].key == null ? null : ValueKey(children[i].key),
          child: ExcludeFocus(
            excluding: i != index,
            child: TickerMode(
              enabled: i == index,
              // Keep a separate selection registrar per page so hidden text
              // cannot participate in the visible page's text selection.
              child: AppSelectionArea(child: children[i]),
            ),
          ),
        ),
    ];
    return _ViewportIndexedStack(index: index, children: pages);
  }
}

class _ViewportIndexedStack extends Stack {
  const _ViewportIndexedStack({required this.index, required super.children});
  final int index;

  @override
  RenderIndexedStack createRenderObject(BuildContext context) =>
      _RenderViewportIndexedStack(
        index: index,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderIndexedStack renderObject,
  ) {
    renderObject
      ..index = index
      ..textDirection = Directionality.of(context);
  }
}

class _RenderViewportIndexedStack extends RenderIndexedStack {
  _RenderViewportIndexedStack({
    required super.index,
    required super.textDirection,
  });

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.hasBoundedWidth && constraints.hasBoundedHeight
      ? constraints.biggest
      : super.computeDryLayout(constraints);

  @override
  void performLayout() {
    if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
      super.performLayout();
      return;
    }
    // The viewport determines size. Hidden children need no geometry until
    // selected, even after a window/keyboard resize or a background data update.
    size = constraints.biggest;
    var child = firstChild;
    for (var i = 0; child != null && i < (index ?? 0); i++) {
      child = childAfter(child);
    }
    if (child == null) return;
    final data = child.parentData! as StackParentData;
    if (data.isPositioned) {
      super.performLayout();
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    data.offset = AlignmentDirectional.topStart
        .resolve(textDirection)
        .alongOffset(
          Offset(
            size.width - child.size.width,
            size.height - child.size.height,
          ),
        );
  }
}
