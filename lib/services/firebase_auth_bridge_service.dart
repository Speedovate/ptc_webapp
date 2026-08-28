import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';
import 'package:webapp/services/network_status_events.dart';
import 'package:webapp/utils/functions.dart';

class FirebaseAuthBridgeService {
  FirebaseAuthBridgeService({
    FirebaseFirestore? firestore,
    AuthStorageBackend? storageBackend,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storageBackend ?? createAuthStorageBackend();

  static final FirebaseAuthBridgeService instance = FirebaseAuthBridgeService();

  static const _currentFirebaseAuthUidKey =
      'paltranco_current_firebase_auth_uid';
  static const _currentFirebaseAuthUserIdKey =
      'paltranco_current_firebase_auth_user_id';

  final FirebaseFirestore _firestore;
  final AuthStorageBackend _storage;

  CollectionReference<Map<String, dynamic>> get _userAuthLinksCollection =>
      _firestore.collection('user_auth_links');

  Future<void> initialize() async {
    await _storage.initialize();
  }

  Future<UserModel> hydrateUser(UserModel user) async {
    await initialize();
    final normalizedUserId = normalizeId(user.id);
    final currentBridgeUserId = normalizeId(
      await _storage.readString(_currentFirebaseAuthUserIdKey),
    );
    final storedBridgeUid = _normalizeBridgeUid(
      await _storage.readString(_currentFirebaseAuthUidKey),
    );
    if (normalizedUserId == null ||
        currentBridgeUserId != normalizedUserId ||
        storedBridgeUid == null ||
        storedBridgeUid == user.firebaseAuthUid) {
      return user;
    }
    return user.copyWith(firebaseAuthUid: storedBridgeUid);
  }

  Future<UserModel> syncSessionForUser(UserModel user) async {
    await initialize();
    final normalizedUserId = normalizeId(user.id);
    final bridgeUid = _normalizeBridgeUid(user.firebaseAuthUid);
    if (normalizedUserId == null || bridgeUid == null) {
      return user;
    }
    await _storage.writeString(_currentFirebaseAuthUserIdKey, normalizedUserId);
    await _storage.writeString(_currentFirebaseAuthUidKey, bridgeUid);
    await _upsertUserAuthLink(user.copyWith(firebaseAuthUid: bridgeUid));
    return user.copyWith(firebaseAuthUid: bridgeUid);
  }

  Future<void> syncUserLink(UserModel user) async {
    await initialize();
    await _upsertUserAuthLink(user);
  }

  Future<void> clearSession() async {
    await initialize();
    await _storage.remove(_currentFirebaseAuthUidKey);
    await _storage.remove(_currentFirebaseAuthUserIdKey);
  }

  Future<void> _upsertUserAuthLink(UserModel user) async {
    final normalizedUserId = normalizeId(user.id);
    final bridgeUid = _normalizeBridgeUid(user.firebaseAuthUid);
    if (!currentNetworkStatus() ||
        normalizedUserId == null ||
        bridgeUid == null) {
      return;
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _userAuthLinksCollection.doc(bridgeUid).set({
      'firebase_auth_uid': bridgeUid,
      'user_id': normalizedUserId,
      'role': normalizeRoleKey(user.role),
      'updated_at': nowIso,
    }, SetOptions(merge: true));
  }

  String? _normalizeBridgeUid(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
