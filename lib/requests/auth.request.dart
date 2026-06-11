import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/app_session_reset.dart';
import 'package:webapp/services/photo_storage_service.dart';
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
  final PhotoStorageService _photoStorageService = PhotoStorageService.instance;
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
    return _runAuthRequest(() async {
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
    }, fallback: 'We could not load the users right now.');
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    await initialize();
    final currentId = await _storage.readString(_currentUserIdKey);
    final normalized = normalizeId(currentId);
    if (normalized == null) {
      return null;
    }
    final user = await _getFreshUserById(normalized);
    if (user != null) {
      return user;
    }
    await _clearStoredSession();
    await _cache.clearResource(_usersResourceKey);
    AppSessionReset.clearUserScopedState();
    return null;
  }

  @override
  Future<UserModel> login({
    required String identifier,
    required String password,
  }) async {
    return _runAuthRequest(() async {
      debugPrint('[AUTH_REQUEST][LOGIN] Start identifier=$identifier');
      await initialize();
      await _cache.clearResource(_usersResourceKey);
      AppSessionReset.clearUserScopedState();
      final trimmedIdentifier = identifier.trim();
      final normalizedPhone = normalizePhilippinePhone(trimmedIdentifier);
      final bool isPhoneLogin = normalizedPhone != null;
      final matches = isPhoneLogin
          ? await _usersCollection
                .where('phone', isEqualTo: normalizedPhone)
                .limit(1)
                .get()
          : await _usersCollection
                .where('email', isEqualTo: trimmedIdentifier.toLowerCase())
                .limit(1)
                .get();
      if (matches.docs.isEmpty) {
        debugPrint('[AUTH_REQUEST][LOGIN] No matching user found');
        throw const AuthFailure(
          'No account found for that email or mobile number.',
        );
      }
      final user = await _inflateUser(matches.docs.first);
      debugPrint(
        '[AUTH_REQUEST][LOGIN] Found user id=${user.id} role=${user.role} active=${user.isActive} photo=${user.photo}',
      );
      if ((user.password ?? '') != password) {
        debugPrint(
          '[AUTH_REQUEST][LOGIN] Password mismatch for userId=${user.id}',
        );
        throw const AuthFailure('Incorrect password.');
      }
      if (user.isActive == false) {
        debugPrint('[AUTH_REQUEST][LOGIN] User inactive userId=${user.id}');
        throw const AuthFailure(
          'This account is not active yet. Please contact your admin to activate your account.',
        );
      }
      final loggedInUser = await _persistUserDirect(
        user.copyWith(
          isOnline: _supportsOnline(user.role) ? true : false,
          updatedAt: DateTime.now(),
        ),
      );
      await _storage.writeString(_currentUserIdKey, loggedInUser.id ?? '');
      await _cache.clearResource(_usersResourceKey);
      AppSessionReset.clearUserScopedState();
      debugPrint(
        '[AUTH_REQUEST][LOGIN] Success storedCurrentUserId=${loggedInUser.id}',
      );
      return loggedInUser;
    }, fallback: 'We could not sign you in right now. Please try again.');
  }

  @override
  Future<UserModel> register(UserModel user) async {
    return _runAuthRequest(() async {
      debugPrint(
        '[AUTH_REQUEST][REGISTER] Start role=${user.role} email=${user.email} phone=${user.phone}',
      );
      await initialize();
      await _cache.clearResource(_usersResourceKey);
      AppSessionReset.clearUserScopedState();
      final users = await _getUsersFresh();
      final normalizedRole = (user.role ?? '').trim().toLowerCase();
      final isPendingApprovalRole =
          normalizedRole == 'driver' || normalizedRole == 'helper';
      final normalizedEmail = (user.email ?? '').trim().toLowerCase();
      final normalizedName = _normalizeTitleCase(user.name);
      final emailTaken = users.any(
        (item) => (item.email ?? '').trim().toLowerCase() == normalizedEmail,
      );
      if (emailTaken) {
        debugPrint(
          '[AUTH_REQUEST][REGISTER] Email already taken: $normalizedEmail',
        );
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
        role: normalizedRole,
        email: normalizedEmail,
        name: normalizedName,
        phone: normalizePhilippinePhone(user.phone) ?? user.phone?.trim(),
        isActive: isPendingApprovalRole ? false : true,
        isOnline: false,
        createdAt: user.createdAt ?? now,
        updatedAt: now,
      );
      await _usersCollection.doc(savedUser.id).set(_toFirestoreMap(savedUser));
      await _storage.writeString(_currentUserIdKey, savedUser.id ?? '');
      await _cache.clearResource(_usersResourceKey);
      AppSessionReset.clearUserScopedState();
      debugPrint(
        '[AUTH_REQUEST][REGISTER] Saved user id=${savedUser.id} active=${savedUser.isActive} photo=${savedUser.photo}',
      );
      return savedUser;
    }, fallback: 'We could not create your account right now. Please try again.');
  }

  @override
  Future<UserModel> saveUser(UserModel user) async {
    return _runAuthRequest(() async {
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
        phone: normalizePhilippinePhone(user.phone) ?? user.phone?.trim(),
        isOnline: (user.isActive ?? false) && _supportsOnline(user.role)
            ? (user.isOnline ?? false)
            : false,
        createdAt: existing?.createdAt ?? user.createdAt ?? now,
        updatedAt: now,
      );
      await _usersCollection.doc(nextId).set(_toFirestoreMap(saved));
      await _cache.upsertDocument(
        resourceKey: _usersResourceKey,
        document: _toFirestoreMap(saved),
      );
      final currentUserId = await _storage.readString(_currentUserIdKey);
      if (currentUserId == nextId) {
        await _storage.writeString(_currentUserIdKey, nextId);
      }
      return saved;
    }, fallback: 'We could not save the user right now. Please try again.');
  }

  @override
  Future<UserModel> saveUserPhoto({
    required String userId,
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    return _runAuthRequest(() async {
      debugPrint(
        '[AUTH_REQUEST][PHOTO] Start upload userId=$userId fileName=$fileName size=$size mimeType=$mimeType',
      );
      final normalizedUserId = normalizeId(userId);
      if (normalizedUserId == null) {
        throw const AuthFailure('User ID is required.');
      }
      final currentUser = await _getUserById(normalizedUserId);
      if (currentUser == null) {
        throw const AuthFailure('User not found.');
      }
      final upload = await _photoStorageService.uploadUserPhoto(
        bytes: bytes,
        userId: normalizedUserId,
        fieldKey: 'profile_photo',
        fileName: fileName,
        mimeType: mimeType,
        size: size,
      );
      debugPrint(
        '[AUTH_REQUEST][PHOTO] Storage upload success userId=$normalizedUserId downloadUrl=${upload['download_url']}',
      );
      return saveUser(
        currentUser.copyWith(
          photo: upload['download_url']?.toString(),
          updatedAt: DateTime.now(),
        ),
      );
    }, fallback: 'We could not upload the profile photo right now.');
  }

  @override
  Future<UserModel> saveDriverLicensePhoto({
    required String userId,
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    int? size,
  }) async {
    return _runAuthRequest(() async {
      debugPrint(
        '[AUTH_REQUEST][LICENSE] Start upload userId=$userId fileName=$fileName size=$size mimeType=$mimeType',
      );
      final normalizedUserId = normalizeId(userId);
      if (normalizedUserId == null) {
        throw const AuthFailure('User ID is required.');
      }
      final currentUser = await _getUserById(normalizedUserId);
      if (currentUser == null) {
        throw const AuthFailure('User not found.');
      }
      final driver = currentUser.asDriver;
      if (driver == null) {
        throw const AuthFailure(
          'Only driver accounts can upload license photos.',
        );
      }
      final upload = await _photoStorageService.uploadUserPhoto(
        bytes: bytes,
        userId: normalizedUserId,
        fieldKey: 'license_photo',
        fileName: fileName,
        mimeType: mimeType,
        size: size,
      );
      debugPrint(
        '[AUTH_REQUEST][LICENSE] Storage upload success userId=$normalizedUserId downloadUrl=${upload['download_url']}',
      );
      return saveUser(
        driver.copyWith(
          license: upload['download_url']?.toString(),
          updatedAt: DateTime.now(),
        ),
      );
    }, fallback: 'We could not upload the license photo right now.');
  }

  @override
  Future<void> deleteUser(String userId) async {
    await _runAuthRequest(() async {
      final normalized = normalizeId(userId);
      if (normalized == null) {
        return;
      }
      await _photoStorageService.deleteUserAssets(normalized);
      await _usersCollection.doc(normalized).delete();
      await _cache.clearResource(_usersResourceKey);
      if (await _storage.readString(_currentUserIdKey) == normalized) {
        await _storage.remove(_currentUserIdKey);
        AppSessionReset.clearUserScopedState();
      }
      if (await _storage.readString(_quickLoginSourceUserIdKey) == normalized) {
        await _storage.remove(_quickLoginSourceUserIdKey);
      }
    }, fallback: 'We could not delete the user right now. Please try again.');
  }

  @override
  Future<void> loginAsUser(String userId) async {
    await _runAuthRequest(() async {
      await initialize();
      final normalized = normalizeId(userId);
      if (normalized == null) {
        throw const AuthFailure('User ID is required.');
      }
      await _cache.clearResource(_usersResourceKey);
      final user = await _getFreshUserById(normalized);
      if (user == null) {
        throw const AuthFailure('No account found for that user.');
      }
      final currentUserId = await _storage.readString(_currentUserIdKey);
      if (normalizeId(currentUserId) != null && currentUserId != normalized) {
        await _storage.writeString(_quickLoginSourceUserIdKey, currentUserId!);
      }
      await _storage.writeString(_currentUserIdKey, normalized);
      AppSessionReset.clearUserScopedState();
    }, fallback: 'We could not switch accounts right now. Please try again.');
  }

  @override
  Future<bool> hasQuickLoginSource() async {
    await initialize();
    return normalizeId(await _storage.readString(_quickLoginSourceUserIdKey)) !=
        null;
  }

  @override
  Future<UserModel?> returnToQuickLoginSource() async {
    return _runAuthRequest(() async {
      await initialize();
      final sourceId = normalizeId(
        await _storage.readString(_quickLoginSourceUserIdKey),
      );
      if (sourceId == null) {
        return null;
      }
      await _cache.clearResource(_usersResourceKey);
      final sourceUser = await _getFreshUserById(sourceId);
      if (sourceUser == null) {
        await _storage.remove(_quickLoginSourceUserIdKey);
        await _storage.remove(_currentUserIdKey);
        AppSessionReset.clearUserScopedState();
        return null;
      }
      await _storage.writeString(_currentUserIdKey, sourceId);
      await _storage.remove(_quickLoginSourceUserIdKey);
      AppSessionReset.clearUserScopedState();
      return sourceUser;
    }, fallback: 'We could not switch back to the previous account right now.');
  }

  @override
  Future<void> logout() async {
    await _runAuthRequest(() async {
      await initialize();
      final currentUser = await getCurrentUser();
      if (currentUser != null && _supportsOnline(currentUser.role)) {
        await _persistUserDirect(
          currentUser.copyWith(isOnline: false, updatedAt: DateTime.now()),
        );
      }
      await _clearStoredSession();
      await FirestoreCacheStore.instance.clearAll();
      AppSessionReset.clearUserScopedState();
    }, fallback: 'We could not sign you out right now. Please try again.');
  }

  Future<UserModel?> _getUserById(String id) async {
    final users = await getUsers();
    return users.where((user) => user.id == id).firstOrNull;
  }

  Future<void> _clearStoredSession() async {
    await _storage.remove(_currentUserIdKey);
    await _storage.remove(_quickLoginSourceUserIdKey);
  }

  Future<List<UserModel>> _getUsersFresh() async {
    final types = await _vehicleRequest.getTypes();
    final typeById = {for (final item in types) item.id ?? '': item};
    final snapshot = await _usersCollection.get();
    final users = snapshot.docs
        .map((doc) => _userFromFirestoreMap(documentData(doc), typeById))
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

  Future<UserModel?> _getFreshUserById(String id) async {
    final snapshot = await _usersCollection.doc(id).get();
    if (!snapshot.exists) {
      return null;
    }
    return _inflateUser(snapshot);
  }

  Future<UserModel> _persistUserDirect(UserModel user) async {
    final normalizedId = normalizeId(user.id);
    if (normalizedId == null) {
      throw const AuthFailure('User ID is required.');
    }
    final now = DateTime.now();
    final existing = await _getFreshUserById(normalizedId);
    final saved = user.copyWith(
      id: normalizedId,
      createdAt: existing?.createdAt ?? user.createdAt ?? now,
      updatedAt: user.updatedAt ?? now,
    );
    await _usersCollection.doc(normalizedId).set(_toFirestoreMap(saved));
    return saved;
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

  Future<T> _runAuthRequest<T>(
    Future<T> Function() action, {
    required String fallback,
  }) async {
    try {
      return await action();
    } on AuthFailure {
      rethrow;
    } on FirebaseException catch (error) {
      debugPrint(
        '[AUTH_REQUEST][ERROR] FirebaseException code=${error.code} message=${error.message}',
      );
      throw AuthFailure(userFacingErrorMessage(error, fallback: fallback));
    } catch (error) {
      debugPrint('[AUTH_REQUEST][ERROR] $error');
      throw AuthFailure(userFacingErrorMessage(error, fallback: fallback));
    }
  }
}
