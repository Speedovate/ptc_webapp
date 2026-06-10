import 'dart:convert';

class Booking {
  const Booking({
    this.id,
    this.clientId,
    this.clientStatus,
    this.driverStatus,
    this.helperStatus,
    this.truckId,
    this.driverId,
    this.helperId,
    this.statusOutputs,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? clientId;
  final String? clientStatus;
  final String? driverStatus;
  final String? helperStatus;
  final String? truckId;
  final String? driverId;
  final String? helperId;
  final Map<String, dynamic>? statusOutputs;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Booking copyWith({
    String? id,
    String? clientId,
    String? clientStatus,
    String? driverStatus,
    String? helperStatus,
    String? truckId,
    String? driverId,
    String? helperId,
    Map<String, dynamic>? statusOutputs,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Booking(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      clientStatus: clientStatus ?? this.clientStatus,
      driverStatus: driverStatus ?? this.driverStatus,
      helperStatus: helperStatus ?? this.helperStatus,
      truckId: truckId ?? this.truckId,
      driverId: driverId ?? this.driverId,
      helperId: helperId ?? this.helperId,
      statusOutputs: statusOutputs ?? this.statusOutputs,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'client_id': clientId,
      'client_status': clientStatus,
      'driver_status': driverStatus,
      'helper_status': helperStatus,
      'truck_id': truckId,
      'driver_id': driverId,
      'helper_id': helperId,
      'status_outputs': statusOutputs,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory Booking.fromMap(Map<String, dynamic> map) {
    return Booking(
      id: map['id']?.toString(),
      clientId: map['client_id']?.toString(),
      clientStatus: map['client_status']?.toString(),
      driverStatus: map['driver_status']?.toString(),
      helperStatus: map['helper_status']?.toString(),
      truckId: map['truck_id']?.toString(),
      driverId: map['driver_id']?.toString(),
      helperId: map['helper_id']?.toString(),
      statusOutputs: map['status_outputs'] is Map
          ? Map<String, dynamic>.from(map['status_outputs'] as Map)
          : null,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }

  String toJson() => json.encode(toMap());

  factory Booking.fromJson(String source) {
    return Booking.fromMap(json.decode(source) as Map<String, dynamic>);
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
