import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/models/vehicle_make.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/repositories/interfaces/vehicle_catalog_repository.dart';
import 'package:webapp/services/firestore_public_document_fetcher.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_queue_coordinator_service.dart';
import 'package:webapp/utils/functions.dart';

class VehicleRequest implements VehicleCatalogRepository {
  VehicleRequest({
    FirebaseFirestore? firestore,
    OfflineMutationQueueService? offlineMutationQueueService,
    FirestorePublicDocumentFetcher? firestorePublicDocumentFetcher,
    Future<void> Function()? offlineQueueInitializer,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _offlineMutationQueueService =
           offlineMutationQueueService ?? OfflineMutationQueueService.instance,
       _firestorePublicDocumentFetcher =
           firestorePublicDocumentFetcher ??
           createFirestorePublicDocumentFetcher(),
       _offlineQueueInitializer =
           offlineQueueInitializer ??
           OfflineQueueCoordinatorService.instance.initialize;

  static final VehicleRequest instance = VehicleRequest();
  static const _usersResourceKey = 'users';
  static const _vehicleMakesResourceKey = 'vehicle_makes';
  static const _vehicleTypesResourceKey = 'vehicle_types';
  static const _vehicleSizesResourceKey = 'vehicle_sizes';
  static const Duration _startupTimeout = Duration(seconds: 6);
  static List<VehicleCatalogItem> _cachedTypes = const [];
  static List<VehicleCatalogItem> _cachedSizes = const [];
  static bool _didStartBackgroundOfflineQueueInitialization = false;

  void _writeDocumentsInBackground({
    required String resourceKey,
    required List<Map<String, dynamic>> documents,
  }) {
    unawaited(
      _cache.writeDocuments(
        resourceKey: resourceKey,
        documents: documents,
      ).catchError((error, stackTrace) {}),
    );
  }

  final FirebaseFirestore _firestore;
  final OfflineMutationQueueService _offlineMutationQueueService;
  final FirestorePublicDocumentFetcher _firestorePublicDocumentFetcher;
  final Future<void> Function() _offlineQueueInitializer;
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

  Future<void> initialize() async {
    if (_didStartBackgroundOfflineQueueInitialization) {
      return;
    }
    _didStartBackgroundOfflineQueueInitialization = true;
    if (currentNetworkStatus()) {
      unawaited(
        _refreshVehicleCachesInBackground().catchError((error, stackTrace) {
        }),
      );
    }
    unawaited(
      _offlineQueueInitializer().catchError((error, stackTrace) {}),
    );
  }

  @override
  Future<List<VehicleMake>> getMakes() async {
    return _runRequest(() async {
      initialize();
      final cachedMakes = await _cache.readDocuments(_vehicleMakesResourceKey);
      final cachedTypes = await _cache.readDocuments(_vehicleTypesResourceKey);
      final cachedUsers = await _cache.readDocuments(_usersResourceKey);
      if (cachedMakes != null && cachedMakes.isNotEmpty) {
        if (currentNetworkStatus()) {
          unawaited(_refreshVehicleCachesInBackground());
        }
        final inflated = _inflateMakes(
          makeDocuments: cachedMakes,
          typeDocuments: cachedTypes ?? const <Map<String, dynamic>>[],
          userDocuments: cachedUsers ?? const <Map<String, dynamic>>[],
        );
        return inflated;
      }
      final sdkCachedMakes = await _readCollectionSdkCacheOnly(_makesCollection);
      if (sdkCachedMakes.isNotEmpty) {
        final sdkCachedTypes = cachedTypes ?? await _readCollectionSdkCacheOnly(_typesCollection);
        final sdkCachedUsers = cachedUsers ?? await _readCollectionSdkCacheOnly(_usersCollection);
        _writeDocumentsInBackground(
          resourceKey: _vehicleMakesResourceKey,
          documents: sdkCachedMakes,
        );
        if (sdkCachedTypes.isNotEmpty) {
          _writeDocumentsInBackground(
            resourceKey: _vehicleTypesResourceKey,
            documents: sdkCachedTypes,
          );
        }
        if (sdkCachedUsers.isNotEmpty) {
          _writeDocumentsInBackground(
            resourceKey: _usersResourceKey,
            documents: sdkCachedUsers,
          );
        }
        if (currentNetworkStatus()) {
          unawaited(_refreshVehicleCachesInBackground());
        }
        final inflated = _inflateMakes(
          makeDocuments: sdkCachedMakes,
          typeDocuments: sdkCachedTypes,
          userDocuments: sdkCachedUsers,
        );
        return inflated;
      }
      try {
        final makesSnapshot = await _makesCollection.get().timeout(
          _startupTimeout,
          onTimeout: () => throw TimeoutException('vehicle makes fetch timeout'),
        );
        final makeDocuments = makesSnapshot.docs.map(documentData).toList(growable: false);
        final typeDocuments = cachedTypes ?? const <Map<String, dynamic>>[];
        final userDocuments = cachedUsers ?? const <Map<String, dynamic>>[];
        _writeDocumentsInBackground(
          resourceKey: _vehicleMakesResourceKey,
          documents: makeDocuments,
        );
        if (currentNetworkStatus()) {
          unawaited(_refreshVehicleCachesInBackground());
        }
        final inflated = _inflateMakes(
          makeDocuments: makeDocuments,
          typeDocuments: typeDocuments,
          userDocuments: userDocuments,
        );
        return inflated;
      } catch (error) {
        final lateCachedMakes = await _cache.readDocuments(_vehicleMakesResourceKey);
        if (lateCachedMakes != null && lateCachedMakes.isNotEmpty) {
          final lateCachedTypes =
              await _cache.readDocuments(_vehicleTypesResourceKey) ??
              typeDocumentsOrEmpty(cachedTypes);
          final lateCachedUsers =
              await _cache.readDocuments(_usersResourceKey) ??
              userDocumentsOrEmpty(cachedUsers);
          final inflated = _inflateMakes(
            makeDocuments: lateCachedMakes,
            typeDocuments: lateCachedTypes,
            userDocuments: lateCachedUsers,
          );
          return inflated;
        }
        final makeDocuments = await _fetchCollectionDocumentsViaPublicRest(
          'vehicle_makes',
        );
        final typeDocuments = cachedTypes ?? const <Map<String, dynamic>>[];
        final userDocuments = cachedUsers ?? const <Map<String, dynamic>>[];
        if (makeDocuments.isEmpty) {
          rethrow;
        }
        _writeDocumentsInBackground(
          resourceKey: _vehicleMakesResourceKey,
          documents: makeDocuments,
        );
        if (currentNetworkStatus()) {
          unawaited(_refreshVehicleCachesInBackground());
        }
        final inflated = _inflateMakes(
          makeDocuments: makeDocuments,
          typeDocuments: typeDocuments,
          userDocuments: userDocuments,
        );
        return inflated;
      }
    }, fallback: 'We could not load the vehicle makes right now.');
  }

  @override
  Future<List<VehicleCatalogItem>> getSizes() async {
    return _runRequest(() async {
      initialize();
      final cachedDocuments = await _cache.readDocuments(_vehicleSizesResourceKey);
      if (cachedDocuments != null && cachedDocuments.isNotEmpty) {
        if (currentNetworkStatus()) {
          unawaited(_refreshVehicleCachesInBackground());
        }
        final items = cachedDocuments.map(VehicleCatalogItem.fromMap).toList();
        items.sort(_compareByNewestIdFirst);
        _cachedSizes = List<VehicleCatalogItem>.from(items);
        return items;
      }
      final sdkCachedDocuments = await _readCollectionSdkCacheOnly(
        _sizesCollection,
      );
      if (sdkCachedDocuments.isNotEmpty) {
        _writeDocumentsInBackground(
          resourceKey: _vehicleSizesResourceKey,
          documents: sdkCachedDocuments,
        );
        if (currentNetworkStatus()) {
          unawaited(_refreshVehicleCachesInBackground());
        }
        final items = sdkCachedDocuments.map(VehicleCatalogItem.fromMap).toList();
        items.sort(_compareByNewestIdFirst);
        _cachedSizes = List<VehicleCatalogItem>.from(items);
        return items;
      }
      try {
        final snapshot = await _sizesCollection.get().timeout(
          _startupTimeout,
          onTimeout: () => throw TimeoutException('vehicle sizes fetch timeout'),
        );
        final documents = snapshot.docs.map(documentData).toList(growable: false);
        _writeDocumentsInBackground(
          resourceKey: _vehicleSizesResourceKey,
          documents: documents,
        );
        final items = documents.map(VehicleCatalogItem.fromMap).toList();
        items.sort(_compareByNewestIdFirst);
        _cachedSizes = List<VehicleCatalogItem>.from(items);
        return items;
      } catch (error) {
        final lateCachedDocuments = await _cache.readDocuments(
          _vehicleSizesResourceKey,
        );
        if (lateCachedDocuments != null && lateCachedDocuments.isNotEmpty) {
          final items = lateCachedDocuments.map(VehicleCatalogItem.fromMap).toList();
          items.sort(_compareByNewestIdFirst);
          _cachedSizes = List<VehicleCatalogItem>.from(items);
          return items;
        }
        final documents = await _fetchCollectionDocumentsViaPublicRest(
          'vehicle_sizes',
        );
        if (documents.isEmpty) {
          rethrow;
        }
        _writeDocumentsInBackground(
          resourceKey: _vehicleSizesResourceKey,
          documents: documents,
        );
        final items = documents.map(VehicleCatalogItem.fromMap).toList();
        items.sort(_compareByNewestIdFirst);
        _cachedSizes = List<VehicleCatalogItem>.from(items);
        return items;
      }
    }, fallback: 'We could not load the vehicle sizes right now.');
  }

  VehicleCatalogItem? resolveVehicleSize(String? value) {
    final normalizedValue = normalizeId(value);
    if (normalizedValue == null) {
      return null;
    }
    final upperValue = normalizedValue.toUpperCase();
    for (final item in _cachedSizes) {
      if ((item.id?.trim() ?? '') == normalizedValue) {
        return item;
      }
      if ((item.name?.trim().toUpperCase() ?? '') == upperValue) {
        return item;
      }
      if ((item.slug?.trim().toUpperCase() ?? '') == upperValue) {
        return item;
      }
    }
    return null;
  }

  String? normalizeVehicleSizeId(String? value) {
    final matched = resolveVehicleSize(value);
    final matchedId = normalizeId(matched?.id);
    if (matchedId != null) {
      return matchedId;
    }
    return normalizeId(value);
  }

  String displayVehicleSizeLabel(
    String? value, {
    bool uppercase = false,
    bool preferSlug = false,
  }) {
    final matched = resolveVehicleSize(value);
    final label = preferSlug && matched?.slug?.trim().isNotEmpty == true
        ? matched!.slug!.trim()
        : matched?.name?.trim().isNotEmpty == true
        ? matched!.name!.trim()
        : matched?.slug?.trim().isNotEmpty == true
        ? matched!.slug!.trim()
        : normalizeId(value) ?? '-';
    return uppercase ? label.toUpperCase() : label;
  }

  @override
  Future<List<VehicleCatalogItem>> getTypes() async {
    return _runRequest(() async {
      initialize();
      final cachedDocuments = await _cache.readDocuments(_vehicleTypesResourceKey);
      if (cachedDocuments != null && cachedDocuments.isNotEmpty) {
        if (currentNetworkStatus()) {
          unawaited(_refreshVehicleCachesInBackground());
        }
        final items = cachedDocuments.map(VehicleCatalogItem.fromMap).toList();
        items.sort(_compareByNewestIdFirst);
        _cachedTypes = List<VehicleCatalogItem>.from(items);
        return items;
      }
      final sdkCachedDocuments = await _readCollectionSdkCacheOnly(
        _typesCollection,
      );
      if (sdkCachedDocuments.isNotEmpty) {
        _writeDocumentsInBackground(
          resourceKey: _vehicleTypesResourceKey,
          documents: sdkCachedDocuments,
        );
        if (currentNetworkStatus()) {
          unawaited(_refreshVehicleCachesInBackground());
        }
        final items = sdkCachedDocuments.map(VehicleCatalogItem.fromMap).toList();
        items.sort(_compareByNewestIdFirst);
        _cachedTypes = List<VehicleCatalogItem>.from(items);
        return items;
      }
      try {
        final snapshot = await _typesCollection.get().timeout(
          _startupTimeout,
          onTimeout: () => throw TimeoutException('vehicle types fetch timeout'),
        );
        final documents = snapshot.docs.map(documentData).toList(growable: false);
        _writeDocumentsInBackground(
          resourceKey: _vehicleTypesResourceKey,
          documents: documents,
        );
        final items = documents.map(VehicleCatalogItem.fromMap).toList();
        items.sort(_compareByNewestIdFirst);
        _cachedTypes = List<VehicleCatalogItem>.from(items);
        return items;
      } catch (error) {
        final lateCachedDocuments = await _cache.readDocuments(
          _vehicleTypesResourceKey,
        );
        if (lateCachedDocuments != null && lateCachedDocuments.isNotEmpty) {
          final items = lateCachedDocuments.map(VehicleCatalogItem.fromMap).toList();
          items.sort(_compareByNewestIdFirst);
          _cachedTypes = List<VehicleCatalogItem>.from(items);
          return items;
        }
        final documents = await _fetchCollectionDocumentsViaPublicRest(
          'vehicle_types',
        );
        if (documents.isEmpty) {
          rethrow;
        }
        _writeDocumentsInBackground(
          resourceKey: _vehicleTypesResourceKey,
          documents: documents,
        );
        final items = documents.map(VehicleCatalogItem.fromMap).toList();
        items.sort(_compareByNewestIdFirst);
        _cachedTypes = List<VehicleCatalogItem>.from(items);
        return items;
      }
    }, fallback: 'We could not load the vehicle types right now.');
  }

  Future<Map<String, VehicleCatalogItem>> getTypeByIdCachedFirst() async {
    if (_cachedTypes.isNotEmpty) {
      return {
        for (final item in _cachedTypes)
          if ((item.id ?? '').trim().isNotEmpty) item.id!.trim(): item,
      };
    }

    final cachedDocuments = await _cache.readDocuments(_vehicleTypesResourceKey);
    if (cachedDocuments != null && cachedDocuments.isNotEmpty) {
      final items = cachedDocuments.map(VehicleCatalogItem.fromMap).toList()
        ..sort(_compareByNewestIdFirst);
      _cachedTypes = List<VehicleCatalogItem>.from(items);
      return {
        for (final item in items)
          if ((item.id ?? '').trim().isNotEmpty) item.id!.trim(): item,
      };
    }

    final items = await getTypes();
    return {
      for (final item in items)
        if ((item.id ?? '').trim().isNotEmpty) item.id!.trim(): item,
    };
  }

  List<VehicleMake> _inflateMakes({
    required List<Map<String, dynamic>> makeDocuments,
    required List<Map<String, dynamic>> typeDocuments,
    required List<Map<String, dynamic>> userDocuments,
  }) {
    final typeById = {
      for (final doc in typeDocuments)
        doc['id']?.toString() ?? '': VehicleCatalogItem.fromMap(doc),
    };
    final userById = {
      for (final doc in userDocuments)
        doc['id']?.toString() ?? '': _userFromFirestoreMap(
          doc,
          typeById: typeById,
        ),
    };
    final makes = makeDocuments
        .map(
          (doc) => _makeFromFirestoreMap(
            doc,
            typeById: typeById,
            userById: userById,
          ),
        )
        .toList(growable: false);
    makes.sort(_compareByNewestIdFirst);
    return makes;
  }

  Future<void> _refreshVehicleCachesInBackground() async {
    try {
      final makesSnapshot = await _makesCollection.get().timeout(_startupTimeout);
      final typesSnapshot = await _typesCollection.get().timeout(_startupTimeout);
      final usersSnapshot = await _usersCollection.get().timeout(_startupTimeout);
      await _cache.writeDocuments(
        resourceKey: _vehicleMakesResourceKey,
        documents: makesSnapshot.docs.map(documentData).toList(growable: false),
      );
      await _cache.writeDocuments(
        resourceKey: _vehicleTypesResourceKey,
        documents: typesSnapshot.docs.map(documentData).toList(growable: false),
      );
      await _cache.writeDocuments(
        resourceKey: _usersResourceKey,
        documents: usersSnapshot.docs.map(documentData).toList(growable: false),
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _fetchCollectionDocumentsViaPublicRest(
    String collectionPath,
  ) async {
    final documents = await _firestorePublicDocumentFetcher
        .fetchCollectionDocuments(collectionPath)
        .timeout(_startupTimeout, onTimeout: () {
          throw TimeoutException('public rest $collectionPath fetch timeout');
        });
    return documents;
  }

  Future<List<Map<String, dynamic>>> _readCollectionSdkCacheOnly(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    try {
      final snapshot = await collection
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 1));
      return snapshot.docs.map(documentData).toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  List<Map<String, dynamic>> typeDocumentsOrEmpty(
    List<Map<String, dynamic>>? documents,
  ) {
    return documents ?? const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> userDocumentsOrEmpty(
    List<Map<String, dynamic>>? documents,
  ) {
    return documents ?? const <Map<String, dynamic>>[];
  }

  @override
  Future<VehicleMake> saveMake(VehicleMake make) async {
    return _runRequest(() async {
      final nextId = normalizeId(make.id) ?? await _nextId(_makesCollection);
      final now = DateTime.now();
      final saved = make.copyWith(
        id: nextId,
        createdAt: make.createdAt ?? now,
        updatedAt: now,
      );
      final document = _toFirestoreMap(saved);
      final baseUpdatedAtIso = await _cachedUpdatedAt(
        resourceKey: _vehicleMakesResourceKey,
        documentId: nextId,
      );
      if (currentNetworkStatus()) {
        await _makesCollection.doc(nextId).set(document);
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentUpsert(
          collectionKey: _vehicleMakesResourceKey,
          documentId: nextId,
          document: document,
          baseUpdatedAt: baseUpdatedAtIso,
        );
      }
      await _cache.upsertDocument(
        resourceKey: _vehicleMakesResourceKey,
        document: document,
      );
      return saved;
    }, fallback: 'We could not save the vehicle make right now.');
  }

  @override
  Future<void> deleteMake(String makeId) async {
    await _runRequest(() async {
      final normalized = normalizeId(makeId);
      if (normalized == null) {
        return;
      }
      if (currentNetworkStatus()) {
        await _makesCollection.doc(normalized).delete();
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentDelete(
          collectionKey: _vehicleMakesResourceKey,
          documentId: normalized,
        );
      }
      await _cache.removeDocument(
        resourceKey: _vehicleMakesResourceKey,
        documentId: normalized,
      );
    }, fallback: 'We could not delete the vehicle make right now.');
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
    await _runRequest(() async {
      final normalized = normalizeId(sizeId);
      if (normalized == null) {
        return;
      }
      if (currentNetworkStatus()) {
        await _sizesCollection.doc(normalized).delete();
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentDelete(
          collectionKey: _vehicleSizesResourceKey,
          documentId: normalized,
        );
      }
      await _cache.removeDocument(
        resourceKey: _vehicleSizesResourceKey,
        documentId: normalized,
      );
      _cachedSizes = _cachedSizes
          .where((item) => item.id != normalized)
          .toList();
    }, fallback: 'We could not delete the vehicle size right now.');
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
    await _runRequest(() async {
      final normalized = normalizeId(typeId);
      if (normalized == null) {
        return;
      }
      if (currentNetworkStatus()) {
        await _typesCollection.doc(normalized).delete();
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentDelete(
          collectionKey: _vehicleTypesResourceKey,
          documentId: normalized,
        );
      }
      await _cache.removeDocument(
        resourceKey: _vehicleTypesResourceKey,
        documentId: normalized,
      );
      _cachedTypes = _cachedTypes
          .where((item) => item.id != normalized)
          .toList();
    }, fallback: 'We could not delete the vehicle type right now.');
  }

  Future<VehicleCatalogItem> _saveCatalogItem({
    required CollectionReference<Map<String, dynamic>> collection,
    required String resourceKey,
    required VehicleCatalogItem item,
  }) async {
    return _runRequest(() async {
      final nextId = normalizeId(item.id) ?? await _nextId(collection);
      final now = DateTime.now();
      final saved = item.copyWith(
        id: nextId,
        createdAt: item.createdAt ?? now,
        updatedAt: now,
      );
      final document = saved.toMap();
      final baseUpdatedAtIso = await _cachedUpdatedAt(
        resourceKey: resourceKey,
        documentId: nextId,
      );
      if (currentNetworkStatus()) {
        await collection.doc(nextId).set(document);
      } else {
        await _offlineMutationQueueService.queueCollectionDocumentUpsert(
          collectionKey: resourceKey,
          documentId: nextId,
          document: document,
          baseUpdatedAt: baseUpdatedAtIso,
        );
      }
      await _cache.upsertDocument(resourceKey: resourceKey, document: document);
      if (resourceKey == _vehicleTypesResourceKey) {
        final nextItems = List<VehicleCatalogItem>.from(_cachedTypes);
        final existingIndex = nextItems.indexWhere(
          (entry) => entry.id == saved.id,
        );
        if (existingIndex >= 0) {
          nextItems[existingIndex] = saved;
        } else {
          nextItems.add(saved);
        }
        nextItems.sort(_compareByNewestIdFirst);
        _cachedTypes = nextItems;
      }
      if (resourceKey == _vehicleSizesResourceKey) {
        final nextItems = List<VehicleCatalogItem>.from(_cachedSizes);
        final existingIndex = nextItems.indexWhere(
          (item) => item.id == saved.id,
        );
        if (existingIndex >= 0) {
          nextItems[existingIndex] = saved;
        } else {
          nextItems.add(saved);
        }
        nextItems.sort(_compareByNewestIdFirst);
        _cachedSizes = nextItems;
      }
      return saved;
    }, fallback: 'We could not save this item right now.');
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
        firebaseAuthUid: map['firebase_auth_uid']?.toString(),
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

  Future<String?> _cachedUpdatedAt({
    required String resourceKey,
    required String documentId,
  }) async {
    final documents = await _cache.readDocuments(resourceKey);
    if (documents == null) {
      return null;
    }
    for (final document in documents) {
      if ((document['id']?.toString().trim() ?? '') == documentId) {
        return document['updated_at']?.toString();
      }
    }
    return null;
  }


  Future<T> _runRequest<T>(
    Future<T> Function() action, {
    required String fallback,
  }) async {
    try {
      return await action();
    } on FirebaseException catch (error) {
      throw Exception(userFacingErrorMessage(error, fallback: fallback));
    } catch (error) {
      throw Exception(userFacingErrorMessage(error, fallback: fallback));
    }
  }
}
