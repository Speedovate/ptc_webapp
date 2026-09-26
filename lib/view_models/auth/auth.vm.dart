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
      errorMessage = error.toString();
      notifyListeners();
      return null;
    } finally {
      setBusy(false);
    }
  }

  /// [vehicleCode] is a driver's own vehicle. When present, registration also
  /// opens that vehicle make with the new driver on it and no helper yet, so
  /// the office can assign the helper from the admin screens.
  Future<UserModel?> register({
    required UserModel user,
    String? vehicleCode,
  }) async {
    setBusy(true);
    errorMessage = null;
    notifyListeners();
    try {
      final registeredUser = await _repository.register(
        user,
        vehicleCode: vehicleCode,
      );
      return registeredUser;
    } on AuthFailure catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return null;
    } catch (error) {
      errorMessage = exactUserErrorMessage(error);
      notifyListeners();
      return null;
    } finally {
      setBusy(false);
    }
  }
}
