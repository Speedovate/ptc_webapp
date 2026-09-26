import 'dart:convert';

import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/utils/functions.dart';

class VehicleMake {
  const VehicleMake({
    this.id,
    this.code,
    this.type,
    this.driver,
    this.helper,
    this.investorId,
    this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? code;
  final VehicleCatalogItem? type;
  final UserModel? driver;
  final UserModel? helper;

  /// The investor who owns this truck. Null means Paltranco owns it.
  ///
  /// Ownership lives here and is never inferred. The driver on a make is the
  /// current assignment and rotates constantly, so reading ownership off it
  /// would hand a truck to a new investor the moment somebody changed shifts.
  final String? investorId;

  final bool? isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// An active truck that is not fully crewed out yet: no driver, or no helper.
  /// A driver signs up with the truck alone, so this is the normal state right
  /// after a signup and it is the office that closes it by assigning a helper.
  bool get needsCrew {
    if (isActive == false) {
      return false;
    }
    return normalizeId(driver?.id) == null || normalizeId(helper?.id) == null;
  }

  VehicleMake copyWith({
    String? id,
    String? code,
    VehicleCatalogItem? type,
    UserModel? driver,
    UserModel? helper,
    String? investorId,
    bool clearHelper = false,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VehicleMake(
      id: id ?? this.id,
      code: code ?? this.code,
      type: type ?? this.type,
      driver: driver ?? this.driver,
      helper: clearHelper ? null : helper ?? this.helper,
      investorId: investorId ?? this.investorId,
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
      'helper': helper?.toMap(),
      'investor_id': investorId,
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
      helper: map['helper'] is Map
          ? UserModel.fromMap(Map<String, dynamic>.from(map['helper'] as Map))
          : null,
      investorId: map['investor_id']?.toString(),
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
