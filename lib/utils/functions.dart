import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

Map<String, dynamic> documentData(DocumentSnapshot<Map<String, dynamic>> doc) {
  final rawData = doc.data();
  final data = <String, dynamic>{};
  if (rawData != null) {
    rawData.forEach((key, value) {
      data[key.toString()] = value;
    });
  }
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

  final normalizedRole = normalizeRoleKey(normalized);
  if (normalizedRole == 'client' &&
      (normalized.toLowerCase() == 'sub-client' ||
          normalized.toLowerCase() == 'sub_client' ||
          normalized.toLowerCase() == 'member')) {
    return 'Client';
  }

  return normalized
      .split(RegExp(r'[_\s]+'))
      .where((part) => part.isNotEmpty)
      .map(_titleCasePart)
      .join(' ');
}

String normalizeRoleKey(String? value) {
  final normalized = (value ?? '').trim().toLowerCase().replaceAll('_', '-');
  if (normalized == 'sub-client' || normalized == 'member') {
    return 'client';
  }
  return normalized;
}

bool isAdminRole(String? role) {
  return normalizeRoleKey(role) == 'admin';
}

bool isDispatcherRole(String? role) {
  final normalized = normalizeRoleKey(role);
  return normalized == 'dispatcher' || normalized == 'manager';
}

bool isBackOfficeRole(String? role) {
  return isAdminRole(role) || isDispatcherRole(role);
}

String effectiveBackOfficeRoleKey(String? role) {
  return isDispatcherRole(role) ? 'admin' : normalizeRoleKey(role);
}

bool isPrimaryClientRole(String? role) {
  return normalizeRoleKey(role) == 'client';
}

bool isSubClientRole(String? role) {
  return false;
}

bool isClientScopedRole(String? role) {
  return isPrimaryClientRole(role);
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
  final downloadUrl = mapValue?['download_url']?.toString().trim();
  if (downloadUrl != null && downloadUrl.startsWith('data:')) {
    final commaIndex = downloadUrl.indexOf(',');
    if (commaIndex >= 0 && commaIndex + 1 < downloadUrl.length) {
      try {
        return base64Decode(downloadUrl.substring(commaIndex + 1));
      } catch (_) {
        return null;
      }
    }
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.startsWith('data:')) {
      final commaIndex = trimmed.indexOf(',');
      if (commaIndex >= 0 && commaIndex + 1 < trimmed.length) {
        try {
          return base64Decode(trimmed.substring(commaIndex + 1));
        } catch (_) {
          return null;
        }
      }
    }
  }
  return null;
}

String? photoDownloadUrl(dynamic value, {String key = 'download_url'}) {
  if (value is String) {
    final directUrl = value.trim();
    if (directUrl.isNotEmpty) {
      return directUrl;
    }
  }
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
    final raw = newValue.text;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue();
    }

    var localDigits = digits;
    if (raw.trimLeft().startsWith('+') && localDigits.startsWith('63')) {
      localDigits = localDigits.substring(2);
    } else if (localDigits.startsWith('63')) {
      localDigits = localDigits.substring(2);
    } else if (localDigits.startsWith('0')) {
      localDigits = localDigits.substring(1);
    }
    if (localDigits.length > 10) {
      localDigits = localDigits.substring(0, 10);
    }
    // Keep the country-code prefix after an initial local 0 so the next 9
    // produces +639 instead of dropping the mobile prefix mid-typing.
    final transformed = localDigits.isEmpty ? '+63' : '+63$localDigits';
    final offset = transformed.length;
    return TextEditingValue(
      text: transformed,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }
}

/// Keeps the mixed login identifier usable for email while formatting values
/// that clearly start as a Philippine mobile number.
class EmailOrPhilippinesPhoneInputFormatter extends TextInputFormatter {
  const EmailOrPhilippinesPhoneInputFormatter();

  static const _phoneFormatter = PhilippinesPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (RegExp(r'[A-Za-z@]').hasMatch(text)) {
      return newValue;
    }

    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final isPhonePrefix =
        text.startsWith('+') ||
        digits.startsWith('0') ||
        digits.startsWith('9') ||
        digits.startsWith('63');
    return isPhonePrefix
        ? _phoneFormatter.formatEditUpdate(oldValue, newValue)
        : newValue;
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

String userFacingErrorMessage(Object error, {String fallback = ''}) {
  final message = exactUserErrorMessage(error, fallback: fallback);
  if (message.trim().isNotEmpty) {
    return message.trim();
  }
  return error.toString().trim();
}

String exactUserErrorMessage(Object error, {String fallback = ''}) {
  if (error is FirebaseException) {
    final raw = error.message ?? error.code;
    final normalized = _normalizeRawErrorText(raw, '');
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return error.toString().trim();
  }
  if (error is PlatformException) {
    final raw = error.message ?? error.code;
    final normalized = _normalizeRawErrorText(raw, '');
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return error.toString().trim();
  }
  final normalized = _normalizeRawErrorText(error.toString(), '');
  if (normalized.isNotEmpty) {
    return normalized;
  }
  return error.toString().trim();
}

String normalizeUserErrorText(String? rawMessage, {String fallback = ''}) {
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
    return normalized;
  }

  return _sentenceCase(normalized);
}

String _normalizeRawErrorText(String? rawMessage, String fallback) {
  final text = (rawMessage ?? '').trim();
  if (text.isEmpty) {
    return fallback;
  }

  final normalized = text
      .replaceFirst(
        RegExp(
          r'^(Exception|Error|StateError|AuthFailure|FirebaseException):\s*',
        ),
        '',
      )
      .replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '')
      .trim();
  if (normalized.isEmpty) {
    return fallback;
  }
  return normalized;
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
  if (normalized.contains('incorrect password') ||
      normalized.contains('old password is incorrect')) {
    return 'The password you entered is incorrect.';
  }
  if (normalized.contains('no account found for that email or mobile number')) {
    return 'No account was found for that email or phone number.';
  }
  if (normalized.contains('that email is already registered') ||
      normalized.contains('email already exists') ||
      normalized.contains('email already registered')) {
    return 'That email address is already in use.';
  }
  if (normalized.contains('that phone number is already registered') ||
      normalized.contains('phone already exists') ||
      normalized.contains('phone number already exists') ||
      normalized.contains('mobile number already exists')) {
    return 'That phone number is already in use.';
  }
  if (normalized.contains('not active yet')) {
    return 'This account is not active yet. Please contact your admin.';
  }
  if (normalized.contains('unauthenticated')) {
    return 'Please sign in again and try again.';
  }
  if (normalized.contains('network-request-failed') ||
      normalized.contains('network error') ||
      normalized.contains('failed to fetch') ||
      normalized.contains('progressevent')) {
    return 'Please check your internet connection and try again.';
  }
  if (normalized.contains('public firestore fetch timeout') ||
      normalized.contains('fetch timeout') ||
      normalized.contains('request took too long') ||
      normalized.contains('timeoutexception') ||
      normalized.contains('future not completed')) {
    return 'The request took too long. Please try again.';
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
    if (normalized.contains('email')) {
      return 'Please enter a valid email address.';
    }
    if (normalized.contains('phone') || normalized.contains('mobile')) {
      return 'Please enter a valid phone number.';
    }
    if (normalized.contains('password')) {
      return 'Please check the password and try again.';
    }
    if (normalized.contains('query')) {
      return 'This data could not be loaded correctly right now. Please try again.';
    }
    return fallback;
  }
  if (normalized.contains('failed-precondition')) {
    if (normalized.contains('index')) {
      return 'This data is still being prepared on the server. Please try again shortly.';
    }
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
