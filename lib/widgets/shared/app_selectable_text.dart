import 'package:flutter/material.dart';

/// Selectable display text without EditableText's internal scrolling or caret.
class AppSelectableText extends StatelessWidget {
  const AppSelectableText(this.data, {super.key, this.style, this.textAlign});

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final text = Text(data, style: style, textAlign: textAlign);
    // Reuse page/dialog selection so a drag can span adjacent display text.
    return SelectionContainer.maybeOf(context) == null
        ? SelectionArea(child: text)
        : text;
  }
}
