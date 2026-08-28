import 'package:webapp/models/booking.dart';
import 'package:webapp/constants/palawan_locations.dart';
import 'package:webapp/models/status_field.dart';
import 'package:webapp/models/status_form.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/repositories/interfaces/status_form_repository.dart';
import 'package:webapp/utils/functions.dart';

class StatusFormEngine {
  const StatusFormEngine(this._repository);

  final StatusFormRepository _repository;

  Future<StatusForm?> getForm(String role, String currentStatusKey) {
    return _repository.getStatusFormByRoleAndStatus(role, currentStatusKey);
  }

  Future<List<StatusField>> getFields(String statusFormId) {
    return _repository.getFields(statusFormId);
  }

  Map<String, String> validateFields(
    List<StatusField> fields,
    Map<String, dynamic> answers,
  ) {
    final errors = <String, String>{};

    for (final field in fields) {
      final key = field.key;
      if (key == null || key.isEmpty || field.isActive == false) {
        continue;
      }

      final answer = answers[key];
      final isRequired = field.required ?? false;
      final title = field.title?.trim();

      if (!isFieldVisible(field, answers)) {
        continue;
      }

      if (isRequired && _isEmptyAnswer(answer)) {
        errors[key] =
            field.requiredError ??
            ((title?.isNotEmpty == true)
                ? '$title is required.'
                : 'This field is required.');
        continue;
      }

      if (_isEmptyAnswer(answer)) {
        continue;
      }

      final min = field.min;
      final max = field.max;
      final type = field.type;
      final normalizedKey = key.trim().toLowerCase();
      final optionSourceKey = field.optionSourceKey?.trim().toLowerCase();
      final isIdKey = normalizedKey.endsWith('_id');
      final usesDynamicSource =
          optionSourceKey != null &&
          statusFieldDynamicOptionSources.contains(optionSourceKey);
      final usesIdBackedDynamicSelection =
          normalizedKey == 'driver_id' ||
          normalizedKey == 'helper_id' ||
          (isIdKey && usesDynamicSource) ||
          optionSourceKey == statusFieldOptionSourceDrivers ||
          optionSourceKey == statusFieldOptionSourceHelpers ||
          optionSourceKey == statusFieldOptionSourceClientMembers;

      if (answer is String && isPalawanLocationFieldKey(normalizedKey)) {
        if (!isValidPalawanLocationOption(answer)) {
          errors[key] =
              field.validationError ??
              ((title?.isNotEmpty == true)
                  ? 'Select a valid $title.'
                  : 'Select a valid option.');
        }
        continue;
      }

      if (answer is String &&
          (type == 'dropdown' || type == 'search_dropdown') &&
          !usesIdBackedDynamicSelection &&
          field.options.isNotEmpty) {
        final normalizedAnswer = answer.trim().toLowerCase();
        final hasMatch = field.options.any(
          (option) => option.trim().toLowerCase() == normalizedAnswer,
        );
        if (!hasMatch) {
          errors[key] =
              field.validationError ??
              ((title?.isNotEmpty == true)
                  ? 'Select a valid $title.'
                  : 'Select a valid option.');
        }
        continue;
      }

      if (answer is String &&
          (type == 'text' ||
              type == 'number' ||
              type == 'email' ||
              type == 'phone')) {
        if (min != null && answer.length < min) {
          errors[key] = field.validationError ?? 'Input is too short.';
        } else if (max != null && answer.length > max) {
          errors[key] = field.validationError ?? 'Input is too long.';
        } else if (type == 'number') {
          final numberError = _validateNumber(answer);
          if (numberError != null) {
            errors[key] = field.validationError ?? numberError;
          }
        } else if (type == 'email' ||
            (type == 'text' && _looksLikeEmailField(field))) {
          final emailError = _validateEmail(answer);
          if (emailError != null) {
            errors[key] = field.validationError ?? emailError;
          }
        } else if (type == 'phone' ||
            (type == 'text' && _looksLikePhoneField(field))) {
          final phoneError = _validatePhone(answer);
          if (phoneError != null) {
            errors[key] = field.validationError ?? phoneError;
          }
        }
      }

      if (answer is num) {
        if (min != null && answer < min) {
          errors[key] = field.validationError ?? 'Value is too low.';
        } else if (max != null && answer > max) {
          errors[key] = field.validationError ?? 'Value is too high.';
        }
      }

      if (answer is List) {
        if (min != null && answer.length < min) {
          errors[key] =
              field.validationError ?? 'Not enough items were provided.';
        } else if (max != null && answer.length > max) {
          errors[key] =
              field.validationError ?? 'Too many items were provided.';
        }
      }
    }

    return errors;
  }

