import 'package:webapp/models/user.dart';

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
