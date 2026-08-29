import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/role_access.request.dart';

class RoleAccessService extends ChangeNotifier {
  RoleAccessService._();

  static const List<String> _preferredRoleOrder = [
    'client',
    'driver',
    'admin',
    'helper',
    'dispatcher',
    'manager',
  ];
  static const Set<String> _onlineEligibleRoles = {'driver', 'helper'};
  static const Set<String> _assignedBookingRoles = {'driver', 'helper'};

  static final RoleAccessService instance = RoleAccessService._();

  final RoleAccessRequest _request = RoleAccessRequest.instance;
  Map<String, DispatcherAccessConfig> _configsByRole =
      <String, DispatcherAccessConfig>{};
  String? _currentRole;
  bool _isInitialized = false;
  Future<void>? _initializingFuture;

  DispatcherAccessConfig get dispatcherAccess =>
      _configsByRole['dispatcher'] ?? DispatcherAccessConfig.defaults();
  List<DispatcherAccessConfig> get roleAccessConfigs =>
      _configsByRole.values.toList(growable: false);
  List<String> get knownRoleKeys => orderedKnownRoleKeys;
  List<String> get orderedKnownRoleKeys {
    final sourceRoles = {
      ...builtInRoleKeys,
      ..._configsByRole.keys,
    }.where((role) => role != 'sub-client');
    final roles = sourceRoles.toList(growable: false)
          ..sort((a, b) {
            final aIndex = _preferredRoleOrder.indexOf(a);
            final bIndex = _preferredRoleOrder.indexOf(b);
            if (aIndex != -1 && bIndex != -1) {
              return aIndex.compareTo(bIndex);
            }
            if (aIndex != -1) {
              return -1;
            }
            if (bIndex != -1) {
              return 1;
            }
            return a.compareTo(b);
          });
    return roles;
  }

  List<String> get publicRegisterRoleKeys => orderedKnownRoleKeys
      .where(
        (role) => role == 'client' || role == 'driver' || role == 'helper',
      )
      .toList(growable: false);

  List<String> get adminUserRoleKeys => orderedKnownRoleKeys;

  List<String> get workflowRoleKeys => orderedKnownRoleKeys
      .toList(growable: false);
  bool get isInitialized => _isInitialized;
  String? get currentRoleKey => _currentRole;

  Future<void> initialize() async {
    final existingInitialization = _initializingFuture;
    if (existingInitialization != null) {
      await existingInitialization;
      return;
    }
    if (_isInitialized) {
      return;
    }
    final initialization = refresh();
    _initializingFuture = initialization;
    try {
      await initialization;
      _isInitialized = true;
    } finally {
      _initializingFuture = null;
    }
  }

  Future<void> refresh() async {
    try {
      final configs = await _request.getAllRoleAccessConfigs();
      _configsByRole = {
        for (final config in configs) _normalizeRoleKey(config.role)!: config,
      };
    } catch (error) {
      // Preserve the last known in-memory config if refresh fails.
    }
    notifyListeners();
  }

  void setCurrentUser(UserModel? user) {
    final nextRole = _normalizeRoleKey(user?.role);
    if (_currentRole == nextRole) {
      return;
    }
    _currentRole = nextRole;
    notifyListeners();
  }

  Future<void> saveDispatcherAccess(DispatcherAccessConfig config) async {
    final saved = await _request.saveDispatcherAccess(config);
    _configsByRole['dispatcher'] = saved;
    notifyListeners();
  }

  Future<void> saveRoleAccess(DispatcherAccessConfig config) async {
    final normalizedRole = _normalizeRoleKey(config.role);
    if (normalizedRole == null) {
      return;
    }
    final saved = await _request.saveRoleAccess(
      config.copyWith(id: normalizedRole, role: normalizedRole),
    );
    _configsByRole[normalizedRole] = saved;
    notifyListeners();
  }

