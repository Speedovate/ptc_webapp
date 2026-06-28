import 'dart:convert';

import 'package:webapp/utils/functions.dart';

const _clientMemberUndefined = Object();

class ClientMember {
  const ClientMember({
    this.id,
    this.clientId,
    this.userId,
    this.email,
    this.photo,
    this.name,
    this.phone,
    this.position,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? clientId;
  final String? userId;
  final String? email;
  final String? photo;
  final String? name;
  final String? phone;
  final String? position;
  final bool? isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ClientMember copyWith({
    Object? id = _clientMemberUndefined,
    Object? clientId = _clientMemberUndefined,
    Object? userId = _clientMemberUndefined,
    Object? email = _clientMemberUndefined,
    Object? photo = _clientMemberUndefined,
    Object? name = _clientMemberUndefined,
    Object? phone = _clientMemberUndefined,
    Object? position = _clientMemberUndefined,
    Object? isActive = _clientMemberUndefined,
    Object? createdAt = _clientMemberUndefined,
    Object? updatedAt = _clientMemberUndefined,
  }) {
    return ClientMember(
      id: identical(id, _clientMemberUndefined) ? this.id : id as String?,
      clientId: identical(clientId, _clientMemberUndefined)
          ? this.clientId
          : clientId as String?,
      userId: identical(userId, _clientMemberUndefined)
          ? this.userId
          : userId as String?,
      email: identical(email, _clientMemberUndefined)
          ? this.email
          : email as String?,
      photo: identical(photo, _clientMemberUndefined)
          ? this.photo
          : photo as String?,
      name: identical(name, _clientMemberUndefined)
          ? this.name
          : name as String?,
      phone: identical(phone, _clientMemberUndefined)
          ? this.phone
          : phone as String?,
      position: identical(position, _clientMemberUndefined)
          ? this.position
          : position as String?,
      isActive: identical(isActive, _clientMemberUndefined)
          ? this.isActive
          : isActive as bool?,
      createdAt: identical(createdAt, _clientMemberUndefined)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _clientMemberUndefined)
          ? this.updatedAt
          : updatedAt as DateTime?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'client_id': clientId,
      'user_id': userId,
      'email': email,
      'photo': photo,
      'name': name,
      'phone': phone,
      'position': position,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory ClientMember.fromMap(Map<String, dynamic> map) {
    return ClientMember(
      id: map['id']?.toString(),
      clientId: map['client_id']?.toString(),
      userId: map['user_id']?.toString(),
      email: map['email']?.toString(),
      photo: map['photo']?.toString(),
      name: map['name']?.toString(),
      phone: map['phone']?.toString(),
      position: map['position']?.toString(),
      isActive: map['is_active'] as bool? ?? true,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }

  String toJson() => json.encode(toMap());

  factory ClientMember.fromJson(String source) {
    return ClientMember.fromMap(json.decode(source) as Map<String, dynamic>);
  }

  String get displayName {
    final trimmed = name?.trim();
    return trimmed?.isNotEmpty == true ? trimmed! : 'Unnamed Member';
  }

  String get normalizedPhone {
    return normalizePhilippinePhone(phone) ?? (phone?.trim() ?? '');
  }
}

DateTime? _toDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse(value.toString());
}
