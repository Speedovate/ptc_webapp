class DispatcherAccessCapability {
  static const dashboardRead = 'dashboard.read';
  static const dashboardUpdateBilling = 'dashboard.update_billing';
  static const dashboardExport = 'dashboard.export';

  static const bookingsCreate = 'bookings.create';
  static const bookingsRead = 'bookings.read';
  static const bookingsUpdate = 'bookings.update';

  static const usersCreate = 'users.create';
  static const usersRead = 'users.read';
  static const usersUpdate = 'users.update';
  static const usersDelete = 'users.delete';
  static const usersImpersonate = 'users.impersonate';

  static const vehicleMakesCreate = 'vehicle_makes.create';
  static const vehicleMakesRead = 'vehicle_makes.read';
  static const vehicleMakesUpdate = 'vehicle_makes.update';
  static const vehicleMakesDelete = 'vehicle_makes.delete';

  static const vehicleTypesCreate = 'vehicle_types.create';
  static const vehicleTypesRead = 'vehicle_types.read';
  static const vehicleTypesUpdate = 'vehicle_types.update';
  static const vehicleTypesDelete = 'vehicle_types.delete';

  static const vehicleSizesCreate = 'vehicle_sizes.create';
  static const vehicleSizesRead = 'vehicle_sizes.read';
  static const vehicleSizesUpdate = 'vehicle_sizes.update';
  static const vehicleSizesDelete = 'vehicle_sizes.delete';

  static const statusesCreate = 'statuses.create';
  static const statusesRead = 'statuses.read';
  static const statusesUpdate = 'statuses.update';
  static const statusesDelete = 'statuses.delete';

  static const formsCreate = 'forms.create';
  static const formsRead = 'forms.read';
  static const formsUpdate = 'forms.update';
  static const formsDelete = 'forms.delete';

  static const fieldsCreate = 'fields.create';
  static const fieldsRead = 'fields.read';
  static const fieldsUpdate = 'fields.update';
  static const fieldsDelete = 'fields.delete';

  static const supportCreate = 'support.create';
  static const supportRead = 'support.read';
  static const supportUpdate = 'support.update';

  static const roleAccessRead = 'role_access.read';
  static const roleAccessUpdate = 'role_access.update';

  static const profileRead = 'profile.read';
  static const profileUpdate = 'profile.update';

  static const syncRead = 'sync.read';
  static const syncUpdate = 'sync.update';

  static const values = <String>[
    dashboardRead,
    dashboardUpdateBilling,
    dashboardExport,
    bookingsCreate,
    bookingsRead,
    bookingsUpdate,
    usersCreate,
    usersRead,
    usersUpdate,
    usersDelete,
    usersImpersonate,
    vehicleMakesCreate,
    vehicleMakesRead,
    vehicleMakesUpdate,
    vehicleMakesDelete,
    vehicleTypesCreate,
    vehicleTypesRead,
    vehicleTypesUpdate,
    vehicleTypesDelete,
    vehicleSizesCreate,
    vehicleSizesRead,
    vehicleSizesUpdate,
    vehicleSizesDelete,
    statusesCreate,
    statusesRead,
    statusesUpdate,
    statusesDelete,
    formsCreate,
    formsRead,
    formsUpdate,
    formsDelete,
    fieldsCreate,
    fieldsRead,
    fieldsUpdate,
    fieldsDelete,
    supportCreate,
    supportRead,
    supportUpdate,
    roleAccessRead,
    roleAccessUpdate,
    profileRead,
    profileUpdate,
    syncRead,
    syncUpdate,
  ];
}

const builtInRoleKeys = <String>[
  'admin',
  'dispatcher',
  'manager',
  'client',
  'driver',
  'helper',
];

final Map<String, bool> defaultAdminAccessCapabilities = {
  for (final capability in DispatcherAccessCapability.values) capability: true,
};

