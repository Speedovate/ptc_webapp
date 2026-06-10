import 'dart:convert';

class VehicleCatalogItem {
  const VehicleCatalogItem({
    this.id,
    this.name,
    this.slug,
    this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? name;
  final String? slug;
  final bool? isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  VehicleCatalogItem copyWith({
    String? id,
    String? name,
    String? slug,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VehicleCatalogItem(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory VehicleCatalogItem.fromMap(Map<String, dynamic> map) {
    return VehicleCatalogItem(
      id: map['id']?.toString(),
      name: map['name']?.toString(),
      slug: map['slug']?.toString(),
      isActive: map['is_active'] as bool?,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }

  String toJson() => json.encode(toMap());

  factory VehicleCatalogItem.fromJson(String source) {
    return VehicleCatalogItem.fromMap(
      json.decode(source) as Map<String, dynamic>,
    );
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
