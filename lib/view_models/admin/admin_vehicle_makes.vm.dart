import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/services/app_warmup_service.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';

class AdminVehicleMakesViewModel extends BaseViewModel {
  AdminVehicleMakesViewModel({
    VehicleCatalogRepository? repository,
    AuthRepository? authRepository,
  }) : _repository = repository ?? VehicleRequest.instance,
       _authRepository = authRepository ?? AuthRequest.instance {
    _makes = List<VehicleMake>.from(_cachedMakes);
    _drivers = List<UserModel>.from(_cachedDrivers);
    _types = List<VehicleCatalogItem>.from(_cachedTypes);
    _errorMessage = _cachedErrorMessage;
    _hasLoadedOnce = _cachedHasLoadedOnce;
  }

  final VehicleCatalogRepository _repository;
  final AuthRepository _authRepository;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  final AppWarmupService _warmupService = AppWarmupService.instance;
  StreamSubscription<void>? _catalogCacheUpdatesSubscription;
  static List<VehicleMake> _cachedMakes = const [];
  static List<UserModel> _cachedDrivers = const [];
  static List<VehicleCatalogItem> _cachedTypes = const [];
  static String? _cachedErrorMessage;
  static bool _cachedHasLoadedOnce = false;

  static void clearCachedState() {
    _cachedMakes = const [];
    _cachedDrivers = const [];
    _cachedTypes = const [];
    _cachedErrorMessage = null;
    _cachedHasLoadedOnce = false;
  }

  List<VehicleMake> _makes = const [];
  List<UserModel> _drivers = const [];
  List<VehicleCatalogItem> _types = const [];
  String? _errorMessage;
  String _busyMessage = 'Loading, please wait ...';
  bool _hasLoadedOnce = false;
  bool _didScheduleWarmRetry = false;
  bool _isRealtimeRefreshing = false;

  List<VehicleMake> get makes => _makes;
  List<UserModel> get drivers => _drivers;
  List<VehicleCatalogItem> get types => _types;
  String? get errorMessage => _errorMessage;
  String get busyMessage => _busyMessage;
  bool get showBlockingLoading =>
      isBusy && !_hasLoadedOnce && _makes.isEmpty && _cachedMakes.isEmpty;
  bool get canReadMakes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleMakesRead,
  );
  bool get canCreateMakes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleMakesCreate,
  );
  bool get canUpdateMakes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleMakesUpdate,
  );
  bool get canDeleteMakes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleMakesDelete,
  );

  Future<void> load() async {
    _ensureCatalogRealtimeSubscription();
    if (!canReadMakes) {
      _errorMessage = 'You do not have access to view vehicle makes.';
      notifyListeners();
      return;
    }
    _busyMessage = 'Loading vehicle makes ...';
    final hasSharedPrimaryData = VehicleRequest.hasResolvedMakes;
    final hasVisiblePrimaryData =
        _makes.isNotEmpty || _cachedMakes.isNotEmpty || hasSharedPrimaryData;
    final shouldShowLoadingState = !_hasLoadedOnce && !hasVisiblePrimaryData;
    if (shouldShowLoadingState) {
      setBusy(true);
    }
    _errorMessage = null;
    try {
      if (hasSharedPrimaryData && _makes.isEmpty) {
        _makes = List<VehicleMake>.from(VehicleRequest.hydratedMakesSnapshot);
        _sortMakes();
        notifyListeners();
      }
      await _warmupService.warmVehicleMakes();
      _makes = await _repository.getMakes();
      _sortMakes();
      _cachedMakes = List<VehicleMake>.from(_makes);
      _cachedErrorMessage = null;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      notifyListeners();
      unawaited(_loadSupportingDataInBackground());
      _scheduleWarmRetryIfNeeded();
    } catch (error) {
      _errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the vehicle makes right now.',
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
      await _warmupService.warmVehicleMakes();
      _makes = await _repository.getMakes();
      _sortMakes();
      _cachedMakes = List<VehicleMake>.from(_makes);
      await _loadSupportingDataInBackground();
      notifyListeners();
    } catch (_) {
      // Keep the current visible state if a live refresh fails.
    } finally {
      _isRealtimeRefreshing = false;
    }
  }

  Future<void> _loadSupportingDataInBackground() async {
    try {
      await Future.wait([
        _warmupService.warmVehicleTypes(),
        _warmupService.warmUsers(),
      ]);
      final types = await _repository.getTypes();
      final drivers =
          (await _authRepository.getUsers())
              .where((user) => normalizeRoleKey(user.role) == 'driver')
              .toList()
            ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
      _types = types;
      _drivers = drivers;
      _cachedTypes = List<VehicleCatalogItem>.from(_types);
      _cachedDrivers = List<UserModel>.from(_drivers);
      notifyListeners();
    } catch (error) {
      // Warm retry scheduling handles later recovery; keep current UI state.
    }
  }

  void _scheduleWarmRetryIfNeeded() {
    if (_didScheduleWarmRetry ||
        !currentNetworkStatus() ||
        _makes.isNotEmpty ||
        _cachedMakes.isNotEmpty) {
      return;
    }
    _didScheduleWarmRetry = true;
    unawaited(_retryLoadAfterWarmup());
  }

  Future<void> _retryLoadAfterWarmup() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    try {
      await _warmupService.warmVehicleMakes();
      final refreshedMakes = await _repository.getMakes();
      if (refreshedMakes.isEmpty) {
        return;
      }
      _makes = refreshedMakes;
      _sortMakes();
      _cachedMakes = List<VehicleMake>.from(_makes);
      _cachedErrorMessage = null;
      notifyListeners();
      unawaited(_loadSupportingDataInBackground());
    } catch (_) {}
  }

  Future<VehicleMake> saveMake(VehicleMake make) async {
    final isExisting = (make.id ?? '').trim().isNotEmpty;
    if (isExisting ? !canUpdateMakes : !canCreateMakes) {
      throw const AuthFailure(
        'You do not have access to save vehicle makes.',
      );
    }
    _busyMessage = 'Saving vehicle make ...';
    setBusy(true);
    try {
      final saved = await _repository.saveMake(make);
      final index = _makes.indexWhere((item) => item.id == saved.id);
      if (index >= 0) {
        _makes[index] = saved;
      } else {
        _makes = [..._makes, saved];
      }
      _sortMakes();
      _cachedMakes = List<VehicleMake>.from(_makes);
      notifyListeners();
      return saved;
    } catch (error) {
      rethrow;
    } finally {
      setBusy(false);
    }
  }

  Future<void> deleteMake(VehicleMake make) async {
    if (!canDeleteMakes) {
      throw const AuthFailure(
        'You do not have access to delete vehicle makes.',
      );
    }
    final makeId = make.id;
    if (makeId == null || makeId.isEmpty) {
      return;
    }
    _busyMessage = 'Deleting vehicle make ...';
    setBusy(true);
    try {
      await _repository.deleteMake(makeId);
      _makes = _makes.where((item) => item.id != makeId).toList();
      _cachedMakes = List<VehicleMake>.from(_makes);
      notifyListeners();
    } finally {
      setBusy(false);
    }
  }

  Future<VehicleMake> setMakeActive(VehicleMake make, bool isActive) {
    if (!canUpdateMakes) {
      throw const AuthFailure(
        'You do not have access to update vehicle makes.',
      );
    }
    _busyMessage = isActive
        ? 'Activating vehicle make ...'
        : 'Deactivating vehicle make ...';
    return saveMake(
      make.copyWith(isActive: isActive, updatedAt: DateTime.now()),
    );
  }

  void _sortMakes() {
    _makes.sort((a, b) {
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
