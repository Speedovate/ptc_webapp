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

String? normalizePhilippinePhone(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final compact = trimmed.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  if (RegExp(r'^\+639\d{9}$').hasMatch(compact)) {
    return compact;
  }
  if (RegExp(r'^639\d{9}$').hasMatch(compact)) {
    return '+$compact';
  }
  if (RegExp(r'^09\d{9}$').hasMatch(compact)) {
    return '+63${compact.substring(1)}';
  }
  if (RegExp(r'^9\d{9}$').hasMatch(compact)) {
    return '+63$compact';
  }
  return null;
}

bool isValidPhilippinePhone(String? value) {
  return normalizePhilippinePhone(value) != null;
}

Uint8List? decodePhotoBytes(dynamic value, {String key = 'bytes'}) {
  if (value is Uint8List) {
    return value;
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  final mapValue = value is Map<String, dynamic>
      ? value
      : value is Map
      ? Map<String, dynamic>.from(value)
      : null;
  final sourceValue = mapValue?[key] ?? value;
  if (sourceValue is Uint8List) {
    return sourceValue;
  }
  if (sourceValue is List<int>) {
    return Uint8List.fromList(sourceValue);
  }
  return null;
}

String? photoDownloadUrl(dynamic value, {String key = 'download_url'}) {
  final mapValue = value is Map<String, dynamic>
      ? value
      : value is Map
      ? Map<String, dynamic>.from(value)
      : null;
  final url = mapValue?[key]?.toString().trim();
  if (url == null || url.isEmpty) {
    return null;
  }
  return url;
}

String? photoStoragePath(dynamic value, {String key = 'storage_path'}) {
  final mapValue = value is Map<String, dynamic>
      ? value
      : value is Map
      ? Map<String, dynamic>.from(value)
      : null;
  final path = mapValue?[key]?.toString().trim();
  if (path == null || path.isEmpty) {
    return null;
  }
  return path;
}

class PhilippinesPhoneInputFormatter extends TextInputFormatter {
  const PhilippinesPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) {
      return newValue;
    }

    final buffer = StringBuffer();
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char == '+' && buffer.isEmpty) {
        buffer.write(char);
        continue;
      }
      if (RegExp(r'\d').hasMatch(char)) {
        buffer.write(char);
      }
    }
    final transformed = buffer.toString();

    if (transformed == newValue.text) {
      return newValue;
    }

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
