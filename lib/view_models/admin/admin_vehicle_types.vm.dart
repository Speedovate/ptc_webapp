import 'package:stacked/stacked.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';

class AdminVehicleTypesViewModel extends BaseViewModel {
  AdminVehicleTypesViewModel({VehicleCatalogRepository? repository})
    : _repository = repository ?? VehicleRequest.instance {
    _types = List<VehicleCatalogItem>.from(_cachedTypes);
    _errorMessage = _cachedErrorMessage;
  }

  final VehicleCatalogRepository _repository;
  static List<VehicleCatalogItem> _cachedTypes = const [];
  static String? _cachedErrorMessage;

  List<VehicleCatalogItem> _types = const [];
  String? _errorMessage;

  List<VehicleCatalogItem> get types => _types;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    setBusy(true);
    _errorMessage = null;
    try {
      _types = await _repository.getTypes();
      _sortTypes();
      _cachedTypes = List<VehicleCatalogItem>.from(_types);
      _cachedErrorMessage = null;
    } catch (_) {
      _errorMessage = 'Failed to load vehicle types.';
      _cachedErrorMessage = _errorMessage;
    } finally {
      setBusy(false);
    }
  }

  Future<VehicleCatalogItem> saveType(VehicleCatalogItem type) async {
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
  }

  Future<void> deleteType(VehicleCatalogItem type) async {
    final typeId = type.id;
    if (typeId == null || typeId.isEmpty) {
      return;
    }
    await _repository.deleteType(typeId);
    _types = _types.where((item) => item.id != typeId).toList();
    _cachedTypes = List<VehicleCatalogItem>.from(_types);
    notifyListeners();
  }

  Future<VehicleCatalogItem> setTypeActive(
    VehicleCatalogItem type,
    bool isActive,
  ) {
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
