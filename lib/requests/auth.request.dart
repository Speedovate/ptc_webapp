import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/utils/functions.dart';

class AuthRequest implements AuthRepository {
  AuthRequest({FirebaseFirestore? firestore, VehicleRequest? vehicleRequest})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _vehicleRequest = vehicleRequest ?? VehicleRequest.instance;

  static final AuthRequest instance = AuthRequest();

  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _quickLoginSourceUserIdKey =
      'paltranco_quick_login_source_user_id';
  static const _usersResourceKey = 'users';

  final FirebaseFirestore _firestore;
  final VehicleRequest _vehicleRequest;
  final AuthStorageBackend _storage = createAuthStorageBackend();
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  @override
  Future<void> initialize() async {
    await _storage.initialize();
  }

  @override
  Future<List<UserModel>> getUsers() async {
    await initialize();
    final types = await _vehicleRequest.getTypes();
    final typeById = {for (final item in types) item.id ?? '': item};
    final documents = await _cache.getDocuments(
      resourceKey: _usersResourceKey,
      fetchDocuments: () async {
        final snapshot = await _usersCollection.get();
        return snapshot.docs.map(documentData).toList();
      },
    );
    final users = documents
        .map((doc) => _userFromFirestoreMap(doc, typeById))
        .toList();
    users.sort((a, b) {
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
    });
    return users;
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    await initialize();
    final currentId = await _storage.readString(_currentUserIdKey);
    final normalized = normalizeId(currentId);
    if (normalized == null) {
      return null;
    }
    return _getUserById(normalized);
  }

  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final matches = await _usersCollection
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();
    if (matches.docs.isEmpty) {
      throw const AuthFailure('No account found for that email.');
    }
    final user = await _inflateUser(matches.docs.first);
    if ((user.password ?? '') != password) {
      throw const AuthFailure('Incorrect password.');
    }
    if (user.isActive == false) {
      throw const AuthFailure('This account is inactive.');
    }
    final loggedInUser = await saveUser(
      user.copyWith(
        isOnline: _supportsOnline(user.role) ? true : false,
        updatedAt: DateTime.now(),
      ),
    );
    await _storage.writeString(_currentUserIdKey, loggedInUser.id ?? '');
    return loggedInUser;
  }

  @override
  Future<UserModel> register(UserModel user) async {
    final users = await getUsers();
    final normalizedEmail = (user.email ?? '').trim().toLowerCase();
    final normalizedName = _normalizeTitleCase(user.name);
    final emailTaken = users.any(
      (item) => (item.email ?? '').trim().toLowerCase() == normalizedEmail,
    );
    if (emailTaken) {
      throw const AuthFailure('That email is already registered.');
    }
    final nextId =
        users
            .map((item) => int.tryParse(item.id ?? ''))
            .whereType<int>()
            .fold<int>(0, (max, value) => value > max ? value : max) +
        1;
    final now = DateTime.now();
    final savedUser = user.copyWith(
      id: '$nextId',
      email: normalizedEmail,
      name: normalizedName,
      isActive: user.isActive ?? true,
      isOnline: false,
      createdAt: user.createdAt ?? now,
      updatedAt: now,
    );
    await _usersCollection.doc(savedUser.id).set(_toFirestoreMap(savedUser));
    await _cache.touch(_usersResourceKey);
    await _storage.writeString(_currentUserIdKey, savedUser.id ?? '');
    return savedUser;
  }

  @override
  Future<UserModel> saveUser(UserModel user) async {
    final users = await getUsers();
    final normalizedEmail = (user.email ?? '').trim().toLowerCase();
    final normalizedName = _normalizeTitleCase(user.name);
    final emailTakenByOther = users.any(
      (item) =>
          item.id != user.id &&
          (item.email ?? '').trim().toLowerCase() == normalizedEmail,
    );
    if (emailTakenByOther) {
      throw const AuthFailure('That email is already registered.');
    }
    final now = DateTime.now();
    final nextId = normalizeId(user.id) ?? await _nextUserId(users);
    final existing = users.where((item) => item.id == nextId).firstOrNull;
    final saved = user.copyWith(
      id: nextId,
      email: normalizedEmail,
      name: normalizedName,
      isOnline: (user.isActive ?? false) && _supportsOnline(user.role)
          ? (user.isOnline ?? false)
          : false,
      createdAt: existing?.createdAt ?? user.createdAt ?? now,
      updatedAt: now,
    );
    await _usersCollection.doc(nextId).set(_toFirestoreMap(saved));
    await _cache.touch(_usersResourceKey);
    final currentUserId = await _storage.readString(_currentUserIdKey);
    if (currentUserId == nextId) {
      await _storage.writeString(_currentUserIdKey, nextId);
    }
    return saved;
  }

  @override
  Future<void> deleteUser(String userId) async {
    final normalized = normalizeId(userId);
    if (normalized == null) {
      return;
    }
    await _usersCollection.doc(normalized).delete();
    await _cache.touch(_usersResourceKey);
    if (await _storage.readString(_currentUserIdKey) == normalized) {
      await _storage.remove(_currentUserIdKey);
    }
    if (await _storage.readString(_quickLoginSourceUserIdKey) == normalized) {
      await _storage.remove(_quickLoginSourceUserIdKey);
    }
  }

  @override
  Future<void> loginAsUser(String userId) async {
    await initialize();
    final normalized = normalizeId(userId);
    if (normalized == null) {
      throw const AuthFailure('User ID is required.');
    }
    final user = await _getUserById(normalized);
    if (user == null) {
      throw const AuthFailure('No account found for that user.');
    }
    final currentUserId = await _storage.readString(_currentUserIdKey);
    if (normalizeId(currentUserId) != null && currentUserId != normalized) {
      await _storage.writeString(_quickLoginSourceUserIdKey, currentUserId!);
    }
    await _storage.writeString(_currentUserIdKey, normalized);
  }

  @override
  Future<bool> hasQuickLoginSource() async {
    await initialize();
    return normalizeId(await _storage.readString(_quickLoginSourceUserIdKey)) !=
        null;
  }

  @override
  Future<UserModel?> returnToQuickLoginSource() async {
    await initialize();
    final sourceId = normalizeId(
      await _storage.readString(_quickLoginSourceUserIdKey),
    );
    if (sourceId == null) {
      return null;
    }
    await _storage.writeString(_currentUserIdKey, sourceId);
    await _storage.remove(_quickLoginSourceUserIdKey);
    return _getUserById(sourceId);
  }

  @override
  Future<void> logout() async {
    await initialize();
    final currentUser = await getCurrentUser();
    if (currentUser != null && _supportsOnline(currentUser.role)) {
      await saveUser(
        currentUser.copyWith(isOnline: false, updatedAt: DateTime.now()),
      );
    }
    await _storage.remove(_currentUserIdKey);
    await _storage.remove(_quickLoginSourceUserIdKey);
  }

  Future<UserModel?> _getUserById(String id) async {
    final users = await getUsers();
    return users.where((user) => user.id == id).firstOrNull;
  }

  Future<UserModel> _inflateUser(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final typeById = {
      for (final item in await _vehicleRequest.getTypes()) item.id ?? '': item,
    };
    return _userFromFirestoreMap(documentData(doc), typeById);
  }

  UserModel _userFromFirestoreMap(
    Map<String, dynamic> map,
    Map<String, VehicleCatalogItem> typeById,
  ) {
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

  Map<String, dynamic> _toFirestoreMap(UserModel user) {
    final data = user.toMap();
    if (user is DriverModel) {
      data['vehicle_type_id'] = user.vehicleType?.id;
      data.remove('vehicle_type');
    }
    return data;
  }

  Future<String> _nextUserId(List<UserModel> users) async {
    final highest = users
        .map((item) => int.tryParse(item.id ?? ''))
        .whereType<int>()
        .fold<int>(0, (max, value) => value > max ? value : max);
    return '${highest + 1}';
  }

  bool _supportsOnline(String? role) {
    final normalizedRole = (role ?? '').trim().toLowerCase();
    return normalizedRole == 'driver' || normalizedRole == 'helper';
  }

  String? _normalizeTitleCase(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return value;
    }
    return toTitleCase(trimmed);
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
