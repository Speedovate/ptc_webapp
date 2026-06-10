import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

Map<String, dynamic> documentData(DocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data() ?? <String, dynamic>{};
  return <String, dynamic>{
    if (!data.containsKey('id') && doc.id.trim().isNotEmpty) 'id': doc.id,
    ...data,
  };
}

String? normalizeId(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

String humanizeDropdownValue(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return '';
  }

  return normalized
      .split(RegExp(r'[_\s]+'))
      .where((part) => part.isNotEmpty)
      .map(_titleCasePart)
      .join(' ');
}

String toTitleCase(String value) {
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

    final transformed = toTitleCase(text);
    final offset = newValue.selection.baseOffset.clamp(0, transformed.length);

    return TextEditingValue(
      text: transformed,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }
}

String _titleCasePart(String part) {
  return part
      .split('-')
      .where((segment) => segment.isNotEmpty)
      .map((segment) {
        if (segment.length == 1) {
          return segment.toUpperCase();
        }
        return '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}';
      })
      .join('-');
}
