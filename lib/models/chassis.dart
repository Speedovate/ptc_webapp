class Chassis {
  const Chassis({
    required this.id,
    required this.name,
    required this.isActive,
    required this.currentStatus,
    this.currentBookingId,
    this.currentDriverId,
    this.location,
    this.createdAt,
    this.updatedAt,
    this.submissionKey,
  });

  static const ready = 'ready';
  static const loaded = 'loaded';
  static const empty = 'empty';
  static const returning = 'return';
  static const statuses = <String>[ready, loaded, empty, returning];

  final int id;
  final String name;
  final bool isActive;
  final String currentStatus;
  final int? currentBookingId;
  final int? currentDriverId;
  final String? location;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? submissionKey;

  Chassis copyWith({
    int? id,
    String? name,
    bool? isActive,
    String? currentStatus,
    int? currentBookingId,
    bool clearCurrentBookingId = false,
    int? currentDriverId,
    bool clearCurrentDriverId = false,
    String? location,
    bool clearLocation = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? submissionKey,
  }) => Chassis(
    id: id ?? this.id,
    name: name ?? this.name,
    isActive: isActive ?? this.isActive,
    currentStatus: currentStatus ?? this.currentStatus,
    currentBookingId: clearCurrentBookingId
        ? null
        : (currentBookingId ?? this.currentBookingId),
    currentDriverId: clearCurrentDriverId
        ? null
        : (currentDriverId ?? this.currentDriverId),
    location: clearLocation ? null : (location ?? this.location),
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    submissionKey: submissionKey ?? this.submissionKey,
  );

  factory Chassis.fromMap(Map<String, dynamic> map) {
    final status = map['current_status']?.toString().trim().toLowerCase();
    return Chassis(
      id: _asInt(map['id']) ?? 0,
      name: map['name']?.toString().trim() ?? '',
      isActive: map['is_active'] == true,
      currentStatus: statuses.contains(status) ? status! : ready,
      currentBookingId: _asInt(map['current_booking_id']),
      currentDriverId: _asInt(map['current_driver_id']),
      location: _asNullableText(map['location']),
      createdAt: _asDateTime(map['created_at']),
      updatedAt: _asDateTime(map['updated_at']),
      submissionKey: _asNullableText(map['submission_key']),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'is_active': isActive,
    'current_status': currentStatus,
    'current_booking_id': currentBookingId,
    'current_driver_id': currentDriverId,
    'location': location,
    'created_at': createdAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
    'submission_key': submissionKey,
  };

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _asNullableText(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }
}
