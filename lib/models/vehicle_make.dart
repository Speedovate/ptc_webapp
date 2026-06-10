import 'dart:convert';

import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';

class VehicleMake {
  const VehicleMake({
    this.id,
    this.code,
    this.type,
    this.driver,
    this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? code;
  final VehicleCatalogItem? type;
  final UserModel? driver;
  final bool? isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  VehicleMake copyWith({
    String? id,
    String? code,
    VehicleCatalogItem? type,
    UserModel? driver,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VehicleMake(
      id: id ?? this.id,
      code: code ?? this.code,
      type: type ?? this.type,
      driver: driver ?? this.driver,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'type': type?.toMap(),
      'driver': driver?.toMap(),
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory VehicleMake.fromMap(Map<String, dynamic> map) {
    return VehicleMake(
      id: map['id']?.toString(),
      code: map['code']?.toString(),
      type: map['type'] is Map
          ? VehicleCatalogItem.fromMap(
              Map<String, dynamic>.from(map['type'] as Map),
            )
          : null,
      driver: map['driver'] is Map
          ? UserModel.fromMap(Map<String, dynamic>.from(map['driver'] as Map))
          : null,
      isActive: map['is_active'] as bool?,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }

  String toJson() => json.encode(toMap());

  factory VehicleMake.fromJson(String source) {
    return VehicleMake.fromMap(json.decode(source) as Map<String, dynamic>);
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
