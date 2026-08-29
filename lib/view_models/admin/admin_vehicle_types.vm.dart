import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';

class AdminVehicleTypesViewModel extends BaseViewModel {
  AdminVehicleTypesViewModel({VehicleCatalogRepository? repository})
    : _repository = repository ?? VehicleRequest.instance {
    _types = List<VehicleCatalogItem>.from(_cachedTypes);
    _errorMessage = _cachedErrorMessage;
    _hasLoadedOnce = _cachedHasLoadedOnce;
  }

  final VehicleCatalogRepository _repository;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  StreamSubscription<void>? _catalogCacheUpdatesSubscription;
  static List<VehicleCatalogItem> _cachedTypes = const [];
  static String? _cachedErrorMessage;
  static bool _cachedHasLoadedOnce = false;

  static void clearCachedState() {
    _cachedTypes = const [];
    _cachedErrorMessage = null;
    _cachedHasLoadedOnce = false;
  }

  List<VehicleCatalogItem> _types = const [];
  String? _errorMessage;
  String _busyMessage = 'Loading, please wait ...';
  bool _hasLoadedOnce = false;
  bool _didScheduleWarmRetry = false;
  bool _isRealtimeRefreshing = false;

  List<VehicleCatalogItem> get types => _types;
  String? get errorMessage => _errorMessage;
  String get busyMessage => _busyMessage;
  bool get showBlockingLoading =>
      isBusy && !_hasLoadedOnce && _types.isEmpty && _cachedTypes.isEmpty;
  bool get canReadTypes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleTypesRead,
  );
  bool get canCreateTypes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleTypesCreate,
  );
  bool get canUpdateTypes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleTypesUpdate,
  );
  bool get canDeleteTypes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleTypesDelete,
  );

  Future<void> load() async {
    _ensureCatalogRealtimeSubscription();
    if (!canReadTypes) {
      _errorMessage = 'You do not have access to view vehicle types.';
      notifyListeners();
      return;
    }
    _busyMessage = 'Loading vehicle types ...';
    final hasVisiblePrimaryData = _types.isNotEmpty || _cachedTypes.isNotEmpty;
    final shouldShowLoadingState = !_hasLoadedOnce && !hasVisiblePrimaryData;
    if (shouldShowLoadingState) {
      setBusy(true);
    }
    _errorMessage = null;
    try {
      _types = await _repository.getTypes();
      _sortTypes();
      _cachedTypes = List<VehicleCatalogItem>.from(_types);
      _cachedErrorMessage = null;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      notifyListeners();
      _scheduleWarmRetryIfNeeded();
    } catch (error) {
      _errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the vehicle types right now.',
      );
      _cachedErrorMessage = _errorMessage;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      notifyListeners();
      _scheduleWarmRetryIfNeeded();
    } finally {
      if (shouldShowLoadingState) {
        setBusy(false);
      }
    }
  }

  void _ensureCatalogRealtimeSubscription() {
    _catalogCacheUpdatesSubscription ??= VehicleRequest.instance
        .watchCatalogCacheUpdates()
        .listen((_) {
          unawaited(_reloadFromRealtime());
        });
  }

  Future<void> _reloadFromRealtime() async {
    if (_isRealtimeRefreshing) {
      return;
    }
    _isRealtimeRefreshing = true;
    try {
      _types = await _repository.getTypes();
      _sortTypes();
      _cachedTypes = List<VehicleCatalogItem>.from(_types);
      notifyListeners();
    } catch (_) {
      // Keep the current visible state if a live refresh fails.
    } finally {
      _isRealtimeRefreshing = false;
    }
  }

  void _scheduleWarmRetryIfNeeded() {
    if (_didScheduleWarmRetry ||
        !currentNetworkStatus() ||
        _types.isNotEmpty ||
        _cachedTypes.isNotEmpty) {
      return;
    }
    _didScheduleWarmRetry = true;
    unawaited(_retryLoadAfterWarmup());
  }

  Future<void> _retryLoadAfterWarmup() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    try {
      final refreshedTypes = await _repository.getTypes();
      if (refreshedTypes.isEmpty) {
        return;
      }
      _types = refreshedTypes;
      _sortTypes();
      _cachedTypes = List<VehicleCatalogItem>.from(_types);
      _cachedErrorMessage = null;
      notifyListeners();
    } catch (_) {}
  }

  Future<VehicleCatalogItem> saveType(VehicleCatalogItem type) async {
    final isExisting = (type.id ?? '').trim().isNotEmpty;
    if (isExisting ? !canUpdateTypes : !canCreateTypes) {
      throw const AuthFailure(
        'You do not have access to save vehicle types.',
      );
    }
    _busyMessage = 'Saving vehicle type ...';
    setBusy(true);
    try {
      final saved = await _repository.saveType(type);
      final index = _types.indexWhere((item) => item.id == saved.id);
      if (index >= 0) {
        _types[index] = saved;
      } else {
        _types = [..._types, saved];
      }
      _sortTypes();
      _cachedTypes = List<VehicleCatalogItem>.from(_types);
      notifyListeners();
      return saved;
    } catch (error) {
      rethrow;
    } finally {
      setBusy(false);
    }
  }

  Future<void> deleteType(VehicleCatalogItem type) async {
    if (!canDeleteTypes) {
      throw const AuthFailure(
        'You do not have access to delete vehicle types.',
      );
    }
    final typeId = type.id;
    if (typeId == null || typeId.isEmpty) {
      return;
    }
    _busyMessage = 'Deleting vehicle type ...';
    setBusy(true);
    try {
      await _repository.deleteType(typeId);
      _types = _types.where((item) => item.id != typeId).toList();
      _cachedTypes = List<VehicleCatalogItem>.from(_types);
      notifyListeners();
    } finally {
      setBusy(false);
    }
  }

  Future<VehicleCatalogItem> setTypeActive(
    VehicleCatalogItem type,
    bool isActive,
  ) {
    if (!canUpdateTypes) {
      throw const AuthFailure(
        'You do not have access to update vehicle types.',
      );
    }
    _busyMessage = isActive
        ? 'Activating vehicle type ...'
        : 'Deactivating vehicle type ...';
    return saveType(
      type.copyWith(isActive: isActive, updatedAt: DateTime.now()),
    );
  }

  void _sortTypes() {
    _types.sort((a, b) {
      final createdComparison = _compareLatestFirst(a.createdAt, b.createdAt);
      if (createdComparison != 0) {
        return createdComparison;
      }

      final aId = int.tryParse(a.id ?? '');
      final bId = int.tryParse(b.id ?? '');
      if (aId != null && bId != null) {
        return bId.compareTo(aId);
      }
      return (b.id ?? '').compareTo(a.id ?? '');
    });
  }

  int _compareLatestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) {
      return 0;
    }
    if (a == null) {
      return 1;
    }
    if (b == null) {
      return -1;
    }
    return b.compareTo(a);
  }

  @override
  void dispose() {
    _catalogCacheUpdatesSubscription?.cancel();
    super.dispose();
  }
}