  bool canAccess(
    String capabilityKey, {
    String? role,
  }) {
    final normalizedRole = effectiveRoleKey(role);
    final config = normalizedRole == null ? null : _configsByRole[normalizedRole];
    final resolvedValue = config != null
        ? config.isEnabled(capabilityKey)
        : (normalizedRole == null
              ? false
              : (defaultAccessCapabilitiesForRole(normalizedRole)[capabilityKey] ??
                    false));
    if (resolvedValue) {
      return true;
    }
    return _resolveImplicitAccess(
      capabilityKey,
      role: normalizedRole,
      config: config,
    );
  }

  String? effectiveRoleKey(String? fallbackRole) {
    return _currentRole ?? _normalizeRoleKey(fallbackRole);
  }

  bool _resolveImplicitAccess(
    String capabilityKey, {
    required String? role,
    required DispatcherAccessConfig? config,
  }) {
    if (role == null) {
      return false;
    }
    bool hasExplicit(String key) {
      if (config != null && config.isEnabled(key)) {
        return true;
      }
      return defaultAccessCapabilitiesForRole(role)[key] == true;
    }

    switch (capabilityKey) {
      case DispatcherAccessCapability.supportRead:
      case DispatcherAccessCapability.supportCreate:
      case DispatcherAccessCapability.supportUpdate:
      case DispatcherAccessCapability.profileRead:
      case DispatcherAccessCapability.profileUpdate:
        return true;
      case DispatcherAccessCapability.syncUpdate:
        return hasExplicit(DispatcherAccessCapability.syncRead);
      default:
        return false;
    }
  }

  DispatcherAccessConfig? accessConfigForRole(String? role) {
    final normalizedRole = _normalizeRoleKey(role);
    if (normalizedRole == null) {
      return null;
    }
    return _configsByRole[normalizedRole] ??
        DispatcherAccessConfig.defaults(roleKey: normalizedRole);
  }

  bool hasAnyAccess(
    Iterable<String> capabilityKeys, {
    String? role,
  }) {
    for (final capabilityKey in capabilityKeys) {
      if (canAccess(capabilityKey, role: role)) {
        return true;
      }
    }
    return false;
  }

  bool hasWorkflowAdminScope({String? role}) {
    return canAccess(DispatcherAccessCapability.bookingsRead, role: role) &&
        canAccess(DispatcherAccessCapability.usersRead, role: role);
  }

  bool usesAdminShell({String? role}) {
    return canAccess(DispatcherAccessCapability.usersRead, role: role) ||
        canAccess(DispatcherAccessCapability.dashboardRead, role: role) ||
        canAccess(DispatcherAccessCapability.vehicleMakesRead, role: role) ||
        canAccess(DispatcherAccessCapability.vehicleTypesRead, role: role) ||
        canAccess(DispatcherAccessCapability.vehicleSizesRead, role: role) ||
        canAccess(DispatcherAccessCapability.statusesRead, role: role) ||
        canAccess(DispatcherAccessCapability.formsRead, role: role) ||
        canAccess(DispatcherAccessCapability.fieldsRead, role: role) ||
        canAccess(DispatcherAccessCapability.roleAccessRead, role: role);
  }

  bool isOnlineEligibleRole(String? role) {
    final normalizedRole = _normalizeRoleKey(role);
    return normalizedRole != null && _onlineEligibleRoles.contains(normalizedRole);
  }

  bool isAssignedBookingRole(String? role) {
    final normalizedRole = _normalizeRoleKey(role);
    return normalizedRole != null && _assignedBookingRoles.contains(normalizedRole);
  }

  String assignedBookingRoleLabel(String? role) {
    final normalizedRole = _normalizeRoleKey(role);
    return switch (normalizedRole) {
      'driver' => 'Driver',
      'helper' => 'Helper',
      _ => 'Assigned User',
    };
  }

  List<String> workflowResolutionRoles(String? role) {
    final normalizedRole = _normalizeRoleKey(role);
    if (normalizedRole == null) {
      return const [];
    }
    final resolved = <String>[normalizedRole];
    if (hasWorkflowAdminScope(role: normalizedRole)) {
      for (final workflowRole in workflowRoleKeys) {
        if (!resolved.contains(workflowRole)) {
          resolved.add(workflowRole);
        }
      }
    }
    return resolved;
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
}
