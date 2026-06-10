import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';

class MockVehicleCatalogRepository implements VehicleCatalogRepository {
  MockVehicleCatalogRepository._();

  static final MockVehicleCatalogRepository instance =
      MockVehicleCatalogRepository._();

  static final DateTime _seededNow = DateTime.now();

  static final VehicleCatalogItem _primeMoverType = VehicleCatalogItem(
    id: '1',
    name: 'Prime Mover',
    slug: 'PM',
    isActive: true,
    createdAt: _seededNow,
    updatedAt: _seededNow,
  );

  static final UserModel _ronaldIniego = DriverModel(
    id: '3',
    role: 'driver',
    email: 'itronald@gmail.com',
    name: 'Ronald Iniego',
    phone: '+639939470079',
    vehicleType: _primeMoverType,
    isActive: true,
    isOnline: false,
    password: 'password',
    createdAt: _seededNow,
    updatedAt: _seededNow,
  );

  static final List<VehicleMake> _makes = [
    VehicleMake(
      id: '1',
      code: 'PM1',
      type: _primeMoverType,
      driver: _ronaldIniego,
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];

  static final List<VehicleCatalogItem> _types = [
    _primeMoverType,
  ];

  static final List<VehicleCatalogItem> _sizes = [
    VehicleCatalogItem(
      id: '1',
      name: '20 Footer',
      slug: '20 FTR',
      isActive: true,
      createdAt: _seededNow,
      updatedAt: _seededNow,
    ),
  ];

  @override
  Future<List<VehicleMake>> getMakes() async {
    return List<VehicleMake>.from(_makes);
  }

  @override
  Future<List<VehicleCatalogItem>> getSizes() async {
    return List<VehicleCatalogItem>.from(_sizes);
  }

  @override
  Future<List<VehicleCatalogItem>> getTypes() async {
    return List<VehicleCatalogItem>.from(_types);
  }

  @override
  Future<VehicleMake> saveMake(VehicleMake make) async {
    final now = DateTime.now();
    final index = _makes.indexWhere((item) => item.id == make.id && item.id != null);
    if (index >= 0) {
      final existing = _makes[index];
      final saved = make.copyWith(
        id: existing.id,
        createdAt: existing.createdAt ?? now,
        updatedAt: now,
      );
      _makes[index] = saved;
      return saved;
    }

    final saved = make.copyWith(
      id: _nextId(_makes.map((item) => item.id)),
      createdAt: make.createdAt ?? now,
      updatedAt: now,
    );
    _makes.add(saved);
    return saved;
  }

  @override
  Future<void> deleteMake(String makeId) async {
    _makes.removeWhere((item) => item.id == makeId);
  }

  @override
  Future<VehicleCatalogItem> saveSize(VehicleCatalogItem size) async {
    return _saveCatalogItem(
      item: size,
      items: _sizes,
    );
  }

  @override
  Future<void> deleteSize(String sizeId) async {
    _sizes.removeWhere((item) => item.id == sizeId);
  }

  @override
  Future<VehicleCatalogItem> saveType(VehicleCatalogItem type) async {
    return _saveCatalogItem(
      item: type,
      items: _types,
    );
  }

  @override
  Future<void> deleteType(String typeId) async {
    _types.removeWhere((item) => item.id == typeId);
  }

  Future<VehicleCatalogItem> _saveCatalogItem({
    required VehicleCatalogItem item,
    required List<VehicleCatalogItem> items,
  }) async {
    final now = DateTime.now();
    final index = items.indexWhere((existing) => existing.id == item.id && item.id != null);
    if (index >= 0) {
      final existing = items[index];
      final saved = item.copyWith(
        id: existing.id,
        createdAt: existing.createdAt ?? now,
        updatedAt: now,
      );
      items[index] = saved;
      return saved;
    }

    final saved = item.copyWith(
      id: _nextId(items.map((existing) => existing.id)),
      createdAt: item.createdAt ?? now,
      updatedAt: now,
    );
    items.add(saved);
    return saved;
  }

  static String _nextId(Iterable<String?> ids) {
    final highest = ids
        .map((id) => int.tryParse(id ?? ''))
        .whereType<int>()
        .fold<int>(0, (max, value) => value > max ? value : max);
    return '${highest + 1}';
  }
}
