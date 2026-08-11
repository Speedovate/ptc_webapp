import 'dart:convert';

import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_make.dart';

const _bookingUndefined = Object();

class Booking {
  const Booking({
    this.id,
    this.client,
    this.clientStatus,
    this.billingStatus,
    this.driverStatus,
    this.helperStatus,
    this.vehicleMake,
    this.driver,
    this.helper,
    this.statusOutputs,
    this.createdAt,
    this.updatedAt,
    this.localSyncStatus,
  });

  final String? id;
  final UserModel? client;
  final String? clientStatus;
  final String? billingStatus;
  final String? driverStatus;
  final String? helperStatus;
  final VehicleMake? vehicleMake;
  final UserModel? driver;
  final UserModel? helper;
  final Map<String, dynamic>? statusOutputs;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? localSyncStatus;

  Booking copyWith({
    Object? id = _bookingUndefined,
    Object? client = _bookingUndefined,
    Object? clientStatus = _bookingUndefined,
    Object? billingStatus = _bookingUndefined,
    Object? driverStatus = _bookingUndefined,
    Object? helperStatus = _bookingUndefined,
    Object? vehicleMake = _bookingUndefined,
    Object? driver = _bookingUndefined,
    Object? helper = _bookingUndefined,
    Object? statusOutputs = _bookingUndefined,
    Object? createdAt = _bookingUndefined,
    Object? updatedAt = _bookingUndefined,
    Object? localSyncStatus = _bookingUndefined,
  }) {
    return Booking(
      id: identical(id, _bookingUndefined) ? this.id : id as String?,
      client: identical(client, _bookingUndefined)
          ? this.client
          : client as UserModel?,
      clientStatus: identical(clientStatus, _bookingUndefined)
          ? this.clientStatus
          : clientStatus as String?,
      billingStatus: identical(billingStatus, _bookingUndefined)
          ? this.billingStatus
          : billingStatus as String?,
      driverStatus: identical(driverStatus, _bookingUndefined)
          ? this.driverStatus
          : driverStatus as String?,
      helperStatus: identical(helperStatus, _bookingUndefined)
          ? this.helperStatus
          : helperStatus as String?,
      vehicleMake: identical(vehicleMake, _bookingUndefined)
          ? this.vehicleMake
          : vehicleMake as VehicleMake?,
      driver: identical(driver, _bookingUndefined)
          ? this.driver
          : driver as UserModel?,
      helper: identical(helper, _bookingUndefined)
          ? this.helper
          : helper as UserModel?,
      statusOutputs: identical(statusOutputs, _bookingUndefined)
          ? this.statusOutputs
          : statusOutputs as Map<String, dynamic>?,
      createdAt: identical(createdAt, _bookingUndefined)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _bookingUndefined)
          ? this.updatedAt
          : updatedAt as DateTime?,
      localSyncStatus: identical(localSyncStatus, _bookingUndefined)
          ? this.localSyncStatus
          : localSyncStatus as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'client': client?.toMap(),
      'client_status': clientStatus,
      'billing_status': billingStatus,
      'driver_status': driverStatus,
      'helper_status': helperStatus,
      'vehicle_make': vehicleMake?.toMap(),
      'driver': driver?.toMap(),
      'helper': helper?.toMap(),
      'status_outputs': statusOutputs,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'local_sync_status': localSyncStatus,
    };
  }

  factory Booking.fromMap(Map<String, dynamic> map) {
    return Booking(
      id: map['id']?.toString(),
      client: _toUserModel(map['client']),
      clientStatus: map['client_status']?.toString(),
      billingStatus: map['billing_status']?.toString(),
      driverStatus: map['driver_status']?.toString(),
      helperStatus: map['helper_status']?.toString(),
      vehicleMake: _toVehicleMake(map['vehicle_make']),
      driver: _toUserModel(map['driver']),
      helper: _toUserModel(map['helper']),
      statusOutputs: map['status_outputs'] is Map
          ? Map<String, dynamic>.from(map['status_outputs'] as Map)
          : null,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
      localSyncStatus: map['local_sync_status']?.toString(),
    );
  }

  String toJson() => json.encode(toMap());

  factory Booking.fromJson(String source) {
    return Booking.fromMap(json.decode(source) as Map<String, dynamic>);
  }

  static UserModel? _toUserModel(dynamic value) {
    if (value is Map) {
      return UserModel.fromMap(Map<String, dynamic>.from(value));
    }
    return null;
  }

  static VehicleMake? _toVehicleMake(dynamic value) {
    if (value is Map) {
      return VehicleMake.fromMap(Map<String, dynamic>.from(value));
    }
    return null;
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
