import 'dart:async';
import 'dart:convert';

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
import 'package:webapp/services/firebase_auth_bridge_service.dart';
import 'package:webapp/services/firestore_public_document_fetcher.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/services/offline_mutation_queue_service.dart';
import 'package:webapp/services/offline_media_sync_service.dart';
import 'package:webapp/services/offline_queue_coordinator_service.dart';
import 'package:webapp/services/photo_storage_service.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';

class AuthRequest implements AuthRepository {
  AuthRequest({
    FirebaseFirestore? firestore,
    VehicleRequest? vehicleRequest,
    AuthStorageBackend? storageBackend,
    OfflineMutationQueueService? offlineMutationQueueService,
    OfflineMediaSyncService? offlineMediaSyncService,
    PhotoStorageService? photoStorageService,
    FirebaseAuthBridgeService? firebaseAuthBridgeService,
    FirestorePublicDocumentFetcher? firestorePublicDocumentFetcher,
    Future<void> Function()? offlineQueueInitializer,
    Future<void> Function()? offlineQueueFlusher,
  })
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _vehicleRequest = vehicleRequest ?? VehicleRequest.instance,
      _storage = storageBackend ?? createAuthStorageBackend(),
      _photoStorageService = photoStorageService ?? PhotoStorageService.instance,
      _firebaseAuthBridgeService =
          firebaseAuthBridgeService ?? FirebaseAuthBridgeService.instance,
      _firestorePublicDocumentFetcher =
          firestorePublicDocumentFetcher ??
          createFirestorePublicDocumentFetcher(),
      _offlineMutationQueueService =
          offlineMutationQueueService ?? OfflineMutationQueueService.instance,
      _offlineMediaSyncService =
          offlineMediaSyncService ?? OfflineMediaSyncService.instance,
      _offlineQueueInitializer =
          offlineQueueInitializer ??
          OfflineQueueCoordinatorService.instance.initialize,
      _offlineQueueFlusher =
          offlineQueueFlusher ?? OfflineQueueCoordinatorService.instance.flushAll;

  static final AuthRequest instance = AuthRequest();

  static const _currentUserIdKey = 'paltranco_current_user_id';
  static const _quickLoginSourceUserIdKey =
      'paltranco_quick_login_source_user_id';
  static const _quickLoginSourceSnapshotKey =
      'paltranco_quick_login_source_snapshot';
  static const _knownSessionUserIdsKey = 'paltranco_known_session_user_ids';
  static const _currentSessionAuthSnapshotKey =
      'paltranco_current_session_auth_snapshot';
  static const _usersResourceKey = 'users';
  static const Duration _startupTimeout = Duration(seconds: 6);
  static const Duration _loginLookupTimeout = Duration(seconds: 10);
  static const Duration _loginFallbackLookupTimeout = Duration(seconds: 3);
  static const Duration _localWriteTimeout = Duration(seconds: 2);
  static const Duration _photoUploadTimeout = Duration(minutes: 1);
  static const Duration _deleteTimeout = Duration(seconds: 6);
  static const Duration _remoteUserWriteTimeout = Duration(seconds: 30);

  final FirebaseFirestore _firestore;
  final VehicleRequest _vehicleRequest;
  final AuthStorageBackend _storage;
  final PhotoStorageService _photoStorageService;
  final FirebaseAuthBridgeService _firebaseAuthBridgeService;
  final FirestorePublicDocumentFetcher _firestorePublicDocumentFetcher;
  final OfflineMutationQueueService _offlineMutationQueueService;
  final OfflineMediaSyncService _offlineMediaSyncService;
  final Future<void> Function() _offlineQueueInitializer;
  final Future<void> Function() _offlineQueueFlusher;
  late final FirestoreCollectionCache _cache = FirestoreCollectionCache(
    firestore: _firestore,
  );
  bool _isInitialized = false;
  Future<void>? _initializingFuture;
  String? _pendingSelfSessionUserId;
  Map<String, dynamic>? _pendingSelfSessionSnapshot;
  DateTime? _pendingSelfSessionExpiresAt;

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _clientMembersCollection =>
      _firestore.collection('client_members');

  @override
  Future<void> initialize() async {
    final existingInitialization = _initializingFuture;
    if (existingInitialization != null) {
      await existingInitialization;
      return;
    }
    if (_isInitialized) {
      return;
    }
    final initialization = _initializeInternal();
    _initializingFuture = initialization;
    try {
      await initialization;
      _isInitialized = true;
    } finally {
      _initializingFuture = null;
    }
  }

  Future<void> _initializeInternal() async {
    await _storage.initialize();
    await _firebaseAuthBridgeService.initialize();
    await _rememberStoredSessionAnchors();
    unawaited(
      _offlineQueueInitializer().then((_) {
      }).catchError((error, stackTrace) {
      }),
    );
  }