  bool checkDependencies(Booking booking, StatusForm statusForm) {
    if (statusForm.dependencies.isEmpty) {
      return true;
    }

    for (final dependency in statusForm.dependencies) {
      final expectedStatus = dependency.statusKey;
      if (expectedStatus == null || dependency.statusType == null) {
        return false;
      }

      final actualStatus = switch (dependency.statusType) {
        'client_status' => booking.clientStatus,
        'driver_status' => booking.driverStatus,
        'helper_status' => booking.helperStatus,
        _ => null,
      };

      if (actualStatus != expectedStatus) {
        return false;
      }
    }

    return true;
  }

  String? getBlockedMessage(Booking booking, StatusForm statusForm) {
    if (checkDependencies(booking, statusForm)) {
      return null;
    }
    return statusForm.blockedMessage;
  }

  Booking applyOutputToBooking(
    Booking booking,
    StatusForm statusForm,
    List<StatusField> fields,
    Map<String, dynamic> answers,
    String userId,
    String? userRole,
  ) {
    final nextStatus = statusForm.nextStatusKey;
    final vehicleMakeId = _stringAnswer(answers['vehicle_make_id']);
    final normalizedAnswers = _normalizeAnswersForStorage(answers, fields);
    final changedAnswers = _changedAnswersForStorage(
      booking.statusOutputs,
      normalizedAnswers,
    );
    final displayStatusKey = (statusForm.currentStatusKey ?? 'status').trim();
    final nextOutputs = appendStatusOutputSection(
      booking.statusOutputs ?? const <String, dynamic>{},
      displayStatusKey: displayStatusKey,
      statusFormReference: statusForm.toReferenceMap(),
      submittedRole: userRole,
      submittedRoles: [
        if (userRole?.trim().isNotEmpty == true) userRole!.trim(),
      ],
      submittedBy: userId,
      fields: changedAnswers,
    );

    return booking.copyWith(
      clientStatus: nextStatus ?? booking.clientStatus,
      driverStatus: nextStatus ?? booking.driverStatus,
      helperStatus: nextStatus ?? booking.helperStatus,
      vehicleMake: vehicleMakeId == null
          ? booking.vehicleMake
          : VehicleMake(id: vehicleMakeId),
      statusOutputs: nextOutputs,
      updatedAt: DateTime.now(),
    );
  }

  static Map<String, dynamic> appendStatusOutputSection(
    Map<String, dynamic> existingOutputs, {
    required String displayStatusKey,
    required Map<String, dynamic>? statusFormReference,
    required String? submittedRole,
    required List<String> submittedRoles,
    required String submittedBy,
    required Map<String, dynamic> fields,
    DateTime? submittedAt,
  }) {
    final trimmedDisplayStatusKey = displayStatusKey.trim().isEmpty
        ? 'status'
        : displayStatusKey.trim();
    final resolvedSubmittedAt = submittedAt ?? DateTime.now();
    final nextOutputs = Map<String, dynamic>.from(existingOutputs);
    final entryKey = buildStatusOutputEntryKey(
      trimmedDisplayStatusKey,
      submittedAt: resolvedSubmittedAt,
    );
    nextOutputs[entryKey] = {
      'status_key': trimmedDisplayStatusKey,
      'status_form': statusFormReference,
      'submitted_role': submittedRole,
      'submitted_roles': submittedRoles,
      'submitted_by': submittedBy,
      'submitted_at': resolvedSubmittedAt.toIso8601String(),
      'fields': fields,
    };
    return nextOutputs;
  }

  static String buildStatusOutputEntryKey(
    String displayStatusKey, {
    DateTime? submittedAt,
  }) {
    final trimmedStatusKey = displayStatusKey.trim().isEmpty
        ? 'status'
        : displayStatusKey.trim();
    final timestamp = (submittedAt ?? DateTime.now()).microsecondsSinceEpoch;
    return '${trimmedStatusKey}__$timestamp';
  }

  static bool _isEmptyAnswer(dynamic value) {
    if (value == null) {
      return true;
    }
    if (value is String) {
      return value.trim().isEmpty;
    }
    if (value is List) {
      return value.isEmpty;
    }
    return false;
  }

  static bool isFieldVisible(
    StatusField field,
    Map<String, dynamic> answers,
  ) {
    final controllerKey = field.visibilityControllerKey?.trim();
    final allowedValues = field.visibilityOptionValues
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (controllerKey == null ||
        controllerKey.isEmpty ||
        allowedValues.isEmpty) {
      return true;
    }
    final answer = answers[controllerKey];
    if (_isEmptyAnswer(answer)) {
      return false;
    }
    final normalizedAllowed = allowedValues
        .map((item) => item.toLowerCase())
        .toSet();
    if (answer is String) {
      return normalizedAllowed.contains(answer.trim().toLowerCase());
    }
    if (answer is List) {
      return answer.any(
        (item) => normalizedAllowed.contains(item.toString().trim().toLowerCase()),
      );
    }
    return normalizedAllowed.contains(answer.toString().trim().toLowerCase());
  }

