import 'dart:convert';

const _statusUndefined = Object();

class Status {
  const Status({
    this.id,
    this.key,
    this.label,
    this.description,
    this.applicableRoles = const [],
    this.roleMessages = const {},
    this.sortOrder,
    this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? key;
  final String? label;
  final String? description;
  final List<String> applicableRoles;
  final Map<String, String> roleMessages;
  final int? sortOrder;
  final bool? isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Status copyWith({
    Object? id = _statusUndefined,
    Object? key = _statusUndefined,
    Object? label = _statusUndefined,
    Object? description = _statusUndefined,
    List<String>? applicableRoles,
    Map<String, String>? roleMessages,
    Object? sortOrder = _statusUndefined,
    Object? isActive = _statusUndefined,
    Object? createdAt = _statusUndefined,
    Object? updatedAt = _statusUndefined,
  }) {
    return Status(
      id: identical(id, _statusUndefined) ? this.id : id as String?,
      key: identical(key, _statusUndefined)
          ? this.key
          : key as String?,
      label: identical(label, _statusUndefined)
          ? this.label
          : label as String?,
      description: identical(description, _statusUndefined)
          ? this.description
          : description as String?,
      applicableRoles: applicableRoles ?? this.applicableRoles,
      roleMessages: roleMessages ?? this.roleMessages,
      sortOrder: identical(sortOrder, _statusUndefined)
          ? this.sortOrder
          : sortOrder as int?,
      isActive: identical(isActive, _statusUndefined)
          ? this.isActive
          : isActive as bool?,
      createdAt: identical(createdAt, _statusUndefined)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _statusUndefined)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'key': key,
      'label': label,
      'description': description,
      'applicable_roles': applicableRoles,
      'role_messages': roleMessages,
      'sort_order': sortOrder,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory Status.fromMap(Map<String, dynamic> map) {
    return Status(
      id: map['id']?.toString(),
      key: map['key']?.toString(),
      label: map['label']?.toString(),
      description: map['description']?.toString(),
      applicableRoles: (map['applicable_roles'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      roleMessages: (map['role_messages'] as Map?)
              ?.map(
                (key, value) => MapEntry(
                  key.toString(),
                  value?.toString() ?? '',
                ),
              ) ??
          const {},
      sortOrder: _toInt(map['sort_order']),
      isActive: map['is_active'] as bool?,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }

  String toJson() => json.encode(toMap());

  factory Status.fromJson(String source) {
    return Status.fromMap(
      json.decode(source) as Map<String, dynamic>,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Status &&
        other.id == id &&
        other.key == key &&
        other.label == label &&
        other.description == description &&
        _listEquals(other.applicableRoles, applicableRoles) &&
        _mapEquals(other.roleMessages, roleMessages) &&
        other.sortOrder == sortOrder &&
        other.isActive == isActive &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    key,
    label,
    description,
    Object.hashAll(applicableRoles),
    Object.hashAll(
      roleMessages.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    sortOrder,
    isActive,
    createdAt,
    updatedAt,
  );

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

  static bool _mapEquals(Map<String, String> a, Map<String, String> b) {
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
