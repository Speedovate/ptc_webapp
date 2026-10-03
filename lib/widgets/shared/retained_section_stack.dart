import 'package:flutter/material.dart';

/// Retains navigation state while limiting animation and repaint work to the
/// visible section. Hidden sections keep their data subscriptions and drafts.
class RetainedSectionStack extends StatelessWidget {
  const RetainedSectionStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: index,
    children: [
      for (var i = 0; i < children.length; i++)
        RepaintBoundary(
          key: children[i].key == null ? null : ValueKey(children[i].key),
          // Each retained page owns its selection. A shell-wide registrar also
          // includes hidden IndexedStack text at the same screen coordinates,
          // which can select an invisible page instead of the visible one.
          // Keep this wrapper stable so navigation retains drafts and scroll.
          child: TickerMode(
            enabled: i == index,
            child: SelectionArea(child: children[i]),
          ),
        ),
    ],
  );
}
