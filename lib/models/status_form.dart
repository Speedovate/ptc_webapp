import 'dart:convert';

import 'package:webapp/models/status_field.dart';

const _statusDependencyUndefined = Object();
const _statusFormUndefined = Object();
const _statusFieldOverrideUndefined = Object();

class StatusDependency {
  const StatusDependency({
    this.statusType,
    this.statusKey,
  });

  final String? statusType;
  final String? statusKey;

  StatusDependency copyWith({
    Object? statusType = _statusDependencyUndefined,
    Object? statusKey = _statusDependencyUndefined,
  }) {
    return StatusDependency(
      statusType: identical(statusType, _statusDependencyUndefined)
          ? this.statusType
          : statusType as String?,
      statusKey: identical(statusKey, _statusDependencyUndefined)
          ? this.statusKey
          : statusKey as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status_type': statusType,
      'status_key': statusKey,
    };
  }

  factory StatusDependency.fromMap(Map<String, dynamic> map) {
    return StatusDependency(
      statusType: map['status_type']?.toString(),
      statusKey: map['status_key']?.toString(),
    );
  }

  String toJson() => json.encode(toMap());

  factory StatusDependency.fromJson(String source) {
    return StatusDependency.fromMap(
      json.decode(source) as Map<String, dynamic>,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is StatusDependency &&
        other.statusType == statusType &&
        other.statusKey == statusKey;
  }

  @override
  int get hashCode => Object.hash(statusType, statusKey);
}

class StatusFieldOverride {
  const StatusFieldOverride({
    this.required,
    this.placeholder,
  });

  final bool? required;
  final String? placeholder;

  StatusFieldOverride copyWith({
    Object? required = _statusFieldOverrideUndefined,
    Object? placeholder = _statusFieldOverrideUndefined,
  }) {
    return StatusFieldOverride(
      required: identical(required, _statusFieldOverrideUndefined)
          ? this.required
          : required as bool?,
      placeholder: identical(placeholder, _statusFieldOverrideUndefined)
          ? this.placeholder
          : placeholder as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'required': required,
      'placeholder': placeholder,
    };
  }

