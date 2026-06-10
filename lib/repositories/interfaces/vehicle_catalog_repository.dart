import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';

abstract class VehicleCatalogRepository {
  Future<List<VehicleMake>> getMakes();
  Future<List<VehicleCatalogItem>> getSizes();
  Future<List<VehicleCatalogItem>> getTypes();
  Future<VehicleMake> saveMake(VehicleMake make);
  Future<void> deleteMake(String makeId);
  Future<VehicleCatalogItem> saveSize(VehicleCatalogItem size);
  Future<void> deleteSize(String sizeId);
  Future<VehicleCatalogItem> saveType(VehicleCatalogItem type);
  Future<void> deleteType(String typeId);
}
