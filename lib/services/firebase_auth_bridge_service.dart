import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/local/auth_storage_backend.dart';

class FirebaseAuthBridgeService {
  FirebaseAuthBridgeService({
    FirebaseFirestore? firestore,
    AuthStorageBackend? storageBackend,
  });

  static final FirebaseAuthBridgeService instance = FirebaseAuthBridgeService();

  Future<void> initialize() async {}

  Future<UserModel> hydrateUser(UserModel user) async => user;

  Future<UserModel> syncSessionForUser(UserModel user) async => user;

  Future<void> syncUserLink(UserModel user) async {}

  Future<void> clearSession() async {}
}
