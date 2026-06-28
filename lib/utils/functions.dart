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

String normalizeRoleKey(String? value) {
  final normalized = (value ?? '').trim().toLowerCase().replaceAll('_', '-');
  return normalized;
}

bool isPrimaryClientRole(String? role) {
  return normalizeRoleKey(role) == 'client';
}

bool isSubClientRole(String? role) {
  return normalizeRoleKey(role) == 'sub-client';
}

bool isClientScopedRole(String? role) {
  return isPrimaryClientRole(role) || isSubClientRole(role);
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

String userFacingErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is FirebaseException) {
    final mapped = _firebaseErrorMessage(error.code, fallback: fallback);
    if (mapped != null) {
      return mapped;
    }
    final fromMessage = normalizeUserErrorText(error.message, fallback: '');
    if (fromMessage.isNotEmpty) {
      return fromMessage;
    }
    return fallback;
  }

  if (error is PlatformException) {
    final mapped = _firebaseErrorMessage(error.code, fallback: fallback);
    if (mapped != null) {
      return mapped;
    }
    return normalizeUserErrorText(
      error.message ?? error.code,
      fallback: fallback,
    );
  }

  return normalizeUserErrorText(error.toString(), fallback: fallback);
}

String normalizeUserErrorText(
  String? rawMessage, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  final text = (rawMessage ?? '').trim();
  if (text.isEmpty) {
    return fallback;
  }

  final normalized = text
      .replaceFirst(
        RegExp(r'^(Exception|Error|StateError|AuthFailure):\s*'),
        '',
      )
      .replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '')
      .trim();
  if (normalized.isEmpty) {
    return fallback;
  }

  final lower = normalized.toLowerCase();
  final mapped = _firebaseErrorMessage(lower, fallback: fallback);
  if (mapped != null) {
    return mapped;
  }

  if (_looksTechnical(lower)) {
    return fallback;
  }

  return _sentenceCase(normalized);
}

String _sentenceCase(String value) {
  if (value.isEmpty) {
    return value;
  }
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

bool _looksTechnical(String value) {
  return value.contains("type '") ||
      value.contains('stack trace') ||
      value.contains('null check operator used on a null value') ||
      value.contains('instance of') ||
      value.contains('dart') ||
      value.contains('firebaseexception') ||
      value.contains('platformexception');
}

String? _firebaseErrorMessage(
  String codeOrMessage, {
  required String fallback,
}) {
  final normalized = codeOrMessage.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }

  if (normalized.contains('permission-denied') ||
      normalized.contains('storage/unauthorized') ||
      normalized.contains('unauthorized')) {
    return 'You do not have permission to do that right now.';
  }
  if (normalized.contains('unauthenticated')) {
    return 'Please sign in again and try again.';
  }
  if (normalized.contains('network-request-failed') ||
      normalized.contains('network error')) {
    return 'Please check your internet connection and try again.';
  }
  if (normalized.contains('unavailable')) {
    return 'Service is temporarily unavailable. Please try again.';
  }
  if (normalized.contains('deadline-exceeded')) {
    return 'The request took too long. Please try again.';
  }
  if (normalized.contains('not-found') ||
      normalized.contains('object-not-found')) {
    return 'The requested item could not be found anymore.';
  }
  if (normalized.contains('already-exists')) {
    return 'That item already exists.';
  }
  if (normalized.contains('invalid-argument') ||
      normalized.contains('invalid value')) {
    return 'Some information is invalid. Please review and try again.';
  }
  if (normalized.contains('failed-precondition')) {
    return 'This action cannot be completed right now.';
  }
  if (normalized.contains('aborted') || normalized.contains('cancelled')) {
    return 'This action could not be completed. Please try again.';
  }
  if (normalized.contains('resource-exhausted') ||
      normalized.contains('quota-exceeded')) {
    return 'Service is busy right now. Please try again later.';
  }
  if (normalized.contains('storage/unknown') ||
      normalized.contains('unknown error occurred') ||
      normalized.contains('internal')) {
    return fallback;
  }

  return null;
}