  static List<StatusField> visibleFields(
    List<StatusField> fields,
    Map<String, dynamic> answers,
  ) {
    return fields.where((field) => isFieldVisible(field, answers)).toList();
  }

  static bool _looksLikeEmailField(StatusField field) {
    final haystack = [
      field.key,
      field.title,
      field.subtitle,
      field.placeholder,
      field.instructions,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains('email') || haystack.contains('e-mail');
  }

  static bool _looksLikePhoneField(StatusField field) {
    final haystack = [
      field.key,
      field.title,
      field.subtitle,
      field.placeholder,
      field.instructions,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains('phone') ||
        haystack.contains('mobile') ||
        haystack.contains('contact number') ||
        haystack.contains('phone number');
  }

  static String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    final emailRegex = RegExp(
      r"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$",
      caseSensitive: false,
    );
    if (!emailRegex.hasMatch(trimmed)) {
      return 'Please enter a valid email.';
    }
    return null;
  }

  static String? _validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (!isValidPhilippinePhone(trimmed)) {
      return 'Enter a valid PH mobile number.';
    }
    return null;
  }

  static String? _validateNumber(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    return num.tryParse(trimmed) == null
        ? 'Please enter a valid number.'
        : null;
  }

  static String? _stringAnswer(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Map<String, dynamic> _normalizeAnswersForStorage(
    Map<String, dynamic> answers,
    List<StatusField> fields,
  ) {
    final fieldByKey = {
      for (final field in fields)
        if (field.key != null && field.key!.trim().isNotEmpty)
          field.key!.trim(): field,
    };
    final normalized = <String, dynamic>{};

    answers.forEach((key, value) {
      final field = fieldByKey[key];
      if (field != null && !isFieldVisible(field, answers)) {
        return;
      }
      if (value is String && field?.type == 'phone') {
        normalized[key] = normalizePhilippinePhone(value) ?? value.trim();
        return;
      }
      normalized[key] = value;
    });

    return normalized;
  }

  static Map<String, dynamic> _changedAnswersForStorage(
    Map<String, dynamic>? existingOutputs,
    Map<String, dynamic> normalizedAnswers,
  ) {
    if (normalizedAnswers.isEmpty) {
      return const <String, dynamic>{};
    }

    final previousValues = _latestFieldValues(existingOutputs);
    final changed = <String, dynamic>{};

    normalizedAnswers.forEach((key, value) {
      if (!_fieldValuesEqual(previousValues[key], value)) {
        changed[key] = value;
      }
    });

    return changed;
  }

  static Map<String, dynamic> _latestFieldValues(
    Map<String, dynamic>? outputs,
  ) {
    if (outputs == null || outputs.isEmpty) {
      return const <String, dynamic>{};
    }

    final sections = outputs.entries
        .where((entry) => entry.value is Map)
        .map((entry) {
          final raw = Map<String, dynamic>.from(entry.value as Map);
          return (
            entryKey: entry.key,
            submittedAt: _toDateTime(raw['submitted_at']),
            fields: raw['fields'] is Map
                ? Map<String, dynamic>.from(raw['fields'] as Map)
                : const <String, dynamic>{},
          );
        })
        .toList();

    sections.sort((a, b) {
      final aSubmittedAt = a.submittedAt;
      final bSubmittedAt = b.submittedAt;
      if (aSubmittedAt != null && bSubmittedAt != null) {
        return bSubmittedAt.compareTo(aSubmittedAt);
      }
      if (aSubmittedAt != null) {
        return -1;
      }
      if (bSubmittedAt != null) {
        return 1;
      }
      return b.entryKey.compareTo(a.entryKey);
    });

    final latestValues = <String, dynamic>{};
    for (final section in sections) {
      section.fields.forEach((key, value) {
        latestValues.putIfAbsent(key, () => value);
      });
    }
    return latestValues;
  }

  static bool _fieldValuesEqual(dynamic left, dynamic right) {
    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (var index = 0; index < left.length; index += 1) {
        if (!_fieldValuesEqual(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) {
        return false;
      }
      for (final entry in left.entries) {
        if (!_fieldValuesEqual(right[entry.key], entry.value)) {
          return false;
        }
      }
      return true;
    }
    return left == right;
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse(value.toString());
  }
}
