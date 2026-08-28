import 'dart:convert';

import 'package:webapp/models/vehicle_catalog_item.dart';

class UserModel {
  const UserModel({
    this.id,
    this.firebaseAuthUid,
    this.role,
    this.parentClientId,
    this.email,
    this.name,
    this.photo,
    this.phone,
    this.position,
    this.isActive = false,
    this.isOnline = false,
    this.password,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? firebaseAuthUid;
  final String? role;
  final String? parentClientId;
  final String? email;
  final String? name;
  final String? photo;
  final String? phone;
  final String? position;
  final bool? isActive;
  final bool? isOnline;
  final String? password;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DriverModel? get asDriver => this is DriverModel ? this as DriverModel : null;

  UserModel copyWith({
    String? id,
    String? firebaseAuthUid,
    String? role,
    String? parentClientId,
    String? email,
    String? name,
    String? photo,
    String? phone,
    String? position,
    bool? isActive,
    bool? isOnline,
    String? password,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? license,
    VehicleCatalogItem? vehicleType,
  }) {
    final nextRole = role ?? this.role;
    final currentDriver = asDriver;

    if (nextRole == 'driver') {
      return DriverModel(
        id: id ?? this.id,
        firebaseAuthUid: firebaseAuthUid ?? this.firebaseAuthUid,
        role: nextRole,
        parentClientId: parentClientId ?? this.parentClientId,
        email: email ?? this.email,
        name: name ?? this.name,
        photo: photo ?? this.photo,
        phone: phone ?? this.phone,
        position: position ?? this.position,
        isActive: isActive ?? this.isActive,
        isOnline: isOnline ?? this.isOnline,
        password: password ?? this.password,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        license: license ?? currentDriver?.license,
        vehicleType: vehicleType ?? currentDriver?.vehicleType,
      );
    }

    return UserModel(
      id: id ?? this.id,
      firebaseAuthUid: firebaseAuthUid ?? this.firebaseAuthUid,
      role: nextRole,
      parentClientId: parentClientId ?? this.parentClientId,
      email: email ?? this.email,
      name: name ?? this.name,
      photo: photo ?? this.photo,
      phone: phone ?? this.phone,
      position: position ?? this.position,
      isActive: isActive ?? this.isActive,
      isOnline: isOnline ?? this.isOnline,
      password: password ?? this.password,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firebase_auth_uid': firebaseAuthUid,
      'role': role,
      'parent_client_id': parentClientId,
      'email': email,
      'name': name,
      'photo': photo,
      'phone': phone,
      'position': position,
      'is_active': isActive,
      'is_online': isOnline,
      'password': password,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    if (map['role']?.toString() == 'driver') {
      return DriverModel.fromMap(map);
    }

    return UserModel(
      id: map['id']?.toString(),
      firebaseAuthUid: map['firebase_auth_uid']?.toString(),
      role: map['role']?.toString(),
      parentClientId: map['parent_client_id']?.toString(),
      email: map['email']?.toString(),
      name: map['name']?.toString(),
      photo: map['photo']?.toString(),
      phone: map['phone']?.toString(),
      position: map['position']?.toString(),
      isActive: map['is_active'] as bool? ?? false,
      isOnline: map['is_online'] as bool? ?? false,
      password: map['password']?.toString(),
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }

  String toJson() => json.encode(toMap());

  factory UserModel.fromJson(String source) {
    return UserModel.fromMap(json.decode(source) as Map<String, dynamic>);
  }
}

class DriverModel extends UserModel {
  const DriverModel({
    super.id,
    super.firebaseAuthUid,
    super.role = 'driver',
    super.parentClientId,
    super.email,
    super.name,
    super.photo,
    super.phone,
    super.position,
    super.isActive = false,
    super.isOnline = false,
    super.password,
    super.createdAt,
    super.updatedAt,
    this.license,
    this.vehicleType,
  });

  final String? license;
  final VehicleCatalogItem? vehicleType;

  @override
  Map<String, dynamic> toMap() {
    return {
      ...super.toMap(),
      'license': license,
      'vehicle_type': vehicleType?.toMap(),
    };
  }

  factory DriverModel.fromMap(Map<String, dynamic> map) {
    return DriverModel(
      id: map['id']?.toString(),
      firebaseAuthUid: map['firebase_auth_uid']?.toString(),
      role: map['role']?.toString() ?? 'driver',
      parentClientId: map['parent_client_id']?.toString(),
      email: map['email']?.toString(),
      name: map['name']?.toString(),
      photo: map['photo']?.toString(),
      phone: map['phone']?.toString(),
      position: map['position']?.toString(),
      isActive: map['is_active'] as bool? ?? false,
      isOnline: map['is_online'] as bool? ?? false,
      password: map['password']?.toString(),
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
      license: map['license']?.toString(),
      vehicleType: map['vehicle_type'] is Map
          ? VehicleCatalogItem.fromMap(
              Map<String, dynamic>.from(map['vehicle_type'] as Map),
            )
          : null,
    );
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
