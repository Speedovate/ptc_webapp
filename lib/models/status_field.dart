import 'dart:convert';

import 'package:webapp/models/status_form.dart';

const _statusFieldUndefined = Object();
const statusFieldOptionSourceStatic = 'static';
const statusFieldOptionSourceUsers = 'users';
const statusFieldOptionSourceClients = 'clients';
const statusFieldOptionSourceAdmins = 'admins';
const statusFieldOptionSourceDrivers = 'drivers';
const statusFieldOptionSourceHelpers = 'helpers';
const statusFieldOptionSourceClientMembers = 'client_members';
const statusFieldOptionSourceVehicleMakes = 'vehicle_makes';
const statusFieldOptionSourceVehicleTypes = 'vehicle_types';
const statusFieldOptionSourceVehicleSizes = 'vehicle_sizes';
const statusFieldOptionSourceStatuses = 'statuses';
const statusFieldOptionSourceForms = 'forms';
const statusFieldOptionSourceFields = 'fields';
const statusFieldOptionSourceBookings = 'bookings';
const statusFieldOptionSourcePuertoPrincesaBarangays =
    'puerto_princesa_barangays';
const statusFieldDynamicOptionSources = <String>[
  statusFieldOptionSourceUsers,
  statusFieldOptionSourceClients,
  statusFieldOptionSourceAdmins,
  statusFieldOptionSourceDrivers,
  statusFieldOptionSourceHelpers,
  statusFieldOptionSourceClientMembers,
  statusFieldOptionSourceVehicleMakes,
  statusFieldOptionSourceVehicleTypes,
  statusFieldOptionSourceVehicleSizes,
  statusFieldOptionSourceStatuses,
  statusFieldOptionSourceForms,
  statusFieldOptionSourceFields,
  statusFieldOptionSourceBookings,
  statusFieldOptionSourcePuertoPrincesaBarangays,
];
const statusFieldOptionSourceLabels = <String, String>{
  statusFieldOptionSourceStatic: 'Static',
  statusFieldOptionSourceUsers: 'Users',
  statusFieldOptionSourceClients: 'Clients',
  statusFieldOptionSourceAdmins: 'Admins',
  statusFieldOptionSourceDrivers: 'Drivers',
  statusFieldOptionSourceHelpers: 'Helpers',
  statusFieldOptionSourceClientMembers: 'Clients',
  statusFieldOptionSourceVehicleMakes: 'Vehicle Makes',
  statusFieldOptionSourceVehicleTypes: 'Vehicle Types',
  statusFieldOptionSourceVehicleSizes: 'Vehicle Sizes',
  statusFieldOptionSourceStatuses: 'Statuses',
  statusFieldOptionSourceForms: 'Forms',
  statusFieldOptionSourceFields: 'Fields',
  statusFieldOptionSourceBookings: 'Bookings',
  statusFieldOptionSourcePuertoPrincesaBarangays:
      'Puerto Princesa Barangays',
};

