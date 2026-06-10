import 'package:stacked/stacked.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/repositories/local/local_vehicle_catalog_repository.dart';

class AdminVehicleSizesViewModel extends BaseViewModel {
  AdminVehicleSizesViewModel({
    VehicleCatalogRepository? repository,
  }) : _repository = repository ?? LocalVehicleCatalogRepository.instance;

  final VehicleCatalogRepository _repository;

  List<VehicleCatalogItem> _sizes = const [];
  String? _errorMessage;

  List<VehicleCatalogItem> get sizes => _sizes;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    setBusy(true);
    _errorMessage = null;
    try {
      _sizes = await _repository.getSizes();
    } catch (_) {
      _errorMessage = 'Failed to load vehicle sizes.';
    } finally {
      setBusy(false);
    }
  }

  Future<VehicleCatalogItem> saveSize(VehicleCatalogItem size) async {
    final saved = await _repository.saveSize(size);
    final index = _sizes.indexWhere((item) => item.id == saved.id);
    if (index >= 0) {
      _sizes[index] = saved;
    } else {
      _sizes = [..._sizes, saved];
    }
    _sortSizes();
    notifyListeners();
    return saved;
  }

  Future<void> deleteSize(VehicleCatalogItem size) async {
    final sizeId = size.id;
    if (sizeId == null || sizeId.isEmpty) {
      return;
    }
    await _repository.deleteSize(sizeId);
    _sizes = _sizes.where((item) => item.id != sizeId).toList();
    notifyListeners();
  }

  Future<VehicleCatalogItem> setSizeActive(
    VehicleCatalogItem size,
    bool isActive,
  ) {
    return saveSize(
      size.copyWith(
        isActive: isActive,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _sortSizes() {
    _sizes.sort((a, b) {
      final createdComparison = _compareLatestFirst(
        a.createdAt,
        b.createdAt,
      );
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
