import 'dart:async';

import 'package:stacked/stacked.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/utils/functions.dart';

class AuthViewModel extends BaseViewModel {
  AuthViewModel({AuthRepository? repository})
    : _repository = repository ?? AuthRequest.instance;

  final AuthRepository _repository;

  String? errorMessage;

  Future<UserModel?> login({
    required String identifier,
    required String password,
  }) async {
    setBusy(true);
    errorMessage = null;
    notifyListeners();
    try {
      final user = await _repository.login(
        identifier: identifier,
        password: password,
      );
      return user;
    } on AuthFailure catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return null;
    } catch (error) {
      errorMessage = exactUserErrorMessage(
        error,
        fallback: 'Sign in failed.',
      );
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
      final registeredUser = await _repository.register(user);
      return registeredUser;
    } on AuthFailure catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return null;
    } catch (error) {
      errorMessage = userFacingErrorMessage(
        error,
        fallback:
            'We could not create your account right now. Please try again.',
      );
      notifyListeners();
      return null;
    } finally {
      setBusy(false);
    }
  }
}