  factory StatusFieldOverride.fromMap(Map<String, dynamic> map) {
    return StatusFieldOverride(
      required: map['required'] as bool?,
      placeholder: map['placeholder']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is StatusFieldOverride &&
        other.required == required &&
        other.placeholder == placeholder;
  }

  @override
  int get hashCode => Object.hash(required, placeholder);
}

class StatusForm {
  const StatusForm({
    this.id,
    this.role,
    this.roles = const [],
    this.isMainForm,
    this.currentStatusKey,
    this.nextStatusKey,
    this.statusText,
    this.statusSubtext,
    this.buttonText,
    this.fields = const [],
    this.fieldOverrides = const {},
    this.dependencies = const [],
    this.blockedMessage,
    this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? role;
  final List<String> roles;
  final bool? isMainForm;
  final String? currentStatusKey;
  final String? nextStatusKey;
  final String? statusText;
  final String? statusSubtext;
  final String? buttonText;
  final List<StatusField> fields;
  final Map<String, StatusFieldOverride> fieldOverrides;
  final List<StatusDependency> dependencies;
  final String? blockedMessage;
  final bool? isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  StatusForm copyWith({
    Object? id = _statusFormUndefined,
    Object? role = _statusFormUndefined,
    List<String>? roles,
    Object? isMainForm = _statusFormUndefined,
    Object? currentStatusKey = _statusFormUndefined,
    Object? nextStatusKey = _statusFormUndefined,
    Object? statusText = _statusFormUndefined,
    Object? statusSubtext = _statusFormUndefined,
    Object? buttonText = _statusFormUndefined,
    List<StatusField>? fields,
    Map<String, StatusFieldOverride>? fieldOverrides,
    List<StatusDependency>? dependencies,
    Object? blockedMessage = _statusFormUndefined,
    Object? isActive = _statusFormUndefined,
    Object? createdAt = _statusFormUndefined,
    Object? updatedAt = _statusFormUndefined,
  }) {
    return StatusForm(
      id: identical(id, _statusFormUndefined) ? this.id : id as String?,
      role: identical(role, _statusFormUndefined) ? this.role : role as String?,
      roles: roles ?? this.roles,
      isMainForm: identical(isMainForm, _statusFormUndefined)
          ? this.isMainForm
          : isMainForm as bool?,
      currentStatusKey: identical(currentStatusKey, _statusFormUndefined)
          ? this.currentStatusKey
          : currentStatusKey as String?,
      nextStatusKey: identical(nextStatusKey, _statusFormUndefined)
          ? this.nextStatusKey
          : nextStatusKey as String?,
      statusText: identical(statusText, _statusFormUndefined)
          ? this.statusText
          : statusText as String?,
      statusSubtext: identical(statusSubtext, _statusFormUndefined)
          ? this.statusSubtext
          : statusSubtext as String?,
      buttonText: identical(buttonText, _statusFormUndefined)
          ? this.buttonText
          : buttonText as String?,
      fields: fields ?? this.fields,
      fieldOverrides: fieldOverrides ?? this.fieldOverrides,
      dependencies: dependencies ?? this.dependencies,
      blockedMessage: identical(blockedMessage, _statusFormUndefined)
          ? this.blockedMessage
          : blockedMessage as String?,
      isActive: identical(isActive, _statusFormUndefined)
          ? this.isActive
          : isActive as bool?,
      createdAt: identical(createdAt, _statusFormUndefined)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _statusFormUndefined)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'role': role,
      'roles': roles,
      'is_main_form': isMainForm,
      'current_status_key': currentStatusKey,
      'next_status_key': nextStatusKey,
      'status_text': statusText,
      'status_subtext': statusSubtext,
      'button_text': buttonText,
      'fields': fields.map((item) => item.toReferenceMap()).toList(),
      'field_overrides': fieldOverrides.map(
        (key, value) => MapEntry(key, value.toMap()),
      ),
      'dependencies': dependencies.map((item) => item.toMap()).toList(),
      'blocked_message': blockedMessage,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory StatusForm.fromMap(Map<String, dynamic> map) {
    final dependencyMaps = map['dependencies'] as List<dynamic>? ?? const [];
    final fieldMaps = map['fields'] as List<dynamic>? ?? const [];
    final fieldOverrideMaps = (map['field_overrides'] as Map?)?.map(
          (key, value) => MapEntry(
            key.toString(),
            StatusFieldOverride.fromMap(
              Map<String, dynamic>.from(value as Map),
            ),
          ),
        ) ??
        const <String, StatusFieldOverride>{};
    final parsedRoles = (map['roles'] as List<dynamic>? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final parsedRole = map['role']?.toString().trim();
    final parsedFields = fieldMaps
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map(StatusField.fromMap)
        .toList();
    return StatusForm(
      id: map['id']?.toString(),
      role: parsedRole?.isNotEmpty == true ? parsedRole : null,
      roles: parsedRoles.isNotEmpty
          ? parsedRoles
          : (parsedRole?.isNotEmpty == true ? [parsedRole!] : const []),
      isMainForm: map['is_main_form'] as bool?,
      currentStatusKey: map['current_status_key']?.toString(),
      nextStatusKey: map['next_status_key']?.toString(),
      statusText: map['status_text']?.toString(),
      statusSubtext: map['status_subtext']?.toString(),
      buttonText: map['button_text']?.toString(),
      fields: parsedFields,
      fieldOverrides: fieldOverrideMaps,
      dependencies: dependencyMaps
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map(StatusDependency.fromMap)
          .toList(),
      blockedMessage: map['blocked_message']?.toString(),
      isActive: map['is_active'] as bool?,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }

  String toJson() => json.encode(toMap());

  factory StatusForm.fromJson(String source) {
    return StatusForm.fromMap(json.decode(source) as Map<String, dynamic>);
  }

  Map<String, dynamic> toReferenceMap() {
    return {
      'id': id,
      'role': role,
      'roles': roles,
      'is_main_form': isMainForm,
      'current_status_key': currentStatusKey,
      'next_status_key': nextStatusKey,
      'status_text': statusText,
      'status_subtext': statusSubtext,
      'button_text': buttonText,
      'is_active': isActive,
    };
  }

  StatusForm toReferenceForm() {
    return StatusForm(
      id: id,
      role: role,
      roles: roles,
      isMainForm: isMainForm,
      currentStatusKey: currentStatusKey,
      nextStatusKey: nextStatusKey,
      statusText: statusText,
      statusSubtext: statusSubtext,
      buttonText: buttonText,
      fieldOverrides: fieldOverrides,
      dependencies: dependencies,
      blockedMessage: blockedMessage,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  List<String> get resolvedRoles {
    if (roles.isNotEmpty) {
      return roles
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    final trimmedRole = role?.trim();
    if (trimmedRole == null || trimmedRole.isEmpty) {
      return const [];
    }
    return [trimmedRole];
  }

  String? get primaryRole {
    final resolved = resolvedRoles;
    return resolved.isEmpty ? null : resolved.first;
  }

  bool get resolvedIsMainForm => isMainForm ?? true;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is StatusForm &&
        other.id == id &&
        other.role == role &&
        _listEquals(other.roles, roles) &&
        other.isMainForm == isMainForm &&
        other.currentStatusKey == currentStatusKey &&
        other.nextStatusKey == nextStatusKey &&
        other.statusText == statusText &&
        other.statusSubtext == statusSubtext &&
        other.buttonText == buttonText &&
        _fieldListEquals(other.fields, fields) &&
        _fieldOverrideMapEquals(other.fieldOverrides, fieldOverrides) &&
        _dependencyListEquals(other.dependencies, dependencies) &&
        other.blockedMessage == blockedMessage &&
        other.isActive == isActive &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    role,
    Object.hashAll(roles),
    isMainForm,
    currentStatusKey,
    nextStatusKey,
    statusText,
    statusSubtext,
    buttonText,
    Object.hashAll(fields.map((field) => field.id)),
    Object.hashAll(
      fieldOverrides.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAll(dependencies),
    blockedMessage,
    isActive,
    createdAt,
    updatedAt,
  );

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

  static bool _dependencyListEquals(
    List<StatusDependency> a,
    List<StatusDependency> b,
  ) {
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

  static bool _fieldListEquals(List<StatusField> a, List<StatusField> b) {
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

  static bool _fieldOverrideMapEquals(
    Map<String, StatusFieldOverride> a,
    Map<String, StatusFieldOverride> b,
  ) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
