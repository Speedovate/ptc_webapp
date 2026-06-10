import 'package:flutter/services.dart';

class NameCaseTextInputFormatter extends TextInputFormatter {
  const NameCaseTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) {
      return newValue;
    }

    final transformed = _toTitleCase(text);
    final offset = newValue.selection.baseOffset.clamp(0, transformed.length);

    return TextEditingValue(
      text: transformed,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }

  static String _toTitleCase(String value) {
    String capitalizeSegment(String segment) {
      if (segment.isEmpty) {
        return segment;
      }
      return '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}';
    }

    String capitalizeDelimited(String word, String delimiter) {
      return word.split(delimiter).map(capitalizeSegment).join(delimiter);
    }

    return value.splitMapJoin(
      RegExp(r'(\s+)'),
      onMatch: (match) => match.group(0) ?? '',
      onNonMatch: (word) =>
          capitalizeDelimited(capitalizeDelimited(word, '-'), "'"),
    );
  }
}