const Map<String, bool> defaultDispatcherAccessCapabilities = {
  DispatcherAccessCapability.dashboardRead: true,
  DispatcherAccessCapability.dashboardUpdateBilling: true,
  DispatcherAccessCapability.dashboardExport: true,
  DispatcherAccessCapability.bookingsCreate: true,
  DispatcherAccessCapability.bookingsRead: true,
  DispatcherAccessCapability.bookingsUpdate: true,
  DispatcherAccessCapability.usersCreate: true,
  DispatcherAccessCapability.usersRead: true,
  DispatcherAccessCapability.usersUpdate: true,
  DispatcherAccessCapability.usersDelete: false,
  DispatcherAccessCapability.usersImpersonate: false,
  DispatcherAccessCapability.vehicleMakesCreate: false,
  DispatcherAccessCapability.vehicleMakesRead: false,
  DispatcherAccessCapability.vehicleMakesUpdate: false,
  DispatcherAccessCapability.vehicleMakesDelete: false,
  DispatcherAccessCapability.vehicleTypesCreate: false,
  DispatcherAccessCapability.vehicleTypesRead: false,
  DispatcherAccessCapability.vehicleTypesUpdate: false,
  DispatcherAccessCapability.vehicleTypesDelete: false,
  DispatcherAccessCapability.vehicleSizesCreate: false,
  DispatcherAccessCapability.vehicleSizesRead: false,
  DispatcherAccessCapability.vehicleSizesUpdate: false,
  DispatcherAccessCapability.vehicleSizesDelete: false,
  DispatcherAccessCapability.statusesCreate: false,
  DispatcherAccessCapability.statusesRead: false,
  DispatcherAccessCapability.statusesUpdate: false,
  DispatcherAccessCapability.statusesDelete: false,
  DispatcherAccessCapability.formsCreate: false,
  DispatcherAccessCapability.formsRead: false,
  DispatcherAccessCapability.formsUpdate: false,
  DispatcherAccessCapability.formsDelete: false,
  DispatcherAccessCapability.fieldsCreate: false,
  DispatcherAccessCapability.fieldsRead: false,
  DispatcherAccessCapability.fieldsUpdate: false,
  DispatcherAccessCapability.fieldsDelete: false,
  DispatcherAccessCapability.supportCreate: true,
  DispatcherAccessCapability.supportRead: true,
  DispatcherAccessCapability.supportUpdate: true,
  DispatcherAccessCapability.roleAccessRead: false,
  DispatcherAccessCapability.roleAccessUpdate: false,
  DispatcherAccessCapability.profileRead: true,
  DispatcherAccessCapability.profileUpdate: true,
  DispatcherAccessCapability.syncRead: true,
  DispatcherAccessCapability.syncUpdate: true,
};

const Map<String, bool> defaultClientAccessCapabilities = {
  DispatcherAccessCapability.bookingsCreate: true,
  DispatcherAccessCapability.bookingsRead: true,
  DispatcherAccessCapability.bookingsUpdate: true,
  DispatcherAccessCapability.supportCreate: true,
  DispatcherAccessCapability.supportRead: true,
  DispatcherAccessCapability.supportUpdate: true,
  DispatcherAccessCapability.roleAccessRead: false,
  DispatcherAccessCapability.roleAccessUpdate: false,
  DispatcherAccessCapability.profileRead: true,
  DispatcherAccessCapability.profileUpdate: true,
  DispatcherAccessCapability.syncRead: true,
  DispatcherAccessCapability.syncUpdate: true,
};

const Map<String, bool> defaultDriverAccessCapabilities = {
  DispatcherAccessCapability.bookingsRead: true,
  DispatcherAccessCapability.bookingsUpdate: true,
  DispatcherAccessCapability.supportCreate: true,
  DispatcherAccessCapability.supportRead: true,
  DispatcherAccessCapability.supportUpdate: true,
  DispatcherAccessCapability.roleAccessRead: false,
  DispatcherAccessCapability.roleAccessUpdate: false,
  DispatcherAccessCapability.profileRead: true,
  DispatcherAccessCapability.profileUpdate: true,
  DispatcherAccessCapability.syncRead: true,
  DispatcherAccessCapability.syncUpdate: true,
};

