import 'package:webapp/models/user.dart';
import 'dart:typed_data';

abstract class AuthRepository {
  Future<void> initialize();
  Future<List<UserModel>> getUsers();
  Future<UserModel?> getCurrentUser();
  Future<UserModel> login({
    required String email,
    required String password,
  });
  Future<UserModel> register(UserModel user);
  Future<UserModel> saveUser(UserModel user);
  Future<UserModel> saveUserPhoto({
    required String userId,
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    int? size,
  });
  Future<UserModel> saveDriverLicensePhoto({
    required String userId,
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    int? size,
  });
  Future<void> deleteUser(String userId);
  Future<void> loginAsUser(String userId);
  Future<bool> hasQuickLoginSource();
  Future<UserModel?> returnToQuickLoginSource();
  Future<void> logout();
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