class StatusField {
  const StatusField({
    this.id,
    this.statusForm,
    this.key,
    this.type,
    this.title,
    this.subtitle,
    this.instructions,
    this.placeholder,
    this.required,
    this.min,
    this.max,
    this.options = const [],
    this.optionSourceKey,
    this.visibilityControllerKey,
    this.visibilityOptionValues = const [],
    this.requiredError,
    this.validationError,
    this.sortOrder,
    this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final StatusForm? statusForm;
  final String? key;
  final String? type;
  final String? title;
  final String? subtitle;
  final String? instructions;
  final String? placeholder;
  final bool? required;
  final int? min;
  final int? max;
  final List<String> options;
  final String? optionSourceKey;
  final String? visibilityControllerKey;
  final List<String> visibilityOptionValues;
  final String? requiredError;
  final String? validationError;
  final int? sortOrder;
  final bool? isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  StatusField copyWith({
    Object? id = _statusFieldUndefined,
    Object? statusForm = _statusFieldUndefined,
    Object? key = _statusFieldUndefined,
    Object? type = _statusFieldUndefined,
    Object? title = _statusFieldUndefined,
    Object? subtitle = _statusFieldUndefined,
    Object? instructions = _statusFieldUndefined,
    Object? placeholder = _statusFieldUndefined,
    Object? required = _statusFieldUndefined,
    Object? min = _statusFieldUndefined,
    Object? max = _statusFieldUndefined,
    List<String>? options,
    Object? optionSourceKey = _statusFieldUndefined,
    Object? visibilityControllerKey = _statusFieldUndefined,
    List<String>? visibilityOptionValues,
    Object? requiredError = _statusFieldUndefined,
    Object? validationError = _statusFieldUndefined,
    Object? sortOrder = _statusFieldUndefined,
    Object? isActive = _statusFieldUndefined,
    Object? createdAt = _statusFieldUndefined,
    Object? updatedAt = _statusFieldUndefined,
  }) {
    return StatusField(
      id: identical(id, _statusFieldUndefined) ? this.id : id as String?,
      statusForm: identical(statusForm, _statusFieldUndefined)
          ? this.statusForm
          : statusForm as StatusForm?,
      key: identical(key, _statusFieldUndefined) ? this.key : key as String?,
      type: identical(type, _statusFieldUndefined)
          ? this.type
          : type as String?,
      title: identical(title, _statusFieldUndefined)
          ? this.title
          : title as String?,
      subtitle: identical(subtitle, _statusFieldUndefined)
          ? this.subtitle
          : subtitle as String?,
      instructions: identical(instructions, _statusFieldUndefined)
          ? this.instructions
          : instructions as String?,
      placeholder: identical(placeholder, _statusFieldUndefined)
          ? this.placeholder
          : placeholder as String?,
      required: identical(required, _statusFieldUndefined)
          ? this.required
          : required as bool?,
      min: identical(min, _statusFieldUndefined) ? this.min : min as int?,
      max: identical(max, _statusFieldUndefined) ? this.max : max as int?,
      options: options ?? this.options,
      optionSourceKey: identical(optionSourceKey, _statusFieldUndefined)
          ? this.optionSourceKey
          : optionSourceKey as String?,
      visibilityControllerKey: identical(
        visibilityControllerKey,
        _statusFieldUndefined,
      )
          ? this.visibilityControllerKey
          : visibilityControllerKey as String?,
      visibilityOptionValues:
          visibilityOptionValues ?? this.visibilityOptionValues,
      requiredError: identical(requiredError, _statusFieldUndefined)
          ? this.requiredError
          : requiredError as String?,
      validationError: identical(validationError, _statusFieldUndefined)
          ? this.validationError
          : validationError as String?,
      sortOrder: identical(sortOrder, _statusFieldUndefined)
          ? this.sortOrder
          : sortOrder as int?,
      isActive: identical(isActive, _statusFieldUndefined)
          ? this.isActive
          : isActive as bool?,
      createdAt: identical(createdAt, _statusFieldUndefined)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _statusFieldUndefined)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'status_form': statusForm?.toReferenceMap(),
      'key': key,
      'type': type,
      'title': title,
      'subtitle': subtitle,
      'instructions': instructions,
      'placeholder': placeholder,
      'required': required,
      'min': min,
      'max': max,
      'options': options,
      'option_source_key': optionSourceKey,
      'visibility_controller_key': visibilityControllerKey,
      'visibility_option_values': visibilityOptionValues,
      'required_error': requiredError,
      'validation_error': validationError,
      'sort_order': sortOrder,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toReferenceMap() {
    return {
      'id': id,
      'key': key,
      'type': type,
      'title': title,
      'placeholder': placeholder,
      'required': required,
      'is_active': isActive,
    };
  }

  factory StatusField.fromMap(Map<String, dynamic> map) {
    return StatusField(
      id: map['id']?.toString(),
      statusForm: _toStatusForm(map['status_form']),
      key: map['key']?.toString(),
      type: map['type']?.toString(),
      title: map['title']?.toString(),
      subtitle: map['subtitle']?.toString(),
      instructions: map['instructions']?.toString(),
      placeholder: map['placeholder']?.toString(),
      required: map['required'] as bool?,
      min: _toInt(map['min']),
      max: _toInt(map['max']),
      options: (map['options'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      optionSourceKey: map['option_source_key']?.toString(),
      visibilityControllerKey: map['visibility_controller_key']?.toString(),
      visibilityOptionValues:
          (map['visibility_option_values'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList(),
      requiredError: map['required_error']?.toString(),
      validationError: map['validation_error']?.toString(),
      sortOrder: _toInt(map['sort_order']),
      isActive: map['is_active'] as bool?,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }

  String toJson() => json.encode(toMap());

  factory StatusField.fromJson(String source) {
    return StatusField.fromMap(json.decode(source) as Map<String, dynamic>);
  }

  static StatusForm? _toStatusForm(dynamic value) {
    if (value is Map) {
      return StatusForm.fromMap(Map<String, dynamic>.from(value));
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is StatusField &&
        other.id == id &&
        other.statusForm?.id == statusForm?.id &&
        other.key == key &&
        other.type == type &&
        other.title == title &&
        other.subtitle == subtitle &&
        other.instructions == instructions &&
        other.placeholder == placeholder &&
        other.required == required &&
        other.min == min &&
        other.max == max &&
        _listEquals(other.options, options) &&
        other.optionSourceKey == optionSourceKey &&
        other.visibilityControllerKey == visibilityControllerKey &&
        _listEquals(other.visibilityOptionValues, visibilityOptionValues) &&
        other.requiredError == requiredError &&
        other.validationError == validationError &&
        other.sortOrder == sortOrder &&
        other.isActive == isActive &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    statusForm?.id,
    key,
    type,
    title,
    subtitle,
    instructions,
    placeholder,
    required,
    min,
    max,
    Object.hashAll(options),
    optionSourceKey,
    visibilityControllerKey,
    Object.hashAll(visibilityOptionValues),
    requiredError,
    validationError,
    sortOrder,
    isActive,
    createdAt,
    updatedAt,
  ]);

  static int? _toInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
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

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }

  static String? normalizedOptionSourceKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