const Map<String, bool> defaultHelperAccessCapabilities = {
  DispatcherAccessCapability.bookingsRead: true,
  DispatcherAccessCapability.bookingsUpdate: true,
  DispatcherAccessCapability.supportCreate: true,
  DispatcherAccessCapability.supportRead: true,
  DispatcherAccessCapability.supportUpdate: true,
  DispatcherAccessCapability.roleAccessRead: false,
  DispatcherAccessCapability.roleAccessUpdate: false,
  DispatcherAccessCapability.profileRead: true,
  DispatcherAccessCapability.profileUpdate: true,
  DispatcherAccessCapability.syncRead: true,
  DispatcherAccessCapability.syncUpdate: true,
};

Map<String, bool> defaultAccessCapabilitiesForRole(String roleKey) {
  final normalizedRole = _normalizeRoleKey(roleKey) ?? '';
  final seededDefaults = switch (normalizedRole) {
    'admin' => defaultAdminAccessCapabilities,
    'dispatcher' => defaultDispatcherAccessCapabilities,
    'manager' => defaultDispatcherAccessCapabilities,
    'client' => defaultClientAccessCapabilities,
    'driver' => defaultDriverAccessCapabilities,
    'helper' => defaultHelperAccessCapabilities,
    _ => const <String, bool>{},
  };
  return {
    for (final capability in DispatcherAccessCapability.values)
      capability: seededDefaults[capability] == true,
  };
}

class DispatcherAccessConfig {
  const DispatcherAccessConfig({
    this.id = 'dispatcher',
    this.role = 'dispatcher',
    required this.capabilities,
    this.createdAtIso,
    this.updatedAtIso,
  });

  final String id;
  final String role;
  final Map<String, bool> capabilities;
  final String? createdAtIso;
  final String? updatedAtIso;

  factory DispatcherAccessConfig.defaults({
    String roleKey = 'dispatcher',
  }) {
    final normalizedRole = _normalizeRoleKey(roleKey) ?? 'dispatcher';
    final baseCapabilities = defaultAccessCapabilitiesForRole(normalizedRole);
    return DispatcherAccessConfig(
      id: normalizedRole,
      role: normalizedRole,
      capabilities: baseCapabilities,
    );
  }

  factory DispatcherAccessConfig.fromMap(Map<String, dynamic> map) {
    final resolvedRole = map['role']?.toString().trim().isNotEmpty == true
        ? map['role'].toString().trim()
        : 'dispatcher';
    final rawCapabilities = map['capabilities'];
    final capabilities = <String, bool>{
      ...defaultAccessCapabilitiesForRole(resolvedRole),
    };
    if (rawCapabilities is Map) {
      rawCapabilities.forEach((key, value) {
        capabilities[key.toString()] = value == true;
      });
    }
    return DispatcherAccessConfig(
      id: map['id']?.toString().trim().isNotEmpty == true
          ? map['id'].toString().trim()
          : 'dispatcher',
      role: resolvedRole,
      capabilities: capabilities,
      createdAtIso: map['created_at']?.toString(),
      updatedAtIso: map['updated_at']?.toString(),
    );
  }

  DispatcherAccessConfig copyWith({
    String? id,
    String? role,
    Map<String, bool>? capabilities,
    String? createdAtIso,
    String? updatedAtIso,
  }) {
    return DispatcherAccessConfig(
      id: id ?? this.id,
      role: role ?? this.role,
      capabilities: capabilities ?? this.capabilities,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
    );
  }

  bool isEnabled(String capabilityKey) {
    return capabilities[capabilityKey] ??
        defaultAccessCapabilitiesForRole(role)[capabilityKey] ??
        false;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'role': role,
      'capabilities': {
        for (final capability in DispatcherAccessCapability.values)
          capability: isEnabled(capability),
      },
      'created_at': createdAtIso,
      'updated_at': updatedAtIso,
    };
  }
}

String? _normalizeRoleKey(String? value) {
  final normalized = (value ?? '').trim().toLowerCase().replaceAll('_', '-');
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized == 'sub-client' || normalized == 'member') {
    return 'client';
  }
  return normalized;
}
