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

class AdminVehicleSizesViewModel extends BaseViewModel {
  AdminVehicleSizesViewModel({VehicleCatalogRepository? repository})
    : _repository = repository ?? VehicleRequest.instance {
    _sizes = List<VehicleCatalogItem>.from(_cachedSizes);
    _errorMessage = _cachedErrorMessage;
    _hasLoadedOnce = _cachedHasLoadedOnce;
  }

  final VehicleCatalogRepository _repository;
  final RoleAccessService _roleAccessService = RoleAccessService.instance;
  static List<VehicleCatalogItem> _cachedSizes = const [];
  static String? _cachedErrorMessage;
  static bool _cachedHasLoadedOnce = false;

  static void clearCachedState() {
    _cachedSizes = const [];
    _cachedErrorMessage = null;
    _cachedHasLoadedOnce = false;
  }

  List<VehicleCatalogItem> _sizes = const [];
  String? _errorMessage;
  String _busyMessage = 'Loading, please wait ...';
  bool _hasLoadedOnce = false;
  bool _didScheduleWarmRetry = false;

  List<VehicleCatalogItem> get sizes => _sizes;
  String? get errorMessage => _errorMessage;
  String get busyMessage => _busyMessage;
  bool get canReadSizes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleSizesRead,
  );
  bool get canCreateSizes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleSizesCreate,
  );
  bool get canUpdateSizes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleSizesUpdate,
  );
  bool get canDeleteSizes => _roleAccessService.canAccess(
    DispatcherAccessCapability.vehicleSizesDelete,
  );

  Future<void> load() async {
    if (!canReadSizes) {
      _errorMessage = 'You do not have access to view vehicle sizes.';
      notifyListeners();
      return;
    }
    _busyMessage = 'Loading vehicle sizes ...';
    final hasVisiblePrimaryData = _sizes.isNotEmpty || _cachedSizes.isNotEmpty;
    final shouldShowLoadingState = !_hasLoadedOnce && !hasVisiblePrimaryData;
    if (shouldShowLoadingState) {
      setBusy(true);
    }
    _errorMessage = null;
    try {
      _sizes = await _repository.getSizes();
      _sortSizes();
      _cachedSizes = List<VehicleCatalogItem>.from(_sizes);
      _cachedErrorMessage = null;
      _hasLoadedOnce = true;
      _cachedHasLoadedOnce = true;
      notifyListeners();
      _scheduleWarmRetryIfNeeded();
    } catch (error) {
      _errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the vehicle sizes right now.',
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

  void _scheduleWarmRetryIfNeeded() {
    if (_didScheduleWarmRetry ||
        !currentNetworkStatus() ||
        _sizes.isNotEmpty ||
        _cachedSizes.isNotEmpty) {
      return;
    }
    _didScheduleWarmRetry = true;
    unawaited(_retryLoadAfterWarmup());
  }

  Future<void> _retryLoadAfterWarmup() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    try {
      final refreshedSizes = await _repository.getSizes();
      if (refreshedSizes.isEmpty) {
        return;
      }
      _sizes = refreshedSizes;
      _sortSizes();
      _cachedSizes = List<VehicleCatalogItem>.from(_sizes);
      _cachedErrorMessage = null;
      notifyListeners();
    } catch (_) {}
  }

  Future<VehicleCatalogItem> saveSize(VehicleCatalogItem size) async {
    final isExisting = (size.id ?? '').trim().isNotEmpty;
    if (isExisting ? !canUpdateSizes : !canCreateSizes) {
      throw const AuthFailure(
        'You do not have access to save vehicle sizes.',
      );
    }
    _busyMessage = 'Saving vehicle size ...';
    setBusy(true);
    try {
      final saved = await _repository.saveSize(size);
      final index = _sizes.indexWhere((item) => item.id == saved.id);
      if (index >= 0) {
        _sizes[index] = saved;
      } else {
        _sizes = [..._sizes, saved];
      }
      _sortSizes();
      _cachedSizes = List<VehicleCatalogItem>.from(_sizes);
      notifyListeners();
      return saved;
    } finally {
      setBusy(false);
    }
  }

  Future<void> deleteSize(VehicleCatalogItem size) async {
    if (!canDeleteSizes) {
      throw const AuthFailure(
        'You do not have access to delete vehicle sizes.',
      );
    }
    final sizeId = size.id;
    if (sizeId == null || sizeId.isEmpty) {
      return;
    }
    _busyMessage = 'Deleting vehicle size ...';
    setBusy(true);
    try {
      await _repository.deleteSize(sizeId);
      _sizes = _sizes.where((item) => item.id != sizeId).toList();
      _cachedSizes = List<VehicleCatalogItem>.from(_sizes);
      notifyListeners();
    } finally {
      setBusy(false);
    }
  }

  Future<VehicleCatalogItem> setSizeActive(
    VehicleCatalogItem size,
    bool isActive,
  ) {
    if (!canUpdateSizes) {
      throw const AuthFailure(
        'You do not have access to update vehicle sizes.',
      );
    }
    _busyMessage = isActive
        ? 'Activating vehicle size ...'
        : 'Deactivating vehicle size ...';
    return saveSize(
      size.copyWith(isActive: isActive, updatedAt: DateTime.now()),
    );
  }

  void _sortSizes() {
    _sizes.sort((a, b) {
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
}
