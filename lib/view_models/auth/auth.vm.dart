import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/repositories/local/local_auth_repository.dart';

class AuthViewModel extends BaseViewModel {
  AuthViewModel({
    AuthRepository? repository,
  }) : _repository = repository ?? LocalAuthRepository.instance;

  final AuthRepository _repository;

  String? errorMessage;

  Future<UserModel?> login({
    required String email,
    required String password,
  }) async {
    setBusy(true);
    errorMessage = null;
    notifyListeners();
    try {
      return await _repository.login(email: email, password: password);
    } on AuthFailure catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return null;
    } finally {
      setBusy(false);
    }
  }

  Future<UserModel?> register(UserModel user) async {
    setBusy(true);
    errorMessage = null;
    notifyListeners();
    try {
      return await _repository.register(user);
    } on AuthFailure catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return null;
    } finally {
      setBusy(false);
    }
  }
}
