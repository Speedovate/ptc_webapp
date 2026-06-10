import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/utils/functions.dart';

class VehicleRequest implements VehicleCatalogRepository {
  VehicleRequest({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static final VehicleRequest instance = VehicleRequest();
  static const _usersResourceKey = 'users';
  static const _vehicleMakesResourceKey = 'vehicle_makes';
  static const _vehicleTypesResourceKey = 'vehicle_types';
  static const _vehicleSizesResourceKey = 'vehicle_sizes';

  final FirebaseFirestore _firestore;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );

  CollectionReference<Map<String, dynamic>> get _makesCollection =>
      _firestore.collection('vehicle_makes');
  CollectionReference<Map<String, dynamic>> get _typesCollection =>
      _firestore.collection('vehicle_types');
  CollectionReference<Map<String, dynamic>> get _sizesCollection =>
      _firestore.collection('vehicle_sizes');
  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  @override
  Future<List<VehicleMake>> getMakes() async {
    final snapshots = await Future.wait([
      _cache.getDocuments(
        resourceKey: _vehicleMakesResourceKey,
        fetchDocuments: () async {
          final snapshot = await _makesCollection.get();
          return snapshot.docs.map(documentData).toList();
        },
      ),
      _cache.getDocuments(
        resourceKey: _vehicleTypesResourceKey,
        fetchDocuments: () async {
          final snapshot = await _typesCollection.get();
          return snapshot.docs.map(documentData).toList();
        },
      ),
      _cache.getDocuments(
        resourceKey: _usersResourceKey,
        fetchDocuments: () async {
          final snapshot = await _usersCollection.get();
          return snapshot.docs.map(documentData).toList();
        },
      ),
    ]);
    final typeById = {
      for (final doc in snapshots[1])
        doc['id']?.toString() ?? '': VehicleCatalogItem.fromMap(doc),
    };
    final userById = {
      for (final doc in snapshots[2])
        doc['id']?.toString() ?? '': _userFromFirestoreMap(
          doc,
          typeById: typeById,
        ),
    };
    final makes = snapshots[0]
        .map(
          (doc) => _makeFromFirestoreMap(
            doc,
            typeById: typeById,
            userById: userById,
          ),
        )
        .toList();
    makes.sort(_compareByNewestIdFirst);
    return makes;
  }

  @override
  Future<List<VehicleCatalogItem>> getSizes() async {
    final documents = await _cache.getDocuments(
      resourceKey: _vehicleSizesResourceKey,
      fetchDocuments: () async {
        final snapshot = await _sizesCollection.get();
        return snapshot.docs.map(documentData).toList();
      },
    );
    final items = documents.map(VehicleCatalogItem.fromMap).toList();
    items.sort(_compareByNewestIdFirst);
    return items;
  }

  @override
  Future<List<VehicleCatalogItem>> getTypes() async {
    final documents = await _cache.getDocuments(
      resourceKey: _vehicleTypesResourceKey,
      fetchDocuments: () async {
        final snapshot = await _typesCollection.get();
        return snapshot.docs.map(documentData).toList();
      },
    );
    final items = documents.map(VehicleCatalogItem.fromMap).toList();
    items.sort(_compareByNewestIdFirst);
    return items;
  }

  @override
  Future<VehicleMake> saveMake(VehicleMake make) async {
    final nextId = normalizeId(make.id) ?? await _nextId(_makesCollection);
    final now = DateTime.now();
    final saved = make.copyWith(
      id: nextId,
      createdAt: make.createdAt ?? now,
      updatedAt: now,
    );
    await _makesCollection.doc(nextId).set(_toFirestoreMap(saved));
    await _cache.upsertDocument(
      resourceKey: _vehicleMakesResourceKey,
      document: _toFirestoreMap(saved),
    );
    return saved;
  }

  @override
  Future<void> deleteMake(String makeId) async {
    final normalized = normalizeId(makeId);
    if (normalized == null) {
      return;
    }
    await _makesCollection.doc(normalized).delete();
    await _cache.removeDocument(
      resourceKey: _vehicleMakesResourceKey,
      documentId: normalized,
    );
  }

  @override
  Future<VehicleCatalogItem> saveSize(VehicleCatalogItem size) async {
    return _saveCatalogItem(
      collection: _sizesCollection,
      resourceKey: _vehicleSizesResourceKey,
      item: size,
    );
  }

  @override
  Future<void> deleteSize(String sizeId) async {
    final normalized = normalizeId(sizeId);
    if (normalized == null) {
      return;
    }
    await _sizesCollection.doc(normalized).delete();
    await _cache.removeDocument(
      resourceKey: _vehicleSizesResourceKey,
      documentId: normalized,
    );
  }

  @override
  Future<VehicleCatalogItem> saveType(VehicleCatalogItem type) async {
    return _saveCatalogItem(
      collection: _typesCollection,
      resourceKey: _vehicleTypesResourceKey,
      item: type,
    );
  }

  @override
  Future<void> deleteType(String typeId) async {
    final normalized = normalizeId(typeId);
    if (normalized == null) {
      return;
    }
    await _typesCollection.doc(normalized).delete();
    await _cache.removeDocument(
      resourceKey: _vehicleTypesResourceKey,
      documentId: normalized,
    );
  }

  Future<VehicleCatalogItem> _saveCatalogItem({
    required CollectionReference<Map<String, dynamic>> collection,
    required String resourceKey,
    required VehicleCatalogItem item,
  }) async {
    final nextId = normalizeId(item.id) ?? await _nextId(collection);
    final now = DateTime.now();
    final saved = item.copyWith(
      id: nextId,
      createdAt: item.createdAt ?? now,
      updatedAt: now,
    );
    await collection.doc(nextId).set(saved.toMap());
    await _cache.upsertDocument(
      resourceKey: resourceKey,
      document: saved.toMap(),
    );
    return saved;
  }

  Map<String, dynamic> _toFirestoreMap(VehicleMake make) {
    return {
      'id': make.id,
      'code': make.code,
      'type_id': make.type?.id,
      'driver_id': make.driver?.id,
      'is_active': make.isActive,
      'created_at': make.createdAt?.toIso8601String(),
      'updated_at': make.updatedAt?.toIso8601String(),
    };
  }

  VehicleMake _makeFromFirestoreMap(
    Map<String, dynamic> map, {
    required Map<String, VehicleCatalogItem> typeById,
    required Map<String, UserModel> userById,
  }) {
    return VehicleMake(
      id: map['id']?.toString(),
      code: map['code']?.toString(),
      type: typeById[map['type_id']?.toString()],
      driver: userById[map['driver_id']?.toString()],
      isActive: map['is_active'] as bool?,
      createdAt: _toDateTime(map['created_at']),
      updatedAt: _toDateTime(map['updated_at']),
    );
  }

  UserModel _userFromFirestoreMap(
    Map<String, dynamic> map, {
    required Map<String, VehicleCatalogItem> typeById,
  }) {
    final vehicleType = typeById[map['vehicle_type_id']?.toString()];
    if (map['role']?.toString() == 'driver') {
      return DriverModel(
        id: map['id']?.toString(),
        role: map['role']?.toString() ?? 'driver',
        email: map['email']?.toString(),
        name: map['name']?.toString(),
        photo: map['photo']?.toString(),
        phone: map['phone']?.toString(),
        isActive: map['is_active'] as bool? ?? false,
        isOnline: map['is_online'] as bool? ?? false,
        password: map['password']?.toString(),
        createdAt: _toDateTime(map['created_at']),
        updatedAt: _toDateTime(map['updated_at']),
        lat: _toDouble(map['lat']),
        lng: _toDouble(map['lng']),
        license: map['license']?.toString(),
        vehicleType: vehicleType,
      );
    }
    return UserModel.fromMap(map);
  }

  Future<String> _nextId(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    final snapshot = await collection.get();
    final highest = snapshot.docs
        .map((doc) => int.tryParse(documentData(doc)['id']?.toString() ?? ''))
        .whereType<int>()
        .fold<int>(0, (max, value) => value > max ? value : max);
    return '${highest + 1}';
  }

  int _compareByNewestIdFirst(dynamic a, dynamic b) {
    final aDate = a.updatedAt ?? a.createdAt;
    final bDate = b.updatedAt ?? b.createdAt;
    if (aDate == null && bDate == null) {
      final aId = int.tryParse(a.id ?? '');
      final bId = int.tryParse(b.id ?? '');
      if (aId != null && bId != null) {
        return bId.compareTo(aId);
      }
      return (b.id ?? '').compareTo(a.id ?? '');
    }
    if (aDate == null) {
      return 1;
    }
    if (bDate == null) {
      return -1;
    }
    return bDate.compareTo(aDate);
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }

  double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
