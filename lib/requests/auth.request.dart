import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/client_member.request.dart';
import 'package:webapp/requests/firestore_cache_store.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/app_session_reset.dart';
import 'package:webapp/services/booking_offline_upload_queue_service.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_cleanup_queue_service.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/offline_sync_status_service.dart';
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
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';
  static const _usersResourceKey = 'users';
  static bool _didRunSubClientMigration = false;

  final FirebaseFirestore _firestore;
  final VehicleRequest _vehicleRequest;
  final AuthStorageBackend _storage = createAuthStorageBackend();
  final PhotoStorageService _photoStorageService = PhotoStorageService.instance;
  final OfflineMutationQueueService _offlineMutationQueueService =
      OfflineMutationQueueService.instance;
  final OfflineMediaSyncService _offlineMediaSyncService =
      OfflineMediaSyncService.instance;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _clientMembersCollection =>
      _firestore.collection('client_members');

  @override
  Future<void> initialize() async {
    await _storage.initialize();
    await _offlineMediaSyncService.initialize();
    await _offlineMutationQueueService.initialize();
  }

  Future<void> migrateSubClientDataOnce() async {
    if (_didRunSubClientMigration) {
      return;
    }
    _didRunSubClientMigration = true;
    try {
      await _migrateLegacyMemberUsers();
      await _migrateClientMemberDocumentIds();
      await _cache.clearResource(_usersResourceKey);
    } catch (_) {}
  }

  @override
  Future<List<UserModel>> getUsers() async {
    return _runAuthRequest(() async {
      await initialize();
      final documentsFuture = _cache.getDocuments(
        resourceKey: _usersResourceKey,
        fetchDocuments: () async {
          final snapshot = await _usersCollection.get();
          return snapshot.docs.map(documentData).toList();
        },
      );
      final typeByIdFuture = _vehicleRequest.getTypeByIdCachedFirst();
      final documents = await documentsFuture;
      final typeById = await typeByIdFuture;
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
    final user = currentNetworkStatus()
        ? await _getFreshUserById(normalized)
        : await _getCachedUserById(normalized);
    if (user != null) {
      return user;
    }
    if (currentNetworkStatus()) {
      final cachedUser = await _getCachedUserById(normalized);
      if (cachedUser != null) {
        return cachedUser;
      }
    }
    await _clearStoredSession();
    AppSessionReset.clearUserScopedState();
    return null;
  }

  @override
  Future<UserModel> login({
    required String identifier,
    required String password,
  }) async {
    return _runAuthRequest(() async {
      await initialize();
      AppSessionReset.clearUserScopedState();
      final trimmedIdentifier = identifier.trim();
      final normalizedPhone = normalizePhilippinePhone(trimmedIdentifier);
      final bool isPhoneLogin = normalizedPhone != null;
      final user = await _resolveLoginUser(
        identifier: trimmedIdentifier,
        normalizedPhone: normalizedPhone,
        isPhoneLogin: isPhoneLogin,
      );
      if ((user.password ?? '') != password) {
        throw const AuthFailure('Incorrect password.');
      }
      if (user.isActive == false) {
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
      await _rememberKnownSessionUserId(loggedInUser.id);
      await _refreshOfflineQueueScopes();
      AppSessionReset.clearUserScopedState();
      return loggedInUser;
    }, fallback: 'We could not sign you in right now. Please try again.');
  }

  @override
  Future<UserModel> register(UserModel user) async {
    return _runAuthRequest(
      () async {
        await initialize();
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
          parentClientId: normalizeId(user.parentClientId),
          email: normalizedEmail,
          name: normalizedName,
          phone: normalizePhilippinePhone(user.phone) ?? user.phone?.trim(),
          position: _normalizeFlexibleText(user.position),
          isActive: isPendingApprovalRole ? false : true,
          isOnline: false,
          createdAt: user.createdAt ?? now,
          updatedAt: now,
        );
        await _usersCollection
            .doc(savedUser.id)
            .set(_toFirestoreMap(savedUser));
        await _storage.writeString(_currentUserIdKey, savedUser.id ?? '');
        await _rememberKnownSessionUserId(savedUser.id);
        await _refreshOfflineQueueScopes();
        await _cache.upsertDocument(
          resourceKey: _usersResourceKey,
          document: _toFirestoreMap(savedUser),
        );
        AppSessionReset.clearUserScopedState();
        return savedUser;
      },
      fallback: 'We could not create your account right now. Please try again.',
    );
  }

  @override
  Future<UserModel> saveUser(UserModel user) async {
    return _runAuthRequest(() async {
      await initialize();
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
        parentClientId: normalizeId(user.parentClientId),
        email: normalizedEmail,
        name: normalizedName,
        phone: normalizePhilippinePhone(user.phone) ?? user.phone?.trim(),
        position: _normalizeFlexibleText(user.position),
        isOnline: (user.isActive ?? false) && _supportsOnline(user.role)
            ? (user.isOnline ?? false)
            : false,
        createdAt: existing?.createdAt ?? user.createdAt ?? now,
        updatedAt: now,
      );
      final document = _toFirestoreMap(saved);
      final baseUpdatedAtIso =
          existing?.updatedAt?.toUtc().toIso8601String() ??
          user.updatedAt?.toUtc().toIso8601String();
      if (currentNetworkStatus()) {
        await _usersCollection.doc(nextId).set(document);
      } else {
        await _offlineMutationQueueService.queueUserUpsert(
          userId: nextId,
          document: document,
          baseUpdatedAt: baseUpdatedAtIso,
        );
      }
      await _cache.upsertDocument(
        resourceKey: _usersResourceKey,
        document: document,
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
      final normalizedUserId = normalizeId(userId);
      if (normalizedUserId == null) {
        throw const AuthFailure('User ID is required.');
      }
      final currentUser = await _getUserById(normalizedUserId);
      if (currentUser == null) {
        throw const AuthFailure('User not found.');
      }
      if (!currentNetworkStatus()) {
        final queued = await _offlineMediaSyncService.queueUserPhotoUpload(
          userId: normalizedUserId,
          fieldKey: 'profile_photo',
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          size: size,
          originalValue: currentUser.photo,
        );
        final queuedUser = currentUser.copyWith(
          photo: queued.previewUrl,
          updatedAt: queued.queuedAt,
        );
        await _cache.upsertDocument(
          resourceKey: _usersResourceKey,
          document: _toFirestoreMap(queuedUser),
        );
        return queuedUser;
      }
      try {
        final upload = await _photoStorageService.uploadUserPhoto(
          bytes: bytes,
          userId: normalizedUserId,
          fieldKey: 'profile_photo',
          fileName: fileName,
          mimeType: mimeType,
          size: size,
        );
        return saveUser(
          currentUser.copyWith(
            photo: upload['download_url']?.toString(),
            updatedAt: DateTime.now(),
          ),
        );
      } catch (error) {
        final normalizedError = normalizeUserErrorText(
          error.toString(),
          fallback: '',
        ).toLowerCase();
        if (!_isQueueableUploadError(normalizedError)) {
          rethrow;
        }
        final queued = await _offlineMediaSyncService.queueUserPhotoUpload(
          userId: normalizedUserId,
          fieldKey: 'profile_photo',
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          size: size,
          originalValue: currentUser.photo,
        );
        final queuedUser = currentUser.copyWith(
          photo: queued.previewUrl,
          updatedAt: queued.queuedAt,
        );
        await _cache.upsertDocument(
          resourceKey: _usersResourceKey,
          document: _toFirestoreMap(queuedUser),
        );
        return queuedUser;
      }
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
      if (!currentNetworkStatus()) {
        final queued = await _offlineMediaSyncService.queueUserPhotoUpload(
          userId: normalizedUserId,
          fieldKey: 'license_photo',
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          size: size,
          originalValue: driver.license,
        );
        final queuedUser = driver.copyWith(
          license: queued.previewUrl,
          updatedAt: queued.queuedAt,
        );
        await _cache.upsertDocument(
          resourceKey: _usersResourceKey,
          document: _toFirestoreMap(queuedUser),
        );
        return queuedUser;
      }
      try {
        final upload = await _photoStorageService.uploadUserPhoto(
          bytes: bytes,
          userId: normalizedUserId,
          fieldKey: 'license_photo',
          fileName: fileName,
          mimeType: mimeType,
          size: size,
        );
        return saveUser(
          driver.copyWith(
            license: upload['download_url']?.toString(),
            updatedAt: DateTime.now(),
          ),
        );
      } catch (error) {
        final normalizedError = normalizeUserErrorText(
          error.toString(),
          fallback: '',
        ).toLowerCase();
        if (!_isQueueableUploadError(normalizedError)) {
          rethrow;
        }
        final queued = await _offlineMediaSyncService.queueUserPhotoUpload(
          userId: normalizedUserId,
          fieldKey: 'license_photo',
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          size: size,
          originalValue: driver.license,
        );
        final queuedUser = driver.copyWith(
          license: queued.previewUrl,
          updatedAt: queued.queuedAt,
        );
        await _cache.upsertDocument(
          resourceKey: _usersResourceKey,
          document: _toFirestoreMap(queuedUser),
        );
        return queuedUser;
      }
    }, fallback: 'We could not upload the license photo right now.');
  }

  @override
  Future<UserModel> changePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    return _runAuthRequest(() async {
      final normalizedUserId = normalizeId(userId);
      if (normalizedUserId == null) {
        throw const AuthFailure('User ID is required.');
      }
      final trimmedOldPassword = oldPassword.trim();
      final trimmedNewPassword = newPassword.trim();
      if (trimmedOldPassword.isEmpty) {
        throw const AuthFailure('Old password is required.');
      }
      if (trimmedNewPassword.isEmpty) {
        throw const AuthFailure('New password is required.');
      }
      if (trimmedNewPassword.length < 6) {
        throw const AuthFailure('New password must be at least 6 characters.');
      }

      final currentUser = await _getFreshUserById(normalizedUserId);
      if (currentUser == null) {
        throw const AuthFailure('User not found.');
      }
      if ((currentUser.password ?? '') != trimmedOldPassword) {
        throw const AuthFailure('Old password is incorrect.');
      }
      if (trimmedOldPassword == trimmedNewPassword) {
        throw const AuthFailure(
          'New password must be different from the old password.',
        );
      }

      final updatedUser = await saveUser(
        currentUser.copyWith(
          password: trimmedNewPassword,
          updatedAt: DateTime.now(),
        ),
      );
      final currentUserId = normalizeId(
        await _storage.readString(_currentUserIdKey),
      );
      if (currentUserId == normalizedUserId) {
        await _storage.writeString(_currentUserIdKey, normalizedUserId);
      }
      return updatedUser;
    }, fallback: 'We could not change the password right now.');
  }

  @override
  Future<void> deleteUser(String userId) async {
    await _runAuthRequest(() async {
      await initialize();
      final normalized = normalizeId(userId);
      if (normalized == null) {
        return;
      }
      final deletedUser = await _getUserById(normalized);
      if (currentNetworkStatus()) {
        await _deleteLinkedClientMemberRecords(normalized);
        await _photoStorageService.deleteUserAssets(normalized);
        await _usersCollection.doc(normalized).delete();
      } else {
        await _offlineMutationQueueService.queueUserDelete(userId: normalized);
      }
      await _cache.removeDocument(
        resourceKey: _usersResourceKey,
        documentId: normalized,
      );
      final parentClientId = normalizeId(deletedUser?.parentClientId);
      if (parentClientId != null) {
        await FirestoreCacheStore.instance.clearResource(
          '${ClientMemberRequest.resourceKeyPrefix}:$parentClientId',
        );
      }
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
      final user = currentNetworkStatus()
          ? await _getFreshUserById(normalized)
          : await _getCachedUserById(normalized);
      if (user == null) {
        throw const AuthFailure('No account found for that user.');
      }
      final currentUserId = await _storage.readString(_currentUserIdKey);
      if (normalizeId(currentUserId) != null && currentUserId != normalized) {
        await _storage.writeString(_quickLoginSourceUserIdKey, currentUserId!);
      }
      await _storage.writeString(_currentUserIdKey, normalized);
      await _rememberKnownSessionUserId(normalized);
      await _refreshOfflineQueueScopes();
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
      final sourceUser = currentNetworkStatus()
          ? await _getFreshUserById(sourceId)
          : await _getCachedUserById(sourceId);
      if (sourceUser == null) {
        await _storage.remove(_quickLoginSourceUserIdKey);
        await _storage.remove(_currentUserIdKey);
        AppSessionReset.clearUserScopedState();
        return null;
      }
      await _storage.writeString(_currentUserIdKey, sourceId);
      await _storage.remove(_quickLoginSourceUserIdKey);
      await _rememberKnownSessionUserId(sourceId);
      await _refreshOfflineQueueScopes();
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
      await _refreshOfflineQueueScopes();
      AppSessionReset.clearUserScopedState();
    }, fallback: 'We could not sign you out right now. Please try again.');
  }

  Future<UserModel?> _getUserById(String id) async {
    final users = await getUsers();
    return users.where((user) => user.id == id).firstOrNull;
  }

  Future<UserModel?> _getCachedUserById(String id) async {
    try {
      return await _getUserById(id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearStoredSession() async {
    await _storage.remove(_currentUserIdKey);
    await _storage.remove(_quickLoginSourceUserIdKey);
  }

  Future<void> _rememberKnownSessionUserId(String? userId) async {
    final normalizedUserId = normalizeId(userId);
    if (normalizedUserId == null) {
      return;
    }
    final existing = await _storage.readStringList(_knownSessionUserIdsKey);
    final next = <String>[
      normalizedUserId,
      ...existing.where((item) => normalizeId(item) != normalizedUserId),
    ];
    await _storage.writeStringList(_knownSessionUserIdsKey, next);
  }

  Future<void> _refreshOfflineQueueScopes() async {
    await _offlineMediaSyncService.initialize();
    await _offlineMutationQueueService.initialize();
    await OfflineCleanupQueueService.instance.initialize();
    await BookingOfflineUploadQueueService.instance.initialize();
    await OfflineSyncStatusService.instance.initialize();
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
    final existing = currentNetworkStatus()
        ? await _getFreshUserById(normalizedId)
        : await _getCachedUserById(normalizedId);
    final saved = user.copyWith(
      id: normalizedId,
      createdAt: existing?.createdAt ?? user.createdAt ?? now,
      updatedAt: user.updatedAt ?? now,
    );
    final document = _toFirestoreMap(saved);
    final baseUpdatedAtIso =
        existing?.updatedAt?.toUtc().toIso8601String() ??
        user.updatedAt?.toUtc().toIso8601String();
    if (currentNetworkStatus()) {
      await _usersCollection.doc(normalizedId).set(document);
    } else {
      await _offlineMutationQueueService.queueUserUpsert(
        userId: normalizedId,
        document: document,
        baseUpdatedAt: baseUpdatedAtIso,
      );
    }
    await _cache.upsertDocument(
      resourceKey: _usersResourceKey,
      document: document,
    );
    return saved;
  }

  Future<UserModel> _resolveLoginUser({
    required String identifier,
    required String? normalizedPhone,
    required bool isPhoneLogin,
  }) async {
    if (!currentNetworkStatus()) {
      final offlineUser = await _findCachedUserByIdentifier(
        identifier: identifier,
        normalizedPhone: normalizedPhone,
        isPhoneLogin: isPhoneLogin,
      );
      if (offlineUser == null) {
        throw const AuthFailure(
          'No cached account found for that email or mobile number.',
        );
      }
      return offlineUser;
    }

    try {
      final matches = isPhoneLogin
          ? await _usersCollection
                .where('phone', isEqualTo: normalizedPhone)
                .limit(1)
                .get()
          : await _usersCollection
                .where('email', isEqualTo: identifier.toLowerCase())
                .limit(1)
                .get();
      if (matches.docs.isEmpty) {
        throw const AuthFailure(
          'No account found for that email or mobile number.',
        );
      }
      return _inflateUser(matches.docs.first);
    } catch (error) {
      if (!_isOfflineAuthLookupError(error)) {
        rethrow;
      }
      final offlineUser = await _findCachedUserByIdentifier(
        identifier: identifier,
        normalizedPhone: normalizedPhone,
        isPhoneLogin: isPhoneLogin,
      );
      if (offlineUser == null) {
        rethrow;
      }
      return offlineUser;
    }
  }

  Future<UserModel?> _findCachedUserByIdentifier({
    required String identifier,
    required String? normalizedPhone,
    required bool isPhoneLogin,
  }) async {
    final users = await _getUsersCachedOnly();
    if (isPhoneLogin) {
      for (final user in users) {
        if (normalizePhilippinePhone(user.phone) == normalizedPhone) {
          return user;
        }
      }
      return null;
    }
    final normalizedEmail = identifier.trim().toLowerCase();
    for (final user in users) {
      if ((user.email ?? '').trim().toLowerCase() == normalizedEmail) {
        return user;
      }
    }
    return null;
  }

  Future<List<UserModel>> _getUsersCachedOnly() async {
    final documents =
        await FirestoreCacheStore.instance.readDocumentMaps(_usersResourceKey) ??
        const <Map<String, dynamic>>[];
    final types = await _vehicleRequest.getTypes();
    final typeById = {for (final item in types) item.id ?? '': item};
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

  bool _isOfflineAuthLookupError(Object error) {
    final normalized = normalizeUserErrorText(
      error.toString(),
      fallback: '',
    ).toLowerCase();
    return normalized.contains('offline') ||
        normalized.contains('internet connection') ||
        normalized.contains('network') ||
        normalized.contains('progressEvent'.toLowerCase()) ||
        normalized.contains('client is offline');
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

  Future<void> _migrateLegacyMemberUsers() async {
    final snapshot = await _usersCollection
        .where('role', isEqualTo: 'member')
        .get();
    for (final doc in snapshot.docs) {
      final data = documentData(doc);
      await _usersCollection.doc(doc.id).set({...data, 'role': 'sub-client'});
    }
  }

  Future<void> _migrateClientMemberDocumentIds() async {
    final snapshot = await _clientMembersCollection.get();
    for (final doc in snapshot.docs) {
      final data = documentData(doc);
      final userId = normalizeId(data['user_id']?.toString());
      if (userId == null || userId == doc.id) {
        continue;
      }
      final clientId = normalizeId(data['client_id']?.toString());
      final migratedData = <String, dynamic>{
        ...data,
        'id': userId,
        'user_id': userId,
        'client_id': clientId,
      };
      await _clientMembersCollection.doc(userId).set(migratedData);
      await _clientMembersCollection.doc(doc.id).delete();
      if (clientId != null) {
        await FirestoreCollectionCache(firestore: _firestore).removeDocument(
          resourceKey: '${ClientMemberRequest.resourceKeyPrefix}:$clientId',
          documentId: doc.id,
        );
        await FirestoreCollectionCache(firestore: _firestore).upsertDocument(
          resourceKey: '${ClientMemberRequest.resourceKeyPrefix}:$clientId',
          document: migratedData,
        );
      }
    }
  }

  Future<void> _deleteLinkedClientMemberRecords(String userId) async {
    final matches = await _clientMembersCollection
        .where('user_id', isEqualTo: userId)
        .get();
    for (final doc in matches.docs) {
      final data = documentData(doc);
      final clientId = normalizeId(data['client_id']?.toString());
      await _clientMembersCollection.doc(doc.id).delete();
      if (clientId != null) {
        await FirestoreCollectionCache(firestore: _firestore).removeDocument(
          resourceKey: '${ClientMemberRequest.resourceKeyPrefix}:$clientId',
          documentId: doc.id,
        );
      }
    }
    final directDoc = await _clientMembersCollection.doc(userId).get();
    if (directDoc.exists) {
      final data = documentData(directDoc);
      final clientId = normalizeId(data['client_id']?.toString());
      await _clientMembersCollection.doc(userId).delete();
      if (clientId != null) {
        await FirestoreCollectionCache(firestore: _firestore).removeDocument(
          resourceKey: '${ClientMemberRequest.resourceKeyPrefix}:$clientId',
          documentId: userId,
        );
      }
    }
  }

  String? _normalizeTitleCase(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return value;
    }
    return toTitleCase(trimmed);
  }

  String? _normalizeFlexibleText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return value;
    }
    return trimmed;
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

  bool _isQueueableUploadError(String normalizedError) {
    return normalizedError.contains('internet connection') ||
        normalizedError.contains('temporarily unavailable') ||
        normalizedError.contains('request took too long') ||
        normalizedError.contains('failed to fetch') ||
        normalizedError.contains('network error') ||
        normalizedError.contains('network-request-failed') ||
        normalizedError.contains('progressevent');
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
      throw AuthFailure(userFacingErrorMessage(error, fallback: fallback));
    } catch (error) {
      throw AuthFailure(userFacingErrorMessage(error, fallback: fallback));
    }
  }
}
