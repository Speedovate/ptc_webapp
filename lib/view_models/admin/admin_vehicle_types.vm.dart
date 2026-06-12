import 'package:stacked/stacked.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/utils/functions.dart';

class AdminVehicleTypesViewModel extends BaseViewModel {
  AdminVehicleTypesViewModel({VehicleCatalogRepository? repository})
    : _repository = repository ?? VehicleRequest.instance {
    _types = List<VehicleCatalogItem>.from(_cachedTypes);
    _errorMessage = _cachedErrorMessage;
  }

  final VehicleCatalogRepository _repository;
  static List<VehicleCatalogItem> _cachedTypes = const [];
  static String? _cachedErrorMessage;

  static void clearCachedState() {
    _cachedTypes = const [];
    _cachedErrorMessage = null;
  }

  List<VehicleCatalogItem> _types = const [];
  String? _errorMessage;
  String _busyMessage = 'Loading, please wait ...';

  List<VehicleCatalogItem> get types => _types;
  String? get errorMessage => _errorMessage;
  String get busyMessage => _busyMessage;

  Future<void> load() async {
    _busyMessage = 'Loading vehicle types ...';
    setBusy(true);
    _errorMessage = null;
    try {
      _types = await _repository.getTypes();
      _sortTypes();
      _cachedTypes = List<VehicleCatalogItem>.from(_types);
      _cachedErrorMessage = null;
    } catch (error) {
      _errorMessage = userFacingErrorMessage(
        error,
        fallback: 'We could not load the vehicle types right now.',
      );
      _cachedErrorMessage = _errorMessage;
    } finally {
      setBusy(false);
    }
  }

  Future<VehicleCatalogItem> saveType(VehicleCatalogItem type) async {
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
    } finally {
      setBusy(false);
    }
  }

  Future<void> deleteType(VehicleCatalogItem type) async {
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
}
