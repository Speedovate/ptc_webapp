import 'package:stacked/stacked.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/utils/functions.dart';

class AdminVehicleSizesViewModel extends BaseViewModel {
  AdminVehicleSizesViewModel({VehicleCatalogRepository? repository})
    : _repository = repository ?? VehicleRequest.instance {
    _sizes = List<VehicleCatalogItem>.from(_cachedSizes);
    _errorMessage = _cachedErrorMessage;
  }

  final VehicleCatalogRepository _repository;
  static List<VehicleCatalogItem> _cachedSizes = const [];
  static String? _cachedErrorMessage;

  static void clearCachedState() {
    _cachedSizes = const [];
    _cachedErrorMessage = null;
  }

  List<VehicleCatalogItem> _sizes = const [];
  String? _errorMessage;
  String _busyMessage = 'Loading, please wait ...';

  List<VehicleCatalogItem> get sizes => _sizes;
  String? get errorMessage => _errorMessage;
  String get busyMessage => _busyMessage;

  Future<void> load() async {
    _busyMessage = 'Loading vehicle sizes ...';
    setBusy(true);
    _errorMessage = null;
    try {
      _sizes = await _repository.getSizes();
      _sortSizes();
      _cachedSizes = List<VehicleCatalogItem>.from(_sizes);
      _cachedErrorMessage = null;
    } catch (error) {
      _errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the vehicle sizes right now.',
      );
      _cachedErrorMessage = _errorMessage;
    } finally {
      setBusy(false);
    }
  }

  Future<VehicleCatalogItem> saveSize(VehicleCatalogItem size) async {
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
