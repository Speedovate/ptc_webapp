import 'package:webapp/widgets/shared/app_selection_area.dart';
import 'package:flutter/material.dart';

/// Retains drafts and subscriptions, and paints only the selected page.
/// Flutter owns layout for every retained page, including hidden scrollbars
/// and LayoutBuilders that receive deferred background updates.
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
        Align(
          key: children[i].key == null ? null : ValueKey(children[i].key),
          alignment: AlignmentDirectional.topStart,
          child: RepaintBoundary(
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
        ),
    ];
    return IndexedStack(index: index, children: pages);
  }
}