  @override
  Future<List<UserModel>> getUsers() async {
    return _runAuthRequest(() async {
      await initialize();
      final cachedUsers = await _getUsersCachedOnly();
      if (cachedUsers.isNotEmpty) {
        if (currentNetworkStatus()) {
          unawaited(_refreshUsersCacheInBackground());
        }
        return cachedUsers;
      }

      final typeByIdFuture = _vehicleRequest
          .getTypeByIdCachedFirst()
          .timeout(_startupTimeout, onTimeout: () => <String, VehicleCatalogItem>{});
      final documents = await _usersCollection.get().timeout(
        _startupTimeout,
        onTimeout: () {
          throw TimeoutException('users fetch timeout');
        },
      );
      final rawDocuments = documents.docs.map(documentData).toList(growable: false);
      await _cache.writeDocuments(
        resourceKey: _usersResourceKey,
        documents: rawDocuments,
      );
      await _writeUsersCacheLocally(rawDocuments);
      final typeById = await typeByIdFuture;
      final users = rawDocuments
          .map((doc) => _userFromFirestoreMap(doc, typeById))
          .toList(growable: false);
      _sortUsersNewestFirst(users);
      return users;
    }, fallback: 'We could not load the users right now.');
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    await initialize();
    final currentId = await _storage.readString(_currentUserIdKey);
    final normalized = normalizeId(currentId);
    final isOnline = currentNetworkStatus();
    if (normalized == null) {
      return null;
    }
    await _rememberKnownSessionUserId(normalized);
    final cachedUser = await _getCachedUserById(normalized);
    if (cachedUser != null) {
      if (isOnline) {
        unawaited(_validateStoredSessionInBackground(normalized));
      }
      return await _firebaseAuthBridgeService.hydrateUser(cachedUser);
    }
    final sessionSnapshotUser = _userFromSessionSnapshot(
      await _readCurrentSessionSnapshot(),
    );
    if (normalizeId(sessionSnapshotUser?.id) == normalized) {
      if (isOnline) {
        unawaited(_validateStoredSessionInBackground(normalized));
      }
      return await _firebaseAuthBridgeService.hydrateUser(sessionSnapshotUser!);
    }
    if (isOnline) {
      final freshUser = await _getStartupSafeCurrentUser(normalized);
      if (freshUser != null) {
        return await _firebaseAuthBridgeService.hydrateUser(freshUser);
      }
    }
    if (!isOnline) {
      return null;
    }
    await _clearStoredSession();
    AppSessionReset.clearUserScopedState();
    return null;
  }

