import 'package:stacked/stacked.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/local/local_auth_repository.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/repositories/local/local_vehicle_catalog_repository.dart';

class AdminVehicleMakesViewModel extends BaseViewModel {
  AdminVehicleMakesViewModel({
    VehicleCatalogRepository? repository,
    AuthRepository? authRepository,
  }) : _repository = repository ?? LocalVehicleCatalogRepository.instance,
       _authRepository = authRepository ?? LocalAuthRepository.instance;

  final VehicleCatalogRepository _repository;
  final AuthRepository _authRepository;

  List<VehicleMake> _makes = const [];
  List<UserModel> _drivers = const [];
  List<VehicleCatalogItem> _types = const [];
  String? _errorMessage;

  List<VehicleMake> get makes => _makes;
  List<UserModel> get drivers => _drivers;
  List<VehicleCatalogItem> get types => _types;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    setBusy(true);
    _errorMessage = null;
    try {
      _makes = await _repository.getMakes();
      _types = await _repository.getTypes();
      _drivers = (await _authRepository.getUsers())
          .where((user) => user.role == 'driver')
          .toList()
        ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
      _sortMakes();
    } catch (_) {
      _errorMessage = 'Failed to load vehicle makes.';
    } finally {
      setBusy(false);
    }
  }

  Future<VehicleMake> saveMake(VehicleMake make) async {
    final saved = await _repository.saveMake(make);
    final index = _makes.indexWhere((item) => item.id == saved.id);
    if (index >= 0) {
      _makes[index] = saved;
    } else {
      _makes = [..._makes, saved];
    }
    _sortMakes();
    notifyListeners();
    return saved;
  }

  Future<void> deleteMake(VehicleMake make) async {
    final makeId = make.id;
    if (makeId == null || makeId.isEmpty) {
      return;
    }
    await _repository.deleteMake(makeId);
    _makes = _makes.where((item) => item.id != makeId).toList();
    notifyListeners();
  }

  Future<VehicleMake> setMakeActive(
    VehicleMake make,
    bool isActive,
  ) {
    return saveMake(
      make.copyWith(
        isActive: isActive,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _sortMakes() {
    _makes.sort((a, b) {
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
