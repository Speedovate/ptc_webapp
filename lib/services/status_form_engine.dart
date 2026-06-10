import 'package:webapp/models/booking.dart';
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
  ) {
    final nextStatus = statusForm.nextStatusKey;
    final outputKey = (nextStatus?.trim() == 'cancelled')
        ? 'cancelled'
        : (statusForm.currentStatusKey ?? 'status');
    final truckId = _stringAnswer(answers['truck_id']);
    final normalizedAnswers = _normalizeAnswersForStorage(answers, fields);
    final nextOutputs = Map<String, dynamic>.from(booking.statusOutputs ?? {})
      ..[outputKey] = {
        'status_form': statusForm.toReferenceMap(),
        'submitted_role': statusForm.primaryRole ?? statusForm.role,
        'submitted_roles': statusForm.resolvedRoles,
        'submitted_by': userId,
        'submitted_at': DateTime.now().toIso8601String(),
        'fields': normalizedAnswers,
      };

    return booking.copyWith(
      clientStatus: nextStatus ?? booking.clientStatus,
      driverStatus: nextStatus ?? booking.driverStatus,
      helperStatus: nextStatus ?? booking.helperStatus,
      truck: truckId == null ? booking.truck : VehicleMake(id: truckId),
      statusOutputs: nextOutputs,
      updatedAt: DateTime.now(),
    );
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
      if (value is String && field?.type == 'phone') {
        normalized[key] = normalizePhilippinePhone(value) ?? value.trim();
        return;
      }
      normalized[key] = value;
    });

    return normalized;
  }
}