  Stream<void> watchCurrentSessionInvalidation() async* {
    await initialize();
    final currentUserId = normalizeId(await _storage.readString(_currentUserIdKey));
    if (currentUserId == null) {
      return;
    }
    yield* _usersCollection.doc(currentUserId).snapshots().asyncExpand((snapshot) async* {
      if (snapshot.metadata.isFromCache) {
        return;
      }
      final activeUserId = normalizeId(await _storage.readString(_currentUserIdKey));
      if (activeUserId != currentUserId) {
        return;
      }
      final validatedUser = await _validateCurrentSessionWithFreshUser(
        currentUserId,
        snapshot.exists ? await _inflateUser(snapshot) : null,
      );
      if (validatedUser == null) {
        yield null;
      }
    });
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
      final loginUser = user.copyWith(
        isOnline: _supportsOnline(user.role) ? true : false,
        updatedAt: DateTime.now(),
      );
      final loggedInUser = await _persistUserForLogin(loginUser);
      final bridgedUser = await _firebaseAuthBridgeService.syncSessionForUser(
        loggedInUser,
      );
      await _storage.writeString(_currentUserIdKey, loggedInUser.id ?? '');
      await _writeCurrentSessionSnapshot(bridgedUser);
      await _rememberKnownSessionUserId(bridgedUser.id);
      unawaited(
        _refreshOfflineQueueScopes().then((_) {
        }),
      );
      AppSessionReset.clearUserScopedState();
      return bridgedUser;
    }, fallback: 'We could not sign you in right now. Please try again.');
  }

  @override
  Future<UserModel> register(UserModel user) async {
    return _runAuthRequest(
      () async {
        await initialize();
        AppSessionReset.clearUserScopedState();
        var users = await _getUsersCachedOnly();
        if (users.isEmpty && currentNetworkStatus()) {
          try {
            users = await _getUsersFresh().timeout(
              _startupTimeout,
              onTimeout: () => const <UserModel>[],
            );
          } catch (error) {
            // Best-effort remote refresh only; local cache path continues.
          }
        } else if (currentNetworkStatus()) {
          unawaited(_refreshUsersCacheInBackground());
        }
        final normalizedRole = normalizeRoleKey(user.role);
        final isPendingApprovalRole =
            normalizedRole == 'driver' || normalizedRole == 'helper';
        final normalizedEmail = (user.email ?? '').trim().toLowerCase();
        final normalizedPhone =
            normalizePhilippinePhone(user.phone) ?? user.phone?.trim() ?? '';
        final normalizedName = _normalizeTitleCase(user.name);
        final emailTaken = users.any(
          (item) => (item.email ?? '').trim().toLowerCase() == normalizedEmail,
        );
        if (emailTaken) {
          throw const AuthFailure('That email is already registered.');
        }
        final phoneTaken = users.any((item) {
          final itemPhone =
              normalizePhilippinePhone(item.phone) ?? item.phone?.trim() ?? '';
          return itemPhone.isNotEmpty &&
              normalizedPhone.isNotEmpty &&
              itemPhone == normalizedPhone;
        });
        if (phoneTaken) {
          throw const AuthFailure('That phone number is already registered.');
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
          phone: normalizedPhone,
          position: _normalizeFlexibleText(user.position),
          isActive: isPendingApprovalRole ? false : true,
          isOnline: false,
          createdAt: user.createdAt ?? now,
          updatedAt: now,
        );
        final document = _toFirestoreMap(savedUser);
        if (currentNetworkStatus()) {
          try {
            await _usersCollection
                .doc(savedUser.id)
                .set(document)
                .timeout(_remoteUserWriteTimeout);
          } catch (error) {
            throw AuthFailure(
              userFacingErrorMessage(
                error,
                fallback:
                    'We could not create your account right now. Please try again.',
              ),
            );
          }
        } else {
          try {
            await _offlineMutationQueueService
                .queueUserUpsert(
                  userId: savedUser.id!,
                  document: document,
                  baseUpdatedAt: null,
                )
                .timeout(_localWriteTimeout);
          } catch (queueError) {
            // Queue persistence is best-effort; cache/session writes still proceed.
          }
        }
        try {
          await _cache
              .upsertDocument(
                resourceKey: _usersResourceKey,
                document: document,
              )
              .timeout(_localWriteTimeout);
        } catch (cacheError) {
          // Cache write failure should not block registration success.
        }
        try {
          await _upsertUserCacheLocally(document).timeout(_localWriteTimeout);
        } catch (localCacheError) {
          // Secondary local cache write is best-effort only.
        }
        UserModel bridgedUser = savedUser;
        try {
          bridgedUser = await _firebaseAuthBridgeService
              .syncSessionForUser(savedUser)
              .timeout(_loginFallbackLookupTimeout, onTimeout: () => savedUser);
        } catch (error) {
          // Bridge sync is optional because this app uses Firestore-backed auth state.
        }
        await _storage
            .writeString(_currentUserIdKey, savedUser.id ?? '')
            .timeout(_localWriteTimeout);
        try {
          await _writeCurrentSessionSnapshot(bridgedUser).timeout(
            _localWriteTimeout,
          );
        } catch (sessionSnapshotError) {
          // Session snapshot write is best-effort only.
        }
        try {
          await _rememberKnownSessionUserId(bridgedUser.id).timeout(
            _localWriteTimeout,
          );
        } catch (knownUserError) {
          // Known-session tracking is best-effort only.
        }
        unawaited(
          _refreshOfflineQueueScopes().then((_) {
          }).catchError((error, stackTrace) {
          }),
        );
        AppSessionReset.clearUserScopedState();
        return bridgedUser;
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
      final normalizedPhone =
          normalizePhilippinePhone(user.phone) ?? user.phone?.trim() ?? '';
      final normalizedName = _normalizeTitleCase(user.name);
      final emailTakenByOther = users.any(
        (item) =>
            item.id != user.id &&
            (item.email ?? '').trim().toLowerCase() == normalizedEmail,
      );
      if (emailTakenByOther) {
        throw const AuthFailure('That email is already registered.');
      }
      final phoneTakenByOther = users.any((item) {
        if (item.id == user.id) {
          return false;
        }
        final itemPhone =
            normalizePhilippinePhone(item.phone) ?? item.phone?.trim() ?? '';
        return itemPhone.isNotEmpty &&
            normalizedPhone.isNotEmpty &&
            itemPhone == normalizedPhone;
      });
      if (phoneTakenByOther) {
        throw const AuthFailure('That phone number is already registered.');
      }
      final now = DateTime.now();
      final nextId = normalizeId(user.id) ?? await _nextUserId(users);
      final existing = users.where((item) => item.id == nextId).firstOrNull;
      final saved = user.copyWith(
        id: nextId,
        parentClientId: normalizeId(user.parentClientId),
        email: normalizedEmail,
        name: normalizedName,
        phone: normalizedPhone,
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
      final currentUserId = normalizeId(await _storage.readString(_currentUserIdKey));
      final isCurrentUserUpdate = currentUserId == nextId;
      if (isCurrentUserUpdate) {
        _stagePendingSelfSessionSnapshot(saved);
      }
      if (currentNetworkStatus()) {
        try {
          await _usersCollection
              .doc(nextId)
              .set(document)
              .timeout(_remoteUserWriteTimeout);
        } catch (error) {
          await _offlineMutationQueueService
              .queueUserUpsert(
                userId: nextId,
                document: document,
                baseUpdatedAt: baseUpdatedAtIso,
              )
              .timeout(_localWriteTimeout);
        }
      } else {
        await _offlineMutationQueueService.queueUserUpsert(
          userId: nextId,
          document: document,
          baseUpdatedAt: baseUpdatedAtIso,
        ).timeout(_localWriteTimeout);
      }
      await _cache.upsertDocument(
        resourceKey: _usersResourceKey,
        document: document,
      ).timeout(_localWriteTimeout, onTimeout: () {});
      await _firebaseAuthBridgeService.syncUserLink(saved).timeout(
        _localWriteTimeout,
        onTimeout: () => saved,
      );
      if (isCurrentUserUpdate) {
        await _storage.writeString(_currentUserIdKey, nextId).timeout(
          _localWriteTimeout,
          onTimeout: () {},
        );
        final bridgedCurrentUser = await _firebaseAuthBridgeService
            .syncSessionForUser(saved)
            .timeout(_localWriteTimeout, onTimeout: () => saved);
        await _writeCurrentSessionSnapshot(bridgedCurrentUser).timeout(
          _localWriteTimeout,
          onTimeout: () {},
        );
        _clearPendingSelfSessionSnapshot();
      }
      return saved;
    }, fallback: 'We could not save the user right now. Please try again.');
  }

  void _stagePendingSelfSessionSnapshot(UserModel user) {
    _pendingSelfSessionUserId = normalizeId(user.id);
    _pendingSelfSessionSnapshot = _sessionAuthSnapshotForUser(user);
    _pendingSelfSessionExpiresAt = DateTime.now().add(
      const Duration(seconds: 15),
    );
  }

  void _clearPendingSelfSessionSnapshot() {
    _pendingSelfSessionUserId = null;
    _pendingSelfSessionSnapshot = null;
    _pendingSelfSessionExpiresAt = null;
  }

  bool _matchesPendingSelfSessionSnapshot(
    String currentUserId,
    Map<String, dynamic> freshSnapshot,
  ) {
    final pendingUserId = _pendingSelfSessionUserId;
    final pendingSnapshot = _pendingSelfSessionSnapshot;
    final expiresAt = _pendingSelfSessionExpiresAt;
    if (pendingUserId == null ||
        pendingSnapshot == null ||
        expiresAt == null ||
        pendingUserId != currentUserId) {
      return false;
    }
    if (DateTime.now().isAfter(expiresAt)) {
      _clearPendingSelfSessionSnapshot();
      return false;
    }
    return _sessionAuthSnapshotsEqual(pendingSnapshot, freshSnapshot);
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
      final currentUser =
          await _getCachedUserById(normalizedUserId) ??
          await _getUserById(
            normalizedUserId,
          ).timeout(_startupTimeout, onTimeout: () => null);
      if (currentUser == null) {
        throw const AuthFailure('User not found.');
      }
      if (!currentNetworkStatus()) {
        try {
          final queued = await _offlineMediaSyncService
              .queueUserPhotoUpload(
                userId: normalizedUserId,
                fieldKey: 'profile_photo',
                bytes: bytes,
                fileName: fileName,
                mimeType: mimeType,
                size: size,
                originalValue: currentUser.photo,
              )
              .timeout(_photoUploadTimeout);
          final queuedUser = currentUser.copyWith(
            photo: queued.previewUrl,
            updatedAt: queued.queuedAt,
          );
          await _applyImmediateUserPhotoState(queuedUser).timeout(
            _localWriteTimeout,
          );
          return queuedUser;
        } catch (queueError) {
          final previewUser = _userWithImmediatePhotoPreview(
            currentUser,
            bytes: bytes,
            mimeType: mimeType,
          );
          await _applyImmediateUserPhotoState(previewUser).timeout(
            _localWriteTimeout,
          );
          return previewUser;
        }
      }
      try {
        final upload = await _photoStorageService
            .uploadUserPhoto(
          bytes: bytes,
          userId: normalizedUserId,
          fieldKey: 'profile_photo',
          fileName: fileName,
          mimeType: mimeType,
          size: size,
        )
            .timeout(_photoUploadTimeout);
        final uploadedUser = currentUser.copyWith(
          photo: upload['download_url']?.toString(),
          updatedAt: DateTime.now(),
        );
        await _applyImmediateUserPhotoState(uploadedUser).timeout(
          _localWriteTimeout,
          onTimeout: () {},
        );
        return await saveUser(uploadedUser);
      } catch (error) {
        final normalizedError = normalizeUserErrorText(
          error.toString(),
          fallback: '',
        ).toLowerCase();
        if (!_isQueueableUploadError(normalizedError)) {
          rethrow;
        }
        try {
          final queued = await _offlineMediaSyncService
              .queueUserPhotoUpload(
                userId: normalizedUserId,
                fieldKey: 'profile_photo',
                bytes: bytes,
                fileName: fileName,
                mimeType: mimeType,
                size: size,
                originalValue: currentUser.photo,
              )
              .timeout(_photoUploadTimeout);
          final queuedUser = currentUser.copyWith(
            photo: queued.previewUrl,
            updatedAt: queued.queuedAt,
          );
          await _applyImmediateUserPhotoState(queuedUser).timeout(
            _localWriteTimeout,
          );
          return queuedUser;
        } catch (queueError) {
          final previewUser = _userWithImmediatePhotoPreview(
            currentUser,
            bytes: bytes,
            mimeType: mimeType,
          );
          await _applyImmediateUserPhotoState(previewUser).timeout(
            _localWriteTimeout,
          );
          return previewUser;
        }
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
      final currentUser =
          await _getCachedUserById(normalizedUserId) ??
          await _getUserById(
            normalizedUserId,
          ).timeout(_startupTimeout, onTimeout: () => null);
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
        final queued = await _offlineMediaSyncService
            .queueUserPhotoUpload(
              userId: normalizedUserId,
              fieldKey: 'license_photo',
              bytes: bytes,
              fileName: fileName,
              mimeType: mimeType,
              size: size,
              originalValue: driver.license,
            )
            .timeout(_photoUploadTimeout);
        final queuedUser = driver.copyWith(
          license: queued.previewUrl,
          updatedAt: queued.queuedAt,
        );
        await _cache.upsertDocument(
          resourceKey: _usersResourceKey,
          document: _toFirestoreMap(queuedUser),
        ).timeout(_localWriteTimeout);
        return queuedUser;
      }
      try {
        final upload = await _photoStorageService
            .uploadUserPhoto(
          bytes: bytes,
          userId: normalizedUserId,
          fieldKey: 'license_photo',
          fileName: fileName,
          mimeType: mimeType,
          size: size,
        )
            .timeout(_photoUploadTimeout);
        return await saveUser(
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
        try {
          final queued = await _offlineMediaSyncService
              .queueUserPhotoUpload(
                userId: normalizedUserId,
                fieldKey: 'license_photo',
                bytes: bytes,
                fileName: fileName,
                mimeType: mimeType,
                size: size,
                originalValue: driver.license,
              )
              .timeout(_photoUploadTimeout);
          final queuedUser = driver.copyWith(
            license: queued.previewUrl,
            updatedAt: queued.queuedAt,
          );
          await _cache.upsertDocument(
            resourceKey: _usersResourceKey,
            document: _toFirestoreMap(queuedUser),
          ).timeout(_localWriteTimeout);
          return queuedUser;
        } catch (queueError) {
          return driver;
        }
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
        await _writeCurrentSessionSnapshot(updatedUser);
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
      final deletedUser =
          await _getCachedUserById(normalized) ??
          await _getUserById(normalized).timeout(
            _startupTimeout,
            onTimeout: () => null,
          );
      if (currentNetworkStatus()) {
        unawaited(
          _deleteLinkedClientMemberRecords(normalized)
              .timeout(_deleteTimeout)
              .catchError((_) {}),
        );
        unawaited(
          _photoStorageService.deleteUserAssets(normalized)
              .timeout(_deleteTimeout)
              .catchError((_) {}),
        );
        try {
          await _usersCollection.doc(normalized).delete().timeout(_deleteTimeout);
        } catch (_) {
          await _offlineMutationQueueService
              .queueUserDelete(userId: normalized)
              .timeout(_localWriteTimeout);
        }
      } else {
        await _offlineMutationQueueService
            .queueUserDelete(userId: normalized)
            .timeout(_localWriteTimeout);
      }
      await _cache.removeDocument(
        resourceKey: _usersResourceKey,
        documentId: normalized,
      ).timeout(_localWriteTimeout, onTimeout: () {});
      final parentClientId = normalizeId(deletedUser?.parentClientId);
      if (parentClientId != null) {
        await FirestoreCacheStore.instance.clearResource(
          '${ClientMemberRequest.resourceKeyPrefix}:$parentClientId',
        ).timeout(_localWriteTimeout, onTimeout: () {});
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
        final currentSnapshot = await _readCurrentSessionSnapshot();
        final currentSourceUser =
            currentSnapshot != null
            ? _userFromSessionSnapshot(currentSnapshot)
            : await _getCachedUserById(currentUserId!);
        await _rememberKnownSessionUserId(currentUserId);
        await _storage.writeString(_quickLoginSourceUserIdKey, currentUserId!);
        if (currentSourceUser != null) {
          await _storage.writeString(
            _quickLoginSourceSnapshotKey,
            jsonEncode(_sessionAuthSnapshotForUser(currentSourceUser)),
          );
        } else {
          await _storage.remove(_quickLoginSourceSnapshotKey);
        }
      }
      await _storage.writeString(_currentUserIdKey, normalized);
      final bridgedUser = await _firebaseAuthBridgeService.syncSessionForUser(
        user,
      );
      await _writeCurrentSessionSnapshot(bridgedUser);
      await _rememberKnownSessionUserId(normalized);
      await _refreshOfflineQueueScopes();
      AppSessionReset.clearUserScopedState();
    }, fallback: 'We could not switch accounts right now. Please try again.');
  }

  @override
  Future<bool> hasQuickLoginSource() async {
    await initialize();
    final sourceId = normalizeId(
      await _storage.readString(_quickLoginSourceUserIdKey),
    );
    if (sourceId != null) {
      await _rememberKnownSessionUserId(sourceId);
    }
    return sourceId != null;
  }

  @override
  Future<UserModel?> returnToQuickLoginSource() async {
    return _runAuthRequest(() async {
      await initialize();
      final activeSessionUserId = normalizeId(
        await _storage.readString(_currentUserIdKey),
      );
      final activeSessionSnapshot = await _readCurrentSessionSnapshot();
      final activeSessionFallbackUser =
          activeSessionUserId == null
          ? _userFromSessionSnapshot(activeSessionSnapshot)
          : await _getCachedUserById(activeSessionUserId) ??
                _userFromSessionSnapshot(activeSessionSnapshot);
      final sourceId = normalizeId(
        await _storage.readString(_quickLoginSourceUserIdKey),
      );
      final sourceSnapshot = await _readQuickLoginSourceSnapshot();
      if (sourceId == null) {
        await _storage.remove(_quickLoginSourceSnapshotKey);
        return activeSessionFallbackUser;
      }
      UserModel? sourceUser;
      sourceUser = _userFromSessionSnapshot(sourceSnapshot);
      if (normalizeId(sourceUser?.id) != sourceId) {
        sourceUser = null;
      }
      if (sourceUser == null && currentNetworkStatus()) {
        sourceUser = await _getFreshUserById(
          sourceId,
        ).timeout(_startupTimeout, onTimeout: () => null);
      }
      sourceUser ??= await _getCachedUserById(sourceId);
      if (normalizeId(sourceUser?.id) != sourceId) {
        sourceUser = null;
      }
      if (sourceUser == null) {
        await _storage.remove(_quickLoginSourceUserIdKey);
        await _storage.remove(_quickLoginSourceSnapshotKey);
        return activeSessionFallbackUser;
      }
      final bridgedSourceUser = await _firebaseAuthBridgeService
          .syncSessionForUser(sourceUser);
      await _storage.writeString(_currentUserIdKey, sourceId);
      await _writeCurrentSessionSnapshot(bridgedSourceUser);
      await _storage.remove(_quickLoginSourceUserIdKey);
      await _storage.remove(_quickLoginSourceSnapshotKey);
      await _rememberKnownSessionUserId(sourceId);
      await _refreshOfflineQueueScopes();
      AppSessionReset.clearUserScopedState();
      return bridgedSourceUser;
    }, fallback: 'We could not switch back to the previous account right now.');
  }

  @override
  Future<void> logout() async {
    await _runAuthRequest(() async {
      await initialize();
      final currentUser = await getCurrentUser();
      if (currentUser != null && _supportsOnline(currentUser.role)) {
        unawaited(
          () async {
            try {
              await _persistUserDirect(
                currentUser.copyWith(
                  isOnline: false,
                  updatedAt: DateTime.now(),
                ),
              );
            } catch (_) {}
          }(),
        );
      }
      await _firebaseAuthBridgeService.clearSession();
      await _clearStoredSession();
      AppSessionReset.clearUserScopedState();
      unawaited(_refreshOfflineQueueScopes().catchError((_) {}));
    }, fallback: 'We could not sign you out right now. Please try again.');
  }

  Future<UserModel?> _getUserById(String id) async {
    final users = await getUsers();
    return users.where((user) => user.id == id).firstOrNull;
  }

  Future<UserModel?> _getCachedUserById(String id) async {
    try {
      final normalizedId = normalizeId(id);
      if (normalizedId == null) {
        return null;
      }
      final cachedUsers = await _getUsersCachedOnly();
      for (final user in cachedUsers) {
        if (normalizeId(user.id) == normalizedId) {
          return user;
        }
      }
      final sessionSnapshot = await _readCurrentSessionSnapshot();
      final sessionSnapshotUser = _userFromSessionSnapshot(sessionSnapshot);
      if (normalizeId(sessionSnapshotUser?.id) == normalizedId) {
        return sessionSnapshotUser;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearStoredSession() async {
    await _storage.remove(_currentUserIdKey);
    await _storage.remove(_quickLoginSourceUserIdKey);
    await _storage.remove(_quickLoginSourceSnapshotKey);
    await _storage.remove(_currentSessionAuthSnapshotKey);
  }

  Future<void> _clearStoredSessionPreservingState() async {
    await _storage.remove(_currentUserIdKey);
    await _storage.remove(_quickLoginSourceUserIdKey);
    await _storage.remove(_quickLoginSourceSnapshotKey);
    await _storage.remove(_currentSessionAuthSnapshotKey);
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

  Future<void> _rememberStoredSessionAnchors() async {
    final currentUserId = await _storage.readString(_currentUserIdKey);
    final quickLoginSourceUserId = await _storage.readString(
      _quickLoginSourceUserIdKey,
    );
    await _rememberKnownSessionUserId(currentUserId);
    await _rememberKnownSessionUserId(quickLoginSourceUserId);
  }

  Future<void> _refreshOfflineQueueScopes() async {
    await _offlineQueueInitializer();
    unawaited(
      _offlineQueueFlusher().catchError((error, stackTrace) {}),
    );
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

  Future<void> _refreshUsersCacheInBackground() async {
    try {
      final users = await _getUsersFresh().timeout(
        _startupTimeout,
        onTimeout: () => const <UserModel>[],
      );
      if (users.isEmpty) {
        return;
      }
      final documents = users
          .map((user) => _toFirestoreMap(user))
          .toList(growable: false);
      await _cache.writeDocuments(
        resourceKey: _usersResourceKey,
        documents: documents,
      );
      await _writeUsersCacheLocally(documents);
    } catch (error) {
      // Background cache refresh must never block startup or interactive flows.
    }
  }

  void _sortUsersNewestFirst(List<UserModel> users) {
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
  }

  Future<UserModel?> _getFreshUserById(String id) async {
    final snapshot = await _usersCollection.doc(id).get();
    if (!snapshot.exists) {
      return null;
    }
    return _inflateUser(snapshot);
  }

  Future<UserModel?> _getStartupSafeCurrentUser(String currentUserId) async {
    try {
      final freshUser = await _getFreshUserById(
        currentUserId,
      ).timeout(_startupTimeout, onTimeout: () {
        return null;
      });
      if (freshUser == null) {
        final cachedUser = await _getCachedUserById(currentUserId);
        if (cachedUser != null) {
          return cachedUser;
        }
        if (!currentNetworkStatus()) {
          final sessionSnapshotUser = _userFromSessionSnapshot(
            await _readCurrentSessionSnapshot(),
          );
          if (normalizeId(sessionSnapshotUser?.id) == currentUserId) {
            return sessionSnapshotUser;
          }
        }
      }
      final validatedUser = await _validateCurrentSessionWithFreshUser(
        currentUserId,
        freshUser,
        allowSessionClear: false,
      ).timeout(_startupTimeout, onTimeout: () {
        return freshUser;
      });
      return validatedUser;
    } catch (error) {
      final cachedUser = await _getCachedUserById(currentUserId);
      return cachedUser;
    }
  }

  Future<void> _validateStoredSessionInBackground(String currentUserId) async {
    try {
      if (!currentNetworkStatus()) {
        return;
      }
      final validatedUser = await _getStartupSafeCurrentUser(currentUserId);
      if (validatedUser == null) {
        await _clearStoredSessionPreservingState();
      }
    } catch (error) {
      // Background validation is intentionally silent to avoid disrupting active sessions.
    }
  }

  Future<UserModel?> _validateCurrentSessionWithFreshUser(
    String currentUserId,
    UserModel? freshUser,
    {bool allowSessionClear = true}
  ) async {
    if (!currentNetworkStatus()) {
      final cachedUser = await _getCachedUserById(currentUserId);
      if (cachedUser != null) {
        return cachedUser;
      }
      final sessionSnapshotUser = _userFromSessionSnapshot(
        await _readCurrentSessionSnapshot(),
      );
      if (normalizeId(sessionSnapshotUser?.id) == currentUserId) {
        return sessionSnapshotUser;
      }
      return null;
    }
    if (freshUser == null) {
      if (!allowSessionClear) {
        return await _getCachedUserById(currentUserId) ??
            _userFromSessionSnapshot(await _readCurrentSessionSnapshot());
      }
      await _clearStoredSessionPreservingState();
      return null;
    }
    if (await _offlineMutationQueueService.hasPendingUserMutation(currentUserId)) {
      return freshUser;
    }
    final storedSnapshot = await _readCurrentSessionSnapshot();
    final freshSnapshot = _sessionAuthSnapshotForUser(freshUser);
    if (storedSnapshot == null) {
      await _writeCurrentSessionSnapshot(freshUser);
      _clearPendingSelfSessionSnapshot();
      return freshUser;
    }
    if (!_sessionAuthSnapshotsEqual(storedSnapshot, freshSnapshot)) {
      if (_matchesPendingSelfSessionSnapshot(currentUserId, freshSnapshot)) {
        await _writeCurrentSessionSnapshot(freshUser);
        _clearPendingSelfSessionSnapshot();
        return freshUser;
      }
      if (!allowSessionClear) {
        _clearPendingSelfSessionSnapshot();
        return freshUser;
      }
      await _clearStoredSessionPreservingState();
      _clearPendingSelfSessionSnapshot();
      return null;
    }
    _clearPendingSelfSessionSnapshot();
    return freshUser;
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

  Future<UserModel> _persistUserForLogin(UserModel user) async {
    final normalizedId = normalizeId(user.id);
    if (normalizedId == null) {
      return user;
    }
    final normalizedUser = user.copyWith(id: normalizedId);
    final document = _toFirestoreMap(normalizedUser);
    await _upsertUserCacheLocally(document);
    unawaited(
      _persistUserDirect(normalizedUser).then((_) {
      }).catchError((error) {
      }),
    );
    return normalizedUser;
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
      final lookupFuture = isPhoneLogin
          ? _usersCollection
                .where('phone', isEqualTo: normalizedPhone)
                .limit(1)
                .get()
          : _usersCollection
                .where('email', isEqualTo: identifier.toLowerCase())
                .limit(1)
                .get();
      final matches = await lookupFuture.timeout(_loginLookupTimeout, onTimeout: () {
            throw TimeoutException(
              isPhoneLogin
                  ? 'login firestore phone lookup timeout'
                  : 'login firestore email lookup timeout',
            );
          });
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
      if (offlineUser != null) {
        return offlineUser;
      }
      final fallbackResults = await Future.wait<UserModel?>([
        _findUserByIdentifierViaDirectoryFetch(
          identifier: identifier,
          normalizedPhone: normalizedPhone,
          isPhoneLogin: isPhoneLogin,
        ).timeout(
          _loginFallbackLookupTimeout,
          onTimeout: () => null,
        ),
        _findUserByIdentifierViaPublicRestDirectory(
          identifier: identifier,
          normalizedPhone: normalizedPhone,
          isPhoneLogin: isPhoneLogin,
        ).timeout(
          _loginFallbackLookupTimeout,
          onTimeout: () => null,
        ),
      ]);
      final directoryUser = fallbackResults[0];
      final publicRestUser = fallbackResults[1];
      if (directoryUser != null) {
        return directoryUser;
      }
      if (publicRestUser != null) {
        return publicRestUser;
      }
      throw _buildLoginLookupFailure(error, isPhoneLogin: isPhoneLogin);
    }
  }

  AuthFailure _buildLoginLookupFailure(
    Object error, {
    required bool isPhoneLogin,
  }) {
    final normalized = normalizeUserErrorText(
      error.toString(),
      fallback: '',
    ).toLowerCase();
    if (normalized.contains('timeout') ||
        normalized.contains('failed to fetch') ||
        normalized.contains('network') ||
        normalized.contains('progressevent')) {
      return const AuthFailure(
        'We could not reach the account records right now. Please check your connection and try again.',
      );
    }
    if (normalized.contains('failed-precondition') ||
        normalized.contains('index') ||
        normalized.contains('invalid-argument') ||
        normalized.contains('invalid value') ||
        normalized.contains('query')) {
      return AuthFailure(
        isPhoneLogin
            ? 'We could not verify that phone number right now. Please try again shortly.'
            : 'We could not verify that email address right now. Please try again shortly.',
      );
    }
    return const AuthFailure(
      'We could not look up that account right now. Please try again.',
    );
  }

  Future<UserModel?> _findCachedUserByIdentifier({
    required String identifier,
    required String? normalizedPhone,
    required bool isPhoneLogin,
  }) async {
    final firestoreCachedUser = await _findFirestoreSdkCachedUserByIdentifier(
      identifier: identifier,
      normalizedPhone: normalizedPhone,
      isPhoneLogin: isPhoneLogin,
    );
    if (firestoreCachedUser != null) {
      return firestoreCachedUser;
    }
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

  Future<UserModel?> _findFirestoreSdkCachedUserByIdentifier({
    required String identifier,
    required String? normalizedPhone,
    required bool isPhoneLogin,
  }) async {
    try {
      final snapshot = await (isPhoneLogin
              ? _usersCollection
                    .where('phone', isEqualTo: normalizedPhone)
                    .limit(1)
                    .get(const GetOptions(source: Source.cache))
              : _usersCollection
                    .where('email', isEqualTo: identifier.trim().toLowerCase())
                    .limit(1)
                    .get(const GetOptions(source: Source.cache)))
          .timeout(const Duration(seconds: 1));
      if (snapshot.docs.isEmpty) {
        return null;
      }
      return UserModel.fromMap(documentData(snapshot.docs.first));
    } catch (_) {
      return null;
    }
  }

  Future<List<UserModel>> _getUsersCachedOnly() async {
    final documents =
        await FirestoreCacheStore.instance.readDocumentMaps(_usersResourceKey) ??
        const <Map<String, dynamic>>[];
    final users = documents
        .map(UserModel.fromMap)
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

  Future<UserModel?> _findUserByIdentifierViaDirectoryFetch({
    required String identifier,
    required String? normalizedPhone,
    required bool isPhoneLogin,
  }) async {
    try {
      final snapshot = await _usersCollection
          .get()
          .timeout(_loginLookupTimeout, onTimeout: () {
            throw TimeoutException('login users directory fetch timeout');
          });
      final documents = snapshot.docs.map(documentData).toList(growable: false);
      await _writeUsersCacheLocally(documents);
      final users = documents.map(UserModel.fromMap).toList(growable: false);
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
    } catch (error) {
      return null;
    }
  }

  Future<UserModel?> _findUserByIdentifierViaPublicRestDirectory({
    required String identifier,
    required String? normalizedPhone,
    required bool isPhoneLogin,
  }) async {
    try {
      final documents = await _firestorePublicDocumentFetcher
          .fetchCollectionDocuments('users')
          .timeout(_loginLookupTimeout, onTimeout: () {
            throw TimeoutException('login public rest users fetch timeout');
          });
      if (documents.isEmpty) {
        return null;
      }
      await _writeUsersCacheLocally(documents);
      final users = documents.map(UserModel.fromMap).toList(growable: false);
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
    } catch (error) {
      return null;
    }
  }

  Future<void> _writeUsersCacheLocally(
    List<Map<String, dynamic>> documents,
  ) async {
    await FirestoreCacheStore.instance.writeDocumentMaps(
      _usersResourceKey,
      documents,
    );
    final latestUpdatedAt = documents
        .map((document) => document['updated_at']?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .fold<String>('none', (latest, value) {
          if (latest == 'none' || value.compareTo(latest) > 0) {
            return value;
          }
          return latest;
        });
    await FirestoreCacheStore.instance.writeVersion(
      _usersResourceKey,
      '$latestUpdatedAt|${documents.length}',
    );
  }

  Future<void> _upsertUserCacheLocally(Map<String, dynamic> document) async {
    final documentId = document['id']?.toString().trim() ?? '';
    if (documentId.isEmpty) {
      return;
    }
    final currentDocuments =
        await FirestoreCacheStore.instance.readDocumentMaps(_usersResourceKey) ??
        const <Map<String, dynamic>>[];
    final nextDocuments = currentDocuments
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: true);
    final existingIndex = nextDocuments.indexWhere(
      (item) => (item['id']?.toString().trim() ?? '') == documentId,
    );
    if (existingIndex >= 0) {
      nextDocuments[existingIndex] = Map<String, dynamic>.from(document);
    } else {
      nextDocuments.add(Map<String, dynamic>.from(document));
    }
    await _writeUsersCacheLocally(nextDocuments);
  }

  bool _isOfflineAuthLookupError(Object error) {
    final normalized = normalizeUserErrorText(
      error.toString(),
      fallback: '',
    ).toLowerCase();
    return normalized.contains('offline') ||
        normalized.contains('internet connection') ||
        normalized.contains('network') ||
        normalized.contains('timeout') ||
        normalized.contains('invalid-argument') ||
        normalized.contains('invalid value') ||
        normalized.contains('failed-precondition') ||
        normalized.contains('requires an index') ||
        normalized.contains('query requires an index') ||
        normalized.contains('unsupported') ||
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

  Future<Map<String, dynamic>?> _readCurrentSessionSnapshot() async {
    final rawValue = await _storage.readString(_currentSessionAuthSnapshotKey);
    final trimmed = rawValue?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _readQuickLoginSourceSnapshot() async {
    final rawValue = await _storage.readString(_quickLoginSourceSnapshotKey);
    final trimmed = rawValue?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeCurrentSessionSnapshot(UserModel user) async {
    await _storage.writeString(
      _currentSessionAuthSnapshotKey,
      jsonEncode(_sessionAuthSnapshotForUser(user)),
    );
  }

  Future<void> _applyImmediateUserPhotoState(UserModel user) async {
    await _cache.upsertDocument(
      resourceKey: _usersResourceKey,
      document: _toFirestoreMap(user),
    );
    final currentUserId = normalizeId(await _storage.readString(_currentUserIdKey));
    if (currentUserId == normalizeId(user.id)) {
      await _writeCurrentSessionSnapshot(user);
    }
  }

  UserModel _userWithImmediatePhotoPreview(
    UserModel user, {
    required Uint8List bytes,
    String? mimeType,
  }) {
    return user.copyWith(
      photo: Uri.dataFromBytes(
        bytes,
        mimeType: mimeType?.trim().isNotEmpty == true
            ? mimeType!.trim()
            : 'image/jpeg',
      ).toString(),
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> _sessionAuthSnapshotForUser(UserModel user) {
    return <String, dynamic>{
      'id': normalizeId(user.id),
      'role': (user.role ?? '').trim().toLowerCase(),
      'name': (user.name ?? '').trim(),
      'email': (user.email ?? '').trim().toLowerCase(),
      'phone': normalizePhilippinePhone(user.phone) ?? (user.phone ?? '').trim(),
      'password': user.password ?? '',
      'photo': user.photo,
    };
  }

  bool _sessionAuthSnapshotsEqual(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    return (left['id']?.toString() ?? '') == (right['id']?.toString() ?? '') &&
        (left['role']?.toString() ?? '') == (right['role']?.toString() ?? '') &&
        (left['name']?.toString() ?? '') == (right['name']?.toString() ?? '') &&
        (left['email']?.toString() ?? '') ==
            (right['email']?.toString() ?? '') &&
        (left['phone']?.toString() ?? '') ==
            (right['phone']?.toString() ?? '') &&
        (left['password']?.toString() ?? '') ==
            (right['password']?.toString() ?? '');
  }

  UserModel? _userFromSessionSnapshot(Map<String, dynamic>? snapshot) {
    if (snapshot == null) {
      return null;
    }
    final normalizedId = normalizeId(snapshot['id']?.toString());
    if (normalizedId == null) {
      return null;
    }
    return UserModel(
      id: normalizedId,
      role: snapshot['role']?.toString(),
      name: snapshot['name']?.toString(),
      email: snapshot['email']?.toString(),
      phone: snapshot['phone']?.toString(),
      password: snapshot['password']?.toString(),
      photo: snapshot['photo']?.toString(),
      isActive: true,
      isOnline: false,
    );
  }

  UserModel _userFromFirestoreMap(
    Map<String, dynamic> map,
    Map<String, VehicleCatalogItem> typeById,
  ) {
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
    return RoleAccessService.instance.isOnlineEligibleRole(role);
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

  bool _isQueueableUploadError(String normalizedError) {
    return normalizedError.contains('internet connection') ||
        normalizedError.contains('temporarily unavailable') ||
        normalizedError.contains('request took too long') ||
        normalizedError.contains('timeoutexception') ||
        normalizedError.contains('future not completed') ||
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
